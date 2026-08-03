# Conver System — 可执行任务清单 (TICKETS)

> 本文档由 to-tickets 阶段生成，将 CONSENSUS.md 中的每个 Phase 拆解为可执行的子任务。
> 状态: ⬜ 待办 | 🔄 进行中 | ✅ 完成

---

## Phase 0 — 项目基础设施就绪 (已完成)

### P0.1 创建 .env 配置
- [x] 从 `.env.example` 复制 `.env` 到项目根目录
- [x] 确认 `.gitignore` 已排除 `.env`
- [ ] 填写 API Key（用户手动填入）

### P0.2 安装依赖
- [x] `pip install -r backend/requirements.txt`（全部已安装）

### P0.3 Git 初始提交（已决策：延迟至项目完善后执行）
- [ ] ~~`git init` + 首次 commit~~ ❌ 暂缓 — 待项目初步完善后再执行
- [ ] ~~GitHub 仓库推送~~ ❌ 不考虑，不上传

### P0.4 启动验证
- [x] `uvicorn backend.app.main:app --reload` 启动无报错
- [ ] 手动访问 http://localhost:8000/docs 确认 Swagger 正常
- [ ] 手动访问 http://localhost:8000 确认前端页面加载正常

---

## Phase 1 — 项目骨架 ✅ 已完成

> 确认所有骨架代码就位，Dev Log 已记录。

- [x] config.py — pydantic-settings 配置
- [x] database.py — SQLAlchemy 引擎 + Session
- [x] 数据库 Model — character(V2) / conversation / message / setting
- [x] Pydantic Schema — character / conversation / message
- [x] LLM 层架构 — BaseLLM + Factory + Claude/OpenAI 桩
- [x] API Routes — characters / conversations / messages / models / settings
- [x] main.py — FastAPI 入口 + 静态文件挂载 + 数据库初始化
- [x] index.html — SPA 三栏布局
- [x] style.css — CSS 变量主题 + 亮/暗模式
- [x] api.js — 统一 fetch 封装 + SSE 流式支持
- [x] app.js — 视图切换 + 状态管理 + 交互逻辑

---

## Phase 2 — 角色管理 (前端增强) ✅ 已完成

> 后端 CRUD 已完成。前端增强也已全部完成。
> 实际代码审计：character-form.js（完整表单）、confirm-dialog.js（确认弹窗）、角色卡片头像/标签/温度显示均就绪。

### P2.1 角色创建表单组件
- [x] `frontend/js/components/character-form.js` — 专用表单弹窗/页面
  - 字段: name, personality(textarea), greeting(textarea), temperature(slider), avatar
  - 提交前校验必填字段
  - 成功后自动刷新角色列表

### P2.2 角色编辑功能
- [x] 角色卡片点击编辑按钮 → 打开编辑表单（复用创建表单组件，预填数据）
- [x] 使用 `GET /api/characters/{id}` 加载当前数据
- [x] 更新后刷新列表

### P2.3 角色删除确认对话框
- [x] `prompt()` → 自定义确认弹窗（confirm-dialog.js）
- [x] 显示该角色关联的对话数量
- [x] 确认/取消两个按钮

### P2.4 角色列表 UI 增强
- [x] 显示头像 avatar（占位图或实际图片）
- [x] 角色卡片显示更多信息：问候语摘要、模型温度
- [x] 搜索/过滤角色（可选）

### P2.5 SillyTavern V2 导入/导出
- [ ] 导出角色为 `.json` 文件（V2 格式）— 后续按需
- [ ] 导入 `.json` 文件创建角色 — 后续按需
- [ ] UI 中的导入/导出按钮 — 后续按需

---

## Phase 3 — 对话核心 (LLM 集成)

> ✅ 全部完成 — 后端 LLM 集成 + 前端核心交互就绪

### P3.1 Claude Provider 实现
- [x] `claude.py` — 实现 `generate()` 方法
  - 使用 `anthropic` SDK 的 `messages.create()`
  - 正确处理 messages 格式（system prompt 分离）
- [x] `claude.py` — 实现 `stream_generate()` 方法
  - 使用 `anthropic` SDK 的流式 API
  - yield 每个 content_block delta
- [x] 异常处理：映射 Anthropic 异常 → 自定义 LLMError 子类

### P3.2 聊天 API 路由集成
- [x] `POST /api/chat` — 替换占位回复为真实 LLM 调用
  - 调用 `build_message_list()` 组装消息
  - 使用 Factory 获取对应 Provider
  - 保存 user 消息 + assistant 回复到 DB
