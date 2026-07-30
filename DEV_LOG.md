# Conver System — 开发日志 (DEV_LOG)

> 记录 Bug 修复、优化/重构进展、踩坑记录。
> 格式：`[状态] 日期 — 标题`

---

## Phase 1 — 项目骨架

### 2026-07-30

#### 初始化
- [x] 创建 CONSENSUS.md — 记录所有设计决策（经 grilling skill 深度讨论）
- [x] 创建 DEV_LOG.md — 开发日志
- [x] 创建 PROJECT_REFERENCE.md — 项目介绍书

#### 后端骨架
- [x] config.py — pydantic-settings 配置
- [x] database.py — SQLAlchemy 引擎 + Session
- [x] 数据库 Model — character(V2 完整字段) / conversation / message / setting
- [x] Pydantic Schema — character / conversation / message
- [x] LLM 层架构 — BaseLLM 基类 + Factory + Claude/OpenAI 桩
- [x] API Routes — characters / conversations / messages / models / settings
- [x] main.py — FastAPI 入口 + 静态文件挂载 + 数据库初始化

#### 前端骨架
- [x] index.html — SPA 三栏布局（侧栏 + 对话列表 + 聊天区）
- [x] style.css — CSS 变量主题、亮/暗模式、完整组件样式
- [x] api.js — 统一 fetch 封装（含流式 SSE 支持）
- [x] app.js — 视图切换 + 状态管理 + 所有交互逻辑

#### 待办
- [ ] 创建 `.env`（从 `.env.example` 复制）
- [ ] 安装依赖并测试启动

---

## Phase 2 — 角色管理（前端增强）✅

### 2026-07-30

#### 后端（已完成 — Phase 1 骨架阶段已包含）
- [x] characters API Routes — 完整 CRUD
- [x] characters Service — 完整业务逻辑
- [x] Character Schema — Create/Update/Response

#### 前端 ✅ 已全部完成
- [x] character-form.js — 角色创建/编辑专用表单（字段: name/personality/greeting/temperature/avatar）
- [x] 角色编辑功能（预填数据 + 更新）
- [x] 删除确认对话框（显示关联对话数，confirm-dialog.js）
- [x] 角色卡片增强（头像/问候语摘要/温度/标签/对话数）
- [ ] SillyTavern V2 导入/导出（推迟至 Phase 6）

---

## Phase 3 — 对话核心（LLM 集成）

### 2026-07-30

#### 后端 — 全部完成 ✅
- [x] ClaudeProvider.generate() — 实现 Anthropic SDK 非流式调用 ✅
- [x] ClaudeProvider.stream_generate() — 实现流式调用（逐 token) ✅
- [x] LLM 异常映射 — AuthenticationError / RateLimitError / TimeoutError / ContentFilter → 自定义 LLMError ✅
- [x] POST /api/chat — 接入真实 LLM（构建消息列表 → 调用 Provider → 保存回复）✅
- [x] POST /api/chat/stream — SSE StreamingResponse 逐 token 推送 ✅
- [x] 对话上下文管理（system prompt + 滑窗截断 + 角色 greeting 自动插入）✅
- [x] `save_message` 同步更新 conversation.updated_at ✅
- [x] API Key 从 settings 表动态读取 ✅
- [x] 使用角色的 temperature 参数 ✅

#### 前端 — 核心完善
- [x] api.js — fetch 封装 + SSE 流式支持 ✅
- [x] app.js — 聊天 UI + 流式渲染 ✅
- [x] app.js — 思考中指示器（非流式等待时）✅
- [x] style.css — thinking-indicator 动画样式 ✅

---

## Phase 4 — 多模型支持

### 2026-07-30 — OpenAI Provider 实现 + 进度审计

#### 进度审计与修正
- [x] 对项目代码进行全量审计，发现 TICKETS.md 进度标记严重滞后实际代码
- [x] Phase 2 前端实际完成度 100%（character-form.js、confirm-dialog.js、角色卡片增强均已就绪）
- [x] Phase 3 前端实际完成度 100%（流式渲染、思考指示器、快捷键等均已完成）
- [x] 统一修正 TICKETS.md 和 dev-workflow-status 记忆中的进度标记

