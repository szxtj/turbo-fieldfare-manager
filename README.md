# TurboFieldfare Manager & MenuBar App

专为 [TurboFieldfare (Gemma 4 26B-A4B)](https://github.com/drumih/turbo-fieldfare) 打造的原生 macOS 状态栏管理应用与后台运维工具集。

---

## 🌟 项目架构设计

本项目遵循 **“本体独立纯粹，管理外置解耦”** 的设计哲学：

1. **官方本体目录 (`~/turbo-fieldfare`)**：
   - 完整放置在用户主目录 `~/turbo-fieldfare` 中，与官方代码库 100% 保持一致，无任何污染；
   - 包含完整的 15GB+ 模型权重（`scratch/gemma4.gturbo` 及视觉伴侣包）与编译产物；
   - 可随时执行 `git pull` 同步官方最新更新。

2. **管理与状态栏工具 (`turbo-fieldfare-manager`)**：
   - **`TurboFieldfareBar.app`**：轻量级原生 macOS 状态栏 App（基于 Swift / AppKit + SwiftUI）；
   - **`server.sh`**：增强型命令行服务管理与健康探测脚本；
   - **自动化跨设备环境适配**：在新 Mac 上首次启动可自动一键克隆本体仓库并完成初始配置。

---

## 🚀 核心特性

### 1. `TurboFieldfareBar.app` (状态栏管理应用)

- **无 Dock、无冗余主窗口**：作为 macOS Accessory 模式运行，直接常驻系统右上角菜单栏；
- **状态指示图标**：
  - 🟢 **常亮/闪耀**：服务正常运行中且 HTTP 健康检查通过；
  - 🟡 **转圈动画**：服务正在后台启动或加载权重中；
  - 🔴 **暂停/斜线**：服务已停止；
  - ⚠️ **警告标志**：未找到本体仓库或环境异常；
- **实用功能菜单**：
  - 📊 **服务状态与实时日志窗口**：点击弹出小巧精致的状态面板，包含实时滚动日志（支持自动跟随、清空日志、复制测试 cURL 指令）；
  - 🔄 **一键重启服务**；
  - 🛑 **停止 / 启动服务**；
  - 🌐 **检查更新并一键同步官方本体**；
  - 📂 **快捷打开本体目录 (`~/turbo-fieldfare`) 与运行日志**；
  - ❌ **退出应用（自动协同关闭后台推理服务）**。

### 2. `server.sh` (命令行运维脚本)

如果更喜欢在终端中使用命令行：

```bash
./server.sh start    # 启动后台服务 (自动进行模型存在性检查与健康探测)
./server.sh stop     # 优雅停止服务 (带 5s 超时保护与残留清理)
./server.sh restart  # 重启服务
./server.sh status   # 查看运行状态与 HTTP 200 健康指标
./server.sh logs     # 查看实时运行日志 (tail -f)
./server.sh help     # 查看帮助信息
```

---

## 🛠️ 构建与安装

1. **编译并打包 macOS 应用**：

   ```bash
   ./build_app.sh
   ```

   打包完成后会在根目录生成 `TurboFieldfareBar.app`。

2. **安装使用**：
   - 可以直接双击运行当前目录下的 `TurboFieldfareBar.app`；
   - 或者拖拽到系统 `/Applications` (应用程序) 文件夹中，随时在 Spotlight 中启动。

---

## ⚙️ 默认推荐配置

服务启动脚本采用当前版本最高能效的优化组合：

- **监听端口**：`1235` (API Base: `http://127.0.0.1:1235/v1`)
- **上下文容量**：`32768` (32K Tokens)
- **专家缓存槽位**：`24` (LFU 策略，平衡内存占用与高命中率)
- **Prefill 分块**：`auto` (在 v0.7.2+ 下自动解析为 256 分块，长文本 Prompt 预填充速度提升 ~16%)
- **视觉常驻策略**：`on-demand`
- **KV 缓存复用**：`single-prefix`
