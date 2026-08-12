# 架构设计

## 系统架构总览

```
┌─────────────────────────────────────────────────────────────┐
│                      Frontend (SPA)                         │
│           HTML + CSS Custom Properties + Vanilla JS          │
│                    http://localhost:8000                     │
└──────────────────────────┬──────────────────────────────────┘
                           │ REST API (JSON)
                           │ SSE (流式聊天)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                     Backend (FastAPI)                        │
│                                                              │
│  ┌────────────────┐   ┌──────────────┐   ┌───────────────┐  │
│  │   API Routes    │   │   Services   │   │   LLM Layer   │  │
│  │                 │   │              │   │               │  │
│  │ /api/characters │──▶│ Character    │   │  BaseLLM      │  │
│  │ /api/conversations│▶│ Conversation │   │  ├─Claude     │  │
│  │ /api/chats      │──▶│ Message      │──▶│  ├─OpenAI     │  │
│  │ /api/settings   │   │ Settings     │   │  └─(扩展)     │  │
│  └────────┬───────┘   └──────┬───────┘   └───────┬───────┘  │
│           │                  │                    │          │
│           └──────────────────┼────────────────────┘          │
│                              ▼                               │
│                    ┌──────────────────┐                      │
│                    │    SQLite DB      │                      │
│                    │  conver_system.db │                      │
│                    └──────────────────┘                      │
└──────────────────────────────────────────────────────────────┘
```

## 目录结构

