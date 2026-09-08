import AppKit
import Foundation

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let manager = ServiceManager.shared

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 初始化状态栏图标控制器 (直接呈现状态栏图标)
        statusBarController = StatusBarController()

        // 2. 启动瞬间判断：主目录是否存在 ~/turbo-fieldfare
        let repoExists = FileManager.default.fileExists(atPath: manager.repoDir.path)

        if !repoExists {
            // 新 Mac 环境：未在 ~/turbo-fieldfare 发现本体 -> 弹出引导界面
            SetupAndRecoveryWindowController.shared.show(mode: .firstRun)
        } else {
            // 文件夹存在：坚决不显示引导窗口，静默呈现状态栏并在后台启动服务
            if !manager.state.isRunning {
                manager.startService()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // 退出时连同推理服务一起停止
        manager.stopService()
    }
}
