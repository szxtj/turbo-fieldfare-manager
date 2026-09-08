import Foundation
import SwiftUI
import Combine

public enum ServiceState: Equatable {
    case stopped
    case starting
    case running(pid: Int32, port: Int)
    case missingRepo
    case error(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case .stopped:
            return "已停止"
        case .starting:
            return "启动中..."
        case .running(_, let port):
            return "运行中 (端口: \(port))"
        case .missingRepo:
            return "未找到本体仓库"
        case .error(let msg):
            return "异常: \(msg)"
        }
    }
}

public struct RepoCheckResult {
    public let exists: Bool
    public let isUpToDate: Bool
    public let localCommit: String
    public let remoteCommit: String
    public let message: String
}

@MainActor
public final class ServiceManager: ObservableObject {
    public static let shared = ServiceManager()

    @Published public private(set) var state: ServiceState = .stopped
    @Published public private(set) var lastLogLines: [String] = []
    @Published public private(set) var repoStatus: RepoCheckResult?

    public let port = 1235
    public let homeDir: URL
    public let repoDir: URL
    public let serverScript: URL
    public let logFile: URL
    public let pidFile: URL

    private var monitorTimer: Timer?
    private var logFileHandle: FileHandle?
    private var logSource: DispatchSourceFileSystemObject?

    private init() {
        self.homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.repoDir = homeDir.appendingPathComponent("turbo-fieldfare")
        
        // server.sh 优先取 manager 项目目录，其次主目录
        let scriptCandidates = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("server.sh"),
            homeDir.appendingPathComponent("Projects/turbo-fieldfare-manager/server.sh"),
            homeDir.appendingPathComponent("Projects/turbo-fieldfare/server.sh"),
            repoDir.appendingPathComponent("server.sh")
        ]
        self.serverScript = scriptCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            ?? homeDir.appendingPathComponent("Projects/turbo-fieldfare-manager/server.sh")

        self.logFile = homeDir.appendingPathComponent("Library/Logs/turbo-fieldfare.log")
        self.pidFile = URL(fileURLWithPath: "/tmp/turbo_fieldfare_server.pid")