#### OpenAI Provider 实现
- [x] `openai.py` — 实现 `generate()`（非流式）+ `stream_generate()`（流式）
  - 使用 `openai` SDK 的 `AsyncOpenAI` 客户端
  - 支持自定义 `base_url`（兼容第三方 API）
  - 异常映射：AuthenticationError / RateLimitError / APITimeoutError / BadRequestError → 自定义 LLMError
  - 与 ClaudeProvider 同级的 `_prepare_messages()` 逻辑（system 角色在消息列表中处理）
- [x] `llm/__init__.py` — 注册 `OpenAIProvider` 到 Factory（之前被注释掉）
- [x] `conversation.py` — 创建对话时从 settings 表读取默认 provider/model
- [x] 服务启动验证通过（models API 返回 OpenAI 模型列表）

#### 前端模型选择集成
- [x] `app.js` — 新增 `loadModels()` 从 API 加载可用模型列表
- [x] `app.js` — `refreshModelOptions()` 根据选择的 Provider 动态更新模型下拉
- [x] `app.js` — `startChatWithCharacter()` 使用 `state.defaultProvider` / `state.defaultModel`
- [x] `app.js` — 聊天头部显示当前对话使用的模型（model badge）
- [x] `app.js` — 对话列表显示每条对话的模型名
- [x] `app.js` — 对话删除功能（confirm-dialog 确认 + 级联刷新）
- [x] `style.css` — model-badge / conversation delete button 样式
- [x] 设置面板保存时更新 `state.defaultProvider` / `state.defaultModel` 本地状态

#### 启动验证结果
- [x] `uvicorn` 启动无报错（OpenAIProvider 注册成功，无导入错误）
- [x] `GET /api/models` 返回 claude + openai 的完整模型列表
- [x] `GET /api/settings` 返回正常
- [x] 前端 index.html 正常加载
- [ ] API Key 保存时测试连接（待 Phase 4 后续）

---


### 2026-07-30 — to-tickets 阶段

按照 `global/dev-workflow` 规范：

| 步骤 | 状态 | 说明 |
|------|------|------|
| 1. grill me | ✅ 完成 | 需求深度讨论，见 CONSENSUS.md |
| 2. to-spec | ✅ 完成 | CONSENSUS.md + 4 份设计文档 |
| 3. to-tickets | ✅ 完成 | TICKETS.md — 全项目任务分解 |
| 4. implement | ✅ 完成 | Phase 1-5 + P6.1 全部完成 |

## 2026-07-30 — 全量代码审查（code-review skill）

### Standards 轴发现

**硬性违规（违反编码规范）**
1. `database.py:29` — `set_sqlite_pragma()` 参数和返回值无类型注解
2. `database.py:57` — `init_db()` 无返回注解
3. `main.py:46` — `on_startup()` 无返回注解
4. `messages.py:59,139` — 路由函数 `chat`/`chat_stream` 命名不符合 `list_*`/`get_*`/`create_*`/`delete_*` 前缀约定
5. `conversation.py:60` `message.py:46,79` — 函数内部局部导入，违反模块级导入分组约定
6. `settings.py:10` — 使用旧式 `Dict[str, Any]` 而非 `dict[str, Any]`

**代码坏味道**
1. `get_db()` 在 `database.py` 和 `deps.py` 中重复定义
2. ClaudeProvider / OpenAIProvider 异常处理块逐字重复，可抽取 `_translate_error()` 方法
3. 非流式/流式端点的 LLM 错误映射代码重复（`messages.py:102-126 vs 192-203`）
4. Character 模型 JSON 字段（tags/alternate_greetings 等）使用 Text 列，缺少类型约束
5. Message.role 使用 String(20) 而非枚举
6. `post_history_instructions` 等 V2 字段已定义但未被 `build_message_list()` 使用

### Spec 轴发现（对照 CONSENSUS.md）

**缺失/错误实现**
1. **🔴 滑动窗口轮数设置无效**: 值保存到 settings 表但 `build_message_list()` 硬编码 `max_rounds=30`，不从 settings 读取配置
2. **🔴 SSE 错误事件前端静默丢弃**: 后端 `chat_stream` 发送 `{"type": "error", ...}` 但 `api.js:chatStream` 只处理 `token`/`done` 类型
3. **ChatRequest.stream 字段死代码**: `stream: bool` 定义但两个端点均不读取（仅靠 URL 路径决定模式）
4. **V2 角色卡导入/导出**: 完全缺失（CONSENSUS §3 要求存在但标记已推迟）
5. **每对话模型选择无前端 UI**: 创建对话时只能用默认值，无法手动选择