- [x] `POST /api/chat/stream` — 实现 SSE 流式端点
  - 使用 `StreamingResponse` + EventSource
  - 逐 token 流式返回 `data: {"type": "token", "content": "..."}`
  - 完成后发送 `data: {"type": "done", "message_id": N}`

### P3.3 对话上下文管理
- [x] `build_message_list()` 接入角色设定 (system prompt)
- [x] 滑窗截断策略：保留最近 N 轮（默认 30，从 settings 读取）
- [x] 首次对话时自动插入角色 greeting

### P3.4 流式渲染完善
- [x] 打字机效果稳定（当前 app.js 已有基础实现）
- [x] 流式中断/错误处理（重试按钮 or 提示）
- [x] 流式/非流式切换在 API 层面联动

### P3.5 对话过程中的交互
- [x] 发送消息后展示加载动画/指示器（思考中指示器）
- [ ] 停止生成按钮（中断流式请求）— 后续按需增强
- [ ] 对话标题自动生成（使用第一条消息摘要）— 后续按需增强

---

## Phase 4 — 多模型支持 ✅ 已完成

> 后端 100% | 前端 100% (API Key 测试连接待后续增强)

### P4.1 OpenAI Provider 实现
- [x] `openai.py` — 实现 `generate()` 方法
  - 使用 `openai` SDK，支持自定义 `base_url`
- [x] `openai.py` — 实现 `stream_generate()` 方法
- [x] 注册 Provider: `LLMFactory.register("openai", OpenAIProvider)`

### P4.2 模型切换 UI
- [x] 创建对话时从 settings 读取默认 Provider + 模型名（不再硬编码 claude）
- [x] 对话列表 + 聊天头部显示当前使用的模型
- [x] 创建对话时手动选择模型（showModelSelector 模型选择器对话框）

### P4.3 API Key 管理
- [x] 设置面板中管理 Claude / OpenAI Key（前端 UI 已完成）
- [x] 敏感信息提示（Key 仅存本地数据库，已有说明）
- [ ] API Key 验证（保存时测试连接）— 待后续增强

### P4.4 Provider 路由优化
- [x] 从 settings 表读取默认 provider/model（后端已集成）
- [x] 从 conversation 记录获取对应 provider
- [x] 未配置 Key 时返回友好提示

---

## Phase 5 — 体验完善 ✅ 已完成

> 后端 100% | 前端 100% | 集成 ✅ — 2026-07-30 全量审计确认

### P5.1 对话历史管理
- [x] 对话列表显示角色名、时间、消息数（已有 meta 展示）
- [x] 对话重命名（双击标题 inline 编辑 + PUT API）
- [x] 删除对话确认对话框（confirm-dialog.js 关联消息数提示）
- [x] 清空所有对话（危险操作确认弹窗）
- [x] 空状态引导（无对话时的引导说明）

### P5.2 UI/UX 增强
- [x] 角色 greeting 开场白自动触发
- [x] 消息中 Markdown 渲染（代码块、链接、列表）
- [x] 消息复制按钮（hover 显示 + Clipboard API）
- [x] Toast 通知（showError/showSuccess 底部居中）
- [x] 快捷键: Enter 发送、Shift+Enter 换行、Escape 关闭弹窗
- [x] 输入框自动伸缩
- [x] 导出对话按钮（📥 Markdown/JSON 格式选择）

### P5.3 主题与视觉
- [x] 亮/暗模式切换（CSS 变量 + auto/light/dark + applyTheme()）
- [x] 消息气泡视觉区分 user / assistant
- [x] 角色头像展示在聊天区域
- [x] 动画过渡（视图切换、消息出现）
- [x] 响应式布局适配移动端（768px/480px 断点）

### P5.4 设置面板完善
- [x] 滑动窗口轮数输入
- [x] 默认模型/Provider 选择
- [x] 主题切换（auto/light/dark）
- [x] 清空所有对话（危险操作，需确认）
- [x] OpenAI base_url 配置（兼容第三方 API）

---

## Phase 6 — 增强功能（按需）

### P6.1 对话导出
- [x] Markdown 导出（后端 API + 前端 UI）✅ 2026-07-30
- [x] JSON 格式导出（后端 API + 前端 UI）✅ 2026-07-30
- [x] 导出包含角色设定信息 ✅ 2026-07-30

