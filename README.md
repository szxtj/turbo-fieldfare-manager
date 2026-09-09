<p align="center">
  <img src="App/Resources/AppIcon.icns" alt="TurboFieldfareBar App Icon" width="128">
</p>

<h1 align="center">TurboFieldfareBar & Manager</h1>

<p align="center">
  <strong>Native macOS Menu Bar App & Service Manager for <a href="https://github.com/drumih/turbo-fieldfare">TurboFieldfare</a> (Gemma 4 26B-A4B)</strong><br>
  为 TurboFieldfare 打造的原生 macOS 状态栏应用与自动化运维套件
</p>

<p align="center">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&logoColor=white">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Architecture-arm64-5E5CE6">
  <img alt="License: Apache 2.0" src="https://img.shields.io/badge/License-Apache%202.0-2ea44f">
</p>

<p align="center">
  <a href="#english">English</a> · <a href="#简体中文">简体中文</a>
</p>

---

<a name="english"></a>

## English

### Overview

**TurboFieldfareBar** is an elegant, lightweight native macOS menu bar companion for [TurboFieldfare](https://github.com/drumih/turbo-fieldfare) — the breakthrough runtime that runs Google's instruction-tuned **Gemma 4 26B-A4B** multimodal model within a tight ~2 GB memory budget on Apple Silicon Macs.

This manager follows an **"Unpolluted Upstream, Decoupled Management"** architecture:

1. **Clean Upstream Repository (`~/turbo-fieldfare`)**: The official codebase remains 100% clean and pristine in the user's home directory. Upstream updates can be pulled cleanly at any time without git conflicts.
2. **Manager Tooling (`turbo-fieldfare-manager`)**: Contains the native macOS status bar app (`TurboFieldfareBar.app`), automated setup & recovery pipelines, and the robust CLI wrapper (`server.sh`).

---

### Key Features

#### 1. Silent Zero-Window Menu Bar App (`TurboFieldfareBar.app`)

- **Accessory Mode**: Runs quietly in the system status bar without cluttering the Dock or opening redundant windows.
- **Instant Silent Launch**: If `~/turbo-fieldfare` already exists, the app launches instantly with **zero intrusive windows**, docking straight to the menu bar and starting the inference backend in the background.
- **Dynamic Status Indicator**:
  - 🟢 **Sparkle / Solid**: Service running with HTTP 200 health probe passed.
  - 🟡 **Spinning Activity**: Service initializing or streaming weights.
  - 🔴 **Slash / Stopped**: Service gracefully stopped.
  - ⚠️ **Alert Triangle**: Missing repository or environment anomaly.

#### 2. Visual Settings & Performance Panel (`Cmd + ,`)

Configure runtime parameters visually without editing shell scripts:

- **Port**: Loopback port (`1024 - 65535`, default: `1235`).
- **Max Context**: 4K, 8K, 16K, 32K (Recommended), up to 64K (Maximum).
- **MoE Expert Cache**: 8 slots (~1 GB), 16 slots (~2 GB), 24 slots (~3.5 GB, recommended), or 32 slots (~4.5 GB max cache).
- **Eviction Policy**: LFU (Least Frequently Used, recommended) or LRU.
- **KV Prompt Cache**: `single-prefix` reuse mode to slash Time-to-First-Token (TTFT), or `off`.
- **Chunked Prefill**: Enabled with auto chunk size (capped at optimal 256 tokens).
- **Vision Companion Pack Residency**: `on-demand` (loads vision tower only during image requests, saving memory) or `keep-ready`.
- **Hot Restart & Sync**: Supports "Save & Restart", "Restore Defaults", and auto-exports settings to `~/Library/Application Support/TurboFieldfare/config.env` for CLI sharing.

#### 3. Setup & Self-Healing Recovery Wizard

- **First-Run Setup for New Macs**: Automatically clones upstream, compiles the release binary, and downloads the ~14.3 GB Gemma 4 model plus the ~1.1 GB vision pack with resumable downloads.
- **Fault Recovery with Trash Safety**: When models are damaged or corrupted, the wizard **safely moves existing models to the macOS Trash (`~/.Trash`)** via native APIs before re-downloading. **Never permanently deletes user data.**

#### 4. Multimodal Vision Auto-Healing

- Automatically verifies and patches path bindings in `verified-install.json` across directory relocations, eliminating the upstream `vision companion receipt is invalid: path mismatch` degradation.

#### 5. Bilingual Localization (i18n)

- Native support for idiomatic **American English** and **Simplified Chinese**.
- Automatically follows macOS system language preferences; switchable on-the-fly in Settings without restarting.

#### 6. Live Status & Log Console

- Real-time log streaming with auto-scroll, clear log button, one-click test cURL snippet copying, and Finder log viewer.

---

### System Requirements & Platform Limitations

The backend inference engine has strict hardware and OS prerequisites defined by the official TurboFieldfare project:

| Requirement          | Specification                                | Notes                                                                                                                              |
| :------------------- | :------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------- |
| **Architecture**     | **Apple Silicon (arm64)**                    | M-series Macs only. Intel x86_64 is **not supported**.                                                                             |
| **Processor**        | **Apple M1 / M2 / M3 / M4 / M5**             | M1 supports text-only inference. **M2 or newer is required for the Multimodal Vision Companion Pack**.                             |
| **Operating System** | **macOS 26+ (Darwin 26~27)** | Requires Metal 4 support. Older macOS releases are unsupported. |
| **Toolchain**        | **Xcode 26+ & Swift 6.2+**                   | Required for compiling `TurboFieldfareServer` and the repacker.                                                                    |
| **Memory (RAM)**     | **8 GB unified memory or more**              | Successfully validated on base 8 GB M2 MacBook Air.                                                                                |
| **Disk Storage**     | **~16 GB free SSD space**                    | 14.3 GB for Gemma 4 text model + 1.1 GB for image vision companion pack.                                                           |
| **Network**          | **Active Internet connection**               | Needed on first run to stream Hugging Face weights.                                                                                |

---

### Build & Packaging Guide

#### Quick Build

```bash
# Clone this manager repository
git clone https://github.com/drumih/turbo-fieldfare.git ~/turbo-fieldfare
cd ~/Projects/turbo-fieldfare-manager

# Build TurboFieldfareBar.app and package TurboFieldfareBar.dmg
./build_app.sh
```

#### Open-Source Code Signing Options

`build_app.sh` includes a deep OpenSSL X.509 Subject audit to prevent commercial/team identity leaks:

- **Default (Personal Apple ID)**: Scans local keychain, rejects any certificate with corporate/team tags (`Co.`, `Ltd`, `Inc`, `Corp`, `Team`, `Enterprise`), and signs with your personal free Apple Development certificate.
- **Pure Open-Source Ad-hoc Mode (`--adhoc`)**:
  ```bash
  ./build_app.sh --adhoc
  ```
  Applies `codesign -s -` with `TeamIdentifier=not set`. Zero personal email or company identity attached — ideal for public GitHub releases.

#### CLI Operation

```bash
./server.sh start    # Launch in background with health check
./server.sh stop     # Gracefully stop backend process
./server.sh restart  # Restart backend
./server.sh status   # Check running PID, port, context, and HTTP 200 probe
./server.sh logs     # Follow real-time server output (tail -f)
```

---

<a name="简体中文"></a>

## 简体中文

### 项目简介

**TurboFieldfareBar** 是专为 [TurboFieldfare](https://github.com/drumih/turbo-fieldfare) 打造的轻量级原生 macOS 状态栏管理应用与运维工具集。TurboFieldfare 是一款前沿的 Swift + Metal 自研推理引擎，可在仅约 2 GB 统一内存预算下流畅运行 Google 的 260 亿参数多模态大模型 **Gemma 4 26B-A4B**。

本项目遵循 **“本体纯粹独立，管理外置解耦”** 的设计理念：

1. **官方本体目录 (`~/turbo-fieldfare`)**：完整放置于用户主目录下，100% 保持官方最新纯净主线，随时可无冲突执行 `git pull` 同步；
2. **管理与状态栏工具 (`turbo-fieldfare-manager`)**：包含原生状态栏 App（`TurboFieldfareBar.app`）、跨设备一键初始化向导、安全故障恢复中心与多功能运维脚本（`server.sh`）。

---

### 核心功能

#### 1. 秒级静默启动的状态栏 App (`TurboFieldfareBar.app`)

- **纯 Accessory 辅助应用**：无冗余 Dock 图标、无强制弹出的主窗口，静默常驻系统右上角菜单栏；
- **智能分流无干扰**：只要检测到 `~/turbo-fieldfare` 存在，启动时 **100% 不弹任何窗口**，秒级进入状态栏并在后台静默拉起推理服务；
- **状态栏动态图标**：
  - 🟢 **常亮/闪耀**：服务运行中，HTTP 200 健康探测正常；
  - 🟡 **转圈动画**：服务正在后台启动或加载权重；
  - 🔴 **已停止**：服务已优雅停止；
  - ⚠️ **感叹号**：未找到本体仓库或环境异常。

#### 2. 可视化偏好设置与运行参数面板 (`Cmd + ,`)

摆脱手动修改脚本，全套参数界面可视化调节：

- **监听端口**：支持 `1024 - 65535` 自定义（默认 `1235`）；
- **最大上下文长度**：支持 4K、8K、16K、32K（推荐）、极限 64K；
- **MoE 专家缓存槽位**：可选 8 槽位（~1GB）、16 槽位（~2GB）、24 槽位（~3.5GB，推荐）、32 槽位（~4.5GB 最大缓存）；
- **缓存淘汰策略**：LFU（最不常使用，官方推荐）与 LRU；
- **Prompt KV 缓存复用**：`single-prefix` 单前缀复用（显著降低首字延迟 TTFT）或关闭；
- **分块 Prefill 预热**：支持开启并配置分块大小（`auto` 自动上限 256 tokens）；
- **视觉伴生包驻留策略**：`on-demand`（按需加载，节省显存）或 `keep-ready`（始终常驻）；
- **热重启与环境同步**：支持“保存并重启服务”、“恢复默认配置”，并自动同步生成 `config.env` 供终端脚本共享。

#### 3. 首次引导与故障自愈向导

- **新 Mac 一键引导**：自动执行官方克隆、编译 Server 二进制、下载 14.3GB 文本模型及 1.1GB 视觉伴侣包（支持流式断点续传）；
- **废纸篓安全保护自愈**：在重新下载模型前，通过 macOS 原生 API 将损坏文件**安全移入系统废纸篓 (`~/.Trash`)**，绝不执行不可逆的强删，保障数据安全。

#### 4. 多模态图像服务自愈修复

- 自动检测并校准项目迁移后 `verified-install.json` 收据中的绝对路径绑定，彻底根除官方原版在路径移动后报 `vision companion receipt is invalid` 并自动降级为纯文本的问题。

#### 5. 地道美式英语与双语动态切换 (i18n)

- 界面完整覆盖地道美式英语（American English）与简体中文；
- 默认自动跟随 macOS 系统语言环境，也可在设置面板顶栏即时手动切换，全窗口实时生效。

#### 6. 实时服务仪表盘与日志流

- 支持自动滚屏日志终端、日志清空、一键复制测试 cURL 指令及快速定位 Finder 日志文件。

---

### 系统要求与环境限制

底层推理引擎对硬件及 macOS 系统环境有明确的官方硬性要求：

| 维度           | 要求规格                                     | 说明                                                                                    |
| :------------- | :------------------------------------------- | :-------------------------------------------------------------------------------------- |
| **芯片架构**   | **Apple Silicon (arm64)**                    | 仅支持苹果 M 系列自研芯片，**不支持 Intel x86 架构**。                                  |
| **处理器型号** | **Apple M1 / M2 / M3 / M4 / M5**             | M1 仅支持纯文本推理；**多模态图像视觉包（Vision Pack）必须要求 M2 或更新的芯片**。      |
| **系统版本** | **macOS 26+ (Darwin 26~27)** | 深度依赖 **Metal 4**，旧版 macOS 无法编译和运行。 |
| **编译工具链** | **Xcode 26+ 及 Swift 6.2+**                  | 用于编译 `TurboFieldfareServer` 及 Repacker 工具。                                      |
| **统一内存**   | **8 GB 及以上**                              | 已在 8 GB 内存的 M2 MacBook Air 基准测试通过。                                          |
| **存储空间**   | **约 16 GB 可用 SSD 空间**                   | 文本模型约 14.3 GB，图像伴生包约 1.1 GB。                                               |
| **网络环境**   | **可用互联网连接**                           | 首次需要从 Hugging Face 流式下载模型权重。                                              |

---

### 构建与打包发布

#### 快速编译与打包

```bash
# 确保本体位于主目录
git clone https://github.com/drumih/turbo-fieldfare.git ~/turbo-fieldfare

# 进入本管理项目
cd ~/Projects/turbo-fieldfare-manager

# 构建状态栏应用并打包生成 DMG 安装包
./build_app.sh
```

#### 严格开源代码签名审计

`build_app.sh` 脚本内置了 OpenSSL X.509 证书 Subject 深度审核机制，杜绝任何商业或付费企业证书泄露：

- **默认纯个人证书模式**：自动排查并剔除所有包含公司/团队/企业域名的证书，仅选用纯个人免费 Apple ID 证书；
- **纯开源 Ad-hoc 模式 (`--adhoc`)**：
  ```bash
  ./build_app.sh --adhoc
  ```
  采用 `codesign -s -`，完全清空团队签名信息（`TeamIdentifier=not set`），适合公开发布至 GitHub Releases。

#### 命令行管理脚本

```bash
./server.sh start    # 后台启动服务并进行健康探测
./server.sh stop     # 优雅关闭后台服务
./server.sh restart  # 重启服务
./server.sh status   # 检查 PID、端口、上下文及 HTTP 200 就绪状态
./server.sh logs     # 实时追踪日志输出 (tail -f)
```

---

### 开源协议

本项目遵循 [Apache License 2.0](LICENSE) 开源协议，与原项目保持完全一致与生态兼容。
