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
    public let modelDir: URL
    public let serverScript: URL
    public let logFile: URL
    public let pidFile: URL

    private var monitorTimer: Timer?

    private init() {
        self.homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.repoDir = homeDir.appendingPathComponent("turbo-fieldfare")
        self.modelDir = repoDir.appendingPathComponent("scratch/gemma4.gturbo")
        
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
                return
            }
            self.state = .stopped
            return
        }

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

    // MARK: - 仓库检测

    public func checkRepoStatus() async -> RepoCheckResult {
        guard FileManager.default.fileExists(atPath: repoDir.appendingPathComponent(".git").path) else {
            let res = RepoCheckResult(
                exists: false,
                isUpToDate: false,
                localCommit: "",
                remoteCommit: "",
                message: "本体仓库不存在，需要初始化克隆"
            )
            self.repoStatus = res
            return res
        }

        _ = await runSimpleProcess(executable: "/usr/bin/git", arguments: ["-C", repoDir.path, "fetch", "origin", "main"])
        let localCommit = await runSimpleProcess(executable: "/usr/bin/git", arguments: ["-C", repoDir.path, "rev-parse", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteCommit = await runSimpleProcess(executable: "/usr/bin/git", arguments: ["-C", repoDir.path, "rev-parse", "--short", "origin/main"]).trimmingCharacters(in: .whitespacesAndNewlines)

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

    // MARK: - 安全回收站操作 (Trash Item)

    /// 将损坏或现存的模型目录安全移入系统废纸篓，避免不可逆直接删除
    @discardableResult
    public func safelyTrashDamagedModel() throws -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: modelDir.path) {
            var trashedURL: NSURL?
            try fm.trashItem(at: modelDir, resultingItemURL: &trashedURL)
            return trashedURL as URL?
        }
        return nil
    }

    // MARK: - 首次引导全流程 (克隆 -> 编译 -> 自动下载模型 -> 启动)

    public func runInitialSetup(progress: @escaping (String) -> Void) async throws {
        let repoUrl = "https://github.com/drumih/turbo-fieldfare.git"
        
        // 1. 克隆
        progress("🚀 步骤 1/4: 正在从官方源克隆本体仓库到 \(repoDir.path)...")
        let cloneCode = await runStreamingProcess(
            executable: "/usr/bin/git",
            arguments: ["clone", repoUrl, repoDir.path],
            outputHandler: progress
        )
        guard cloneCode == 0, FileManager.default.fileExists(atPath: repoDir.appendingPathComponent("Package.swift").path) else {
            throw NSError(domain: "TurboFieldfareBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "克隆官方仓库失败，请检查网络连接"])
        }
        progress("✅ 官方仓库克隆成功！\n")

        // 2. 编译服务端
        progress("⚙️ 步骤 2/4: 正在编译发布版 TurboFieldfareServer (预计需 1-2 分钟)...")
        let buildCode = await runStreamingProcess(
            executable: "/usr/bin/swift",
            arguments: ["build", "-c", "release", "--product", "TurboFieldfareServer"],
            currentDirectory: repoDir,
            outputHandler: progress
        )
        guard buildCode == 0 else {
            throw NSError(domain: "TurboFieldfareBar", code: 2, userInfo: [NSLocalizedDescriptionKey: "编译 TurboFieldfareServer 失败，请查看上方输出"])
        }
        progress("✅ 服务端二进制编译成功！\n")

        // 3. 自动下载模型权重
        progress("📥 步骤 3/4: 正在下载 Gemma 4 26B-A4B 模型权重 (约 14.3GB)...")
        progress("💡 提示: 采用流式断点续传下载，耗时取决于网络带宽，请耐心等待...")
        let downloadCode = await runStreamingProcess(
            executable: "/usr/bin/swift",
            arguments: ["run", "-c", "release", "TurboFieldfareRepack", "--output", "scratch/gemma4.gturbo", "--overwrite", "--resume"],
            currentDirectory: repoDir,
            outputHandler: progress
        )
        guard downloadCode == 0 else {
            throw NSError(domain: "TurboFieldfareBar", code: 3, userInfo: [NSLocalizedDescriptionKey: "下载/解压模型权重失败，支持再次尝试进行断点续传"])
        }
        progress("✅ 模型权重下载并校验成功！\n")

        // 4. 启动服务
        progress("🚀 步骤 4/4: 正在后台拉起 TurboFieldfare 服务...")
        startService()
        
        var retries = 0
        while retries < 15 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            retries += 1
            if await checkHealth() {
                progress("🎉 服务初始化全部完成，健康检查通过 (HTTP 200)！已为您自动常驻系统状态栏。")
                return
            }
        }
        progress("⚠️ 服务已启动，正在等待模型最终就绪...")
    }

    // MARK: - 故障自愈恢复全流程 (清理 -> 重置/拉取 -> 编译 -> 废纸篓安全备份 -> 重新下载模型 -> 启动)

    public func runFullRecovery(progress: @escaping (String) -> Void) async throws {
        progress("🛑 步骤 1/6: 正在清理任何僵死或残留的服务进程...")
        stopService()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        progress("✅ 进程环境清理完毕。\n")

        // 2. 检查并重置/克隆仓库
        if !FileManager.default.fileExists(atPath: repoDir.appendingPathComponent(".git").path) {
            progress("🌐 步骤 2/6: 未检测到本体仓库，正在重新克隆...")
            let repoUrl = "https://github.com/drumih/turbo-fieldfare.git"
            let cloneCode = await runStreamingProcess(
                executable: "/usr/bin/git",
                arguments: ["clone", repoUrl, repoDir.path],
                outputHandler: progress
            )
            guard cloneCode == 0 else {
                throw NSError(domain: "TurboFieldfareBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "克隆仓库失败"])
            }
        } else {
            progress("🔄 步骤 2/6: 正在拉取官方最新代码并恢复纯净状态...")
            _ = await runStreamingProcess(executable: "/usr/bin/git", arguments: ["-C", repoDir.path, "fetch", "origin", "main"], outputHandler: progress)
            _ = await runStreamingProcess(executable: "/usr/bin/git", arguments: ["-C", repoDir.path, "reset", "--hard", "origin/main"], outputHandler: progress)
        }
        progress("✅ 仓库代码状态已对齐官方最新主线！\n")

        // 3. 重新编译
        progress("⚙️ 步骤 3/6: 正在重新编译 TurboFieldfareServer...")
        let buildCode = await runStreamingProcess(
            executable: "/usr/bin/swift",
            arguments: ["build", "-c", "release", "--product", "TurboFieldfareServer"],
            currentDirectory: repoDir,
            outputHandler: progress
        )
        guard buildCode == 0 else {
            throw NSError(domain: "TurboFieldfareBar", code: 2, userInfo: [NSLocalizedDescriptionKey: "编译失败"])
        }
        progress("✅ 重新编译完成！\n")

        // 4. 将旧模型安全移入系统回收站
        progress("🗑️ 步骤 4/6: 正在将现存可能损坏的模型文件夹安全移入系统废纸篓 (Trash)...")
        do {
            if let trashedLocation = try safelyTrashDamagedModel() {
                progress("✅ 已将旧模型移至系统废纸篓: \(trashedLocation.path)")
                progress("   (若后续需要恢复旧文件，可随时从系统废纸篓中还原)")
            } else {
                progress("ℹ️ 未发现旧模型文件夹，无需移动。")
            }
        } catch {
            progress("⚠️ 移入废纸篓时出现异常: \(error.localizedDescription)，继续下一步...")
        }
        progress("\n")

        // 5. 重新下载模型
        progress("📥 步骤 5/6: 正在重新下载与配置 Gemma 4 模型权重...")
        progress("💡 提示: 重新下载支持断点续传，耗时视网速而定...")
        let downloadCode = await runStreamingProcess(
            executable: "/usr/bin/swift",
            arguments: ["run", "-c", "release", "TurboFieldfareRepack", "--output", "scratch/gemma4.gturbo", "--overwrite", "--resume"],
            currentDirectory: repoDir,
            outputHandler: progress
        )
        guard downloadCode == 0 else {
            throw NSError(domain: "TurboFieldfareBar", code: 3, userInfo: [NSLocalizedDescriptionKey: "下载模型失败，请检查网络后重试"])
        }
        progress("✅ 模型权重下载并就绪！\n")

        // 6. 重启服务并验证
        progress("🚀 步骤 6/6: 正在重新拉起后台服务并进行健康检查...")
        startService()

        var retries = 0
        while retries < 15 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            retries += 1
            if await checkHealth() {
                progress("🎉 故障恢复成功！推理服务已正常工作 (HTTP 200)！")
                return
            }
        }
        progress("⚠️ 服务已重新拉起，请在状态栏菜单中观察健康状态。")
    }

    // MARK: - 同步最新版本

    public func syncToLatest(progress: @escaping (String) -> Void) async {
        progress("正在拉取最新代码...")
        _ = await runStreamingProcess(executable: "/usr/bin/git", arguments: ["-C", repoDir.path, "pull", "origin", "main"], outputHandler: progress)

        progress("正在重新编译 TurboFieldfareServer...")
        _ = await runStreamingProcess(
            executable: "/usr/bin/swift",
            arguments: ["build", "-c", "release", "--product", "TurboFieldfareServer"],
            currentDirectory: repoDir,
            outputHandler: progress
        )
        progress("同步与构建完成！")
        _ = await checkRepoStatus()
    }

    // MARK: - 实时流式子进程执行器

    public func runStreamingProcess(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        outputHandler: @escaping (String) -> Void
    ) async -> Int32 {
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

                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = { fileHandle in
                    let data = fileHandle.availableData
                    if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            outputHandler(text)
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    handle.readabilityHandler = nil
                    let remaining = handle.readDataToEndOfFile()
                    if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                        DispatchQueue.main.async {
                            outputHandler(text)
                        }
                    }
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    handle.readabilityHandler = nil
                    DispatchQueue.main.async {
                        outputHandler("进程异常: \(error.localizedDescription)\n")
                    }
                    continuation.resume(returning: 1)
                }
            }
        }
    }

    private func runSimpleProcess(executable: String, arguments: [String], currentDirectory: URL? = nil) async -> String {
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