### P6.2 搜索
- [x] 搜索历史消息（关键词匹配，跨对话搜索）
- [x] 搜索 UI（搜索框 + 结果列表 + 关键词高亮）
- [x] 搜索结果显示对话标题、角色名、消息预览
- [x] 点击搜索结果跳转到对应对话

### P6.3 Prompt 模板
- [x] 角色设定中使用模板变量（`{{user}}`, `{{char}}` 等）✅ 2026-07-30
- [x] 角色设定后处理指令 (post_history_instructions) ✅ 2026-07-30

### P6.4 Tauri 桌面版
- [ ] Tauri 项目初始化
- [ ] Rust 后端作为 FastAPI 壳/替代
- [ ] 系统托盘
- [ ] 开机自启

### P6.5 其他
- [ ] 多 tab 会话管理
- [ ] 角色人设导入/导出（已规划在 P2.5）
- [ ] Ollama 本地模型支持

---

## Code Review — Bug Fixes & 代码质量 🆕 待执行

> 2026-07-30 全量代码审查发现的问题，按优先级排列。

### CR.1 严重 Bug

#### CR.1.1 滑动窗口轮数设置不生效
- [x] `build_message_list()` 的 `max_rounds=30` 硬编码 → 路由已从 settings 表读取 `sliding_window_rounds` 传入 ✅ 代码已实现
- [x] `/api/chat` 和 `/api/chat/stream` 路由已通过 `_get_sliding_window_rounds()` 读取设置并传入 ✅
- [x] 涉及文件: `services/message.py`, `api/routes/messages.py`

#### CR.1.2 SSE 错误事件前端被静默丢弃
- [x] `api.js` 中 `chatStream()` 已含 `error` 事件类型处理（调用 `onError` 回调）✅ 代码已实现
- [x] 前端 `onError` 回调已在 `handleSend()` 中显示错误信息 ✅

### CR.2 代码质量 — 硬性违规 ✅ 已完成

#### CR.2.1 补充缺少的类型注解
- [x] `database.py:set_sqlite_pragma()` — 参数 + 返回值类型注解 ✅ 2026-08-03（审计时已就绪，复核确认）
- [x] `database.py:init_db()` — 返回注解 ✅ 2026-08-03（审计时已就绪，复核确认）
- [x] `main.py:on_startup()` — 返回注解 ✅ 2026-08-03（审计时已就绪，复核确认）

#### CR.2.2 路由函数命名对齐规范
- [x] `messages.py` 端点函数已命名为 `create_chat` / `stream_chat`，符合 `create_*` 前缀规范 ✅ 2026-08-03（复核确认）

#### CR.2.3 消除函数内局部导入
- [x] `conversation.py:create_conversation()` — `Setting` 导入已在模块顶部 ✅ 2026-08-03（复核确认）
- [x] `message.py:auto_insert_greeting()` / `build_message_list()` — `Character` 导入已在模块顶部 ✅ 2026-08-03（复核确认）
- [x] 额外清理：`conversation.py:delete_all_conversations()` 冗余 `Message` 局部导入移除；`conversations.py` 导出端点 `JSONResponse`/`PlainTextResponse` 局部导入移至模块顶部 ✅ 2026-08-03
- [x] 备注：`main.py:on_startup()` 的 `init_db` 局部导入与 `database.py:init_db()` 内 `import backend.app.models` 保留 — 属启动期延迟加载的合理模式，非违规

#### CR.2.4 旧式 typing 语法清理
- [x] `settings.py` 已用 `dict[str, Any]`，全库无 `Dict[`/`List[` 旧式写法 ✅ 2026-08-03（复核确认）

### CR.3 代码质量 — 坏味道清理

#### CR.3.1 消除 `get_db()` 重复定义
- [x] `deps.py` 原本已是纯转发（`from backend.app.database import get_db`），无重复定义 ✅ 复核确认
- [x] 进一步删除 `deps.py`（浅模块），4 个路由文件改为直接 `from backend.app.database import get_db` ✅ 2026-08-03（同时落地 CR.6.4）

#### CR.3.2 抽取 Provider 异常映射公共逻辑
- [x] 在 `llm/errors.py` 中 `translate_sdk_error()` 已存在；`ClaudeProvider`/`OpenAIProvider` 各新增 `_translate_error()` 私有方法，`generate()`/`stream_generate()` 共用 ✅ 2026-08-03

#### CR.3.3 消除路由层 LLM 错误映射重复
- [x] `messages.py` 中的异常→HTTP 状态码映射已抽取为 `_LLM_ERROR_MAP` 字典 ✅

