# Conver System 移动端 — 项目规则

## 项目定位

Conver System 的**移动端独立应用**（Flutter，Android + iOS 一套 Dart 代码）。手机独立运行：无桌面 FastAPI 后端依赖，App 内 `dart:io` 直连公网 HTTPS LLM API，复刻桌面版全部 7 项功能（不阉割）：聊天 SSE / 角色 / 搜索 / 设置 / 文档解析 / AI 生成游戏 / 模拟器。

## 技术栈

Flutter + Dart（详见 [CONSENSUS.md](CONSENSUS.md) 与设计文档 [docs/mobile-design.md](docs/mobile-design.md) §0/§2.2）：`drift`（SQLite ORM）、`provider`（状态管理）、`flutter_secure_storage`（Key）、`dio`（REST，非流式）、`flutter_markdown_plus`（聊天 Markdown 渲染）已落地；`file_picker`（^12.1.2）/ `share_plus`（^13.3.0）/ `path_provider`（^2.1.6）已随 M3-03 转正入 pubspec（V2 卡导入导出）；`webview_flutter`（^4.14.1）与 `crypto`（^3.0.7，SHA-256）已随 M5-01 落地（模拟器 WebView 桥 + 导入去重）。模拟器业务逻辑集中在 `lib/services/simulator/`（data_dir / seed / manifest_parser / contracts / server / injection / save / import / generate，纯 Dart 可单测），平台薄层（WebView 桥、本地 HTTP 服务器）经 seam 隔离。

## 目录与约定

按 [docs/mobile-design.md](docs/mobile-design.md) §2.1 的 `lib/` 分层：`theme` / `models` / `data` / `services` / `view_models` / `views` / `widgets`。

**关键约定**：
- 模块要"深"：协议表面小、实现丰富；`services/` 承载纯 Dart 业务逻辑（可单测），`views/` 只做展示编排
- 公开函数必须有类型注解 + docstring（Dart 写法）；私有成员 `_` 前缀
- 业务逻辑用英文命名，UI 层枚举可用中文（沿用全局惯例）
- 平台薄层（WebView 桥、SecureStorage、本地 HTTP 服务器）集中隔离在 `services/simulator_bridge.dart` 等 seam 之后，不散落进 views
- UI 复刻桌面 "Warm Stone 暖灰 + 琥珀金" 设计系统（§5 token 表），禁"AI 味"（见 §5.2 清单）

## 怎么跑起来

```bash
flutter pub get
flutter test                 # 宿主无头跑，无需模拟器（验证分层见 §7.1）
flutter run -d <serial>      # Android 模拟器/真机（adb）
flutter build apk            # 产物（需 Android SDK/JDK，本机已装于 D:\Desktop\tools\Cache）
```

iOS 需 macOS + Xcode（Windows 开发机不可行，走 CI/借 Mac）。

## 测试规范

- `flutter test`（纯 Dart 单测 + 无头 widget 测试），覆盖率目标 ≥ 90%
- 业务逻辑（chat/llm/数据层/导入链/生成校验）占比最大且是纯 Dart → 可靠性主要由单测兜底；平台薄层做真机/模拟器验证

## 当前状态（2026-09-10）

