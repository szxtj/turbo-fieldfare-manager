import SwiftUI
import AppKit

public final class SettingsWindowController: NSWindowController {
    public static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = LocalizationManager.shared.tr("TurboFieldfare Settings", "TurboFieldfare 服务偏好设置")
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
        self.window?.title = LocalizationManager.shared.tr("TurboFieldfare Settings", "TurboFieldfare 服务偏好设置")
        self.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window?.makeKeyAndOrderFront(nil)
    }
}

public struct SettingsView: View {
    @ObservedObject var manager = ServiceManager.shared
    @ObservedObject var l10n = LocalizationManager.shared

    @State private var draftConfig: ServerConfiguration = .default
    @State private var portString: String = "1235"
    @State private var showSaveSuccess: Bool = false
    @State private var saveNoticeMessage: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部导航标题
            headerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - 表单配置区域
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generalAndLanguageSection
                    Divider()
                    networkSection
                    Divider()
                    moeAndCacheSection
                    Divider()
                    accelerationAndVisionSection
                }
                .padding(24)
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // MARK: - 底部操作栏
            footerBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 660, height: 720)
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
                Text(l10n.tr("Service Configuration & Performance", "服务运行与性能参数设置"))
                    .font(.system(size: 15, weight: .bold))
                Text(l10n.tr("Settings persist automatically. Restart the service to apply changes immediately.", "修改后将自动持久化，支持热重启推理服务以立即应用新参数。"))
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

    // MARK: - 0. 通用与语言设置
    private var generalAndLanguageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.tr("General & Language", "通用与语言"), systemImage: "globe")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text(l10n.tr("Interface Language:", "界面语言:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $l10n.language) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 320)
                        Text(l10n.tr("Follows system preferences or switches immediately across all windows.", "自动跟随 macOS 系统语言或手动指定，切换后所有窗口即刻生效。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 1. 网络与基础配置
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.tr("Network & Core", "网络与基础"), systemImage: "network")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text(l10n.tr("Port:", "监听端口:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("1235", text: $portString)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 140)
                            .onChange(of: portString) { newValue in
                                if let p = Int(newValue), (1024...65535).contains(p) {
                                    draftConfig.port = p
                                }
                            }
                        Text(l10n.tr("Default: 1235 (Local OpenAI-compatible API endpoint)", "默认: 1235 (本地 OpenAI 兼容 API 入口)"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Max Context:", "最大上下文:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.maxContext) {
                            Text(l10n.tr("4,096 (4K) - Ultra-low memory", "4,096 (4K) - 极低显存")).tag(4096)
                            Text(l10n.tr("8,192 (8K) - Lightweight", "8,192 (8K) - 轻量日常")).tag(8192)
                            Text(l10n.tr("16,384 (16K) - Upstream default", "16,384 (16K) - 官方默认")).tag(16384)
                            Text(l10n.tr("32,768 (32K) - Recommended (Docs & Vision)", "32,768 (32K) - 推荐，适合长文与图文")).tag(32768)
                            Text(l10n.tr("65,536 (64K) - Maximum context", "65,536 (64K) - 极限超长上下文")).tag(65536)
                        }
                        .labelsHidden()
                        .frame(width: 340)
                        Text(l10n.tr("Larger context windows increase unified memory consumption. 32K is recommended.", "增大上下文会相应提升显存/统一内存消耗，推荐 32K。"))
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
            Label(l10n.tr("MoE Expert Cache & Memory", "MoE 专家与显存缓存"), systemImage: "memorychip")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text(l10n.tr("Cache Slots:", "专家缓存槽位:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.expertCacheSlots) {
                            Text(l10n.tr("8 Slots (~1 GB RAM, minimal footprint)", "8 槽位 (~1GB 显存，极低资源)")).tag(8)
                            Text(l10n.tr("16 Slots (~2 GB RAM, upstream default)", "16 槽位 (~2GB 显存，官方默认)")).tag(16)
                            Text(l10n.tr("24 Slots (~3.5 GB RAM, recommended)", "24 槽位 (~3.5GB 显存，推荐，高命中率)")).tag(24)
                            Text(l10n.tr("32 Slots (~4.5 GB RAM, maximum cache)", "32 槽位 (~4.5GB 显存，最大缓存，最少磁盘 I/O)")).tag(32)
                        }
                        .labelsHidden()
                        .frame(width: 360)
                        Text(l10n.tr("Higher slot counts keep more routed experts resident in memory, slashing disk I/O.", "槽位越多，推理时从磁盘读取权重的延迟越低，大幅加速输出。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Eviction Policy:", "缓存淘汰策略:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.expertCachePolicy) {
                            Text(l10n.tr("LFU (Least Frequently Used - Recommended)", "LFU (最不常使用 - 推荐)")).tag("lfu")
                            Text(l10n.tr("LRU (Least Recently Used)", "LRU (最近最少使用)")).tag("lru")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 380)
                        Text(l10n.tr("Upstream recommendation: LFU maintains higher cache hit rates for routed experts.", "官方默认与推荐算法为 LFU，能维持更高的专家命中率。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Prompt Cache:", "Prompt 缓存复用:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.promptCacheMode) {
                            Text(l10n.tr("single-prefix (Prefix Reuse)", "single-prefix (单前缀复用)")).tag("single-prefix")
                            Text(l10n.tr("off (Disabled)", "off (关闭)")).tag("off")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 320)
                        Text(l10n.tr("Reuses KV cache across turns with identical prefixes to slash TTFT.", "复用系统/多轮前缀 KV 缓存，显著降低首字延迟 (TTFT)。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 3. 预热加速与多模态视觉
    private var accelerationAndVisionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.tr("Prompt Acceleration & Vision Companion", "预热加速与多模态视觉"), systemImage: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text(l10n.tr("Chunked Prefill:", "分块 Prefill 预热:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.prefill) {
                            Text(l10n.tr("Enabled (Recommended)", "开启 (推荐)")).tag("on")
                            Text(l10n.tr("Disabled", "关闭")).tag("off")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 240)
                        Text(l10n.tr("Significantly improves throughput when processing long prompts and large images.", "显著提高长 Prompt 与大图片初次输入的处理吞吐量。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Chunk Size:", "预热分块大小:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.prefillChunkTokens) {
                            Text(l10n.tr("auto (Capped at 256, optimal)", "auto (上限 256 最佳)")).tag("auto")
                            Text("256").tag("256")
                            Text("128").tag("128")
                            Text("64").tag("64")
                            Text("32").tag("32")
                        }
                        .labelsHidden()
                        .frame(width: 260)
                        Text(l10n.tr("Auto runs at 256: boosts prefill speed by ~16% with only ~16 MB RAM overhead.", "auto 自动运行在 256 规格，提速 ~16%，仅多占 ~16MB 显存。"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GridRow {
                    Text(l10n.tr("Vision Residency:", "视觉伴侣驻留:"))
                        .font(.subheadline)
                        .gridColumnAlignment(.trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $draftConfig.visionResidency) {
                            Text(l10n.tr("on-demand (Load on demand, recommended)", "on-demand (按需加载，日常推荐)")).tag("on-demand")
                            Text(l10n.tr("keep-ready (Always resident in memory)", "keep-ready (始终常驻显存)")).tag("keep-ready")
                        }
                        .labelsHidden()
                        .frame(width: 320)
                        Text(l10n.tr("On-demand loads vision expert weights only during image requests, freeing RAM afterward.", "on-demand 仅在输入图片时调入视觉专家，结束后释放，节省内存。"))
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
            Button(l10n.tr("Restore Defaults", "恢复默认配置")) {
                restoreDefaults()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.subheadline)

            Spacer()

            if manager.state.isRunning {
                Button(l10n.tr("Save & Restart Service", "保存并重启服务")) {
                    saveAndRestart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            Button(l10n.tr("Save", "保存")) {
                saveOnly()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - 操作逻辑
    private func restoreDefaults() {
        self.draftConfig = .default
        self.portString = "\(ServerConfiguration.default.port)"
        saveOnly(message: l10n.tr("Restored upstream default settings!", "已重置为官方推荐默认参数并保存！"))
    }

    private func saveOnly(message: String? = nil) {
        if let p = Int(portString), (1024...65535).contains(p) {
            draftConfig.port = p
        }
        manager.applyConfiguration(draftConfig, restartIfRunning: false)
        notifySaved(message: message ?? l10n.tr("✅ Settings saved successfully!", "✅ 配置已成功保存！"))
    }

    private func saveAndRestart() {
        if let p = Int(portString), (1024...65535).contains(p) {
            draftConfig.port = p
        }
        manager.applyConfiguration(draftConfig, restartIfRunning: true)
        notifySaved(message: l10n.tr("🚀 Saved! Service is restarting with new parameters...", "🚀 配置已保存，服务正在以新参数重启..."))
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
