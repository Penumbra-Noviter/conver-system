# Conver System — 移动端设计（Flutter 独立运行）

> 定位：本文档是移动端（Android + iOS）的**架构与设计文档**（单一事实来源）。决策背景见 `mobile-adaptation-research.md`（技术可行性事实，2026-08-28）。
> 决策：**Flutter + 手机独立运行（重写业务逻辑）**，不依赖桌面机。日期 2026-08-28。

---

## 0. 决策记录（ADR 摘要）

### 决策：移动端用 Flutter，独立运行

| 项 | 决策 | 理由 |
|---|---|---|
| 框架 | **Flutter**（一套 Dart → Android + iOS 原生二进制） | SSE 逐 token 渲染无 JS 桥延迟；`drift` SQLite 类型安全；像素级 UI 控制（满足去 AI 味）；`webview_flutter` 官方支持 |
| 架构 | **手机独立运行，重写后端逻辑** | 调研证实 Python/FastAPI 上不了移动端（iOS 无路径，Android Chaquopy 官方不背书）；Tauri 移动端只能做纯 WebView 客户端（无 sidecar 进程能力），仍需远端后端 |
| 数据 | 手机本地 SQLite（`drift`）+ API Key 存系统安全存储（Keychain/Keystore） | 独立可用、无云依赖；与桌面数据各自独立 |
| 后端来源 | 无自建后端；App 内 `dart:io` 直连公网 HTTPS LLM API | 桌面 FastAPI 中间层是 Python SDK 导入所需，移动端直接发 HTTP 即可，省掉整层 |

### 为什么调研结论反而印证了 Flutter 独立路线

调研原本围绕"移动端访问桌面后端"展开，但结论恰好证明**独立运行只能走原生重写**：

- **Python 上不了移动端**（`mobile-adaptation-research.md` §2）：PyInstaller 仅桌面；iOS 无嵌入 CPython 成熟路径（App Store 2.5.2 禁止下载执行代码）；Android Chaquopy 能装纯 Python 依赖但不背书常驻 web server。→ 桌面那套后端无法进手机。
- **Tauri 移动端无法 sidecar**（§1.4）：移动端 shell 插件仅 `open` URL，无进程执行 → Tauri 移动壳也只是"访问远端后端的纯客户端"，同样需要远端后端。
- **结论**：要"手机独立可用"，唯一正解是在移动端原生实现业务逻辑——即用户选定的 Flutter 独立路线。
- **PWA/明文/混合内容政策墙**（§3.4~3.7）：对独立路线**不构成问题**——Flutter App 直连的是公网 HTTPS 的 `api.anthropic.com` / `api.openai.com`，无混合内容、无明文、无 ATS 问题。这比"PWA 访问局域网后端"干净得多。
- **SSE 可用性**（§3.2 / §5.2）：`dart:io` 是原生 HTTP 客户端，**不受浏览器每域 6 连接限制**，多 tab 并行流式无障碍。
- **Tailscale/伴生客户端模式**（§4）：仅作未来"连接桌面同步数据"的可选功能，非独立路线 MVP 所需。

---

## 1. 架构总览