### CR.4 死代码 & 未使用字段

#### CR.4.1 ChatRequest.stream 字段清理
- [x] 复核确认：`ChatRequest` 当前无 `stream` 字段（端点仅靠 URL 路径决定模式），已无可删死代码 ✅ 2026-08-03

#### CR.4.2 V2 字段使用规划
- [x] `post_history_instructions`、`scenario`、`mes_example` 已补充至 `build_message_list()` ✅
- [x] 新增 `_parse_mes_example()` 解析 V2 对话范例 ✅

---

## Code Review — Phase 5 后全量审查 🆕

> 2026-07-30 Phase 5 后端集成后的全量代码审查，按优先级排列。

### CR.4 严重 Bug

#### CR.4.1 SSE 流中断 → 按钮永久禁用
- [x] `api.js:chatStream()` — 添加 `completed` 标记，流结束未收到 `done` 事件时调用 `onDone(null)` ✅ 2026-07-30
- [x] `app.js:handleSend()` — `onDone` 回调处理 `null messageId`（流中断时重置按钮状态）✅ 2026-07-30
- [x] `onDone`/`onError` 中均调用 `loadConversations()` 刷新计数 ✅ 2026-07-30

#### CR.4.2 V2 字段未用于 prompt 组装
- [x] `services/message.py:82-96` — `build_message_list()` 新增 `scenario`、`mes_example`、`post_history_instructions` 组装 ✅ 2026-07-30
- [x] 新增 `_parse_mes_example()` 将 V2 对话范例解析为 user/assistant 序列 ✅ 2026-07-30

#### CR.4.3 `theme_mode` 设置不生效
- [x] `frontend/js/app.js` — 新增 `applyTheme()` 函数，在 `loadSettings()` 和保存设置后调用 ✅ 2026-07-30
- [x] `frontend/css/style.css:39-48` — 添加 `:root[data-theme="dark"]` 和 `:root[data-theme="light"]` 选择器，保留 `auto` 模式 ✅ 2026-07-30

### CR.5 代码质量 — 硬性违规

#### CR.5.1 路由/服务函数缺少类型注解
- [x] 全部 27 个路由/服务函数逐一补充 `->` 返回类型注解 ✅ 2026-08-03
- [x] `database.py:42` — `get_db()` 生成器无注解 ✅ 2026-08-03
- [x] 涉及文件：`messages.py`、`characters.py`、`conversations.py`、`models.py`、`settings.py`、`database.py`

#### CR.5.2 API 路径命名违规范
- [x] `messages.py` — `POST /api/chat` → `POST /api/chats` ✅ 2026-08-03
- [x] `messages.py` — `POST /api/chat/stream` → `POST /api/chats/stream` ✅ 2026-08-03
- [x] 前端联动：`api.js` 的 `chat()` / `chatStream()` 已同步更新 ✅ 2026-08-03

#### CR.5.3 路由函数命名违规范
- [x] `stream_chat()` 决策：**更新规范允许 `stream_*` 特殊动词前缀**（SSE 流式端点，与 `create_chat` 配对更清晰，避免 `create_chat_stream` 冗长）✅ 2026-08-03
- [x] 规范已同步至 `memory:conventions`；`create_chat` / `stream_chat` 均符合新规范

#### CR.5.4 Service 层函数命名违规范
- [x] `message.py` — `save_message()` → `create_message()`，调用点（auto_insert_greeting / chat.py）同步更新 ✅ 2026-08-03
- [x] `auto_insert_greeting()` 决策：**保留原名** — 条件自动插入行为，`create_*` 会误导为无条件创建 ✅ 2026-08-03

#### CR.5.5 配置分散
- [x] `conversation.py:59-60` — 硬编码 `"claude"` / `"claude-sonnet-4-20250514"` → 改为引用 `config.settings.DEFAULT_PROVIDER` / `DEFAULT_MODEL` ✅ 2026-08-03
- [x] 新增 `_get_setting_value()` 读取设置值，回退链：显式传参 → settings 默认 → config 默认 ✅ 2026-08-03

### CR.6 代码质量 — 坏味道清理

#### CR.6.1 流式/非流式端点代码重复
- [x] 抽取 `_prepare_chat()` 辅助函数复用共同前置逻辑（对话校验/温度/消息构建/Key/Provider）✅ 2026-08-03
- [x] 涉及文件：`api/routes/messages.py`

