# Conver System · 移动端（mobile）

Conver System 的移动端应用（Flutter，Android + iOS 独立运行，无桌面后端依赖）。

## 状态

- **当前状态见 [AGENTS.md](AGENTS.md) §当前状态**——逐批次交付记录（M0~M7 + 人机恋阶段 + 技术债批次，最新在前，2026-09-21 收口 F-140/141/142，全量 2836 测绿）
- **已做与避坑见 [DEV_LOG.md](DEV_LOG.md)**（倒序，最新在前）
- **里程碑定位**：M0 脚手架（2026-08-29）→ M1 数据层+设置 → M2 聊天核心 → M3 角色+搜索 → M4 导出/文档解析 → M5 模拟器全量 → M6 去 AI 味打磨 → M7 发布（Android 2026-09-09；iOS 延后，Windows 无 macOS 路径）
- 权威设计文档：`docs/mobile-design.md`（架构 / 7 项功能全量 / 依赖清单 / 里程碑）
- 技术调研：`docs/mobile-adaptation-research.md`
- 模拟器决策（ADR-0002）与桌面环境装载/验证记录见桌面端仓库：`desktop/CONSENSUS.md`、`desktop/DEV_LOG.md`

## 开发文档

- [项目规则](AGENTS.md) — 技术栈、目录约定、测试规范、档位制
- [项目介绍](PROJECT_REFERENCE.md) — 背景、关键决策、常碰坑点
- [设计文档](docs/mobile-design.md) — 架构、7 项功能、模拟器专题、里程碑 M0–M7（单一事实来源）
- [任务清单](TICKETS.md) — 唯一待办事实来源（M0–M7 已录入）
- [发布指南](docs/release-android.md) — 版本策略、AAB/APK 发布命令链、签名核对、keystore 生命周期
- [Android 隐私清单](docs/privacy-android.md) — 数据安全表单备查、零第三方 SDK 实证审计
- [开发日志](DEV_LOG.md) — 已做与避坑
- [共识文档](CONSENSUS.md) — 决策登记与 ADR 索引
- [文档规范](docs/documentation-standards.md) — 单一事实来源分配与跨端引用约定

## 版本控制约定

本库为独立 git 历史（有别于桌面端 `main` 历史），托管于同源仓库

https://github.com/Penumbra-Noviter/conver-system.git

的 **`mobile` 分支**。推送即 `git push -u origin mobile`。

## 快速开始

前置：本机已装载 Flutter SDK（stable）与 Android SDK（环境变量 `JAVA_HOME` / `ANDROID_HOME`）。

```bash
# 1. 拉取依赖
flutter pub get

# 2. 运行测试（全绿为每票底线）
flutter test

# 3. 连接设备或启动模拟器后运行
flutter run

# 4. 构建 debug APK（产物在 build/app/outputs/flutter-apk/）
flutter build apk --debug
```