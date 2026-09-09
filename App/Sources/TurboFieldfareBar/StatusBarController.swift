import AppKit
import SwiftUI
import Combine

@MainActor
public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var cancellables = Set<AnyCancellable>()
    private let manager = ServiceManager.shared

    public override init() {
        super.init()
        setupStatusItem()
        bindServiceState()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIconAndMenu()
    }

    private func bindServiceState() {
        manager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIconAndMenu()
            }
            .store(in: &cancellables)
    }

    private func updateIconAndMenu() {
        guard let button = statusItem.button else { return }

        // 设置状态栏图标与标题
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        switch manager.state {
        case .running:
            if let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Running")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.title = " TF"
            button.toolTip = "TurboFieldfare: 运行中 (端口: \(manager.port))"
        case .starting:
            if let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Starting")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.title = " ..."
            button.toolTip = "TurboFieldfare: 正在启动/初始化..."
        case .stopped:
            if let image = NSImage(systemSymbolName: "bolt.slash", accessibilityDescription: "Stopped")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.title = ""
            button.toolTip = "TurboFieldfare: 服务已停止"
        case .missingRepo:
            if let image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Missing Repo")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.title = " !"
            button.toolTip = "TurboFieldfare: 未找到本体仓库 (~/turbo-fieldfare)"
        case .error(let msg):
            if let image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Error")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.title = ""
            button.toolTip = "TurboFieldfare 异常: \(msg)"
        }
    }

    // MARK: - NSMenuDelegate 动态渲染菜单

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. 标题头
        let titleItem = NSMenuItem(title: "TurboFieldfare Manager", action: nil, keyEquivalent: "")
        titleItem.attributedTitle = NSAttributedString(
            string: "TurboFieldfare Manager",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(titleItem)

        // 状态说明
        let statusText: String
        switch manager.state {
        case .running(let pid, let port):
            statusText = "🟢 状态: 运行中 (PID: \(pid), 端口: \(port))"
        case .starting:
            statusText = "🟡 状态: 正在初始化 / 加载中..."
        case .stopped:
            statusText = "🔴 状态: 已停止"
        case .missingRepo:
            statusText = "⚠️ 状态: 未找到本体仓库 (~/turbo-fieldfare)"
        case .error(let msg):
            statusText = "❌ 异常: \(msg)"
        }
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // 2. 查看服务状态与实时日志
        // 2. 故障自愈核心入口：如果服务未运行、启动失败或遇到问题，优先呈现“尝试恢复”
        if !manager.state.isRunning {
            let recoveryItem = NSMenuItem(
                title: "🛠️ 尝试恢复服务 (重新克隆/编译/安全重下模型)...",
                action: #selector(showRecoveryWizard),
                keyEquivalent: ""
            )
            recoveryItem.target = self
            menu.addItem(recoveryItem)

            menu.addItem(NSMenuItem.separator())
        }

        // 3. 查看服务状态与实时日志
        let showLogItem = NSMenuItem(
            title: "查看服务状态与实时日志...",
            action: #selector(showStatusAndLogWindow),
            keyEquivalent: "l"
        )
        showLogItem.target = self
        menu.addItem(showLogItem)

        let settingsItem = NSMenuItem(
            title: "⚙️ 服务偏好设置与运行参数...",
            action: #selector(showSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 3. 服务控制项
        // 4. 服务基础控制项
        if manager.state.isRunning {
            let restartItem = NSMenuItem(
                title: "重启服务",
                action: #selector(restartService),
                keyEquivalent: "r"
            )
            restartItem.target = self
            menu.addItem(restartItem)

            let stopItem = NSMenuItem(
                title: "停止服务",
                action: #selector(stopService),
                keyEquivalent: "s"
            )
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(
                title: "启动服务",
                action: #selector(startService),
                keyEquivalent: "s"
            )
            startItem.target = self
            menu.addItem(startItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 4. 辅助与快捷入口
        // 5. 维护与自愈项
        let syncItem = NSMenuItem(
            title: "检查更新与同步本体...",
            action: #selector(checkAndSyncUpdates),
            keyEquivalent: "u"
        )
        syncItem.target = self
        menu.addItem(syncItem)

        if manager.state.isRunning {
            let advancedRecoveryItem = NSMenuItem(
                title: "故障自愈与重装中心...",
                action: #selector(showRecoveryWizard),
                keyEquivalent: ""
            )
            advancedRecoveryItem.target = self
            menu.addItem(advancedRecoveryItem)
        }

        let openRepoItem = NSMenuItem(
            title: "打开本体目录 (~/turbo-fieldfare)",
            action: #selector(openRepoFolder),
            keyEquivalent: ""
        )
        openRepoItem.target = self
        menu.addItem(openRepoItem)

        let openLogItem = NSMenuItem(
            title: "打开运行日志文件",
            action: #selector(openLogFile),
            keyEquivalent: ""
        )
        openLogItem.target = self
        menu.addItem(openLogItem)

        menu.addItem(NSMenuItem.separator())

        // 5. 退出
        // 6. 退出
        let quitItem = NSMenuItem(
            title: "退出 (并停止推理服务)",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func showStatusAndLogWindow() {
        StatusAndLogWindowController.shared.showAndActivate()
    }

    @objc private func showSettingsWindow() {
        SettingsWindowController.shared.showAndActivate()
    }

    @objc private func showRecoveryWizard() {
        SetupAndRecoveryWindowController.shared.show(mode: .recovery)
    }

    @objc private func startService() {
        manager.startService()
    }

    @objc private func stopService() {
        manager.stopService()
    }

    @objc private func restartService() {
        manager.restartService()
    }

    @objc private func openRepoFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: manager.repoDir.path)
    }

    @objc private func openLogFile() {
        NSWorkspace.shared.activateFileViewerSelecting([manager.logFile])
    }

    @objc private func checkAndSyncUpdates() {
        StatusAndLogWindowController.shared.showAndActivate()
        Task {
            let status = await manager.checkRepoStatus()
            if !status.exists {
                SetupAndRecoveryWindowController.shared.show(mode: .firstRun)
            } else if !status.isUpToDate {
                let alert = NSAlert()
                alert.messageText = "发现官方最新版本更新"
                alert.informativeText = "\(status.message)\n\n是否立即拉取更新并自动重新编译？"
                alert.addButton(withTitle: "立即同步并编译")
                alert.addButton(withTitle: "稍后")
                if alert.runModal() == .alertFirstButtonReturn {
                    await manager.syncToLatest { msg in
                        print(msg)
                    }
                }
            } else {
                let alert = NSAlert()
                alert.messageText = "已是最新版本"
                alert.informativeText = "当前本地版本 (\(status.localCommit)) 与官方 upstream 完全一致，无需更新。"
                alert.addButton(withTitle: "好的")
                alert.runModal()
            }
        }
    }

    @objc private func quitApp() {
        // 用户明确要求：退出时连同推理服务一起停止
        manager.stopService()
        NSApp.terminate(nil)
    }
}
