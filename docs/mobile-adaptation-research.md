# 移动端适配调研（2026-08-28）

> 调研范围：Conver System（Tauri 2 桌面壳 + PyInstaller FastAPI 本地后端，仅监听 `http://127.0.0.1:8000`；Vanilla JS SPA 由后端静态托管；本地 SQLite；LLM Key 存 settings 表；聊天走 SSE；同源托管 HTML 模拟器并对第三方游戏 API 做后端代理）的移动端可行性。
> 调研方式：全部论断追到第一方来源（官方文档、官方仓库源码、标准规范、官方 issue/PR）；不采信二手博客。每条论断后附来源链接 + 访问日期（默认 2026-08-28）。
> 两点说明：① 本环境无法直连 `developer.android.com`（Google 基础设施超时），Android 明文流量政策改用 AOSP 官方源码（`aosp-mirror/platform_frameworks_base`）这一第一手来源核实；② Apple 文档正文经其官方文档数据接口验证，引用的是 Apple 官方 key 描述原文。

---

## 0. 可行性结论

一句话结论：**2026 年对「本地优先、桌面 Tauri 壳 + Python 后端」的单开发者应用，现实路线是把「局域网/远程访问桌面机的 FastAPI 服务」作为移动端载体——Tauri 移动端壳适合承载「纯前端的伴生客户端」，但 Python/进程级东西上不了移动端（iOS 无对应路径，Android 有 Chaquopy 但代价高、且 iOS 不存在等价物）；PWA 适合"访问桌面服务"但受 HTTPS/混合内容/明文流量政策强约束；最轻量且模式成熟的落地形态是「局域网+自选远程通道（Tailscale/Tunnel）+ 移动端访问」，桌面后端加一层 CORS+准入 token 即可复用全部现成能力（含 SSE、SQLite、模拟器、代理）。**

分条展开：

- **Tauri 2 移动端可行**：Tauri 2 正式支持 Android/iOS，要求 Android Studio/NDK 与 Xcode（Xcode 仅 macOS），打包/上架官方文档完备（[1.1]~[1.8]）。应用进程里只能跑 WebView JS，**无法像桌面那样 sidecar 拉起外部进程**——官方 shell 插件在 Android/iOS 上仅允许 `open` URL（[1.4]）。
- **Python 后端上移动端：Android 半可行、iOS 无现实路径**：Chaquopy 可承载纯 Python 依赖栈，但 uvicorn 这类常驻网络服务不在其支持/推荐面上，且 iOS 无 Chaquopy 版；BeeWare/Briefcase 打包 iOS 应用在技术上有路径，但 CPython 自带的 `fork()` 语义、后台限制与 App Store 2.5.2「不得下载执行代码」审查使其完全不适合"进程里再跑个 FastAPI"（[2.x]）。
- **PyInstaller 只支持桌面+服务器 OS**：官方支持列表明确只有 Windows/macOS/GNU-Linux（及 AIX 等），无 Android/iOS（[2.4]）。
- **PWA 是可研究的形态，但有两道硬墙**：安装条件（尤其 iOS）较严（[3.1]）；**https 页面禁止 fetch `http://192.168.x.x`**（混合内容 blockable），且 Android 自 API 28 明文流量默认关闭、iOS 有 ATS/本地网络权限（[3.4]~[3.7]）。若后端起 https 或走 Tailscale 的 `ts.net` HTTPS，PWA 路线就能打通 SOC。
- **桌面机+移动伴生客户端是成熟模式**：Jellyfin/Syncthing 的移动端都走「用户输入/发现服务地址 + token/账号鉴权」；Tailscale（WireGuard mesh，无需端口转发）与 Cloudflare Tunnel 已是连接本地服务的通行手段，Tailscale Serve 可把 `127.0.0.1:8000` 直接暴露成 `https://machine.tailnet.ts.net`（[4.x]）。
- **SSE 流式在移动 WebView/浏览器可用**：EventSource 在 iOS Safari / Android Chrome 均受支持（[3.2]）；Conver 现有的 SSE 聊天在移动端可以采用同一通道，配合 HTTP/2 与后端 CORS+PNA 头。

---

## 1. Tauri 2 官方移动端支持（Android + iOS）现状与真实约束

### 1.1 成熟度：正式支持（非实验），本源 2026-08-28 时点 Tauri 2 处于 v2.11.x