```
┌─────────────────────────────────────────────────────┐
│              Flutter App (Android + iOS)              │
│                                                       │
│  ┌──────────────┐   ┌──────────────────────────────┐  │
│  │  UI (Widgets) │   │  业务逻辑层（纯 Dart）         │  │
│  │              │   │  替代桌面 FastAPI 后端          │  │
│  │  HomeShell   │   │  ┌────────────────────────┐  │  │
│  │  (底部导航5)  │   │  │ ChatService           │  │  │
│  │  ChatView    │──▶│  │  • buildMessageList   │  │  │
│  │  CharList    │   │  │  • streamReply (SSE)  │  │  │
│  │  SearchView  │   │  │  • regenerate         │  │  │
│  │  SimListView │   │  │  • 滑窗/模板变量       │  │  │
│  │  Settings    │   │  └────────────────────────┘  │  │
│  │              │   │  ┌────────────────────────┐  │  │
│  │              │   │  │ LLMService            │  │  │
│  │              │   │  │  • ClaudeProvider     │  │  │
│  │              │   │  │  • OpenAIProvider     │  │  │
│  │              │   │  │  • (直接发 HTTP+SSE)  │  │  │
│  │              │   │  └────────────────────────┘  │  │
│  │              │   │  ┌────────────────────────┐  │  │
│  │              │   │  │ 数据层（drift）         │  │  │
│  │              │   │  │  • 角色/对话/消息/设置  │  │  │
│  │              │   │  │  • 搜索 / V2卡 / 导出   │  │  │
│  │              │   │  └────────────────────────┘  │  │
│  │              │   └──────────────────────────────┘  │
│  │              │                                      │
│  │  ┌───────────▼──┐  ┌─────────────────────────────┐  │
│  │  │ SQLite(drift) │  │ WebView (模拟器 HTML 游戏)  │  │
│  │  │ SecureStorage │  │ + file_picker / share       │  │
│  │  │ (API Keys)    │  └─────────────────────────────┘  │
│  │  └───────────────┘                                   │
│  └───────────────┬──────────────────────────────────────┘
│                  │ HTTPS（直连公网 LLM API）
│                  ▼
│     ┌─────────────────────────┐
│     │  api.anthropic.com      │
│     │  api.openai.com         │
│     │  （及国产兼容 base_url）  │
│     └─────────────────────────┘
└─────────────────────────────────────────────────────┘
```

**与桌面的关键差异**：桌面有 FastAPI 中间层（Python SDK 导入 + 凭据解析 + 模拟器代理）。移动端全部在 App 内完成——LLM 直连、无代理、无同源 iframe。

---

## 2. 项目结构与依赖

### 2.1 目录（新建 `mobile/` 顶层目录，与 `backend/`、`frontend/` 并列）

```
mobile/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── app.dart                    # MaterialApp + 主题注入
│   ├── theme/
│   │   ├── conver_theme.dart       # 设计 token → ThemeData（§5）
│   │   ├── colors.dart
│   │   └── text_styles.dart
│   ├── models/                     # Character/Conversation/Message/Setting/Simulator
│   ├── data/
│   │   ├── database/app_database.dart   # drift DB（4 表）
│   │   └── repositories/                # 各表仓储
│   ├── services/
│   │   ├── llm/                    # llm_provider / claude / openai / factory
│   │   ├── chat_service.dart       # 回合编排（滑窗/模板变量/重生成）
│   │   ├── character_card.dart     # SillyTavern V2 卡 导入导出
│   │   ├── document_parser.dart    # LLM 从文本提角色字段
│   │   ├── game_generator.dart     # AI 生成游戏 + 六项校验
│   │   ├── search_service.dart
│   │   └── simulator_bridge.dart   # WebView ↔ Flutter 桥（§4）
│   ├── view_models/                # Provider 状态
│   ├── views/
│   │   ├── home_shell.dart         # 底部导航（§6.1）
│   │   ├── chat/                   # 对话列表 + 聊天
│   │   ├── characters/             # 列表 + 创建向导
│   │   ├── search/
│   │   ├── simulators/             # 列表 + 运行(WebView) + 存档
│   │   ├── settings/
│   │   └── profile/                # 「我」：手册/关于/桌面版
│   └── widgets/                    # 共享组件
└── assets/
    ├── simulators/                 # 22 款内置单文件 HTML 随包
    └── icons/
```

### 2.2 依赖清单

| 包 | 用途 | 备注 |
|---|---|---|
| `drift` + `drift_flutter` | SQLite ORM（类型安全、迁移、响应式查询） | 替换桌面 SQLAlchemy |
| `dio` | REST 调用（拦截器/进度/超时/断点） | 用户拍板选 dio（替代 `http`） |
| `flutter_markdown` | 聊天 Markdown 渲染 | 需自定义样式对齐主题 |
| `webview_flutter` | 模拟器 HTML 游戏 | 官方 |
| `flutter_secure_storage` | API Key（Keychain/Keystore） | 替换桌面 DB settings |
| `file_picker` | 角色卡/文档/游戏文件选择 | 移动端不能选文件夹（调研 §1.5） |
| `share_plus` | 导出对话/角色卡/存档分享 | |
| `provider` | 状态管理 | 轻量，官方推荐 |
| `path_provider` | 数据目录定位 | |