```
conver-system/
├── backend/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py                # FastAPI 入口，路由注册 + 静态文件挂载
│   │   ├── config.py              # pydantic-settings 配置管理
│   │   ├── database.py            # SQLAlchemy 引擎 + Session
│   │   │
│   │   ├── api/
│   │   │   ├── __init__.py
│   │   │   ├── errors.py          # 全局 exception handler（领域族 + LLM 族，_IMPORT_FORMAT_HINT 随迁）
│   │   │   └── routes/
│   │   │       ├── __init__.py
│   │   │       ├── characters.py  # 角色 CRUD
│   │   │       ├── chat.py        # 聊天端点（HTTP 映射 + SSE 帧包装，逻辑在 services/chat.py）
│   │   │       ├── conversations.py # 对话管理
│   │   │       ├── messages.py    # 消息检索（GET 历史 + 搜索）
│   │   │       ├── models.py      # 可用模型列表
│   │   │       └── settings.py    # 配置管理
│   │   │
│   │   ├── models/                # SQLAlchemy ORM
│   │   │   ├── __init__.py
│   │   │   ├── character.py
│   │   │   ├── conversation.py
│   │   │   ├── message.py
│   │   │   └── setting.py
│   │   │
│   │   ├── schemas/               # Pydantic 请求/响应
│   │   │   ├── __init__.py
│   │   │   ├── character.py
│   │   │   ├── conversation.py
│   │   │   ├── message.py
│   │   │   └── settings.py
│   │   │
│   │   └── services/
│   │       ├── __init__.py
│   │       ├── character.py
│   │       ├── character_card.py  # SillyTavern V2 卡转换层
│   │       ├── chat.py            # 聊天回合深模块（prepare_chat / complete_chat / chat_error_response / stream_reply）
│   │       ├── conversation.py
│   │       ├── conversation_export.py # 对话导出（json/markdown 深模块）
│   │       ├── data_dir.py        # 数据目录解析（纯 stdlib，契约表 v2；run_backend / migrate_data 委托）
│   │       ├── message.py
│   │       ├── setting.py         # 运行时设置读写（白名单 + 回退链 + 整型容错）
│   │       └── llm/
│   │           ├── __init__.py
│   │           ├── base.py        # BaseLLM 抽象基类（含 test_connection）
│   │           ├── claude.py      # Claude Provider
│   │           ├── openai.py      # OpenAI Provider
│   │           ├── factory.py     # Provider 工厂
│   │           ├── prompt.py      # Prompt 组装纯函数（apply_template_vars / build_messages）
│   │           └── errors.py      # LLM 异常定义
│   │
│   ├── requirements.txt
│   ├── requirements-dev.txt       # pytest / pytest-cov
│   ├── tests/                     # 单元测试（pytest）
│   │   ├── conftest.py            # 共享 fixture（db_session / make_character）
│   │   ├── fixtures/schema.sql    # schema 快照（契约表；test_migrate_data 建库单一来源）
│   │   ├── test_character_card.py
│   │   ├── test_p35.py
│   │   ├── test_prompt.py
│   │   ├── test_settings_connection.py
│   │   ├── test_conversation_export.py
│   │   ├── test_search.py
│   │   ├── test_chat_service.py       # 聊天回合 service 直测（prepare_chat / complete_chat / chat_error_response）
│   │   ├── test_data_dir.py           # 数据目录契约表 v2（Python 侧镜像）
│   │   ├── test_data_dir_connection.py# 连接级消费者测试（空格/中文/#/% 路径真实建库连接）
│   │   ├── test_migrate_data.py / test_packaging.py
│   │   ├── test_schema_snapshot.py     # schema 快照漂移检测（快照 vs ORM）
│   │   ├── test_error_handler.py       # 全局 exception handler wire 测试
│   │   ├── test_provider_registry.py   # Provider 派生注册一致性
│   │   └── test_package_exports.py
│   └── .env.example
│
├── frontend/
│   ├── index.html                 # SPA 入口
│   ├── css/
│   │   └── style.css
│   ├── package.json               # 前端测试基建（Vitest/jsdom，type: module）
│   ├── vitest.config.js
│   ├── tests/                     # 前端单元测试（vitest run；覆盖率 npm run test:coverage）
│   │   ├── format.test.js
│   │   ├── utils.test.js
│   │   ├── api.test.js
│   │   ├── tabs.test.js           # tab 工作区深模块
│   │   ├── stream-session.test.js # 流式回合结算状态机（含 settleTurn 用例组）
│   │   ├── icons.test.js / components-icons.test.js  # 图标 seam 语义
│   │   ├── conversation-activation.test.js
│   │   ├── search-view.test.js / cascade.test.js     # 搜索/级联深模块（T-01）
│   │   ├── chat.test.js / app.test.js                # 编排薄集成（T-06）
│   │   └── model-selector.test.js / settings-panel.test.js  # 组件 jsdom 联动（T-06）
│   ├── js/
│   │   ├── app.js                 # 主入口（接线/视图切换/初始化；搜索与级联已下沉 search-view.js/cascade.js）
│   │   ├── state.js               # 应用级全局状态（会话级字段已退役）
│   │   ├── chat.js                # 聊天域渲染与交互（renderMessages / handleSend；结算委托 settleTurn）
│   │   ├── api.js                 # API 调用层（含 setFetch 注入 seam）
│   │   ├── format.js              # 数据→HTML 纯函数（highlightText / buildMessagesHtml / characterCardHtml）
│   │   ├── search-view.js         # 搜索视图深模块（防抖/五态文案/渲染，initSearchView + 导航钩子注入）
│   │   ├── cascade.js             # 级联删除深模块（批量原语+联动，setCascadeHooks 注入）
│   │   ├── tabs.js                # 会话 tab 工作区深模块（openTab/closeTabs/getTabDisplay/abortStream）
│   │   ├── stream-session.js      # 流式回合结算深模块（createStreamSession + settleTurn + mergeFreshList）
│   │   ├── conversation-activation.js # 激活编排深模块（F-2 守卫/草稿滚动/懒加载，setActivationHooks 注入）
│   │   ├── icons.js               # SVG 图标工厂 seam（iconHtml，唯一动态图标来源）
│   │   ├── components/
│   │   │   ├── character-form.js  # 角色表单（骨架走 modal 工厂，提交走 character-submit）
│   │   │   ├── character-wizard.js# 六步角色创建向导（LLM 智能解析 + 模板；headerExtra 插槽挂步骤指示器）
│   │   │   ├── character-submit.js# 角色提交深模块（splitTags / buildCharacterPayload / 提交态状态机）
│   │   │   ├── confirm-dialog.js  # 确认弹窗（showConfirm / showAlert，复用 openModal）
│   │   │   ├── modal.js           # 通用模态框工厂（openModal：遮罩/头部/三关闭路径/Escape/headerExtra/removeExisting）
│   │   │   ├── model-selector.js  # 模型选择弹窗
│   │   │   ├── export-dialog.js   # 导出弹窗
│   │   │   ├── settings-panel.js  # 设置面板（initSettingsPanel / loadSettings）
│   │   │   └── tab-bar.js         # tab 条 presentational 组件（消费 getTabDisplay 展示契约）
│   │   ├── data/
│   │   │   └── character-templates.js # 角色创建向导内置模板
│   │   └── utils.js               # 工具函数（escapeHtml / downloadBlob / showToast / providerDisplayName）
│   │   └── utils/
│   │       ├── model-utils.js     # 模型选择逻辑（fillModelSelect / createCustomModelHandler）
│   │       └── sse-reader.js      # SSE 流解析纯函数（parseSSEStream）
│   └── assets/
│
├── docs/                          # 核心文档
│   ├── architecture.md
│   ├── api-design.md
│   ├── llm-integration.md
│   ├── documentation-standards.md
│   ├── p2.5-character-import-export.md
│   └── development-plan.md
│
├── pytest.ini                     # pytest 配置（pythonpath + testpaths）
├── conver_system.db               # 运行时生成
├── .gitignore
└── README.md
```

