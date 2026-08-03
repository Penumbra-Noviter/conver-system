# Conver System — 共识文档 (CONSENSUS)

> 记录所有需求定义与技术决策。修改设计前请先更新本文档。

---

## 1. 项目定位

- **类型**：个人娱乐/实验项目
- **形态**：本地优先的网页版 SPA（FastAPI 后端 + 纯前端）
- **受众**：自己用，后续可开源到 GitHub
- **数据主权**：所有数据（含 API Key）存本地 SQLite，不上传云端
- **扩展路径**：网页版 → Tauri 桌面版（Phase 6 按需推进）

## 2. 用户画像与安全模型

- **单用户设计**，不做多租户/多账号隔离
- API Key 通过 UI 设置面板写入 DB（settings 表），运行时可修改立即生效
- SQLite 数据库文件仅存本地，不上传/不共享
- `.env` 仅作配置模板，不存储真实密钥

## 3. 角色管理策略

- **手动创建**：所有字段在 UI 中可编辑；设定不完整（缺人格设定/开场白）时软提示引导补齐，不拦截保存
- **导入/导出**：兼容 SillyTavern Character Card V2 规范（全量映射），首期仅 JSON 卡（PNG 卡留待 P6.x）；导入容错 V1 旧卡与裸 data 格式
- **往返保真**：temperature / URL 头像 / lorebook 等非 V2 标准字段存 `extensions.conver_system.*` 命名空间，导出→导入不丢数据（详见 `docs/p2.5-character-import-export.md`）
- **字段设计**：DB 表完整映射 V2 字段（含 `scenario`、`mes_example`、`alternate_greetings`、`system_prompt`、`post_history_instructions` 等）
- **删除行为**：
  - Phase 2：级联删除（角色 + 关联对话 + 消息）
  - Phase 5：升级为确认对话框，提示用户有 N 条关联记录

## 4. 对话上下文管理

- **默认策略**：滑动窗口，保留最近 20-30 轮消息
- **用户可配**：设置面板中提供滑块调节轮数
- **高级策略**（Phase 6）：摘要压缩
- **对话标题自动生成**（2026-08-03 立项，P3.5）：
  - 创建对话时后端默认标题为「与 {角色名} 的对话」，前端不再传 `title: '新对话'`
  - 发出首条 user 消息后，同步替换为该消息的**规则截断**标题（折叠空白 + 截取 20 字 + 「…」，不剥离 Markdown）
  - 纯规则实现，零 LLM 调用、确定性、无感知延迟

## 5. LLM Provider 策略

| Provider | Phase | 方式 |
|----------|-------|------|
| Claude (Anthropic) | Phase 3 | 官方 anthropic SDK |
| OpenAI（含兼容 API） | Phase 4 | 官方 openai SDK，`base_url` 可配 |
| Ollama 本地模型 | Phase 6 | 可选 |

- Provider 通过 Factory 模式注册，扩展新 Provider 只需按接口实现
- 每个对话记录使用的 `model_provider` 和 `model_name`

## 6. 流式输出

- **两个模式都做**，用户可选择流式/非流式
- 非流式：`POST /api/chats` → 等待 → 完整回复
- 流式：`POST /api/chats/stream` → SSE → 打字机效果渲染
- Phase 3 同时实现两种模式
- **停止生成**（2026-08-03 立项，P3.5）：
  - 仅流式模式提供。流式生成中发送按钮两态变身停止按钮（`➤` ⇄ `⏹ 停止`）
  - 前端 `AbortController` 中止 fetch → SSE 连接断开
  - 后端 `stream_chat` 的 `event_generator` 轮询 `request.is_disconnected()` 感知客户端断开，**保存已生成的部分内容**为 assistant 消息
  - 前端气泡标记「（已停止）」，语义为「用户主动停止」而非错误
  - 非流式模式不提供停止按钮（无法真正中断后端请求，避免「点了停止但消息仍出现」的误导）

## 7. 前端布局与交互

- **布局**：左侧导航栏 + 右侧主内容区（Discord 风格）
  - 侧栏：角色列表 | 对话列表 | 设置入口
  - 主区：聊天界面 / 角色编辑 / 设置面板
- **技术栈**：Vanilla JS (ES Modules) + CSS 自定义变量
- **无构建工具链**：FastAPI Mount 同域服务，手动 F5 刷新

## 8. 配置管理分层

| 配置项 | 存储位置 | 运行时修改 |
|--------|---------|-----------|
| API Key | DB settings 表 | ✅ UI 中修改即时生效 |
| 默认模型 | DB settings 表 | ✅ |
| 滑窗轮数 | DB settings 表 | ✅ |
| UI 偏好 | DB settings 表 | ✅ |
| 每次对话模型 | conversations 表 | ✅ |

## 9. 开发规范

- Git 提交格式：`<type>: <中文说明>`（feat/fix/refactor/docs 等 Conventional Commits）
- **Git 策略**：项目初步完善后再执行 `git init` 及初始提交。在此之前不进行版本控制，不上传 GitHub 仓库。
- 代码规范见 `mem:conventions`（Python: PEP8 + 类型注解，JS: camelCase/ESM）
- 每个 Phase 完成时做 code-review 后提交
- 关键决策更新此 CONSENSUS.md

## 10. Phase 划分

| Phase | 名称 | 核心产出 |
|-------|------|---------|
| 1 | 项目骨架 | 可运行的 FastAPI + SQLite + 前端空壳 |
| 2 | 角色管理 | 角色 CRUD + 前端管理 + V2 导入/导出 |
| 3 | 对话核心 | LLM 接入 + 聊天 UI + 流式/非流式 |
| 4 | 多模型支持 | OpenAI Provider + 模型切换 + API Key 管理 |
| 5 | 体验完善 | 对话历史、UI 美化、快捷操作 |
| 6 | 增强功能 | Tauri 桌面版、导出、搜索等 |

> 更新记录：2026-07-30 初始版本，经 grilling skill 深度讨论后确认。
