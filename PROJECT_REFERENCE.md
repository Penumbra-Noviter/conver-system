# Conver System — 项目介绍书

> **一句话**：本地优先、多模型可切换的角色对话应用。创建带人设的虚拟角色，与不同角色进行 AI 驱动的对话。
> **技术栈**：FastAPI + SQLAlchemy 2.0（**同步 ORM**）+ SQLite + pydantic-settings
> **形态**：网页版 SPA（Vanilla JS ESM），扩展路径为 Tauri 桌面版

---

## 一、项目概述

**当前状态**：功能完整，架构已收敛。Phase 1-5 + P6.1/6.2/6.3 + P2.5 全部完成；代码质量 CR.1-CR.7 清零；测试基础设施就绪（`backend/tests/`，转换层 100% 覆盖）。

**核心能力**：
- **角色管理** — 创建/编辑/删除角色，自定义人设、开场白、语气风格；支持 SillyTavern Character Card V2 格式导入/导出（JSON 卡，兼容 V1 旧卡与裸 data）。
- **多轮对话** — 与不同角色连续对话，历史完整保留，滑动窗口上下文联控（轮数可配）。
- **多模型支持** — 统一 LLM 接入层（Provider 工厂），支持 Claude / OpenAI（含兼容 API，`base_url` 可配）。
- **流式/非流式输出** — 用户可切换打字机效果或完整回复；流式支持停止生成。
- **模板变量** — 角色设定中 `{{user}}`/`{{char}}` 动态替换。
- **本地存储** — 所有数据（含 API Key）存本地 SQLite，无云端依赖。
- **API Key 管理** — 内置设置面板管理密钥，运行时修改即时生效。

## 二、关键决策

| 决策 | 内容 |
|------|------|
| **ORM 形态** | SQLAlchemy 2.0 **同步** ORM + SQLite（不引入异步复杂度），PRAGMA foreign_keys=ON |
| **角色卡 V2** | 兼容 SillyTavern V2 信封 + 裸 data + V1 旧卡；非 V2 标准字段存 `extensions.conver_system.*` 命名空间保证往返保真 |
| **Message.role** | `Role` 枚举，`Enum` 列按值存取（落库存 `user`/`assistant`/`system`），兼容存量 VARCHAR 数据 |
| **上下文策略** | 滑动窗口保留最近 N 轮（默认 30，可从 settings 调），高级摘要压缩留待 Phase 6 |
| **配置分层** | API Key / 默认模型 / 滑窗轮数等运行时配置存 DB settings 表，`.env` 仅作基础模板 |
| **命名规范** | 路由函数 `list_*/get_*/create_*/delete_*` 前缀；SSE 端点允许 `stream_*` 特殊前缀 |
| **Git 策略** | 项目初步完善后已 `git init`，Conventional Commits（`<type>: <中文说明>`） |

## 三、常碰坑点

1. **同步 vs 异步**：代码是同步 ORM，`config.DATABASE_URL` 默认值虽带 `+aiosqlite` 前缀，但 `database.py` 引擎创建时 `replace("+aiosqlite","")` 剔除——勿据此误判项目为异步。
2. **`.env` 位置**：`config.py` 以 `env_file=".env"` 相对 CWD 读取，服务从项目根启动 → `.env` 在**项目根**，不是 `backend/` 下（`backend/.env.example` 仅是模板）。
3. **JSON 列兼容**：Character 的 `tags`/`alternate_greetings` 等为 SQLAlchemy JSON 列，存量 TEXT 数据可无缝读出；`Message.role` 枚举按值存取，存量 VARCHAR 无需迁移。
4. **SSE 停止语义**：停止生成 = 用户主动中止（`AbortController` 断开 + 后端 `is_disconnected()` 感知），气泡标记「（已停止）」而非错误；非流式不提供停止按钮。

## 五、桌面端准备（Tauri 前置）

**当前状态**（2026-08-03）：✅ 工具链完整可用

| 组件 | 版本 | 路径 |
|------|------|------|
| rustup | 1.29.0 | `C:\Users\Administrator\.rustup` |
| rustc / cargo | 1.97.1 (stable) | `C:\Users\Administrator\.cargo\bin\` |
| MSVC 工具 | 14.50.35717 | `C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.50.35717\` |
| Windows SDK | 10.0.22621.0 | `C:\Program Files (x86)\Windows Kits\10\` |

- 目标平台：`x86_64-pc-windows-msvc`
- `cargo build` 冒烟测试通过 ✅

**⚠️ 注意事项**：Git Bash 的 `/usr/bin/link.exe`（GNU coreutils）会遮蔽真正的 MSVC `link.exe`。  
**解决方案**：在 **cmd.exe** 或 **PowerShell** 中运行 `cargo build`。

## 六、相关文档

- [文档规范](docs/documentation-standards.md) — 文档架构与单一事实来源规则
- [共识文档](CONSENSUS.md) — 需求定义与技术决策
- [待办清单](TICKETS.md) — 唯一待办事实来源（活跃 + 归档）
- [开发日志](DEV_LOG.md) — 已做与避坑记录
- 技术细节统一以 `docs/` 为准：**[架构设计](docs/architecture.md)** · **[API 设计](docs/api-design.md)** · **[LLM 集成](docs/llm-integration.md)** · **[P2.5 导入导出](docs/p2.5-character-import-export.md)**
- 用户视角（安装/使用）见 [README.md](README.md)

*本文档定位为项目介绍（背景 / 关键决策 / 常碰坑点）。技术细节不在此维护，统一指向 docs/。*