## 数据流：一次聊天请求

### 非流式

```
用户输入 → POST /api/chats { conversation_id, content }
    │
    ├─ 1. 路由接收请求
    ├─ 2. Service 加载 conversation 及其角色
    ├─ 3. build_message_list 构建 messages（见 llm-integration.md）：
    │    system(system_prompt 或 personality) → [scenario 系统消息] → [mes_example few-shot]
    │    → 历史消息（滑窗，保留最近 N 轮）→ [post_history_instructions] → user(新消息)
    ├─ 4. 从 DB 获取该对话的 model_provider + model_name
    ├─ 5. Factory 获取对应的 LLM Provider 实例
    ├─ 6. provider.generate(messages) → 回复文本
    ├─ 7. 保存 user 消息 + assistant 回复到 DB
    └─ 8. 返回 { reply, message_id, ... }
```

### 流式

```
用户输入 → POST /api/chats/stream
    │
    ├─ 1-5 同上
    ├─ 6. provider.stream_generate(messages) → AsyncIterator[token]
    ├─ 7. 逐 token 通过 SSE 推送给前端
    ├─ 8. 流结束后保存完整消息到 DB
    └─ 9. 前端逐 token 渲染（打字机效果）
```

## 数据库模型

### characters

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增 |
| name | VARCHAR(100) | 角色名称 |
| description | TEXT | 角色简短描述 |
| personality | TEXT | **人设设定**（默认 system prompt） |
| scenario | TEXT | 场景设定（附加 system 消息） |
| first_mes | TEXT | 开场白（V2: first_mes，原 greeting） |
| mes_example | TEXT | 对话范例（few-shot，`<START>` 分隔） |
| system_prompt | TEXT | 覆盖系统提示词（优先于 personality） |
| post_history_instructions | TEXT | 历史后指令 |
| alternate_greetings | JSON | 备选开场白 (list) |
| tags | JSON | 标签 (list) |
| creator | VARCHAR(100) | 创作者 |
| version | VARCHAR(50) | 版本，默认 1.0 |
| creator_notes | JSON | 创作者备注 (dict) |
| extensions | JSON | 扩展字段 (dict) |
| avatar | TEXT | 头像（base64 / 路径，可空） |
| temperature | FLOAT | 默认 0.7 |
| created_at | DATETIME | |
| updated_at | DATETIME | |

### conversations

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增 |
| character_id | INTEGER FK | → characters.id |
| title | VARCHAR(200) | 对话标题 |
| model_provider | VARCHAR(50) | claude / openai |
| model_name | VARCHAR(100) | 具体模型名 |
| created_at | DATETIME | |
| updated_at | DATETIME | |

### messages

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增 |
| conversation_id | INTEGER FK | → conversations.id |
| role | VARCHAR(20) | user / assistant / system（ORM 层 Role 枚举，按值存取） |
| content | TEXT | 消息内容 |
| created_at | DATETIME | |

### settings

| 字段 | 类型 | 说明 |
|------|------|------|
| key | VARCHAR(100) PK | 配置键 |
| value | TEXT | 配置值 |

## 设计决策说明

| 决策 | 理由 |
|------|------|
| **Vanilla JS 而非框架** | 避免构建工具链，个人项目追求轻量 |
| **SQLite 而非 MySQL/PostgreSQL** | 本地优先，零配置部署 |
| **SSE 而非 WebSocket** | 单方向推送（服务器→客户端）足够，实现简单 |
| **Factory 模式接入 LLM** | 新增 Provider 只需加一个新类，不改业务 |
| **personality 单独字段** | 与 name/avatar 等元数据分离，语义清晰 |
