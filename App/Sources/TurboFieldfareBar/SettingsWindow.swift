import SwiftUI
import AppKit

public final class SettingsWindowController: NSWindowController {
    public static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TurboFieldfare 服务偏好设置"
        window.center()
        window.setFrameAutosaveName("TurboFieldfareSettingsWindow")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())

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

public struct SettingsView: View {
    @ObservedObject var manager = ServiceManager.shared

    @State private var draftConfig: ServerConfiguration = .default
    @State private var portString: String = "1235"
    @State private var showSaveSuccess: Bool = false
    @State private var saveNoticeMessage: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部导航标题
            headerBar
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - 表单配置区域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    networkSection
                    Divider()
                    moeAndCacheSection
                    Divider()
                    accelerationAndVisionSection
                }
                .padding(20)
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // MARK: - 底部操作栏
            footerBar
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 620, height: 620)
        .onAppear {
            loadCurrentConfig()
        }
    }

    private func loadCurrentConfig() {
        self.draftConfig = manager.config
        self.portString = "\(manager.config.port)"
    }

    // MARK: - 顶部标题与提示
    private var headerBar: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("服务运行与性能参数设置")
                    .font(.system(size: 15, weight: .bold))
                Text("修改后将自动持久化，支持热重启推理服务以立即应用新参数。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if showSaveSuccess {
                Text(saveNoticeMessage)
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - 1. 网络与基础配置
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("网络与基础", systemImage: "network")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("监听端口:")
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    HStack {
                        TextField("端口号 (1024-65535)", text: $portString)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                            .onChange(of: portString) { newValue in
                                if let p = Int(newValue), (1024...65535).contains(p) {
                                    draftConfig.port = p
                                }
                            }
                        Text("默认: 1235 (本地 OpenAI 兼容 API 入口)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text("最大上下文:")
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.maxContext) {
                            Text("4,096 (4K) - 极低显存").tag(4096)
                            Text("8,192 (8K) - 轻量日常").tag(8192)
                            Text("16,384 (16K) - 平衡推荐").tag(16384)
                            Text("32,768 (32K) - 推荐，适合长文与图文").tag(32768)
                            Text("65,536 (64K) - 极限超长上下文").tag(65536)
                        }
                        .labelsHidden()
                        .frame(width: 280)
                        Text("增大上下文会相应提升显存/统一内存消耗，推荐 32K。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 2. MoE 专家与缓存策略
    private var moeAndCacheSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("MoE 专家与显存缓存", systemImage: "memorychip")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("专家缓存槽位:")
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.expertCacheSlots) {
                            Text("8 槽位 (~1GB 显存，极低资源)").tag(8)
                            Text("16 槽位 (~2GB 显存，官方默认)").tag(16)
                            Text("24 槽位 (~3.5GB 显存，推荐，高命中率)").tag(24)
                            Text("32 槽位 (~4.5GB 显存，最大缓存，最少磁盘 I/O)").tag(32)
                        }
                        .labelsHidden()
                        .frame(width: 320)
                        Text("槽位越多，推理时从磁盘读取权重的延迟越低，大幅加速输出。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text("缓存淘汰策略:")
                        .font(.subheadline)
                    HStack {
                        Picker("", selection: $draftConfig.expertCachePolicy) {
                            Text("LFU (最不常使用 - 推荐)").tag("lfu")
                            Text("LRU (最近最少使用)").tag("lru")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 240)
                        Text("官方默认与推荐算法为 LFU")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text("Prompt 缓存复用:")
                        .font(.subheadline)
                    HStack {
                        Picker("", selection: $draftConfig.promptCacheMode) {
                            Text("single-prefix (单前缀复用)").tag("single-prefix")
                            Text("off (关闭)").tag("off")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 240)
                        Text("复用系统/多轮前缀 KV 缓存，显著降低 TTFT")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 3. 预热加速与多模态视觉
    private var accelerationAndVisionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("预热加速与多模态视觉", systemImage: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("分块 Prefill 预热:")
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    HStack {
                        Picker("", selection: $draftConfig.prefill) {
                            Text("开启 (推荐)").tag("on")
                            Text("关闭").tag("off")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 160)
                        Text("显著提高长 Prompt 与大图片初次输入的处理吞吐量")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text("预热分块大小:")
                        .font(.subheadline)
                    HStack {
                        Picker("", selection: $draftConfig.prefillChunkTokens) {
                            Text("auto (上限 256 最佳)").tag("auto")
                            Text("256").tag("256")
                            Text("128").tag("128")
                            Text("64").tag("64")
                            Text("32").tag("32")
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        Text("auto 自动运行在 256 规格，提速 ~16%，仅多占 ~16MB 显存")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text("视觉伴侣驻留:")
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.visionResidency) {
                            Text("on-demand (按需加载，日常推荐)").tag("on-demand")
                            Text("keep-ready (始终常驻显存)").tag("keep-ready")
                        }
                        .labelsHidden()
                        .frame(width: 260)
                        Text("on-demand 仅在输入图片时调入视觉专家，结束后释放，节省内存。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 底部操作栏
    private var footerBar: some View {
        HStack(spacing: 12) {
            Button("恢复默认配置") {
                restoreDefaults()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.subheadline)

            Spacer()

            if manager.state.isRunning {
                Button("保存并重启服务") {
                    saveAndRestart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Button("保存") {
                saveOnly()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - 操作逻辑
    private func restoreDefaults() {
        self.draftConfig = .default
        self.portString = "\(ServerConfiguration.default.port)"
        saveOnly(message: "已重置为官方推荐默认参数并保存！")
    }

    private func saveOnly(message: String = "✅ 配置已成功保存！") {
        if let p = Int(portString), (1024...65535).contains(p) {
            draftConfig.port = p
        }
        manager.applyConfiguration(draftConfig, restartIfRunning: false)
        notifySaved(message: message)
    }

    private func saveAndRestart() {
        if let p = Int(portString), (1024...65535).contains(p) {
            draftConfig.port = p
        }
        manager.applyConfiguration(draftConfig, restartIfRunning: true)
        notifySaved(message: "🚀 配置已保存，服务正在以新参数重启...")
    }

    private func notifySaved(message: String) {
        self.saveNoticeMessage = message
        withAnimation {
            self.showSaveSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                self.showSaveSuccess = false
            }
        }
    }
}
