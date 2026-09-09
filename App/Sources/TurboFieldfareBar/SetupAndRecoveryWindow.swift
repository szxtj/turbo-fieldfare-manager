import SwiftUI
import AppKit

public enum WizardMode {
    case firstRun
    case recovery
}

public final class SetupAndRecoveryWindowController: NSWindowController {
    public static let shared = SetupAndRecoveryWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("TurboFieldfareSetupAndRecoveryWindow")

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(mode: WizardMode) {
        let l10n = LocalizationManager.shared
        self.window?.title = (mode == .firstRun)
            ? l10n.tr("Welcome to TurboFieldfare (First-Run Setup)", "欢迎使用 TurboFieldfare (首次环境初始化)")
            : l10n.tr("TurboFieldfare Troubleshooting & Recovery", "TurboFieldfare 服务故障恢复中心")

        let view = SetupAndRecoveryView(mode: mode, onDismiss: { [weak self] in
            self?.window?.close()
        })
        self.window?.contentView = NSHostingView(rootView: view)
        self.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window?.makeKeyAndOrderFront(nil)
    }
}

public struct SetupAndRecoveryView: View {
    public let mode: WizardMode
    public let onDismiss: () -> Void

    @ObservedObject private var manager = ServiceManager.shared
    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var isRunningTask: Bool = false
    @State private var taskFinished: Bool = false
    @State private var consoleOutput: [String] = []
    @State private var currentStepIndex: Int = 0
    @State private var errorMessage: String? = nil

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部标题与说明区
            headerView
                .padding(20)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - 步骤概览与安全提示
            stepsOverview
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // MARK: - 实时运行控制台
            consoleSection

            Divider()

            // MARK: - 底部按钮操作栏
            bottomActionBar
                .padding(16)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 660, minHeight: 540)
    }

    // MARK: - 顶部 Header
    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: mode == .firstRun ? "sparkles.rectangle.stack.fill" : "wrench.and.screwdriver.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundColor(mode == .firstRun ? .accentColor : .orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .firstRun
                     ? l10n.tr("New Mac Setup Wizard", "TurboFieldfare 新设备初始化向导")
                     : l10n.tr("Service Troubleshooting & Recovery", "TurboFieldfare 服务故障自愈与恢复"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(mode == .firstRun
                     ? l10n.tr("One-click setup on a new Mac: clones upstream repo, compiles the server, and downloads Gemma 4 model weights.", "在新的 Mac 上一键克隆官方代码、编译推理服务并自动下载 Gemma 4 模型权重。")
                     : l10n.tr("Safely recovers the runtime environment when files are damaged, corrupted, or the service fails to launch.", "当服务因文件缺失、损坏或环境异常启动失败时，一键安全自愈恢复运行环境。"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - 步骤与安全说明
    private var stepsOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mode == .recovery {
                // 安全提示 Banner
                HStack(spacing: 10) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)

                    Text(l10n.tr(
                        "Safe Recovery: Before re-downloading, existing model files are moved to the macOS Trash (~/.Trash) rather than permanently deleted.",
                        "安全回收机制：重新下载前，原模型文件夹将被安全移入「macOS 系统废纸篓」，绝不直接强删，随时可在废纸篓中查找和恢复。"
                    ))
                    .font(.caption)
                    .foregroundColor(.primary)
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            Text(l10n.tr("Automated Pipeline Steps:", "执行流程与自动化检查:"))
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 16) {
                stepItem(
                    index: 1,
                    title: l10n.tr("Upstream Repo", "官方本体仓库"),
                    subtitle: mode == .firstRun
                        ? l10n.tr("Clone to ~/turbo-fieldfare", "克隆到 ~/turbo-fieldfare")
                        : l10n.tr("Sync latest main branch", "拉取对齐官方最新代码")
                )
                stepItem(
                    index: 2,
                    title: l10n.tr("Compile Binary", "编译二进制"),
                    subtitle: l10n.tr("Build TurboFieldfareServer", "构建 TurboFieldfareServer")
                )
                stepItem(
                    index: 3,
                    title: l10n.tr("Model Weights", "下载模型权重"),
                    subtitle: l10n.tr("~14.3GB with resume support", "约 14.3GB，支持断点续传")
                )
                stepItem(
                    index: 4,
                    title: l10n.tr("Launch & Verify", "启动并就绪"),
                    subtitle: l10n.tr("Health probe HTTP 200", "健康检查并常驻状态栏")
                )
            }
        }
    }

    private func stepItem(index: Int, title: String, subtitle: String) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 20, height: 20)
                Text("\(index)")
                    .font(.system(size: 11, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 控制台输出
    private var consoleSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if consoleOutput.isEmpty {
                        Text(mode == .firstRun
                             ? l10n.tr("Ready. Click 'Start Setup' below to begin cloning, building, and downloading weights.", "等待开始... 点击下方「开始一键初始化」按钮，将自动执行克隆、编译与模型下载。")
                             : l10n.tr("Ready. Click 'Start Recovery' below to inspect, trash damaged files, and restore the service.", "等待开始... 点击下方「开始故障恢复」按钮，将自动排查、安全移入废纸篓并重新构建环境。"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(14)
                    } else {
                        ForEach(Array(consoleOutput.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(colorForConsoleLine(line))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.12))
            .onChange(of: consoleOutput.count) { _ in
                if !consoleOutput.isEmpty {
                    withAnimation {
                        proxy.scrollTo(consoleOutput.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - 底部操作栏
    private var bottomActionBar: some View {
        HStack {
            if let err = errorMessage {
                Text("⚠️ \(err)")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            if taskFinished {
                Button(action: onDismiss) {
                    Text(l10n.tr("Finish & Dock to Menu Bar", "完成并进入状态栏"))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else if isRunningTask {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(l10n.tr("Running pipeline, please keep this window open...", "正在执行初始化中，请勿关闭窗口..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(l10n.tr("Cancel", "取消")) {
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Button(action: startPipeline) {
                    Text(mode == .firstRun
                         ? ("🚀 " + l10n.tr("Start Setup", "开始一键初始化"))
                         : ("🛠️ " + l10n.tr("Start Recovery", "开始安全故障恢复")))
                }
                .buttonStyle(.borderedProminent)
                .tint(mode == .firstRun ? .accentColor : .orange)
            }
        }
    }

    // MARK: - 逻辑执行
    private func startPipeline() {
        isRunningTask = true
        errorMessage = nil
        consoleOutput.removeAll()

        Task {
            do {
                if mode == .firstRun {
                    try await manager.runInitialSetup { output in
                        appendOutput(output)
                    }
                } else {
                    try await manager.runFullRecovery { output in
                        appendOutput(output)
                    }
                }
                isRunningTask = false
                taskFinished = true
            } catch {
                isRunningTask = false
                errorMessage = error.localizedDescription
                appendOutput("❌ " + l10n.tr("Interrupted: \(error.localizedDescription)\n", "流程中断: \(error.localizedDescription)\n"))
            }
        }
    }

    private func appendOutput(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                consoleOutput.append(line)
            }
        }
    }

    private func colorForConsoleLine(_ line: String) -> Color {
        if line.contains("❌") || line.contains("error") || line.contains("Error") {
            return .red
        }
        if line.contains("✅") || line.contains("🎉") {
            return .green
        }
        if line.contains("⚠️") || line.contains("💡") {
            return .yellow
        }
        if line.contains("🚀") || line.contains("⚙️") || line.contains("📥") || line.contains("🗑️") {
            return .cyan
        }
        return Color(red: 0.86, green: 0.86, blue: 0.88)
    }
}