---

## 3. 功能迁移映射（"不阉割功能"核对）

| 桌面功能 | 移动端方案 | 难度 |
|---|---|---|
| 聊天（SSE 流式/停止/重生成/复制/切模型/导出） | 全量移植到 Flutter。SSE 用 `dart:io HttpClient` + `Stream`，逐 token 渲染 | ⭐ |
| 角色管理（CRUD/6步向导/V2卡导入导出/级联删除） | 全量。向导改全屏分步；文件选择走 `file_picker`；级联删除在事务内 | ⭐ |
| 搜索（跨对话 + 结果跳转定位高亮） | 全量。`drift` 跨表模糊查询 | ⭐ |
| 设置（API Key/模型/滑窗/主题/模板变量/危险操作） | 全量。Key 存 SecureStorage；模型清单内置 | ⭐ |
| 文档解析（LLM 从文本提角色字段） | 全量。复用桌面 prompt，直连 LLM | ⭐ |
| AI 生成游戏（LLM→HTML + 六项校验） | 全量。校验逻辑用纯 Dart 重写；生成 HTML 落文档目录 | ⭐⭐ |
| 模拟器（HTML 游戏运行 + Key 注入 + 存档管理 + 导入/生成） | **全量**（ADR-0002 锁定）——本地 HTTP 托管 + CORS 直连 + 注入/存档 JS 桥，见 §4 | ⭐⭐⭐ |

**7 项功能全量移植，无阉割。**

---

## 4. 模拟器难点（专节）

### 4.1 桌面形态回顾

桌面：22 款单文件 HTML 游戏**同源托管**于 `/simulators/`，主应用与游戏共享 localStorage，`key-injector` 注入 API Key 到游戏配置控件，后端 `/proxy` 反代第三方游戏 API 绕过 CORS。

### 4.2 移动端形态（ADR-0002 锁定）

- **托管（Q1）**：App 内 `dart:io HttpServer` 监听 `127.0.0.1:<port>`，serve 文档目录下的游戏文件（内置种子首启拷贝，用户导入/AI 生成落文档目录）。origin 为正常 http 源 → localStorage 正常持久化、CORS 行为与桌面同构。
- **Key 注入（Q2）**：`runJavaScript` 从 Dart 单向注入，保留桌面 `key-injector` 契约全部语义（白名单三元组 key/endpoint/model、endpointMode 口径、受管模型 option），游戏代码零改动；C1 写回环熔断删减为「注入幂等守卫」（双向写回不复存在）。
- **存档（Q3）**：单 origin + 前缀隔离（与桌面同构）；存档管理用 `runJavaScript` 枚举 localStorage 键，复用 saveKeys 白名单；导出格式对齐桌面以便双端互迁。
- **存档管理入口（Q12）**：模拟器列表页 AppBar 按钮 → 底部半屏 sheet（一次管全部游戏）。

### 4.3 核心矛盾：无 `/proxy`

桌面靠后端反代解决"游戏直连第三方 API 被 CORS 拦"。移动端无后端，游戏在 WebView 内 fetch LLM API 会撞 CORS。

### 4.4 方案③实测证据（prototype spike，2026-08-28）

对 LLM API 做了 CORS 直连实测（preflight curl + 浏览器真实 fetch，假 Key 即可判定——CORS 在鉴权前执行，放行则拿到 4xx、拦截则 TypeError）。证据目录（桌面库）：`desktop/.scratch/mobile-cors-spike/`。

