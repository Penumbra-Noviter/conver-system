# Conver System 移动端 — 项目规则

## 项目定位

Conver System 的**移动端独立应用**（Flutter，Android + iOS 一套 Dart 代码）。手机独立运行：无桌面 FastAPI 后端依赖，App 内 `dart:io` 直连公网 HTTPS LLM API，复刻桌面版全部 7 项功能（不阉割）：聊天 SSE / 角色 / 搜索 / 设置 / 文档解析 / AI 生成游戏 / 模拟器。

## 技术栈

Flutter + Dart（详见 [CONSENSUS.md](CONSENSUS.md) 与设计文档 [docs/mobile-design.md](docs/mobile-design.md) §0/§2.2）：`drift`（SQLite ORM）、`dio`（REST，用户拍板）、`flutter_secure_storage`（Key）、`webview_flutter`（模拟器）、`provider`（状态管理）、`flutter_markdown` / `file_picker` / `share_plus` / `path_provider`。

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

## 当前状态（2026-08-29）

- ✅ 设计已落盘：`docs/mobile-design.md`（单一事实来源）+ `docs/mobile-adaptation-research.md`（决策背景）；决策集 Q0~Q14 已拍板，ADR-0002 见桌面库 `desktop/CONSENSUS.md`
- ✅ Android 工具链就绪（D:\Desktop\tools\Cache：JDK17/Gradle8.9/SDK35+36/AEHD/AVD medium_phone + Flutter 3.47.2；MCP 插件 preflight 全绿）
- ✅ **M0 已交付**（2026-08-29）：脚手架 + drift 4 表 + 深色主题 token + 5 tab 壳（应用名「汇流」），G0 模拟器空壳验收全项通过；merge 收口 c55ced3
- ⬜ 下一站 M1（数据层 + 设置）：见 [TICKETS.md](TICKETS.md) 活跃表；技术债候选 F-1~F-6 见 [TECH_DEBT.md](TECH_DEBT.md)

## 文档体系

标准档：CLAUDE（本文件）/ [PROJECT_REFERENCE.md](PROJECT_REFERENCE.md)（项目事实）/ [TICKETS.md](TICKETS.md)（唯一待办来源）/ [DEV_LOG.md](DEV_LOG.md)（已做）/ [CONSENSUS.md](CONSENSUS.md)（决策）/ [CONTEXT.md](CONTEXT.md)（领域词汇）。规则见 [docs/documentation-standards.md](docs/documentation-standards.md)。

**档位制**：模块数 ≥ 8 且文档 > 1 页时自动升完整档（新增 CODE_WIKI.md + `scripts/doc_sync.py` 机械防漂移 + F-01 pre-commit 门），对标桌面库。