### 已记录决策

| 优先级 | 事项 | 状态 |
|--------|------|------|
| 🚨 P0 | 修复滑动窗口轮数不生效 | ⬜ 待执行 |
| 🚨 P0 | 修复 SSE 错误事件前端静默丢弃 | ⬜ 待执行 |
| 📋 P1 | 补充缺少的类型注解 | ⬜ 待执行 |
| 📋 P1 | 抽取异常处理公共逻辑（Provider + 路由） | ⬜ 待执行 |
| 📋 P2 | 路由函数重命名 + 导入顺序清理 | ⬜ 待执行 |


### 已记录决策

#### Git 延迟初始化
- **决策**：Git 的一切操作等待项目初步完善后再执行，目前阶段不考虑上传 GitHub 仓库
- **原因**：避免频繁 commit 干扰开发节奏，待代码趋于稳定后再建立版本基线
- **影响**：TICKETS.md 中 P0.3 项标记为暂缓，CONSENSUS.md 第 9 节已补充 Git 策略说明

---

## 2026-07-30 — 全量代码审查（Phase 5 后）

### Standards 硬性违规

- [ ] 全部 27 个路由/服务函数缺少返回类型注解 — `messages.py`(3处)、`characters.py`(5处)、`conversations.py`(6处)、`models.py`(1处)、`settings.py`(2处)、`database.py`(1处) — 部分函数已标注，多处遗漏
- [ ] `messages.py:95,157` — API 路径命名违规范：`POST /api/chat` 应使用复数 `/api/chats`
- [ ] `messages.py:158` — 路由函数 `stream_chat()` 不匹配 `list_*/get_*/create_*` 前缀规范
- [ ] `message.py:27` — Service 层 `save_message` 命名应为 `create_message`
- [ ] `conversation.py:59-60` — 硬编码 `"claude"` / `"claude-sonnet-4-20250514"` 字符串，应引用 `config.settings`

### Standards 代码坏味道

- [ ] 流式/非流式端点 ~90 行重复的前置逻辑（获取 conv → temperature → 存 user 消息 → 构建消息列表 → 拿 API Key → 拿 Provider）
- [ ] `app.js` 中头像 HTML 构造重复 3 次（renderMessages / appendMessage / handleSend 流模式）
- [ ] 复制按钮事件绑定重复 2 次（renderMessages + appendMessage）
- [ ] Character 模型 JSON 字段（tags/alternate_greetings 等）使用 Text 列而非序列化器
- [ ] Message.role 为自由字符串 String(20) 而非枚举
- [ ] `deps.py` 仅重新导出 `database.get_db`，无额外抽象（Middle Man）
- [ ] `messages.py` 混合"消息检索"和"聊天交互"两种职责（Divergent Change）

### Spec 缺失/未完成

- [x] 🔴 V2 字段未用于 prompt 组装 — `scenario`、`mes_example`、`post_history_instructions` 已加入 `build_message_list()` ✅ 2026-07-30
- [x] 🟡 `theme_mode` 设置不生效 — `applyTheme()` + CSS `[data-theme]` 选择器已实现 ✅ 2026-07-30
- [ ] 🟡 `alternate_greetings` 存储但无 UI — 存在 DB 中，无管理界面，无读取逻辑

### Spec 实现错误

- [x] 🔴 SSE 流中断 → 按钮永久禁用 — ✅ 已修复（2026-07-30）
- [ ] 🟡 默认模型覆盖逻辑脆弱 — 靠比较字符串 `"claude-sonnet-4-20250514"` 判断是否覆盖，用户选择同值时不覆盖
- [ ] 🟡 流式时对话列表消息计数错误 — `loadConversations()` 在流结束前调用，计数短暂不准确
- [ ] 🟡 数据加载无用户可见错误提示 — `loadCharacters/loadConversations/loadMessages` 失败只 `console.error`

### 已确认范围蔓延（TICKETS 标记未完成但已有实现）

- 对话重命名（P5.1）
- 模型选择器对话框（P4.2）
- 头像实时预览
- 消息复制按钮（P5.2）

---

## 2026-07-30 — Phase 6.1 对话导出 + CR.9 静默错误修复