| 厂商 | preflight (curl) | 浏览器实测 | 裁决 |
|---|---|---|---|
| DeepSeek（OpenAI 兼容） | 200 + `Acc-Allow-Origin/Methods/Headers` 完整 | HTTP 401（可达服务端） | ✅ 直连放行 |
| Moonshot Kimi（OpenAI 兼容） | — | HTTP 401（可达） | ✅ 直连放行 |
| 智谱 GLM（OpenAI 兼容） | — | HTTP 401（可达） | ✅ 直连放行 |
| Anthropic（Claude 官方） | 403 且**无任何 CORS 头** | TypeError: Failed to fetch | ❌ 拦截 |
| OpenAI（官方） | 本环境不可达 | 超时/拦截 | ❌ 未放行 |

**结论（高置信）**：**国内 OpenAI 兼容厂商放行浏览器 CORS，WebView 内直连可行；Anthropic/OpenAI 官方不放行**。叠加桌面既定设计"claude key 值绝不进入游戏"（游戏只用 OpenAI 兼容端点），**主流使用场景（base_url 指向 DeepSeek/Kimi/GLM/Qwen/自配三方）可直连**，代理问题在主流场景下消失。

> ⚠️ 已按 ADR-0002 消除的原风险：本实测 origin 为 `http://localhost`（正常 origin）；原担心 `loadHtmlString` 的 null/origin 会影响 CORS 与 localStorage——因托管方案选定**本地 HTTP 服务器（正常 http 源）**，该担忧作废。M5 待复验项收敛为「真实 Android/iOS WebView 上 localStorage 的跨重启持久化」（低风险，属平台行为确认，非架构风险）。

### 4.5 最终决策（ADR-0002 锁定，2026-08-28）

| 决策项 | 结论 |
|---|---|
| MVP 门槛 | **完整桥接全量**：本地托管 + Key 自动注入 + 存档管理全做，AI 驱动游戏全通 |
| 托管方式（Q1） | **本地 HTTP 服务器**（`127.0.0.1:<port>` serve 文档目录） |
| 数据目录 + 导入链（Q4） | 内置游戏 assets → 首启种子到文档目录；**导入校验链全量移植**（净化/SHA-256 去重/cfg 探测/粗筛） |
| 安全契约（Q5） | **比桌面更紧**：Key 存 SecureStorage 仅需时注入、claude key 恒不进游戏 |
| 移动覆盖层（Q6） | MVP **不做**（可缩放先行）；移动触屏覆盖层 = 迭代期独立批次 |
| Key 注入（Q2） | 保留桌面注入契约全部语义（游戏零改动），熔断删减为「注入幂等守卫」 |
| 存档隔离（Q3） | 单 origin + 前缀隔离，复用 saveKeys 白名单，导出格式对齐桌面 |
| 存档管理入口（Q12） | 列表页 AppBar 按钮 → 底部半屏 sheet |
| 恶意模式命中（Q14） | **拒绝 + 显示命中关键词清单 + 强制二次确认**（知情放行，化解文档类 HTML 误杀） |

**CORS 直连（方案③）为默认路径**；JS fetch 拦截垫片（方案①）仅为 Claude/OpenAI 官方端点保留兜底位（迭代期视反馈再定）；分期阉割（方案②）不再需要。官方端点游戏先提示「需桌面端运行」。

---

## 5. UI 设计系统（去 AI 味）

### 5.1 设计语言：延续桌面 "Warm Stone 暖灰 + 琥珀金"

桌面端已有一套克制、非模板化的设计系统（`frontend/css/style.css` `:root` token）。移动端**直接复刻**，杜绝通用 AI 聊天 UI。

**色板映射（CSS token → Flutter Color）**：

