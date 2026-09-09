import AppKit
import SwiftUI
import Combine

@MainActor
public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var cancellables = Set<AnyCancellable>()
    private let manager = ServiceManager.shared
    private let l10n = LocalizationManager.shared

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

        l10n.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIconAndMenu()
            }
            .store(in: &cancellables)
    }

    private func updateIconAndMenu() {
        guard let button = statusItem.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        switch manager.state {
        case .running:
            if let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Running")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.title = " TF"
            button.toolTip = l10n.tr(
                "TurboFieldfare: Running (Port: \(manager.port))",
                "TurboFieldfare: 运行中 (端口: \(manager.port))"
            )
        case .starting:
            if let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Starting")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.title = " ..."
            button.toolTip = l10n.tr(
                "TurboFieldfare: Starting up / Initializing...",
                "TurboFieldfare: 正在启动/初始化..."
            )
        case .stopped:
            if let image = NSImage(systemSymbolName: "bolt.slash", accessibilityDescription: "Stopped")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.title = ""
            button.toolTip = l10n.tr(
                "TurboFieldfare: Service stopped",
                "TurboFieldfare: 服务已停止"
            )
        case .missingRepo:
            if let image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Missing Repo")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.title = " !"
            button.toolTip = l10n.tr(
                "TurboFieldfare: Missing upstream repo (~/turbo-fieldfare)",
                "TurboFieldfare: 未找到本体仓库 (~/turbo-fieldfare)"
            )
        case .error(let msg):
            if let image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Error")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
            button.title = ""
            button.toolTip = l10n.tr(
                "TurboFieldfare Error: \(msg)",
                "TurboFieldfare 异常: \(msg)"
            )
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
            statusText = "🟢 " + l10n.tr("Status: Running (PID: \(pid), Port: \(port))", "状态: 运行中 (PID: \(pid), 端口: \(port))")
        case .starting:
            statusText = "🟡 " + l10n.tr("Status: Initializing / Loading weights...", "状态: 正在初始化 / 加载中...")
        case .stopped:
            statusText = "🔴 " + l10n.tr("Status: Stopped", "状态: 已停止")
        case .missingRepo:
            statusText = "⚠️ " + l10n.tr("Status: Missing upstream repo (~/turbo-fieldfare)", "状态: 未找到本体仓库 (~/turbo-fieldfare)")
        case .error(let msg):
            statusText = "❌ " + l10n.tr("Error: \(msg)", "异常: \(msg)")
        }
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // 2. 故障自愈核心入口：如果服务未运行、启动失败或遇到问题，优先呈现“尝试恢复”
        if !manager.state.isRunning {
            let recoveryItem = NSMenuItem(
                title: "🛠️ " + l10n.tr("Recover Service (Re-clone / Rebuild / Safe Re-download)...", "尝试恢复服务 (重新克隆/编译/安全重下模型)..."),
                action: #selector(showRecoveryWizard),
                keyEquivalent: ""
            )
            recoveryItem.target = self
            menu.addItem(recoveryItem)

            menu.addItem(NSMenuItem.separator())
        }

        // 3. 查看服务状态与实时日志
        let showLogItem = NSMenuItem(
            title: l10n.tr("Service Status & Live Logs...", "查看服务状态与实时日志..."),
            action: #selector(showStatusAndLogWindow),
            keyEquivalent: "l"
        )
        showLogItem.target = self
        menu.addItem(showLogItem)

        let settingsItem = NSMenuItem(
            title: "⚙️ " + l10n.tr("Settings & Runtime Parameters...", "服务偏好设置与运行参数..."),
            action: #selector(showSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 4. 服务基础控制项
        if manager.state.isRunning {
            let restartItem = NSMenuItem(
                title: l10n.tr("Restart Service", "重启服务"),
                action: #selector(restartService),
                keyEquivalent: "r"
            )
            restartItem.target = self
            menu.addItem(restartItem)

            let stopItem = NSMenuItem(
                title: l10n.tr("Stop Service", "停止服务"),
                action: #selector(stopService),
                keyEquivalent: "s"
            )
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(
                title: l10n.tr("Start Service", "启动服务"),
                action: #selector(startService),
                keyEquivalent: "s"
            )
            startItem.target = self
            menu.addItem(startItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 5. 维护与自愈项
        let syncItem = NSMenuItem(
            title: l10n.tr("Check for Updates & Sync Upstream...", "检查更新与同步本体..."),
            action: #selector(checkAndSyncUpdates),
            keyEquivalent: "u"
        )
        syncItem.target = self
        menu.addItem(syncItem)

        if manager.state.isRunning {
            let advancedRecoveryItem = NSMenuItem(
                title: l10n.tr("Troubleshooting & Recovery Center...", "故障自愈与重装中心..."),
                action: #selector(showRecoveryWizard),
                keyEquivalent: ""
            )
            advancedRecoveryItem.target = self
            menu.addItem(advancedRecoveryItem)
        }

        let openRepoItem = NSMenuItem(
            title: l10n.tr("Open Upstream Folder (~/turbo-fieldfare)", "打开本体目录 (~/turbo-fieldfare)"),
            action: #selector(openRepoFolder),
            keyEquivalent: ""
        )
        openRepoItem.target = self
        menu.addItem(openRepoItem)

        let openLogItem = NSMenuItem(
            title: l10n.tr("Open Server Log File", "打开运行日志文件"),
            action: #selector(openLogFile),
            keyEquivalent: ""
        )
        openLogItem.target = self
        menu.addItem(openLogItem)

        menu.addItem(NSMenuItem.separator())

        // 6. 退出
        let quitItem = NSMenuItem(
            title: l10n.tr("Quit (Stop Inference Service)", "退出 (并停止推理服务)"),
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
                let alert = NSAlert()
                alert.messageText = l10n.tr("Missing Upstream Repository", "未检测到本体仓库")
                alert.informativeText = l10n.tr(
                    "No repository found at ~/turbo-fieldfare. Would you like to launch the setup wizard now?",
                    "主目录下未找到 ~/turbo-fieldfare 官方项目，是否立即唤起初始化向导自动克隆并编译？"
                )
                alert.addButton(withTitle: l10n.tr("Run Setup Wizard", "立即克隆初始化"))
                alert.addButton(withTitle: l10n.tr("Cancel", "取消"))
                if alert.runModal() == .alertFirstButtonReturn {
                    SetupAndRecoveryWindowController.shared.show(mode: .firstRun)
                }
                return
            }

            let alert = NSAlert()
            alert.messageText = l10n.tr("Upstream Update Check", "版本同步检测")
            if status.isUpToDate {
                alert.informativeText = l10n.tr(
                    "You are currently on the latest upstream version (\(status.localCommit)).\nWould you like to force-pull and re-compile anyway?",
                    "当前已是官方最新主线版本 (\(status.localCommit))。\n是否仍然强制重新同步代码并重新编译？"
                )
            } else {
                alert.informativeText = l10n.tr(
                    "New upstream commits detected!\nLocal: \(status.localCommit)\nRemote: \(status.remoteCommit)\nPull and re-compile now?",
                    "检测到官方主线有新提交！\n本地: \(status.localCommit)\n远端: \(status.remoteCommit)\n是否立即拉取并重新编译？"
                )
            }
            alert.addButton(withTitle: l10n.tr("Sync & Recompile", "拉取并重新编译"))
            alert.addButton(withTitle: l10n.tr("Cancel", "取消"))

            if alert.runModal() == .alertFirstButtonReturn {
                SetupAndRecoveryWindowController.shared.show(mode: .recovery)
            }
        }
    }

    @objc private func quitApp() {
        manager.stopService()
        NSApp.terminate(nil)
    }
}
