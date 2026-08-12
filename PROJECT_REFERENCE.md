# Conver System — 项目介绍书

> **一句话**：本地优先、多模型可切换的角色对话应用。创建带人设的虚拟角色，与不同角色进行 AI 驱动的对话。
> **技术栈**：FastAPI + SQLAlchemy 2.0（**同步 ORM**）+ SQLite + pydantic-settings
> **形态**：网页版 SPA（Vanilla JS ESM）+ Tauri 桌面版（已交付，见 [docs/tauri-desktop.md](docs/tauri-desktop.md)）

---

## 一、项目概述

**当前状态**：功能完整，架构已收敛（2026-08-12）。Phase 1-5 + P6.1/6.2/6.3 + P2.5/3.5/4.3 全部完成；架构深化两波（ARC-1~8）与架构摩擦 11 候选全部落地；P6.5 多 tab 会话管理 + OPT-1 UI 克制化/图标协议收口 + **P6.4 Tauri 桌面版**（8 工单归档）已交付；ARC-9/ARC-10 架构深化批次（14 候选）与四轮技术债区批次（16 项 + TD-1~7 + TD-8~12 + TD-15~24 全清零）全部完成。测试：pytest 360+1skip（后端）+ Vitest 373（前端）+ cargo test 52（Tauri 壳）全绿。

**核心能力**：
- **角色管理** — 创建/编辑/删除角色，自定义人设、开场白、语气风格；六步创建向导（LLM 智能解析 + 内置模板）；支持 SillyTavern Character Card V2 格式导入/导出（JSON 卡，兼容 V1 旧卡与裸 data）。
- **多轮对话** — 与不同角色连续对话，历史完整保留，滑动窗口上下文联控（轮数可配）。
- **多 tab 会话工作区** — 应用内多会话 tab 切换，后台流式继续生成，完成/停止/出错按发起会话写回（防悬挂），刷新后 sessionStorage 恢复。
- **多模型支持** — 统一 LLM 接入层（Provider 工厂），支持 Claude / OpenAI / 兼容 API（`base_url` 可配，聚合平台通用凭证）。
- **流式/非流式输出** — 用户可切换打字机效果或完整回复；流式支持停止生成（部分内容落库）。
- **模板变量** — 角色设定中 `{{user}}`/`{{char}}` 动态替换。
- **搜索历史消息** — 跨对话关键词搜索 + 结果跳转。
- **本地存储** — 所有数据（含 API Key）存本地 SQLite，无云端依赖。
- **API Key 管理** — 内置设置面板管理密钥，运行时修改即时生效（保存时测试连接）。

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

## 四、桌面端（Tauri）已交付

**当前状态**（2026-08-11）：✅ P6.4 Tauri 桌面版已交付（8 工单归档）——Tauri v2 壳 + PyInstaller 打包后端 + 原生前端零改动；期末审核 2 个阻断（后端随包定位、前端随包挂载）均已修复闭合。构建 / 冒烟 / 数据目录 / 已知限制见 [桌面版文档](docs/tauri-desktop.md)，工具链安装见 [tauri-setup.md](docs/tauri-setup.md)。

**⚠️ 注意事项**：在 **cmd.exe** 或 **PowerShell** 中运行 `cargo build` / `tauri build` / PyInstaller（Git Bash 的 coreutils `link.exe` 会遮蔽 MSVC linker，详见 [tauri-setup.md](docs/tauri-setup.md)）。

## 五、相关文档

- [文档规范](docs/documentation-standards.md) — 文档架构与单一事实来源规则
- [共识文档](CONSENSUS.md) — 需求定义与技术决策
- [待办清单](TICKETS.md) — 唯一待办事实来源（活跃 + 归档）
- [开发日志](DEV_LOG.md) — 已做与避坑记录
- 技术细节统一以 `docs/` 为准：**[架构设计](docs/architecture.md)** · **[API 设计](docs/api-design.md)** · **[LLM 集成](docs/llm-integration.md)** · **[P2.5 导入导出](docs/p2.5-character-import-export.md)**
- 用户视角（安装/使用）见 [README.md](README.md)

*本文档定位为项目介绍（背景 / 关键决策 / 常碰坑点）。技术细节不在此维护，统一指向 docs/。*
