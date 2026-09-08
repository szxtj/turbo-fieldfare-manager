import SwiftUI
import AppKit

public final class StatusAndLogWindowController: NSWindowController {
    public static let shared = StatusAndLogWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TurboFieldfare 服务状态与实时日志"
        window.center()
        window.setFrameAutosaveName("TurboFieldfareStatusAndLogWindow")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: StatusAndLogView())

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showAndActivate() {
        self.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window?.makeKeyAndOrderFront(nil)
    }
}

public struct StatusAndLogView: View {
    @ObservedObject var manager = ServiceManager.shared
    @State private var autoScroll: Bool = true
    @State private var copyBanner: String? = nil
    @State private var isSyncing: Bool = false
    @State private var syncLog: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部状态栏卡片
            topCardView
                .padding(16)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - 快捷操作与工具栏
            actionToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // MARK: - 日志区域
            logConsoleView
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            manager.reloadLogs()
        }
    }

    // MARK: - 顶部概览
    private var topCardView: some View {
        HStack(alignment: .center, spacing: 16) {
            // 状态指示图标
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Circle()
                    .fill(statusColor)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("TurboFieldfare Server")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text(statusBadgeText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.15))
                        .foregroundColor(statusColor)
                        .cornerRadius(6)
                }

                HStack(spacing: 14) {
                    Label("端口: \(manager.port)", systemImage: "network")
                    Label("上下文: 32K", systemImage: "doc.text")
                    Label("专家槽位: 24 (LFU)", systemImage: "cpu")
                    Label("Prefill: auto", systemImage: "bolt.fill")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // 控制按钮
            HStack(spacing: 10) {
                if manager.state.isRunning {
                    Button(action: { manager.restartService() }) {
                        Label("重启服务", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Button(action: { manager.stopService() }) {
                        Label("停止服务", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: { manager.startService() }) {
                        Label("启动服务", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
    }

    // MARK: - 工具栏
    private var actionToolbar: some View {
        HStack(spacing: 12) {
            // API 快速复制
            Button(action: copyCurl) {
                Label("复制测试 cURL", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            if let banner = copyBanner {
                Text(banner)
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            Spacer()

            // 自动滚动开关
            Toggle("自动滚动", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(.caption)

            // 清理日志
            Button(action: { manager.clearLogs() }) {
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .font(.caption)

            // 打开 Finder 日志文件
            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([manager.logFile])
            }) {
                Label("打开日志文件", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    // MARK: - 日志视图
    private var logConsoleView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if manager.lastLogLines.isEmpty {
                        Text("暂无日志输出，启动服务后即可在此查看实时输出。")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(16)
                    } else {
                        ForEach(Array(manager.lastLogLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                                .foregroundColor(logLineColor(line))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .onChange(of: manager.lastLogLines.count) { _ in
                if autoScroll, !manager.lastLogLines.isEmpty {
                    withAnimation {
                        proxy.scrollTo(manager.lastLogLines.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - 辅助计算与操作

    private var statusColor: Color {
        switch manager.state {
        case .running:
            return .green
        case .starting:
            return .orange
        case .stopped, .missingRepo, .error:
            return .gray
        }
    }

    private var statusBadgeText: String {
        switch manager.state {
        case .running(let pid, _):
            return "运行中 (PID: \(pid))"
        case .starting:
            return "初始化/启动中..."
        case .stopped:
            return "已停止"
        case .missingRepo:
            return "未找到本体仓库 (~/turbo-fieldfare)"
        case .error(let msg):
            return "异常: \(msg)"
        }
    }

    private func logLineColor(_ line: String) -> Color {
        if line.contains("❌") || line.contains("Error") || line.contains("error") || line.contains("failed") {
            return Color.red.opacity(0.9)
        }
        if line.contains("⚠️") || line.contains("Warning") || line.contains("warning") {
            return Color.yellow.opacity(0.9)
        }
        if line.contains("✅") || line.contains("Complete") || line.contains("HTTP 200") {
            return Color.green.opacity(0.9)
        }
        return Color(red: 0.88, green: 0.88, blue: 0.90)
    }

    private func copyCurl() {
        let curlCommand = """
        curl http://127.0.0.1:\(manager.port)/v1/chat/completions \\
          -H 'Content-Type: application/json' \\
          -d '{"model":"gemma-4-26b-a4b-it","messages":[{"role":"user","content":"你好，请用一句话介绍你自己"}]}'
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(curlCommand, forType: .string)
        withAnimation {
            copyBanner = "cURL 指令已复制到剪贴板！"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                copyBanner = nil
            }
        }
    }
}

