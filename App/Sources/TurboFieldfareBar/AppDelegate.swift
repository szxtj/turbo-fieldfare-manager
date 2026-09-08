import AppKit
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let manager = ServiceManager.shared

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化状态栏图标控制器
        statusBarController = StatusBarController()

        // 初次启动与环境校验
        Task { @MainActor in
            await performStartupCheck()
        }
    }

    private func performStartupCheck() async {
        let repoStatus = await manager.checkRepoStatus()

        if !repoStatus.exists {
            // 新 Mac 环境：未在 ~/turbo-fieldfare 发现本体
            let alert = NSAlert()
            alert.messageText = "欢迎使用 TurboFieldfare Manager"
            alert.informativeText = "检测到这是首次运行或新 Mac 环境，主目录下尚未找到 TurboFieldfare 本体 (~/turbo-fieldfare)。\n\n是否立即从官方源一键克隆本体并完成初始化配置？"
            alert.addButton(withTitle: "一键克隆官方本体")
            alert.addButton(withTitle: "稍后手动配置")
            alert.alertStyle = .informational

            if alert.runModal() == .alertFirstButtonReturn {
                StatusAndLogWindowController.shared.showAndActivate()
                do {
                    try await manager.cloneOfficialRepo { msg in
                        print(msg)
                    }
                    // 克隆完成后拉起服务
                    manager.startService()
                } catch {
                    let errAlert = NSAlert()
                    errAlert.messageText = "克隆或构建失败"
                    errAlert.informativeText = error.localizedDescription
                    errAlert.alertStyle = .critical
                    errAlert.runModal()
                }
            }
        } else {
            // 本体存在：检查是否与最新版本一致
            if repoStatus.isUpToDate {
                // 完全一致：直接启动服务
                if !manager.state.isRunning {
                    manager.startService()
                }
            } else {
                // 发现更新：可提示用户或启动服务
                // 默认策略：直接启动现有可用服务，并在菜单中保留更新提示
                if !manager.state.isRunning {
                    manager.startService()
                }
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // 退出时连同推理服务一起停止
        manager.stopService()
    }
}