| 语义 | CSS（深色默认） | Flutter |
|---|---|---|
| 页面底色 | `--page: #171512` | `Color(0xFF171512)` |
| 面板分层 | `--bg/panel-1..4` | 由深到浅 4 档面板 |
| 边框 | `rgba(244,237,226,0.07/0.13/0.04)` | 低透明暖白边框（三档） |
| 文字 | `--ink-1..4` | 四级文字（`#f1ece4→#7f7467`） |
| **强调（accent）** | `--accent: #d29a47`（琥珀金） | `Color(0xFFD29A47)` |
| 强调软底 | `--accent-soft: rgba(210,154,71,0.13)` | 琥珀 13% 透明度 |
| 成功/危险/警告 | `#79a781` / `#cf7462` / `#d29a47` | 同值 |
| 圆角 | 3–12px，气泡 12px | 克制圆角，**不泛用大圆角** |
| 间距 | 4/8/12/16/20/24/32/40/48 | 同 8pt 栅格 |

### 5.2 "去 AI 味"明确清单（不要做什么）

- ❌ 紫色/蓝色渐变背景、发光描边
- ❌ 机器人/星形/火花吉祥物图标、emoji 图标
- ❌ 过度圆角 + 大投影的"果冻卡片"
- ❌ 满屏大留白小字号（信息密度稀薄）
- ❌ "typing..." 三个点过度使用

**要做什么**：单点琥珀强调、低饱和暖灰层次、1px 边框分割、统一线性图标（沿用桌面 SVG 图标库语义）、信息密度适中的列表。整体是"专业工具感"，不是"聊天机器人感"。

---

## 6. 移动端交互设计（对齐《Web↔移动交互差异》报告）

| 交互 | 桌面 | 移动端方案 |
|---|---|---|
| 导航 | 侧栏 6 模块 | **底部导航 5 tab**：聊天/角色/搜索/模拟器/设置；用户手册/关于/桌面版说明收进设置页分组 |
| 对话列表 | 侧栏常驻 | **全屏抽屉/独立页**（点击进入具体对话），非 35vh 半屏；下拉刷新 |
| 批量选择 | 卡片按钮逐个 | **长按进入多选模式**，批量删除角色/对话 |
| 刷新 | 刷新按钮 | **下拉刷新**（对话列表/角色列表/模拟器列表） |
| 消息操作（复制/重生成） | Hover 显示 | **触屏常驻**小图标（气泡底部），或长按弹出操作条 |
| 复杂表单 | select/级联 | 滚轮 picker / 分步全屏向导 |
| 键盘适配 | — | `viewPadding`/`MediaQuery` 防输入框被键盘遮挡 |
| 停止生成 | 按钮变红 | 红色大按钮，触屏友好 |
| 安全区 | — | `SafeArea` + `env(safe-area-inset-*)` |

### 底部导航信息架构（用户定稿 2026-08-28：设置独立 tab）

```
┌──────┬──────┬──────┬──────┬──────┐
│ 聊天  │ 角色  │ 搜索  │ 模拟器│ 设置  │
│ 💬   │ 👤   │ 🔍   │ 🎮   │ ⚙️   │
└──────┴──────┴──────┴──────┴──────┘
  设置页分组：API 配置 / 默认模型 / 对话 / 主题 / 模板变量 /
             用户手册 / 关于 / 桌面版说明
```

---

## 7. 开发里程碑

| 里程碑 | 内容 | 门 |
|---|---|---|
| **M0 脚手架** | Flutter 工程、drift 建 4 表、主题 token 落地、底部导航壳 | Android 模拟器能跑空壳 |
| **M1 数据层 + 设置** | 角色/对话/消息 CRUD、SecureStorage 存 Key、模型清单、主题切换 | 单测覆盖仓储 + 设置 |
| **M2 聊天核心** | ChatService（滑窗/模板变量/重生成）+ SSE 流式渲染 + 停止 | 端到端打字机流畅 |
| **M3 角色 + 搜索** | 角色列表/6步向导/V2卡导入导出/级联删除；跨对话搜索定位高亮 | 与桌面行为对齐 |
| **M4 导出/文档解析** | 对话导出(JSON/MD)、分享；LLM 文档解析角色字段 | 单测 |
| **M5 模拟器** | WebView 加载 + Key 注入 + localStorage 存档验证 + CORS 直连复验（§4.4）；「我」页收口 | WebView 桥稳定，主流游戏可运行 |
| **M6 去 AI 味打磨** | 动效/空态/错误态/无障碍/弱网断线重连 | 视觉评审 |
| **M7 发布准备** | 双端图标、Android AAB/iOS 签名、隐私清单 | 上架/侧载包 |