        startMonitoring()
        startLogTail()
    }

    // MARK: - 状态监视轮询

    private func startMonitoring() {
        refreshState()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshState()
            }
        }
    }

    public func refreshState() {
        guard FileManager.default.fileExists(atPath: repoDir.path) else {
            self.state = .missingRepo
            return
        }

        guard let pid = readPID(), isProcessAlive(pid: pid) else {
            if case .starting = state {
                // 如果刚刚发出 start 指令，容忍 5 秒启动过渡期
                return
            }
            self.state = .stopped
            return
        }

        // 异步探测 HTTP 探针
        Task {
            let healthy = await checkHealth()
            if healthy {
                self.state = .running(pid: pid, port: self.port)
            } else {
                self.state = .starting
            }
        }
    }

    private func readPID() -> Int32? {
        guard FileManager.default.fileExists(atPath: pidFile.path),
              let content = try? String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(content) else {
            return nil
        }
        return pid
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        return kill(pid, 0) == 0
    }

    public func checkHealth() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/models") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
        } catch {
            return false
        }
        return false
    }

    // MARK: - 服务生命周期控制

    public func startService() {
        guard FileManager.default.fileExists(atPath: repoDir.path) else {
            self.state = .missingRepo
            return
        }
        self.state = .starting
        runScriptCommand("start")
    }

    public func stopService() {
        runScriptCommand("stop")
        self.state = .stopped
    }

    public func restartService() {
        self.state = .starting
        runScriptCommand("restart")
    }

    @discardableResult
    private func runScriptCommand(_ action: String) -> (output: String, exitCode: Int32) {
        guard FileManager.default.fileExists(atPath: serverScript.path) else {
            return ("未找到 server.sh", 1)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [serverScript.path, action]
        
        var env = ProcessInfo.processInfo.environment
        env["TURBO_FIELDFARE_DIR"] = repoDir.path
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, process.terminationStatus)
        } catch {
            return (error.localizedDescription, 1)
        }
    }

    // MARK: - 仓库检测与一键克隆

    public func checkRepoStatus() async -> RepoCheckResult {
        guard FileManager.default.fileExists(atPath: repoDir.appendingPathComponent(".git").path) else {
            let res = RepoCheckResult(
                exists: false,
                isUpToDate: false,
                localCommit: "",
                remoteCommit: "",
                message: "本体仓库不存在，需要克隆"
            )
            self.repoStatus = res
            return res
        }

        // git fetch & 比较 HEAD 与 origin/main
        _ = await runProcess(executable: "/usr/bin/git", arguments: ["-C", repoDir.path, "fetch", "origin", "main"])
        let localCommit = await runProcess(executable: "/usr/bin/git", arguments: ["-C", repoDir.path, "rev-parse", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteCommit = await runProcess(executable: "/usr/bin/git", arguments: ["-C", repoDir.path, "rev-parse", "--short", "origin/main"]).trimmingCharacters(in: .whitespacesAndNewlines)

        let isUpToDate = (!localCommit.isEmpty && localCommit == remoteCommit)
        let message = isUpToDate ? "已是最新版本 (\(localCommit))" : "发现新版本 (本地: \(localCommit) -> 远端: \(remoteCommit))"
        let res = RepoCheckResult(
            exists: true,
            isUpToDate: isUpToDate,
            localCommit: localCommit,
            remoteCommit: remoteCommit,
            message: message
        )
        self.repoStatus = res
        return res
    }

    public func cloneOfficialRepo(progressHandler: @escaping (String) -> Void) async throws {
        let repoUrl = "https://github.com/drumih/turbo-fieldfare.git"
        progressHandler("正在克隆官方仓库到 \(repoDir.path)...")
        
        let output = await runProcess(executable: "/usr/bin/git", arguments: ["clone", repoUrl, repoDir.path])
        progressHandler(output)

        guard FileManager.default.fileExists(atPath: repoDir.appendingPathComponent("Package.swift").path) else {
            throw NSError(domain: "TurboFieldfareBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "克隆失败或缺少 Package.swift"])
        }

        progressHandler("正在编译发布版本 TurboFieldfareServer (需要 1-2 分钟)...")
        let buildOutput = await runProcess(
            executable: "/usr/bin/swift",
            arguments: ["build", "-c", "release", "--product", "TurboFieldfareServer"],
            currentDirectory: repoDir
        )
        progressHandler(buildOutput)
        progressHandler("初始化构建完成！")
    }

    public func syncToLatest(progressHandler: @escaping (String) -> Void) async {
        progressHandler("正在拉取最新代码...")
        let pullOutput = await runProcess(executable: "/usr/bin/git", arguments: ["-C", repoDir.path, "pull", "origin", "main"])
        progressHandler(pullOutput)

        progressHandler("正在重新编译...")
        let buildOutput = await runProcess(
            executable: "/usr/bin/swift",
            arguments: ["build", "-c", "release", "--product", "TurboFieldfareServer"],
            currentDirectory: repoDir
        )
        progressHandler(buildOutput)
        progressHandler("同步与重新构建完成！")
        _ = await checkRepoStatus()
    }

    private func runProcess(executable: String, arguments: [String], currentDirectory: URL? = nil) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let currentDirectory = currentDirectory {
                    process.currentDirectoryURL = currentDirectory
                }
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let str = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: str)
                } catch {
                    continuation.resume(returning: "错误: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 日志 Tail

    private func startLogTail() {
        reloadLogs()
        // 使用 Timer 定期读取新增日志
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadLogs()
            }
        }
    }

    public func reloadLogs() {
        guard FileManager.default.fileExists(atPath: logFile.path) else { return }
        do {
            let content = try String(contentsOf: logFile, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            // 取最后 200 行
            let tail = lines.suffix(200).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            self.lastLogLines = Array(tail)
        } catch {
            // ignore
        }
    }

    public func clearLogs() {
        try? "".write(to: logFile, atomically: true, encoding: .utf8)
        self.lastLogLines = []
    }
}

