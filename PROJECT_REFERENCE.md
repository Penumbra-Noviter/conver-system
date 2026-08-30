# Conver System 移动端 — 项目介绍书

> **一句话**：Conver System 的移动端独立应用——Flutter（Android + iOS）手机直连 LLM API，复刻桌面版角色对话系统全部 7 项功能，无桌面后端依赖。
> **技术栈**：Flutter + Dart（`drift` ORM / `dio` HTTP / `provider` 状态 / `flutter_secure_storage` Key）
> **形态**：Android/iOS 原生二进制；本地 SQLite + 系统安全存储 Key；`dart:io` 直连公网 HTTPS LLM API

---

## 一、项目概述

**当前状态**（2026-08-30）：**M3 已交付**——角色 + 搜索：角色列表卡片+四按钮+下拉刷新+长按批量删除 / 6 步全屏向导+5 模板 / V2 卡导入导出（file_picker ^12.1.2 / share_plus ^13.3.0 / path_provider ^2.1.6 转正）/ 跨对话搜索防抖五态+跳转定位 3s 高亮。729 测试/analyze 0/覆盖率剔除 drift 98.06%/四轴零阻断；冒烟 PASS（建角色→落库→搜索→跳转高亮真机实证）；merge 70bc094 + 期末修复 0057d9e/9cfc4aa；TICKETS 已归档。**上一里程碑 M2**（2026-08-29：聊天核心——LLM Provider 双协议 SSE wire + ChatService 回合编排 + 打字机 UI + 最小临时会话入口 + 设置页测试连接，477 测试/覆盖率手写口径 95.42%，真实流式待配置 Key）。**下一站 M4**（导出/文档解析：对话导出 JSON/MD + 分享；LLM 文档解析角色字段，见 [TICKETS.md](TICKETS.md)）。权威设计文档 = [docs/mobile-design.md](docs/mobile-design.md)（单一事实来源），决策背景 = [docs/mobile-adaptation-research.md](docs/mobile-adaptation-research.md)。

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