### P6.1 对话导出后端 API
- [x] `services/conversation.py` — 新增 `export_conversation_json()` 导出对话为结构化 JSON（含角色信息）
- [x] `services/conversation.py` — 新增 `export_conversation_markdown()` 导出对话为可读 Markdown（按日期分组）
- [x] `api/routes/conversations.py` — 新增 `GET /{id}/export/json` 端点，返回 `Content-Disposition: attachment` 头
- [x] `api/routes/conversations.py` — 新增 `GET /{id}/export/markdown` 端点，返回 `Content-Disposition: attachment` 头
- [x] 404 处理完善，角色/消息空值检查完成

### P6.1 对话导出前端 UI
- [x] `app.js` — 新增 `showExportDialog()` / `createExportDialog()` / `downloadExport()` 导出流程
- [x] `app.js` — 聊天头部新增导出按钮（📥），点击弹出格式选择弹窗
- [x] `app.js` — 导出弹窗提供 Markdown / JSON 二选一，点击后通过 fetch + Blob 下载文件
- [x] `style.css` — 导出对话框样式（`.export-modal`, `.export-option-btn`）

### CR.9 修复 — 数据加载无用户可见错误
- [x] `app.js` — 新增 `showError()` / `showSuccess()` toast 通知函数（底部居中，5秒自动消失）
- [x] `app.js` — `loadCharacters()` catch 块调用 `showError('加载角色列表失败')`
- [x] `app.js` — `loadConversations()` catch 块调用 `showError('加载对话列表失败')`
- [x] `app.js` — `loadMessages()` catch 块调用 `showError('加载消息失败')`
- [x] `style.css` — Toast 通知样式（`.toast`, `.toast-error`, `.toast-success`, `toast-in` 动画）

### CR.4.1 🔴 SSE 流中断 → 按钮永久禁用
- **根因**: `api.js:chatStream()` 中 `reader.read()` 返回 `{done: true}` 时直接 `break` 退出循环，从不触发 `onDone`/`onError`，导致 `app.js` 中 `state.isStreaming` 和 `btnSend.disabled` 永不重置
- **修复**: 
  - 添加 `completed` 标记，收到 `type: "done"` 时设为 `true`；循环结束后若 `!completed` 则调用 `onDone(null)`
  - `app.js` 中 `onDone` 回调处理 `null messageId`：重置按钮状态，有部分内容时仍保存
  - `onDone`/`onError` 中均调用 `loadConversations()` 避免计数卡死

### CR.4.2 🔴 V2 字段未用于 prompt 组装
- **根因**: `build_message_list()` 仅使用 `system_prompt`/`personality`，忽略 `scenario`、`mes_example`、`post_history_instructions`
- **修复**:
  - `scenario` → 附加在 system prompt 后，作为 `[场景设定]` 系统消息
  - `mes_example` → 解析 `<START>` 分隔的 `{{user}}`/`{{char}}` 对话为 few-shot 消息序列（新增 `_parse_mes_example()`）
  - `post_history_instructions` → 附加在历史消息之后、当前输入之前
  - 空字段自动跳过，不增加 token 消耗

### CR.4.3 🟡 theme_mode 设置不生效
- **根因**: `theme_mode` 保存/加载了值但从未应用到 DOM；CSS 只用 `@media (prefers-color-scheme: dark)` 不认强制模式
- **修复**:
  - `app.js` 新增 `applyTheme(mode)`：`auto`/无 → 移除 `data-theme`；`light`/`dark` → 设置到 `<html>`
  - `style.css` 新增 `:root[data-theme="dark"]` 和 `:root[data-theme="light"]` 选择器
  - 媒体查询改为 `:root:not([data-theme="light"])` 避免与显式浅色冲突
  - `loadSettings()` 和保存设置后自动应用主题

---

## 2026-07-30 — 全量进度审计 + 文档同步

### 审计过程
- [x] 逐文件审计 Phase 1-5 + P6.1 的实际代码完成度
- [x] 发现 Phase 4 前端实际达 100%（模型选择器/模型列表/设置集成均已完成）
- [x] 发现 Phase 5 后端实际达 100%、前端 100%（全部功能已实现）
- [x] P6.1 对话导出后端 + 前端均已完成
- [x] CR.3.3 路由层 LLM 错误映射已抽取为 `_LLM_ERROR_MAP` ✅
- [x] CR.4.2 V2 字段已用于 prompt 组装 ✅
- [x] CR.8 流式计数问题已在 onDone/onError 回调中修复 ✅
- [x] CR.10 范围蔓延项目已全部更新标记 ✅