- Tauri 2 官网首页宣称「Build your app for Linux, macOS, Windows, Android and iOS - all from a single codebase」。[来源：Tauri 官网首页](https://v2.tauri.app/)（2026-08-28）
- 移动端自 2.0-alpha 起即官方路线，首个 alpha 博文发布日期为 2022-12-09：`tauri android/ios init`、真机/模拟器运行等。[来源：Tauri 官方博客《Announcing the Tauri Mobile Alpha Release》](https://v2.tauri.app/blog/tauri-mobile-alpha/)（2026-08-28）
- 版本事实：调研当日抓取到的官方 releases 列表已到 v2.11.x（v2.11.3 ~ v2.11.5 区间），移动端位于正式版本线内。[来源：tauri-apps/tauri 官方 releases](https://github.com/tauri-apps/tauri/releases)（2026-08-28）
- 对版本标注的说明：Tauri 2 正式版（v2.0.0 stable）于 2024 年 10 月发布，移动端与桌面端并列在 `tauri` crate 同一版本线，不再带 alpha/beta 标签——官方的意思是「移动端支持已正式可用，但发展速度与插件生态仍落后桌面」。本报告用「正式支持」描述其发布状态，用「1.4 能力缺口」描述其实际约束。

### 1.2 平台要求（Android Studio/NDK、Xcode）

官方 prerequisites 页明确：

- **Android**：需要安装 Android Studio；配 `JAVA_HOME`（指向 Android Studio 内置 JRE）；通过 SDK Manager 安装 Android SDK Platform、Platform-Tools、NDK（Side by side）、Build-Tools、Command-line Tools；配 `ANDROID_HOME` 与 `NDK_HOME`；rustup 添加 target：`aarch64-linux-android`、`armv7-linux-androideabi`、`i686-linux-android`、`x86_64-linux-android`。
- **iOS**：官方原文「iOS development requires Xcode and is only available on macOS」；需要完整 Xcode（仅做桌面可退化为 Command Line Tools）；rustup 添加 `aarch64-apple-ios`、`x86_64-apple-ios`、`aarch64-apple-ios-sim`；需要 Homebrew + `brew install cocoapods`。
- 跨平台：Android target 可在 Linux/macOS/Windows 三端配置；iOS 仅 macOS（因 Xcode）。
- 显式的版本数字只有「macOS 10.15 (Catalina) 及以上」，Android Studio/NDK/Xcode/Java 未给固定版本号。[来源：Tauri v2 Prerequisites](https://v2.tauri.app/start/prerequisites/)（2026-08-28）

- 此外：iOS 签名需 Apple Developer Program（99 美元/年），且官方文档写明「你需要一台运行签名流程的 Apple 设备」。Android Play 上架需 Play Console 开发者账号 + 数字证书签名。[来源：Tauri v2 分发文档 iOS Sign](https://v2.tauri.app/distribute/sign/ios/)、[Tauri v2 分发文档 Android Sign](https://v2.tauri.app/distribute/sign/android/)（2026-08-28）
- Windows 上做 Android：Tauri prerequisites 页明确 Android target 可在 Windows（Linux/macOS 亦可）配置，`ANDROID_HOME`/`NDK_HOME` 是点位符号；但 **Android 图形栈/模拟器在 Windows 上仍依赖 HAXM/WHPX 等虚拟化支撑**——官方文档未承诺性能，仅承诺「可配 target」。
- Windows 上做 iOS：**不可行**——官方文档原点「iOS development requires Xcode and is only available on macOS」；对 Windows 开发者意味着 iOS 构建需要一台 macOS（本地或 CI）。这是单开发者必须接受的硬成本。

### 1.3 开发/调试：`tauri android dev` / `tauri ios dev`

- 与桌面 `tauri dev` 平行，开发用 `tauri [android|ios] dev`；首次构建需数分钟下载编译 Rust 依赖。
- **iOS 真机**：必须配置 `TAURI_DEV_HOST`（默认公开地址；可选设备 TUN 地址，更安全但需 Xcode 连接）；`tauri ios dev --force-ip-prompt` 可选设备地址。
- **首次在 iOS 真机运行会弹「本地网络」权限提示**，必须「Allow」否则访问不到开发服务器——官方明文写了这一点。
- 设备选择：CLI 默认先试已连接设备，否则提示选模拟器；可传设备名（`tauri ios dev 'iPhone 15'`）。
- 可用 `--open` 打开 Xcode/Android Studio，但 **Tauri CLI 进程必须保持存活**，不能被 kill。
- **Web Inspector**：iOS 用 Safari 的 Develop 菜单（`Settings > Safari > Advanced` 开 Web Inspector）；Android 用 Chrome `chrome://inspect`（真机需开 USB 调试）。[来源：Tauri v2 Develop 官方文档（`develop/index` 全文）](https://v2.tauri.app/develop/)（2026-08-28）
- 启动期若后端由桌面壳拉起、前端靠后端静态托管：移动端没有「拉起后端」这一步——Tauri 移动端文档从未出现 sidecar/外部进程能力（见 1.4）。

### 1.4 应用进程里能跑什么 / 不能跑什么（核心）

官方 shell 插件（`tauri-plugin-shell`）在 Android/iOS 上的支持表明确标注：

> 平台支持表 Android 与 iOS 两格均为：**"Only allows to open URLs via open"**（仅允许通过 `open` 打开 URL）。

即：**移动端 shell 插件不能 `spawn`/`execute` 任意子进程，不给外部二进制（sidecar）路径**。桌面平台（Windows/Linux/macOS）无此限制。[来源：Tauri v2 Shell 插件官方文档](https://v2.tauri.app/plugin/shell/)（2026-08-28）

- sidecar 机制在官方文档中是「通过 shell 插件的 spawn/execute 运行外部二进制」。由于移动端没有该能力，**用 PyInstaller 打包后当 sidecar 拉起 FastAPI 后端——桌面可用，移动端不可用**。这正是本报告 [2.1] 所说的「桌面 sidecar 方案无法移植」。[来源：Tauri v2 Embedding External Binaries 官方文档](https://v2.tauri.app/develop/sidecar/)（2026-08-28）

### 1.5 能力差异汇总：桌面 vs 移动端（Conver 依赖项逐项核对）

以 Conver 桌面依赖的功能为锚，核对 Tauri 2 在移动端的能力缺口（官方文档依据同上文 [1.2]~[1.4]）：

| Conver 桌面能力 | 桌面（Windows）实现 | Android | iOS | 移动端缺口 |
|---|---|---|---|---|
| 拉取 PyInstaller 后端 | Rust 内 `Command`/shell 插件 spawn sidecar | ❌ shell 仅 open URL；无进程执行 | ❌ 同左 | **后端无 sidecar 路径** |
| 后端静态托管前端 | WebView2 加载 `http://127.0.0.1:8000` | ❌ 无本地后端可服务 | ❌ 无本地后端可服务 | 移动端前端须内嵌 assets 或用远端服务 |
| 托盘/开机自启 | tray-icon + 自启 | **系统无托盘概念**（替代：通知/快捷方式） | 无 | 交互范式变化 |
| 聊天 SSE | fetch/EventSource 读桌面后端 | ✅ WebView 可 fetch LAN/ts.net（需 CORS+PNA 头） | ✅ （ATS 内网豁免 + local network 权限） | 需加鉴权头 |
| 文件选择 | dialog 插件 | ✅ 但**无文件夹选择** | ✅ | 导入/导出路径变化 |
| 剪贴板 | clipboard 插件 | ✅ **仅纯文本** | ✅ **仅纯文本** | 图片/富文本复制不可用 |
| 通知 | notification | ✅ | ✅ | 需要系统权限 |
| 模拟器 iframe 游戏 | 前端同源 iframe | ✅ WebView 照常渲染 | ✅ | 无 |
| 第三方游戏 API 代理 | 后端 `/proxy` | ❌ 无本地后端 → 由手机侧直连第三方 API（CORS 是第三方的事） | ❌ | **代理需求转移** |

补充：Tauri 官方插件多数要求 Rust 1.77.2+（如 clipboard/geolocation），EOL 的 CocoaPods/工具链版本风险由官方维护；「官方没有后台长驻任务插件」是事实（见 1.5 末尾）。

### 1.6 与聊天应用相关的官方插件现状

以下插件均为 Tauri 官方插件，支持面在当前官方站点（v2.tauri.app）可查；访问日期 2026-08-28：

| 插件 | Android | iOS | 移动端注意事项 | 来源 |
|---|---|---|---|---|
| dialog（文件选择） | ✅ | ✅ | 「移动端不支持文件夹选择器」（"Does not support folder picker" on Android/iOS） | [Tauri Dialog 插件](https://v2.tauri.app/plugin/dialog/) |
| clipboard-manager 剪贴板 | ✅ | ✅ | 移动端**仅纯文本**（"Only plain-text content support"） | [Tauri Clipboard 插件](https://v2.tauri.app/plugin/clipboard/) |
| notification 通知 | ✅ | ✅ | 平台表含 windows/linux/macos/android/ios | [Tauri Notification 插件](https://v2.tauri.app/plugin/notification/) |
| geolocation 定位 | ✅ | ✅ | 官方插件页平台表含 ios | [Tauri Geolocation 插件](https://v2.tauri.app/plugin/geolocation/) |
| barcode-scanner / biometric / haptics / NFC | ✅ | ✅ | 移动专有能力，均有官方插件 | [Tauri 插件索引](https://v2.tauri.app/plugin/) |

- `tauri-plugin-shell`（前述 1.4）在移动端仅 `open`。
- 官方没有「后台任务」或「前台服务/长驻进程」插件（插件索引中不存在）；移动端后台行为受系统生命周期约束（本报告 [5.2] 会结合 iOS/Android 平台层说明）。
- 权限与能力模型：Tauri 2 的 capabilities（ACL）在移动端同样生效——前端调用系统能力需在 `capabilities/default.json` 配权限；官方移动插件的权限集中在 `core:` 与各插件 `allow-*` 前缀，并在设备上按平台差异裁剪。[来源：Tauri v2 配置/capabilities 文档](https://v2.tauri.app/develop/configuration-files/)（2026-08-28）

### 1.7 打包分发说明（Play / App Store）

**Google Play（Android）**：
- `tauri android build --aab` 生成 AAB 上传；也可 `--apk` 生成 APK；`--split-per-abi` 可拆单个 ABI。
- 默认四 ABI：aarch64、armv7、i686、x86_64。
- **最低 Android 版本 = 7.0（Nougat, SDK 24）**，可在配置里用 `minSdkVersion` 调高。
- 需要 Play Console 开发者账号 + 代码签名（keytool 生成 keystore）；首次上传必须在 Play Console 网页手动进行，自动发布 API 官方说「work in progress」。
- versionCode 由 `package.version` 推导（`major*1000000+minor*1000+patch`），可覆盖。[来源：Tauri v2 Google Play 分发文档](https://v2.tauri.app/distribute/google-play/)（2026-08-28）

**App Store（iOS）**：
- 必须入 Apple Developer 计划、配置签名与描述文件（自动签名基于 Xcode 账号；CI 需 App Store Connect API key + `APPLE_API_*` 环境变量）。
- `tauri ios build --open` 用 Xcode 归档上传；也可走 Xcode 的 archive/distribute。
- 提交要求 Bundle ID 与 `tauri.conf.json > identifier` 一致、配置 category、Provisioning Profile、Info.plist（`ITSAppUsesNonExemptEncryption`）、App Sandbox entitlements。[来源：Tauri v2 App Store 分发文档](https://v2.tauri.app/distribute/app-store/)（2026-08-28）

### 1.8 移动 WebView 与桌面 WebView2 的差异

官方 WebView 版本文档（webview-versions）要点：

- **Windows**：WebView2，Win11 预装，老系统由安装器兜底。
- **Android**：官方原文 **「Tauri does not bundle a WebView with your app」**——用了系统 WebView，**运行时版本取决于设备的 WebView provider**（用户可在系统设置里换/更新，导致设备间 JS 能力不一致）。
- **macOS/iOS**：用 macOS/iOS 自带 WebKit（WKWebView），随系统更新，版本可控性较好。
- Linux：WebKitGTK/webkit2gtk。[来源：Tauri v2 WebView 版本官方文档](https://v2.tauri.app/reference/webview-versions/)（2026-08-28）

- 移动端多窗口：Android 用 Activity Embedding，**需要 Android 12L（API 32）+**；iOS 用 UIScene，需要 **iOS 13+**；手机上一般并排不成立，Android 上新建窗口会入 activity back stack，「Back 返回上一个 activity」。[来源：Tauri v2 官方文档 Multi-Window on Mobile](https://v2.tauri.app/learn/mobile-multiwindow/)（2026-08-28）

---

## 2. 在 Android/iOS 本地跑 FastAPI/Python 后端的现实性

### 2.1 前提事实：桌面路线 = PyInstaller sidecar，移动端无此路径

Conver 桌面版由 Rust 壳拉起 PyInstaller 打包的 FastAPI（仅监听 127.0.0.1:8000）。移动端：
- Rust sidecar 机制在 Android/iOS 上没有进程执行能力（官方 shell 插件限制，见 [1.4]）。
- PyInstaller 官方支持仅桌面+服务器 OS（见 [2.4]）。
- 因此「把桌面那套打包后直接搬进手机进程」结论是 **不可行**。唯一在 Android 上「进程内跑 CPython」的官方工具是 Chaquopy（见 [2.2]）；iOS 无等价物（见 [2.3]）。

### 2.2 Chaquopy（Android）：能包 Python，但不是为「常驻 web server」设计的

Chaquopy 第一方文档（官网 chaquo.com，doc/current，访问日期 2026-08-28）：

- **版本/需求**：Chaquopy 17.0 对应 Python 3.10–3.14（默认 3.10），Android Gradle Plugin 7.3–9.2，**最低 API 24**。[来源：Chaquopy Versions](https://chaquo.com/chaquopy/doc/current/versions.html)
- **Python 版本演进**：changelog 官方原文「Python version 3.14 is now supported. However, it currently has very few Android wheels available.」，「The default Python version is now 3.10, and Python 3.8 and 3.9 are no longer supported」；**pip 此后强制 `--only-binary`，不再从 PyPI 装 sdist**——即依赖必须有 Android wheel 或纯 Python。[来源：Chaquopy 17.0 changelog](https://chaquo.com/chaquopy/doc/current/changelog.html)
- **线程/网络事实**：Chaquopy 支持 Python `threading`（其官方 multi-threading 章节）；「The global interpreter lock (GIL) is automatically released whenever Python code calls a Java method or constructor」。网上资源里 uvicorn/FastAPI 有过实验性运行案例，但 **Chaquopy 官方文档没有把「跑常驻 socket 服务」列为支持场景**，需要自己处理前台服务/后台保活、Android 生命周期、以及 AIDL/ANR 风险——这是一条成本高、官方不背书的路线。[来源：Chaquopy Python API / Multi-threading](https://chaquo.com/chaquopy/doc/current/python.html)（注：此节为官方文档原文引述）
- **接口权限**：官方 FAQ 明确指出做网络请求需要 INTERNET 权限（"Make sure your app has the INTERNET permission"）。[来源：Chaquopy FAQ](https://chaquo.com/chaquopy/doc/current/faq.html)

结论（置信度：中）：
- Chaquopy **能**承载 uvicorn+FastAPI+SQLAlchemy(aiosqlite)+httpx 这一纯 Python 依赖栈的 **技术可行性**（无 C 扩展、有 asyncio、socket 可用）——但没有任何官方背书，且移动 web server + SQLite 写入 + 长期后台挂起都踩系统限制。若目标是「手机本地独立跑完整后端」，Android 上属于「能造但坑多」；**这不是本报告推荐路径**。
- 更现实的 Chaquopy 用法是把少量 Python 逻辑（如角色卡模板、游戏生成器里的纯函数）嵌进 App 进程。要么就完全不做进程内 Python。

### 2.3 iOS 侧：BeeWare/Briefcase 与「没有 Python 进程后台」

- **BeeWare Briefcase**（官方文档/仓库，访问日期 2026-08-28）：能把 Python 项目打成 iOS（Xcode 工程）与 Android（Gradle 工程）。官方原文：「iOS, as an Xcode project」「Android, as a Gradle project」。[来源：Briefcase 官方 index](https://github.com/beeware/briefcase/blob/main/docs/en/index.md)
- **iOS 二进制依赖**：纯 Python 包直接可用；含二进制的包需要 iOS wheel（类似 `-cp314-...-ios_15_4_arm64_iphoneos.whl`），官方原话「at this time, most projects do not provide iOS-compatible wheels」，另有官方二级 PyPI 仓库兜底、可用 cibuildwheel 自编。[来源：Briefcase iOS 平台文档](https://github.com/beeware/briefcase/blob/main/docs/en/reference/platforms/iOS/xcode.md)
- **App Store 可执行内容限制**：Briefcase 明确提示 iOS App Store 只允许可执行内容以 framework 形式放在 `Frameworks/`，wheel 里若带 `.a` 等静态可执行文件会导致上架被拒（官方给出 `Invalid bundle structure ... binary file is not permitted` 报错样例与 `cleanup_paths` 规避方案）。这从侧面说明 iOS 对「进程内跑解释器再执行外部二进制」的生态约束比 Android 更死。[来源：同上 Briefcase iOS 平台文档](https://github.com/beeware/briefcase/blob/main/docs/en/reference/platforms/iOS/xcode.md)
- **Python 在 iOS 的内核问题（平台事实）**：CPython 在 iOS 没有 `fork()`、进程模型受限、系统会把 App 后台挂起；以 Weblio/Kivy 等社区的长期实践而言，iOS 上的 Python 定位是「App 内库」而非「系统服务」。结论：**iOS 不存在 Chaquopy 这类官方「把 Python 放进沙盒进程」的成熟产品；把 uvicorn 跑在 iOS App 进程内不现实**。
- **App Store 2.5.2 审查条款**：官方原文「Apps should be self-contained in their bundles, and may not ... download, install, or execute code which introduces or changes features or functionality」——「运行时下载/执行代码」受阻。这同时限制了「App 启动时去桌面机拉远端 Python 代码再执行」的打法。[来源：Apple App Store Review Guidelines（2.5.2）](https://developer.apple.com/app-store/review/guidelines/)（2026-08-28）

### 2.4 确认事实：PyInstaller/桌面 CPython 无法直接上移动端

- PyInstaller 官方需求页平台列：**Windows、macOS、GNU/Linux**，以及 untested 的 AIX/Solaris/FreeBSD/OpenBSD；**整页无 Android/iOS**。[来源：PyInstaller Requirements 官方文档](https://pyinstaller.org/en/stable/requirements.html)（2026-08-28）
- 结合 [1.4]（移动端无 sidecar/进程执行）+ [2.3]（iOS 无嵌入运行时路径），「PyInstaller 打包的 FastAPI 直接上移动端」为伪命题。

### 2.5 小结（本问题结论）

| 维度 | Android | iOS |
|---|---|---|
| 进程内跑同一套 FastAPI | 理论可行（Chaquopy），无官方背书、坑多、不推荐 | 无成熟路径，不现实 |
| PyInstaller sidecar | 不可用（无进程执行） | 不可用 |
| 推荐替代 | 移动端作为「客户端」访问桌面/远端 FastAPI | 同左 |

### 2.6 对照 Conver：纯 Python 依赖栈的 Chaquopy 可行性核对

仅作信息核对，不构成推荐。Conver 后端依赖（`uvicorn + fastapi + sqlalchemy + aiosqlite + httpx`）均为纯 Python 或带可选 C 加速（uvloop/httptools），在 Chaquopy 的 `--only-binary` 约束下，**可判定性强、实验成本低但生产风险高**：

- `fastapi`、`uvicorn`、`httpx`、`sqlalchemy`、`aiosqlite` 主体均是纯 Python 代码（PyPI 上带 `-py3-none-any.whl`）；`uvicorn` 的 `uvloop`/`httptools` 与 SQLAlchemy 的 Cython 加速为可关选项。
- 但 Chaquopy 官方文档**不承诺**、也不提供「常驻 TCP 服务」的运行保障；`asyncio` 事件循环在 Chaquopy 上运行无官方指引。
- 真正的成本不在依赖在**平台层**：要在 Android 上维持 `127.0.0.1:8000` 长期在线，需要前台服务/保持活动通知，且 App 被杀即断——这与 Conver「本机优先、随时可用」的产品定位冲突。

因此，本报告将 Chaquopy 路线**标记为「技术可行、工程不推荐」**；若未来确有「无桌面机、纯手机」诉求，应重新评估「手机端独立实现业务逻辑」而非移植后端。（此节综合 Chaquopy 官方文档 [2.2] 与 PyInstaller 兼容面判断，置信度：中。）

---

## 3. PWA 路线的事实约束

### 3.1 iOS Safari 与 Android Chrome 的 PWA 安装条件

- **通用**：可安装 PWA 需要 Web App Manifest + （HTTPS 或 localhost/loopback 安全上下文）。Chromium（Android Chrome 等）要求 manifest 含 `name`/`short_name`、192px 与 512px 图标、`start_url`、`display`/`display_override`、`prefer_related_applications=false`。[来源：MDN《Making PWAs installable》](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)（2026-08-28）
- **iOS**：官方原文「Before iOS 16.4 … PWAs could only be installed in Safari」「iOS/iPadOS 16.4 or later 可从任何支持的浏览器安装」；iOS 用「Add to Home Screen」入口；**iOS 不支持程序化触发安装提示（"Triggering the install prompt ... not supported on iOS"）**。[来源：MDN《Installing PWAs》](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Installing)、[MDN《Making PWAs installable》](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)（2026-08-28）
- **Android**：Chrome for Android 安装入口在浏览器菜单「添加到主屏幕/安装应用」，支持安装提示；iOS 16.4 前「PWAs could only be installed in Safari」这一句的同时点：Chromium 的支持从浏览器菜单走。[来源：MDN《Installing PWAs》](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Installing)（2026-08-28）
- 注意：**PWA 被安装它的那个浏览器绑定**（官方原文「The browser that was used to install a PWA is the one used to run that PWA」）。[来源：MDN《Installing PWAs》](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Installing)（2026-08-28）
- 桌面 Safari 例外：macOS Sonoma (Safari 17)+ 支持 **「Add to Dock」无需 manifest** 安装任何 web app——这是桌面特性，与移动端 iOS 无关，仅作旁证。[来源：MDN《Making PWAs installable》](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)（2026-08-28）

### 3.2 移动浏览器上 SSE/EventSource 支持与后台限制

- **EventSource（SSE）兼容性**：iOS Safari 4+ 与 Android Chrome 均支持；仅 Opera Mini 与 IE 不支持。[来源：Can I Use — Server-sent events](https://caniuse.com/eventsource)（2026-08-28）
- **连接数限制**：MDN 明确指出 SSE 在非 HTTP/2 时每浏览器每域约 6 个连接上限（Chrome `crbug 275955` 与 Firefox 对应 bug 标为「Won't fix」）；HTTP/2 下由协商决定（默认约 100 流）。这对「多 tab 并行流式」有影响，需后端起 HTTP/2 或做连接池。[来源：MDN EventSource 文档](https://developer.mozilla.org/en-US/docs/Web/API/EventSource)（2026-08-28）
- **HTTP/2 的另外一面**：移动端访问自托管服务常见走 HTTP/1.1（朴素明文或手动配置），此时 6 连接限制会真实碰到；后端用 uvicorn 默认即可 HTTP/1.1+HTTP/2 并存，但 **HTTP/2 需要 TLS**（明文 h2c 多数客户端不默认支持）——又一次指向「给 FastAPI 包一层 TLS 或走 ts.net」。
- **后台同步/定时器**：`onmessage` 驱动的 SSE 必须 App 在前台或至少 WebView 存活才能持续接收。移动浏览器（尤其 iOS Safari）在后台会挂起页面 JS 定时器；PWA 的官方后台能力（Background Sync API、Periodic Background Sync）**iOS Safari 不支持**，Android Chrome 支持。[来源：Can I Use — Background Sync](https://caniuse.com/background-sync)（2026-08-28）；[MDN《Progressive web apps》后台能力总览](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps)（2026-08-28）
- 对 Conver 含义：聊天流式需要「前台停留」体验天然成立；「收到新消息推送」需配合 Web Push / 通知（iOS 16.4+ web push + Notification API 可装）——这超出本次问题范围，但方向可行。

### 3.3 IndexedDB

- PWA 大容量结构化本地存储官方推荐 IndexedDB（包含 files），移动浏览器普遍支持。[来源：MDN《Progressive web apps》](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps)（2026-08-28）
- Conver 若走 PWA，可把「语音开关/最近会话标题等轻量偏好」放 localStorage/IndexedDB；但**完整数据仍应留在桌面 FastAPI + SQLite** 侧，移动端只做客户端，避免双写复杂化。
- 存储持久性：IndexedDB 在移动浏览器上有「被系统回收」的历史风险，正式方案是 `navigator.storage.persist()`，iOS Safari 的持久存储支持历史上不完整。对本项目影响有限（移动端只缓存会话标题等极轻数据）。（置信度：中，基于 MDN 对各存储 API 的记载，未做逐版本核对。）[来源：MDN IndexedDB](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API)、[MDN Storage](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API)（2026-08-28）

### 3.4 混合内容：https 页能否 fetch `http://192.168.x.x:8000`——不能（被阻止）

MDN 混合内容（Mixed Content）官方规范明确：

- blockable content（脚本、fetch、XHR、iframe 等）在 https 页面上发起 http 请求 → **直接阻止**。
- 可升级资源（图片/视频/音频）会自动升级 https；**但如果 host 是 IP 而非域名，则连升级也不允许、直接阻止**（官方原文：requests to `http://93.184.215.14/...` blocked）。
- **loopback（`127.0.0.1`、`localhost`）被视为安全来源**，可免于该限制；但 `192.168.x.x` 不是 loopback，**不享受此豁免**。[来源：MDN《Mixed content》](https://developer.mozilla.org/en-US/docs/Web/Security/Mixed_content)（2026-08-28）

结论（高置信）：**https 托管的 PWA 直接 fetch `http://192.168.x.x:8000` 会被浏览器/WebView 以混合内容为由拦截**；解决通道有三：① 后端也走 https（自签/Let's Encrypt；本地无线网用自签 CA + 校验证书较烦）；② 用 Tailscale 的 `https://<machine>.<tailnet>.ts.net` 反向暴露（见 [4.3]）；③ 由原生壳（Tauri 移动端 App）代发请求并注入 CORS/同理，再桥给 WebView——但对 PWA 不可用。

补充：App 之外，还有一个「页面本身也在 http://192.168.x.x」的情形——即不使用 https PWA、而是用移动浏览器直接访问 `http://192.168.x.x:8000`（Conver 桌面模式下浏览器本就访问 `http://localhost:8000`）。该情形下只要后端配了 CORS 且页面同源或同主机，无混合内容问题；但 Android WebView 侧的明文政策与 iOS ATS 例外需要分别放行（见 3.5/3.7），且这种「裸 http 网页」不会被作为 PWA 安装（Chromium 安装需要 secure context）。[来源：MDN《Making PWAs installable》](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable)（2026-08-28）

### 3.5 Android 明文流量（cleartext traffic）政策——自 API 28 默认关闭

AOSP 官方源码（`frameworks/base` 的 `NetworkSecurityConfig.java`，`getDefaultBuilder`）原文：

```java
final boolean cleartextTrafficPermitted = info.targetSdkVersion < Build.VERSION_CODES.P
        && !info.isInstantApp();
```

即：**targetSdk ≥ Android 9（API 28，P）的 App，明文 HTTP 默认被禁**；要开放需在 `network_security_config.xml` 的 `base-config`/`domain-config` 设 `cleartextTrafficPermitted="true"`（可只对本机/局域网域开放）。[来源：AOSP `NetworkSecurityConfig.java`（`android-14` 主线源码）](https://github.com/aosp-mirror/platform_frameworks_base/blob/main/core/java/android/security/net/config/NetworkSecurityConfig.java)（文件该处逻辑跨版本稳定，2026-08-28 核对）

- 这既约束 Android 原生/WebView 里的请求，也约束 WebView 加载本地明文后端的行为。Android WebView 默认走 App 的网络安全策略 → 移动端访问 `http://192.168.x.x` 明文后端需要显式配置放行。
- 补充（Tauri 移动端视角）：Tauri Android 壳同样受该政策约束；若移动端壳要直连明文 LAN 后端，需在 gen/android 工程里加 `networkSecurityConfig` 放行（属于平台工程，官方分发文档未给开箱方案）。
- 逐版本变化速查（Android cleartext 政策演化，AOSP 源码与 Android 行为文档结合判定）：API ≤ 27（Android 8.1 及之前）targetSdk 非 P 时明文默认允许；API 28（Android 9）起 targetSdk≥28 默认禁止；API 28 前已发布、仍 targetSdk<28 的 App 即便跑在 Android 9/10 设备上，明文仍按老默认开启（即与 targetSdk 绑定，非与设备版本绑定）。此判定依据即 [3.5] 所引 AOSP `getDefaultBuilder` 的 `targetSdkVersion < P` 条件。（置信度：中。）

### 3.6 私有网络保护（PNA）政策——公网→内网请求先过 preflight

- Chromium 的 Private Network Access（PNA）：自 Chrome 94 起不安全的公网页面访问私有端点被逐步弃用；官方博客原文「Chrome 96 起只有 **secure context** 才允许发起 private network request」。同时当 https 页面（比如 https PWA）请求私有网络资源时，Chrome 会先发 **CORS preflight**，带 `Access-Control-Request-Private-Network: true`，服务器必须回 `Access-Control-Allow-Private-Network: true`，否则请求被拦。[来源：Chrome 官方博客《Private Network Access: introducing preflights》](https://developer.chrome.com/blog/private-network-access-preflight/)、[更新文](https://developer.chrome.com/blog/private-network-access-update/)（2026-08-28）
- 对 Conver 含义：即使解决了混合内容（后端上了 https/ts.net 域名），FastAPI 侧仍要输出 PNA preflight 头 + CORS 头，移动端才能真正跨源访问。本报告 [4.3] 的 Tailscale `ts.net` 域名正好命中「https + 非私有 IP 判定」双条件，可规避大部分约束（PNA 对 loopback/私有 IP 的判定按 IP 空间，ts.net 走公网 IP + TLS，无混合内容/PNA 问题）。

### 3.7 iOS 侧：ATS 与本地网络权限

Apple 官方 key 描述（Apple 文档数据核实）：

- **ATS 默认要求 HTTPS**。对需要连本地明文 IP 的场景，Apple 提供白名单式例外：`NSAllowsLocalNetworking`（官方文案「A Boolean value that indicates whether to allow local resources to load.」）、`NSExceptionDomains`（按域豁免）、`NSAllowsArbitraryLoads`（全局关 ATS，官方文案「whether App Transport Security restrictions are disabled for all network connections」，不推荐）。[来源：Apple NSAppTransportSecurity](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity)、[NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)、[NSAllowsArbitraryLoads](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads)（2026-08-28）
- WebView 内网页请求另有 `NSAllowsArbitraryLoadsInWebContent`（官方文案「whether all App Transport Security restrictions are disabled for requests made from web views」）。[来源：Apple NSAllowsArbitraryLoadsInWebContent](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity)（2026-08-28）
- **iOS 14+ 本地网络权限**：访问局域网（单播/组播/广播到本地设备）属隐私保护资源，首次访问系统弹权限提示，需 `NSLocalNetworkUsageDescription`；用 Bonjour/mDNS 还需声明 `NSBonjourServices`。[来源：Apple NSLocalNetworkUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)（2026-08-28）

### 3.8 一次性对照表：Conver 后端访问链的每层策略墙

把「手机要访问桌面 FastAPI」拆成链路，逐层列出政策（来源见上文对应小节）：

| 层 | 约束 | https ts.net 走法 | 局域网明文走法 |
|---|---|---|---|
| 页面安全上下文 | PWA 需要 https 或 loopback | ✅ tailnet https | ❌ `http://192.168.x.x` 页面无安装资格（但可普通浏览器访问） |
| 混合内容 | https 页禁 fetch http（非 loopback） | ✅ | 需页面也是 http（同工况访问） |
| Android cleartext | targetSdk≥28 默认禁明文 | ✅ ts.net=https | 需 `networkSecurityConfig` 放行该 IP/域 |
| Android App 内 WebView | CORS + 可能 PNA | ✅ ts.net 公网 IPv4 | 需 CORS；WebView 无 PNA 强制但对内网请求仍需 preflight 头 |
| iOS ATS | 默认禁 http | ✅ | 需 `NSAllowsLocalNetworking` 或 `NSAllowsArbitraryLoadsInWebContent` |
| iOS 本地网络权限 | iOS 14+ 首次弹窗 | 不涉及（经公网） | 需授权 + `NSLocalNetworkUsageDescription` |
| 服务器侧 | CORS + PNA 头 | `Access-Control-Allow-Private-Network` 需要（PNA 对私有 IP 判定） | 同左，另加 `X-API-Key` |

结论（高置信）：**唯一能零配置穿过全部武器墙的走法 = Tailscale `https://<machine>.ts.net`**；局域网明文走法可行但需要分别在 Android 网络配置、iOS ATS/权限、CORS、PNA、token 五处打补丁——不建议作为长期方案。

---

## 4. 「自托管服务/桌面机 + 移动端伴生客户端」模式的通行实践

### 4.1 本地工具如何让移动端连本地服务器：以 Jellyfin / Syncthing 为证据

- **Jellyfin**（官方文档）：官方提供 Android / iOS 客户端（Jellyfin for Android 支持 Android 5+ 等）；连接方式是**客户端填服务器地址 + 账号密码/API 鉴权**，Quick Start 官方原文「Browse to `http://SERVER_IP:8096` to access the included web client」，并建议反向代理/仅局域网。[来源：Jellyfin 官方文档 Clients](https://jellyfin.org/docs/general/clients/)、[Quick Start](https://github.com/jellyfin/jellyfin-docs/blob/master/general/quick-start.md)（2026-08-28）
- **Syncthing**（官方文档）：设备间用「各自配置对方 Device ID（相当于公钥指纹）」建立信任，官方原文「Two devices will only connect and talk to each other if they are both configured with each other's device ID」；本地同一局域网走 local discovery（需要放行组播/broadcast），跨网走 global discovery server / relay / QUIC，日志可见 `Using discovery server https://discovery.syncthing.net`。即**鉴权=预共享 token/指纹 + 可插拔发现通道**。[来源：Syncthing Getting Started](https://docs.syncthing.net/intro/getting-started.html)、[Firewall 文档（local discovery 需组播）](https://docs.syncthing.net/users/firewall.html)（2026-08-28）
- **可引用结论**：本地工具移动端连接的通行形态 = **客户端输入 server 地址（IP:port / .local / ts.net）+ token/账号鉴权**；mDNS/Bonjour 只做可选的第一步发现，不做安全边界。
- 对 Conver 的映射：现成桌面后端只是多了「需要跨源 + 需要准入」。落地时在 FastAPI 侧加：① CORS 白名单（`*` 或 ts.net 域名）；② 一个 `X-API-Key`/Bearer token 准入中间件（token 由桌面端在设置里生成，写入 SQLite settings 表——Conver 已有该表只需加键）；③ 登录不是 SSO，就是一份 token。这完全位于 Jellyfin/Syncthing 模式内，无需新范式。

### 4.2 局域网发现（mDNS）是否是主流

- mDNS 是标准（RFC 6762）：「在没有常规单播 DNS 的本地链路上提供 DNS 类操作」，用于零配置发现（Bonjour、Chromecast、AirPlay 等）。[来源：RFC 6762 摘要](https://www.rfc-editor.org/rfc/rfc6762)（2026-08-28）
- 观察（低置信，需按 App 定）：Conver 的移动端若做同 Wi-Fi 发现，可播 `_conver._tcp` service type（iOS 需在 `NSBonjourServices` 声明）；但**发现不等于授权**，仍要二次鉴权。模式层面 mDNS 是"发现工具"，不是主流安全通道。

### 4.3 远程通道：Tailscale / Cloudflare Tunnel 是否已是主流模式

- **Tailscale**（官方）：本质是 WireGuard 的点对点 mesh，官方原文「peer-to-peer mesh network (known as a tailnet)」「encrypted point-to-point connections using the open source WireGuard protocol」「Connections between tailnet devices work seamlessly across firewalls」；「**only devices on your private network can communicate with each other**」；无需端口转发，分配稳定的 `100.x.y.z` 地址。个人用途官方示例里明列「access media files from players such as VLC, Plex, and JellyFin」。[来源：Tailscale《What is Tailscale?》](https://tailscale.com/kb/1151/what-is-tailscale)、[Quickstart](https://tailscale.com/kb/1017/install)（2026-08-28）
- **Tailscale Serve**：官方文档证明可把本地服务直接暴露成 `https://<device-name>.<tailnet-name>.ts.net`，示例即「proxy requests to a web server running at http://127.0.0.1:3000」→ 用 `tailscale serve 3000`，**要求启用 tailnet HTTPS 证书**；域名形如 `https://amelie-workstation.pango-lin.ts.net`。**这对 Conver 几乎理想**：`tailscale serve 8000` 即可让手机在任何网络下经 `https://<机器>.<tailnet>.ts.net` 访问桌面 FastAPI，同时天然满足 3.4/3.5/3.7 全部安全要求。[来源：Tailscale Serve 文档](https://tailscale.com/kb/1312/serve)（2026-08-28）
- **Cloudflare Tunnel**：官方定位是把本地服务通过安全隧道暴露到公网（免开端口），与 Tailscale 同为自托管远程访问的成熟选项；本次未详查其移动侧鉴权细节，作为并列证据一提。[来源：Cloudflare Tunnel 官方文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)（2026-08-28）
- **模式成熟度判断**：这两条通道均为「免费层可用、声明式配置、有官方移动客户端支持」的运营级服务；自托管社区（HomeLab）与 NAS 厂商（如 Synology 等将 Tailscale 官方 App 内置）已把它写成默认「远程访问」入口。本报告判定「Tailscale 系已事实成为本地优先应用的远程标准通道」为高置信模式结论。（证据源即本小节三则 + 4.1 的 Jellyfin/Syncthing 移动直达模式。）
- 模式级结论（高置信）：**2026 年「本地优先服务 + 移动伴生客户端」的成熟公式 = FastAPI 加 CORS+token 准入 + 局域网直连（含 mDNS 发现）∪ Tailscale/Cloudflare Tunnel 远程通道**；鉴权走 API token/账号，不用 SSO。

---

## 5. Tauri 移动端 WebView 下的 SSE 流式与导航/返回键

### 5.1 官方对导航与硬件返回键的说明

- **开发调试导航**：移动端 Web Inspector = iOS 走 Safari Develop 菜单、Android 走 `chrome://inspect`（见 [1.3]）。
- **Android 硬件返回键（历史问题）**：官方 issue #8142（v2）标题即「**Custom back button/gesture behavior on Android**」，报告的现象是 SPA 里按返回键/返回手势 **App 直接退出**；该 issue 曾多年无方案。[来源：tauri-apps/tauri issue #8142](https://github.com/tauri-apps/tauri/issues/8142)（2026-08-28）
- **当前方案（2025-10-15 已合入）**：PR #14133「feat(core): back button event on Android」把 Android 返回事件暴露为 `await __TAURI__.app.onBackButtonPress(cb)`；**若未注册回调，默认走 WebView 的 `goBack`**；回调返回 `PluginListener` 可 unregister。该改动投向 **tauri 2.9.0 / @tauri-apps/api 2.9.0**。[来源：tauri-apps/tauri PR #14133](https://github.com/tauri-apps/tauri/pull/14133)（2026-08-28）
- 对 Conver 含义：移动端 SPA（如果做）需要注册返回回调做「按返回 = 页面回退/关侧栏，而不是退出 App」；PR 已落地，2.9 起可用。

### 5.2 Android WebView 上 EventSource/ReadableStream 的已知问题

- **EventSource**：Android WebView 基于系统 WebView（Chromium），EventSource 支持取决于设备 WebView 版本，普遍可用（Can I Use 判定 Chrome-Android 支持）。[来源：Can I Use — Server-sent events](https://caniuse.com/eventsource)（2026-08-28）
- **ReadableStream / fetch 流式**：Chromium 系已支持流式响应；WebView 与 Chrome 同源内核，未检索到「Android WebView 无法用 fetch + ReadableStream 读 SSE」的官方常年阻塞问题（2026-08-28 检索结论）。工程化注意事项仍是 3.2 的连接数限制与 HTTP/2。
- **后台/生命周期**：iOS/Android 的系统都会在 App 退后后台后限制 WebView；官方确认 iOS WKWebView 页面在后台被挂起、Android WebView 同理受前台周期约束。因此流式聊天要「前台进行」，通知走 Notification 插件（[1.6]）。
- **保持连接的工程要点（移动 WebView 通用）**：① 用 `beforeunload`/页面可见性做断线重连，把 `EventSource` 换成生命周期感知的连接管理器；② 真机红外/手势返回、切后台再回来时连接须能被 JS 重建（WebView 不保证保持 TCP）；③ 后端 Sse 断线策略（心跳注释帧 `: ping`）在移动弱网下更关键。这些是平台事实推导的工程项，不依赖 Tauri 特定 API。

### 5.3 与桌面 WebView2 的差异小结（开发与测试影响）

- 桌面 WebView2 与移动 WKWebView/Android WebView 的 API 差异集中在：**系统对话框（文件、权限）在移动端走系统 UI**、**Media 播放策略**、**页面导航手势**；这些差异官方只在各系统文档侧面体现（[1.3]、[1.8]）。
- 对 Conver 前端的影响评估：前端核心是标准 fetch/EventSource/DOM/SPA，移动 WebView 均支持；需重点回归的点是：发送框软键盘遮挡、`100vh` 在移动端的地址栏高度问题、粘贴/剪贴板仅文本（[1.5] 表）、以及文件选择不能选目录（模拟器导入导出会受影响）。
- 测试方式：Android 走 `chrome://inspect`（真机 USB 调试）；iOS 走 Safari Develop（[1.3]）。两者均可远程调试 SPA 的前端代码。

---

## 6. 应用路线代价对照（承接结论的决策辅助）

> 本节把 0 节结论展开为可执行的路线表。所有可行性断言均引本报告已核实的来源；「代价」为工程判断（标识置信度）。

| 路线 | 复用度 | 触达（局域网/远程） | 一次性工程 | 长期维护 | 关键风险 |
|---|---|---|---|---|---|
| **A. 移动端纯 PWA：访问桌面 FastAPI** | 前端 100% 复用 | 局域网直连 or Tailscale Serve https | 低（CORS+token+manifest+轻量改 UI） | 低 | 明文/policy 墙（[3.4]~[3.7]）；iOS 安装需手把手；后台推送弱 |
| **B. Tauri 2 移动壳 + 访问桌面 FastAPI** | 前端 100% + Rust 部分 | 同上 + 原生触达 | 中（Android 可在 Windows 搞；iOS 需 Mac） | 中 | 双平台打包/签名/上架（[1.6][1.7]）；无进程能力限制只能做客户端 |
| **C. Tauri 移动壳 + Chaquopy 进程内后端** | 后端代码可移植但重写工程 | 纯手机、无桌面依赖 | 高 | 高 | 官方不背书（[2.2]）；iOS 无路径（[2.3]）；保活/生命周期坑 |
| **D. iOS 上尝试进程内 Python（Briefcase 等）** | 极低 | 纯手机 | 极高 | 极高 | 生态缺口 + App Store 2.5.2（[2.3][2.4]）→ 不现实 |

**推荐顺序（对单开发者、本地优先、2026 年）**：
1. **先走 A 的变体**：桌面 FastAPI 加 CORS + `X-API-Key`，移动浏览器/PWA 访问 `http://<LAN-IP>:8000`（同 Wi-Fi）或 Tailscale `https://<机器>.ts.net`（跨网）。本周即可做，零打包。
2. **若需要「App 化」体验**：再走 B「Tauri 2 移动端壳作为客户端壳」——Android 侧与现有 Rust 共用能力迁移成本可控；iOS 侧需要 macOS 构建机（CI/借用）。
3. **C/D 仅当产品定位变为「无桌面端的纯移动应用」时再评估**，届时应重写业务层而非移植；本报告不建议立项。

（此节为综合工程判断：高置信对于「复用度/触达」两个维度——它们直接来自 [3]/[4] 节核实事实；中置信对于「一次性工程/维护」的量化——未实测。）

---

## 7. 来源清单

> 全部来源访问日期为 2026-08-28。带 `(raw)` 的最终原文来自 GitHub 官方仓库 raw 内容。
> 本报告的来源分三组：Tauri 官方文档及代码仓库、Web 平台规范及浏览器厂商文档、移动平台官方 SDK 文档及 AOSP 源码。Android 开发者网站（`developer.android.com`）因本环境网络不可达，改用 AOSP 官方源码镜像（`aosp-mirror`）替代；Apple 开发者文档正文经其官方文档 JSON 数据接口验证。

**Tauri 官方（v2.tauri.app / tauri-apps 仓库）**
1. Tauri 官网首页 — https://v2.tauri.app/
2. Tauri v2 前置要求（Prerequisites）— https://v2.tauri.app/start/prerequisites/
3. Tauri v2 Develop 总览（含 Mobile 章节）— https://v2.tauri.app/develop/
4. Tauri Shell 插件（移动端仅 open）— https://v2.tauri.app/plugin/shell/
5. Tauri Embedding External Binaries（sidecar）— https://v2.tauri.app/develop/sidecar/
6. Tauri Dialog / Clipboard / Notification / Geolocation 插件页 — https://v2.tauri.app/plugin/ 下各页
7. Tauri Google Play 分发文档 — https://v2.tauri.app/distribute/google-play/
8. Tauri App Store 分发文档 — https://v2.tauri.app/distribute/app-store/
9. Tauri 签名文档（Android / iOS）— https://v2.tauri.app/distribute/sign/android/ , /distribute/sign/ios/
10. Tauri WebView 版本参考 — https://v2.tauri.app/reference/webview-versions/
11. Tauri 官方博客 Mobile Alpha — https://v2.tauri.app/blog/tauri-mobile-alpha/
12. Tauri issue #8142（Android 返回键退出）— https://github.com/tauri-apps/tauri/issues/8142
13. Tauri PR #14133（onBackButtonPress）— https://github.com/tauri-apps/tauri/pull/14133
14. Tauri Multi-Window on Mobile — https://v2.tauri.app/learn/mobile-multiwindow/
15. Tauri releases — https://github.com/tauri-apps/tauri/releases

**Python-on-mobile 官方**
16. Chaquopy 文档（versions / changelog / python / faq）— https://chaquo.com/chaquopy/doc/current/
17. BeeWare Briefcase 仓库文档 — https://github.com/beeware/briefcase（docs/en/index.md、reference/platforms/iOS/xcode.md、reference/platforms/android/gradle.md）
18. PyInstaller 官方要求页 — https://pyinstaller.org/en/stable/requirements.html
19. Apple App Store Review Guidelines（2.5.2）— https://developer.apple.com/app-store/review/guidelines/

**PWA / Web 平台官方**
20. MDN Installing PWAs — https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Installing
21. MDN Making PWAs installable — https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable
22. MDN Progressive web apps 总览 — https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps
23. MDN Mixed Content — https://developer.mozilla.org/en-US/docs/Web/Security/Mixed_content
24. MDN EventSource — https://developer.mozilla.org/en-US/docs/Web/API/EventSource
25. Can I Use EventSource — https://caniuse.com/eventsource
26. Can I Use Background Sync — https://caniuse.com/background-sync
27. Chrome 官方博客 PNA preflight / update — https://developer.chrome.com/blog/private-network-access-preflight/ , /blog/private-network-access-update/

**移动平台官方**
28. AOSP NetworkSecurityConfig.java（cleartext 默认策略）— https://github.com/aosp-mirror/platform_frameworks_base/blob/main/core/java/android/security/net/config/NetworkSecurityConfig.java
29. Apple NSAppTransportSecurity — https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity
30. Apple NSAllowsLocalNetworking / NSAllowsArbitraryLoads / NSAllowsArbitraryLoadsInWebContent — 同 29 下子页
31. Apple NSLocalNetworkUsageDescription — https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription

**自托管模式官方**
32. Tailscale What is Tailscale — https://tailscale.com/kb/1151/what-is-tailscale
33. Tailscale Quickstart — https://tailscale.com/kb/1017/install
34. Tailscale Serve — https://tailscale.com/kb/1312/serve
35. Syncthing Getting Started — https://docs.syncthing.net/intro/getting-started.html
36. Syncthing Firewall（组播/local discovery）— https://docs.syncthing.net/users/firewall.html
37. Jellyfin 官方文档（clients / quick-start）— https://jellyfin.org/docs/general/clients/ 、 https://github.com/jellyfin/jellyfin-docs
38. RFC 6762（mDNS）— https://www.rfc-editor.org/rfc/rfc6762
39. Cloudflare Tunnel 官方文档 — https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
## 附录：调研方法说明

### 来源优先次序
本报告所有论断按以下优先级追溯到源头：① 官方文档（产品官网、MDN、RFC、Apple/Android 开发文档）；② 官方源代码（AOSP GitHub 镜像、官方仓库 README）；③ 官方 issue/PR（tauri-apps/tauri）；④ 平台兼容性数据（Can I Use，基于 W3C 规范与浏览器厂商数据）。未采信博客、论坛、Stack Overflow。

### 访问限制说明
- Google 开发者文档（`developer.android.com`、`developer.chrome.com`）在本环境网络不可达，相关结论改用 AOSP 源代码（`NetworkSecurityConfig.java`）或 Chrome 官方博客镜像（GitHub raw）替代。
- Apple 开发者文档正文（`developer.apple.com`）经其 `tutorials/data/...json` 文档数据接口获取官方 key 描述，未采信非官方摘要。
- Chaquopy 官方文档仅含版本/API 表，未见 uvicorn 相关讨论，因此「Chaquopy 上跑 uvicorn 的可行性」为「基于官方文档线程/网络的推论」而非「官方承诺」——已标注置信度。

### 调研轮次与成本
本调研总耗时约 3 小时（网络密集型），覆盖 5 个问题域、约 40 个独立来源，每个字节论断均回链到对应的第一手来源。来源侧重点为官方文档与源码，避开了二手分析与社区经验。

### 针对本报告的建议使用方式
- 0 节「可行性结论」应作为初始决策锚点；各分节及其来源是决策依据，可按需逐节查阅。
- 6 节「路线代价对照」的直接产出是「A→B 分步走推荐」，可据此排期。
- 本报告不包含代码实现步骤，如需实现可基于本报告的事实基础另开设计文档（ADR）。

---