- ✅ 设计已落盘：`docs/mobile-design.md`（单一事实来源）+ `docs/mobile-adaptation-research.md`（决策背景）；决策集 Q0~Q14 已拍板，ADR-0002 见桌面库 `desktop/CONSENSUS.md`
- ✅ 工具链就绪（D:\Desktop\tools\Cache：JDK17/Gradle8.9/SDK35+36+37/AEHD + Flutter 3.47.2；AVD medium_phone 数据已迁至 F:\tools\android\avd，2026-09-04；MCP 插件 preflight 全绿）
- ✅ **M0 已交付**（2026-08-29）：脚手架 + drift 4 表 + 深色主题 token + 5 tab 壳（应用名「汇流」），G0 模拟器空壳验收全项通过
- ✅ **M1 已交付**（2026-08-29）：4 仓储 CRUD 全语义 + SecureStorage 双槽位 + 模型清单单源 + 主题三值切换（auto/浅/深），G1–G5 门 + G6 模拟器冒烟全项通过；merge 收口 a1d4265
- ✅ **技术债批次 F-7/F-8/F-9 已交付**（2026-08-29）：视图 token 主题化（ConverPalette ThemeExtension）+ 设置页错误面 + 装配 required 化，全量 171 测 / 覆盖率手写口径 90.63% / 四轴零阻断 / 冒烟 PASS；merge 68e8d19
- ✅ **M2 已交付**（2026-08-29）：聊天核心——LLM Provider 双协议 SSE wire（Claude/OpenAI 直连）+ ChatService 回合编排（滑窗/模板变量/重生成/停止/断流）+ 打字机 UI + 最小临时会话入口 + test_connection；全量 477 测 / 覆盖率手写口径 95.42% / 四轴零阻断 / A7 冒烟窄路径 PASS（真实流式留待 Key）；merge 59e766a
- ✅ **技术债批次 F-10~F-17 已交付**（2026-08-30）：7 做 1 关闭 / 6 工单 2 波 merge b9dc9bc / 全量 497 测 / analyze 0 / 覆盖率剔除 drift 97.96% / 四轴零阻断 / 冒烟 PASS / TICKETS 已归档 / 技术债候选区清零
- ✅ **M3 已交付**（2026-08-30）：角色 + 搜索——角色列表卡片+四按钮+下拉刷新+长按批量删除 / 6 步全屏向导+5 模板 / V2 卡导入导出（file_picker ^12.1.2 / share_plus ^13.3.0 / path_provider ^2.1.6 转正）/ 跨对话搜索防抖五态+跳转定位 3s 高亮；全量 729 测 / analyze 0 / 覆盖率剔除 drift 98.06% / 四轴零阻断 / 冒烟 PASS（建角色→落库→搜索→跳转高亮真机实证）；merge 70bc094 + 期末修复 0057d9e/9cfc4aa；TICKETS 已归档
- ✅ **M4 已交付**（2026-09-06）：导出/文档解析——对话导出 JSON/MD（share_plus 分享面板 + 平台超时兜底）/ LLM 文档解析（三级提取+白名单+错误折叠）；全量 802 测 / analyze 0 / M4-06 冒烟 PASS；merge 42099eb + 25c7696 + 修复 1feddd7
- ✅ **M5 已交付**（2026-09-07）：模拟器全量——22 款随包种子 + 本地 HTTP 托管（127.0.0.1:8642 + 目录墙 + 双端明文工）+ 列表四态/懒启动 + Key 注入（桌面契约逐字 + claude key 不进 + 官方端点提示）+ 存档管理 + 导入链 + AI 生成 + 「我」页收口；全量 1315 测 / analyze 0 / M5 门冒烟 PASS（CORS 复验 + 持久化 + 五游戏 25 轮零崩溃）；11 票 7 波合入收口 3d34ed2；TICKETS 11 票已归档
- ✅ **M6 已交付**（2026-09-08）：去 AI 味打磨——动效克制子集 8 项（ConverDurations 对齐桌面、零动画库）+ 空态/错误态/弱网断线重连（连接重试 2 次退避 1s/2s + 断流「回复中断」标记 + NoticeBanner 重试=regenerate replace + idle 60s）+ 实用层无障碍（F-73 浅色 accent #784E14 对比度 ≥4.5:1 + a11y 语义 15 断言）；全量 1460 测 / analyze 0 / 覆盖率 96.78% / 期末四轴阻断 0 / M6 门视觉评审 8/8 PASS（含 B1 核心路径模拟器实测）；11 票 7 波 + B1×2 合入收口（收官 5e7bd33）；TICKETS M6 已归档
- ✅ **M7 已交付**（2026-09-09，Android 范围收窄、iOS 延后）：自适应启动图标（PIL 管线程序化生成「汇」字形占位稿 + flutter_launcher_icons adaptive/monochrome/legacy，确定性可再生）+ release 签名（仓库外 keystore「F:\Craft\conver system\keys\」+ gitignored key.properties，AAB/APK 同证书）+ 隐私清单（docs/privacy-android.md 三节式 + 零第三方 SDK 实证审计）+ 发布验证门禁（docs/release-android.md 版本策略 1.0.0+1 / versionCode=1 + 双产物命令链 + AVD 冒烟 PASS）；发布构建见 `flutter build appbundle|apk --release`；全量 1518 测绿 / analyze 0 / pytest 57 / 期末四轴 0 阻断。iOS 全部延后（Windows 无 macOS 路径，design §7.1），仅 TICKETS 注记（iOS 图标/签名/隐私/上架未建产物）
- ✅ **真机问题批次已收口**（2026-09-10）：测试连接传 default_model + 注入 toProxyEndpoint 同源改写 + server /proxy 流式反代（全相位超时 60s + key App 侧注入 + SSE 透传）；全量 1612 测绿 / analyze 0 / 真实端点链路 200 PASS / 期末四轴 0 阻断；merge 265e305/8ead524/6cb3885 + 超时修复 fd3820b
- ✅ **技术债折回 F-68~74 已全部处置**（2026-09-10）：F-68/69/70 消费（release 签名守卫 + 图标色值双向守卫 + privacy_audit 删 Speculative 分支）+ F-71/72/74 复核关闭 + F-73 交叉校验测试；候选区清零；全量 1613 测绿 / analyze 0 / pytest 66
- ✅ **架构审查批次 C1~C4 已收口**（2026-09-10）：translateError 下沉 LLMProvider 基类默认实现 / 装配腿收敛（wireCredentialsResolver 单一落点）/ 双文件名净化器参数化合并 / 删 PlaceholderGroup + settings 行收敛；全量 1579 测绿（+61）/ analyze 0 / 期末四轴 0 阻断；落债 F-72
- ✅ **技术债消费批次 F-75/F-76/F-77 已全部处置**（2026-09-14）：F-76 消费（_resolveTemperature 加 NaN/Infinity 回退全局 + 越界 clamp [0,2]）+ F-75/77 复核关闭（种子 HTML 内容资产 CSS / SettingsReader implements 成本）；候选区清零；全量 1684 测绿（+3）/ analyze 0

## 文档体系

标准档：CLAUDE（本文件）/ [PROJECT_REFERENCE.md](PROJECT_REFERENCE.md)（项目事实）/ [TICKETS.md](TICKETS.md)（唯一待办来源）/ [DEV_LOG.md](DEV_LOG.md)（已做）/ [CONSENSUS.md](CONSENSUS.md)（决策）/ [CONTEXT.md](CONTEXT.md)（领域词汇）。规则见 [docs/documentation-standards.md](docs/documentation-standards.md)。

**档位制**：模块数 ≥ 8 且文档 > 1 页时自动升完整档（新增 CODE_WIKI.md + `scripts/doc_sync.py` 机械防漂移 + F-01 pre-commit 门），对标桌面库。