### 更新文档
- [x] TICKETS.md — Phase 4/5 标记为完成、附录快照更新
- [x] PROJECT_REFERENCE.md — 阶段描述更新
- [x] memory:dev-workflow-status — 同步进度
- [x] memory:features — 同步功能清单

### 剩余开放项（代码质量，不影响功能）

| CR | 描述 | 文件 |
|----|------|------|
| CR.5.5 | 硬编码 provider/model → config.settings | conversation.py |
| CR.7 | 默认模型覆盖逻辑脆弱 | conversation.py |
| CR.5.1 | 路由/服务函数缺少类型注解 | 多文件 |
| CR.6.1 | 流式/非流式端点重复代码 | messages.py |
| CR.2.2/5.2 | API 路径/函数命名规范 | messages.py |
| CR.6.2 | 前端头像 HTML 构造重复 | app.js |
| CR.3.2 | Provider 异常映射公共逻辑 | claude.py/openai.py |
| CR.6.3 | JSON 字段/Message.role 枚举 | models.py |
| CR.4.1 | ChatRequest.stream 死代码 | schemas/message.py |

### 功能待增强 (Phase 6)

| 功能 | 状态 |
|------|------|
| 搜索历史消息 | ✅ 已完成 |
| Prompt 模板变量 | ✅ 已完成 |
| Ollama 本地模型 | ⬜ |
| 多 tab 会话管理 | ⬜ |
| 角色 V2 导入/导出 | ⬜（已规划 P2.5） |
| Tauri 桌面版 | ⬜ |
| API Key 测试连接 | ⬜（P4.3 待增强） |

---

## 2026-07-30 — P6.3 Prompt 模板变量 ({{user}}/{{char}}) 实现

### 后端
- [x] `services/message.py` — 新增 `_apply_template_vars(text, user_name, char_name)` 核心替换函数
  - 支持 `{{user}}` → 用户昵称（从 settings 表读取）
  - 支持 `{{char}}` → 角色名称（从 character 数据读取）
- [x] `_parse_mes_example()` — 新增 `user_name`/`char_name` 参数，替换对话范例中的模板变量
- [x] `auto_insert_greeting()` — 新增 `user_name` 参数，替换 greeting 中的模板变量
- [x] `build_message_list()` — 新增 `user_name` 参数，替换以下字段中的模板变量：
  - system_content（system prompt / personality）
  - scenario（场景设定）
  - mes_example（对话范例，通过 `_parse_mes_example`）
  - post_history_instructions（历史后指令）
  - 当前用户输入
- [x] `api/routes/messages.py` — 新增 `_get_user_name(db)` 从 settings 表读取用户昵称
- [x] `create_chat()` / `stream_chat()` — 将 `user_name` 传递到 service 层

### 前端
- [x] `index.html` — 设置面板新增"模板变量"分组 + 用户昵称输入框
- [x] `app.js` — 设置加载/保存时处理 `user_name` 字段
- [x] `character-form.js` — Personality/Greeting/Scenario 字段下方增加模板变量提示
- [x] `style.css` — 新增 `.field-hint` 样式

---

## 2026-07-30 — P6.2 搜索历史消息 实现

### 后端
- [x] `services/message.py` — 新增 `search_messages()` 函数
  - SQL LIKE 搜索 + JOIN Conversation/Character 获取上下文
  - 关键词上下文截取（关键词前后 50 字符）
  - 返回消息预览、对话标题、角色名/头像、时间
- [x] `api/routes/messages.py` — 新增 `GET /api/messages/search?q=&limit=50`
  - 关键词参数 + 数量限制
  - 空查询返回空列表

### 前端
- [x] `api.js` — 新增 `messages.search(q, limit)`
- [x] `index.html` — 新增搜索视图（搜索框 + 结果区）+ 侧栏/移动端导航搜索按钮
- [x] `app.js` — 新增搜索逻辑：
  - `performSearch()` — 防抖 300ms、关键词 ≥ 2 字符
  - `renderSearchResults()` — 渲染结果列表（角色图标、对话名、预览）
  - `highlightText()` — 搜索结果关键词高亮（mark 标签）
  - `navigateToConversation()` — 点击结果跳转到对话
  - 搜索框自动聚焦 + Enter/Escape 快捷键
- [x] `style.css` — 搜索输入框/结果列表/高亮/响应式样式