### 7.1 验证分层（Windows 开发机上"怎么确认它能跑"）

| 层 | 验证方式 | 需要什么 | 在 Windows 开发机可行？ |
|---|---|---|---|
| 业务逻辑（chat/llm/数据层/导入链/生成校验） | `flutter test`（纯 Dart 单测，跑在宿主 Dart VM，**无需模拟器**） | 仅 Flutter SDK | ✅ 本环境可跑 |
| Widget/UI | `flutter test`（无头 widget 测试） | 仅 Flutter SDK | ✅ 本环境可跑 |
| 编译产物 | `flutter build apk` | Android SDK/NDK + JDK | ✅（需本机装 Android 工具链；M0 时验证可用性） |
| Android 运行 | Android Studio AVD 模拟器 / USB 真机（`flutter run`） | AVD 需开启虚拟化（WHPX/Hyper-V）；真机需 adb | ✅ 但需本机配置 |
| iOS 运行 | Xcode Simulator（`flutter run`） | **macOS + Xcode** | ❌ Windows 上不可行；需 Mac/CI（如 GitHub Actions macOS runner） |
| UI 冒烟（可选） | `flutter build web` → 浏览器/Playwright 驱动 | Flutter web target | ✅ 但只验证 UI 逻辑，不验证平台通道 |

**要点**：本项目业务逻辑占绝大多数且是纯 Dart → 大部分可靠性由 `flutter test` 兜底（无模拟器也能持续验证）；平台相关的薄层（WebView 桥、SecureStorage、本地服务器端口绑定）集中做真机/模拟器验证。ZCode 环境没有内置 Android/iOS 模拟器工具；Android 走本机 AVD/真机，iOS 需 macOS（CI/借 Mac）。

---

## 8. 风险与开放问题

| 风险 | 等级 | 对策 |
|---|---|---|
| 模拟器 AI 驱动游戏在 **Claude/OpenAI 官方端点** 下无法直连（CORS） | 中（已实测分界） | 主流国产兼容端点已验证直连可行（§4.4）；官方端点先提示"需桌面端运行"，视反馈再上 fetch 垫片（§4.5） |
| 真实移动 WebView 的 localStorage 跨重启持久化 | 低 | 托管已选本地 HTTP 服务器（正常 http 源，origin 风险消解）；M5 真机复验存档持久化即平台行为确认 |
| iOS 需 macOS 构建（Xcode） | 中 | 无 Mac 则先用 Android 开发，iOS 用 CI/借用；架构上双端同源码 |
| 弱网 SSE 断线 | 中 | 心跳/重连管理器（调研 §5.2 工程要点） |
| 数据与桌面不互通 | 低（既定） | 可选后期：Tailscale + 桌面"导出/导入"或伴生同步（§4 调研路线） |

---

## 9. 相关文档

- 技术可行性事实：[mobile-adaptation-research.md](mobile-adaptation-research.md)（本目录）
- 模拟器决策：桌面库 `desktop/CONSENSUS.md` **ADR-0002**（本地托管 + CORS 直连 + 注入/存档桥）；ADR-0001（桌面 key-injector 契约前提）
- 桌面架构参照：`desktop/docs/architecture.md`（业务逻辑迁移蓝本）
- 桌面设计 token：`desktop/frontend/css/style.css` `:root`
- 桌面 LLM 编排蓝本：`desktop/docs/llm-integration.md` · `desktop/backend/app/services/chat.py`
- 桌面游戏生成/校验蓝本：`desktop/backend/app/services/game_generator.py`
- 桌面模拟器适配蓝本：`desktop/frontend/js/simulator-adapt.js` · `desktop/frontend/js/key-injector.js`
- CORS 实测证据：桌面库 `desktop/.scratch/mobile-cors-spike/`（prototype，请勿复用为生产代码）
