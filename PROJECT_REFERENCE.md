# Conver System 移动端 — 项目介绍书

> **一句话**：Conver System 的移动端独立应用——Flutter（Android + iOS）手机直连 LLM API，复刻桌面版角色对话系统全部 7 项功能，无桌面后端依赖。
> **技术栈**：Flutter + Dart（`drift` ORM / `dio` HTTP / `provider` 状态 / `flutter_secure_storage` Key）
> **形态**：Android/iOS 原生二进制；本地 SQLite + 系统安全存储 Key；`dart:io` 直连公网 HTTPS LLM API

---

## 一、项目概述

**当前状态**（2026-08-29）：**M1 已交付**——数据层 + 设置：4 仓储 CRUD 全语义（桌面服务蓝本逐条对齐：聚合计数/自动命名副作用/天然级联验证）、SecureStorage 双协议槽位（真实 Keystore 通道 G6 实证）、模型清单静态单源（8 provider/60 模型，AST 机械 diff 桌面源）、主题三值切换（auto/浅/深 + 浅色 token 25 值逐字复刻桌面浅色段）。模拟器验收全过（154 测试/analyze 0/Key 真通道往返/切主题即时生效/五 tab 零崩溃）。**下一站 M2**（聊天核心：ChatService + SSE 流式，见 [TICKETS.md](TICKETS.md)）。权威设计文档 = [docs/mobile-design.md](docs/mobile-design.md)（单一事实来源），决策背景 = [docs/mobile-adaptation-research.md](docs/mobile-adaptation-research.md)。

**核心能力**（7 项全量，无阉割）：
- **聊天** — 多轮对话 + SSE 流式打字机渲染 + 停止生成；滑窗上下文、模板变量、重生成、错误态
- **角色** — 列表 / 6 步创建向导（LLM 智能解析 + 内置模板）/ SillyTavern V2 角色卡导入导出 / 级联删除
- **搜索** — 跨对话关键词搜索 + 定位高亮
- **设置** — API 配置 / 默认模型 / 对话 / 主题 / 模板变量（独立 tab）
- **文档解析** — LLM 从自由文本提取角色字段
- **AI 生成游戏** — 世界观 → 模板填充生成 HTML 游戏 + 六项校验闸门
- **模拟器** — 22 款内置 + 导入 + AI 生成 HTML 游戏在 WebView 运行：Key 自动注入 / 存档管理（导出/导入/删除）/ CORS 直连（国产 OpenAI 兼容厂商放行）

## 二、关键决策

| 决策 | 内容 |
|------|------|
| **框架** | Flutter（一套 Dart → Android + iOS 原生二进制），非 Tauri 移动壳 / PWA（调研证伪，§0） |
| **架构** | **手机独立运行**，重写业务逻辑；无自建后端，直连公网 LLM API |
| **数据** | 本地 SQLite（`drift`）+ API Key 存系统安全存储（Keychain/Keystore） |
| **HTTP** | `dio`（用户拍板，替代 `http`） |
| **底部导航** | 5 tab：聊天 / 角色 / 搜索 / 模拟器 / **设置**（设置独立 tab，用户定稿；手册/关于收进设置页） |
| **模拟器 MVP** | 完整桥接全量（本地 HTTP 服务器托管 `127.0.0.1:<port>` + Key 注入 + 存档管理），不阉割分期 |
| **安全契约** | 比桌面更紧：Key 仅白名单注入、claude key 恒不进游戏、游戏 WebView 摸不到主应用数据 |

## 三、常碰坑点

1. **iOS 必须 macOS + Xcode**：Windows 开发机只能做 Android；iOS 构建/模拟器需 CI（如 GitHub Actions macOS runner）或借 Mac。架构上双端同源码。
2. **CORS 分界已实测**：国产 OpenAI 兼容厂商（DeepSeek/Kimi/GLM 等）浏览器直连放行；Claude/OpenAI 官方端点拦截 → 官方端点游戏先提示「需桌面端运行」，兜底 fetch 垫片视反馈再上（§4.4/§4.5）。
3. **模拟器环境冻结坑**：ZCode 的 android-emulator 插件 server 在会话启动时注入环境，改配置/环境变量后需**重启 ZCode 一次** preflight 才看得到（D 盘工具链）。
4. **M5 模拟器里程碑偏大**：拆 tickets 时应再细分——本地服务器 → 注入 → 存档桥 → 导入/生成（§7）。

## 四、验证分层（Windows 开发机怎么确认能跑）

业务逻辑/Widget 用 `flutter test`（宿主无头跑，**无需模拟器**）；编译产物 `flutter build apk`；Android 运行用本机 AVD（`flutter run -d emulator-5554`）；UI 冒烟可 `flutter build web` → Playwright。详见设计文档 §7.1。