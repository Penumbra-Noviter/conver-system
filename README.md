# Conver System · 移动端（mobile）

Conver System 的移动端应用（Flutter，Android + iOS 独立运行，无桌面后端依赖）。

## 状态

- 设计已落盘并拍板（含 ADR-0002 模拟器决议）；Flutter 工程待创建（`/to-spec` → `/to-tickets` 拆单后开工）
- 权威设计文档位于**桌面端仓库**：`desktop/docs/mobile-design.md`（架构 / 7 项功能全量 / 依赖清单 / M0–M7 里程碑）
- 技术调研：`desktop/docs/mobile-adaptation-research.md`
- 环境装载与 Android 模拟器验证记录见桌面端 `desktop/DEV_LOG.md` 与项目记忆

## 版本控制约定

本库为独立 git 历史（有别于桌面端 `main` 历史），托管于同源仓库

https://github.com/Penumbra-Noviter/conver-system.git

的 **`mobile` 分支**。推送即 `git push -u origin mobile`。