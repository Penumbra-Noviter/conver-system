# Conver System — 项目介绍书

> **一句话**：本地优先、多模型可切换的角色对话应用。创建带人设的虚拟角色，与不同角色进行 AI 驱动的对话。
> **技术栈**：FastAPI + SQLAlchemy 2.0（**同步 ORM**）+ SQLite + pydantic-settings
> **形态**：网页版 SPA（Vanilla JS ESM）+ Tauri 桌面版（已交付，见 [docs/tauri-desktop.md](docs/tauri-desktop.md)）

---

## 一、项目概述

**当前状态**：功能完整，架构已收敛（2026-08-19）。Phase 1-5 + P6.1/6.2/6.3 + P2.5/3.5/4.3 全部完成；架构深化两波（ARC-1~8）与架构摩擦 11 候选全部落地；P6.5 多 tab 会话管理 + OPT-1 UI 克制化/图标协议收口 + **P6.4 Tauri 桌面版**（8 工单归档）已交付；ARC-9/ARC-10 架构深化批次（14 候选）与六轮技术债区批次（16 项 + TD-1~7 + TD-8~12 + TD-15~24 + TD-25~27 + TD-29~41/43~45 清零；技术债区清零（TD-1~47 全部处置完毕））全部完成；**U7 模拟器模块**（2026-08-14 交付）——22 款第三方单文件模拟器集成：侧栏入口/卡片列表/筛选/iframe 运行/AI 提示条/冒烟脚本；**U8+U9 模拟器二期**（2026-08-14 交付）——模拟器模块补完：只读凭证端点（GET /api/settings/credentials）+ 主应用 Key 一键注入 + 存档管理面板（导出/导入/删除）；**TD-57/66/67/68 技术债批次**（2026-08-14 交付）——凭证 model 门控收紧（`_OPENAI_PROTOCOL_MODELS` 单源派生）/存档键契约单一来源（save-key-meta.js 深模块）/同源 iframe 信任边界文档化；技术债区清零后复开两轮——**SIM-API-1 模拟器 API 统一由主应用控制**（2026-08-14 交付，ADR-0001 定稿；22 款模拟器 credential/model 自动同步，按钮改「重新同步」）+ **TD-75/76 期末四轴修复**（观察者 attributes 监听 + 写回环熔断，技术债区清零至 TD-1~76）；**C1 写回环状态机收口**（2026-08-15 交付，架构评审候选——模拟器配置同步冷却/熔断状态从 simulator-view 收进 key-injector 单一状态机，`autoSyncIntoGame` path 参数 + `resetSyncLoop()`）+ **C6 后端 LLM 派生链收敛**（2026-08-15 交付，架构评审候选——LLM 派生链四份遍历收敛为 provider_registry.py 派生存取器深模块（PROVIDER_KEYS/API_PROVIDER_MAP/OPENAI_PROTOCOL_MODELS/resolve_api_provider），factory/setting 两消费方对标，F4 缺 id 对称校验修复）+ **C3/C4/C8 技术债批次**（2026-08-15 交付——C3 注入钩子统一 options-object 方言 + setActivationHooks 归位模块级；C8 simulator-contracts 契约深模块（模拟器域常量/file 判据单源）；C4 角色/对话列表视图下沉 list-views 深模块（app.js 纯编排化））+ **会话交付修复**（2026-08-15——模拟器「获取列表」base_url 补 /v1 + 开场白预插 + 桌面版重新打包）+ **D11 关闭行为偏好**（2026-08-15 交付——首次运行关窗行为选择 + 设置页可改，Rust settings.rs + desktop-settings.js 深模块，网页版零影响）+ **模拟器 PC 阅读覆盖层**（2026-08-19 交付——simulator-pc.css 六分区共享覆盖层 + simulator-view.js 注入 + F1/F2 期末修复，22 游戏 HTML 零改动）+ **模拟器配置面板可读性修复**（2026-08-19 交付——vision 全量诊断 22/22，覆盖层分区 7 + 提示条对比度 + 注入副作用修复）+ **T-01/T-02 模拟器接入契约 + 外置数据目录与用户导入**（2026-08-19 交付，5 工单 3 波——接入契约核对脚本 check-simulator-css.mjs + 数据目录外置（CONVER_DATA_DIR/simulators，首启种子幂等）+ POST /api/simulators/import 导入端点（校验/净化/SHA-256 去重/改名/cfg-探测/恶意粗筛不拦截/manifest 原子注册）+ 前端导入 UI（按钮/拖拽双通道 + 安全警告）+ per-game CSS 注入）。**技术债区 F-8/F-9/F-12 批次**（2026-08-19 交付——F-5/F-6 复核关闭（各附实证）、F-8 manifest 结构自愈、F-9 文件名净化收敛（保留设备名/255 字节）、F-12 就绪终态发布顺序修复（复现循环 30 次归零）；期末四轴 0 阻断放行；新落债 F-13~F-17 待立项，见 TICKETS 技术债区）+ **技术债区 F-13~F-17 批次 2**（2026-08-19 交付——F-13/F-14/F-15/F-17 已修（先红后绿 +8 用例）、F-16 复核关闭、F-18/F-19 已修、F-9 注记补 F-17 修订（255→120））+ **技术债区批次 3**（2026-08-19 交付——F-21 docstring 入参契约声明、F-20 复核关闭、F-22 归档流程项；**技术债区清零（F-1~F-22 全部处置完毕）**）+ **AI 游戏生成功能**（2026-08-23 交付，2026-08-25 登记补录——世界观描述 → LLM 填充种子模板生成完整 HTML → 六项校验闸门（结构/模板标记/cfg 契约/可解析性/安全/游戏数据）→ 复用导入管线落盘注册 manifest，校验失败自动重试打磨 ≤3 次；模拟器列表页模态框入口，需先配置 API Key；测试增量：pytest test_game_generator.py 62 用例 + Vitest game-generator.test.js 13 用例，均已计入下方基线）。测试：pytest **809 + 1 skip**（后端）+ Vitest **1164**（前端）+ cargo test 70（Tauri 壳）全绿（权威基线见 CODE_WIKI.md §5 机械标记）。**架构深化批次 S1~S3**（2026-08-27 交付，improve-codebase-architecture 报告 Strong 三候选直落 kickoff 全自动档标准档 3 工单单波并行——S1 重生成消息组装 `append_current_input` 显式路径（PHI 剥离迁入纯函数）/ S2 `_LLM_ERROR_MAP` 顺序契约显式化（显式有序列表 + docstring）/ S3 模拟器配置同步状态机边界收口（观察者生命周期迁入 key-injector 单一模块闭环）；pytest 792→809+1skip、Vitest 1145→1164；期末四轴 1 阻断修复 + 非阻断落债 F-89）；版本号 **v0.5.0**（2026-08-27 升版，8 处清单全升）。

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