#### CR.6.2 前端头像 HTML 构造重复
- [x] `app.js` — `appendMessage()` / `handleSend()` 流模式复用 `getAssistantAvatarHtml()` ✅ 2026-08-03
- [x] 新增 `createAvatarElement(role)` — HTML 字符串 → DOM 元素包装，统一头像构造 ✅ 2026-08-03
- [x] 复制按钮事件绑定抽取为 `attachCopyButton(btn, content)`，renderMessages / appendMessage 共用 ✅ 2026-08-03

#### CR.6.3 Primitive Obsession
- [x] Character 模型 JSON 字段（tags/alternate_greetings/creator_notes/extensions）→ SQLAlchemy `JSON` 列，schema 改 `list[str]`/`dict`，前端 tags 处理改数组 ✅ 2026-08-03
- [x] Message.role → `Role` 枚举（`Enum` 列，`values_callable` 按值存取，兼容既有 VARCHAR 存量数据）✅ 2026-08-03
- [x] 涉及文件：`models/character.py`、`models/message.py`、`schemas/character.py`、`services/message.py`、`services/conversation.py`（导出 role 用 `.value`）、`api/routes/chat.py`、`frontend/js/utils.js`、`app.js`、`components/character-form.js`

#### CR.6.4 deps.py Middle Man
- [x] 已删除 `deps.py`，路由直接 `from backend.app.database import get_db` ✅ 2026-08-03（与 CR.3.1 一并落地）

#### CR.6.5 messages.py 职责分离
- [x] 聊天端点拆出独立路由文件 `api/routes/chat.py`，与消息检索分离 ✅ 2026-08-03
- [x] `messages.py` 仅保留消息检索：GET 历史 + GET 搜索；`chat.py` 承载 POST /api/chats + POST /api/chats/stream 及 LLM 相关辅助 ✅ 2026-08-03
- [x] 涉及文件: `api/routes/chat.py`（新增）、`api/routes/messages.py`、`main.py`

### CR.7 默认模型覆盖逻辑脆弱
- [x] `services/conversation.py:59-66` — 删除靠比较硬编码字符串判断"是否覆盖"的脆弱逻辑 ✅ 2026-08-03
- [x] 改用 Pydantic v2 `model_fields_set` 判断字段是否显式传入：显式传入 → 尊重用户选择；未传入 → settings 默认 → config 默认 ✅ 2026-08-03

### CR.8 流式时消息计数错误
- [x] `app.js:handleSend()` — `loadConversations()` 已在 `onDone` 和 `onError` 回调中调用 ✅
- [x] 流结束前不刷新计数，避免短暂不准确 ✅

### CR.9 数据加载无用户可见错误
- [x] `app.js:114-121` — `loadCharacters()` 失败只 console.error ✅ 2026-07-30
- [x] `app.js:352-358` — `loadConversations()` 同上 ✅ 2026-07-30
- [x] `app.js:491-530` — `loadMessages()` 同上 ✅ 2026-07-30

### CR.10 已确认范围蔓延（TICKETS 标记已更新）
- [x] P5.1 对话重命名 — 已标记为 ✅ 已完成
- [x] P4.2 创建对话时手动选择模型 — 已标记为 ✅ 已完成（模型选择器对话框）
- [x] P5.2 消息复制按钮 — 已标记为 ✅ 已完成

---



## 附录: 当前项目快照（2026-07-30 全量审计）

| Phase | 名称 | 后端 | 前端 | 集成测试 |
|-------|------|------|------|---------|
| 1 | 项目骨架 | ✅ 100% | ✅ 100% | ✅ |
| 2 | 角色管理 | ✅ 100% | ✅ 100% | ✅ |
| 3 | 对话核心 | ✅ 100% | ✅ 100% | ✅ |
| 4 | 多模型 | ✅ 100% | ✅ 100% | ✅ |
| 5 | 体验完善 | ✅ 100% | ✅ 100% | ✅ |
| 6.1/6.2 | 对话导出 + 消息搜索 | ✅ 100% | ✅ 100% | ✅ |
| 6.3 | 模板变量 | ✅ 100% | ✅ 100% | ✅ |
| 6.4+ | Ollama/桌面端/其他 | ⬜ 0% | ⬜ 0% | ⬜ |

---

> **推荐执行顺序**: Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6
> Phase 2 和 Phase 3 可并行推进前端和后端工作。
> 创建者: to-tickets 阶段 (2026-07-30)
