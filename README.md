# Conver System · 移动端（mobile）

Conver System 的移动端应用（Flutter，Android + iOS 独立运行，无桌面后端依赖）。

## 状态

- 设计已落盘并拍板（含 ADR-0002 模拟器决议）；Flutter 工程待创建（`/to-spec` → `/to-tickets` 拆单后开工）
- 权威设计文档：`docs/mobile-design.md`（架构 / 7 项功能全量 / 依赖清单 / M0–M7 里程碑）
- 技术调研：`docs/mobile-adaptation-research.md`
- 模拟器决策（ADR-0002）与桌面环境装载/验证记录见桌面端仓库：`desktop/CONSENSUS.md`、`desktop/DEV_LOG.md`

## 开发文档

- [项目规则](CLAUDE.md) — 技术栈、目录约定、测试规范、档位制
- [项目介绍](PROJECT_REFERENCE.md) — 背景、关键决策、常碰坑点
- [设计文档](docs/mobile-design.md) — 架构、7 项功能、模拟器专题、里程碑 M0–M7（单一事实来源）
- [任务清单](TICKETS.md) — 唯一待办事实来源（M0–M7 已录入）
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