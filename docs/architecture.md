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
│  │ /api/convs      │──▶│ Conversation │   │  ├─Claude     │  │
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
│   │   │   ├── deps.py            # 依赖注入（get_db 等）
│   │   │   └── routes/
│   │   │       ├── __init__.py
│   │   │       ├── characters.py  # 角色 CRUD
│   │   │       ├── conversations.py # 对话管理
│   │   │       ├── messages.py    # 消息 + 聊天
│   │   │       ├── models.py      # 可用模型列表
│   │   │       └── settings.py    # 配置管理
│   │   │
│   │   ├── models/                # SQLAlchemy ORM
│   │   │   ├── __init__.py
│   │   │   ├── character.py
│   │   │   ├── conversation.py
│   │   │   └── message.py
│   │   │
│   │   ├── schemas/               # Pydantic 请求/响应
│   │   │   ├── __init__.py
│   │   │   ├── character.py
│   │   │   ├── conversation.py
│   │   │   └── message.py
│   │   │
│   │   └── services/
│   │       ├── __init__.py
│   │       ├── character.py
│   │       ├── conversation.py
│   │       ├── message.py
│   │       └── llm/
│   │           ├── __init__.py
│   │           ├── base.py        # BaseLLM 抽象基类
│   │           ├── claude.py      # Claude Provider
│   │           ├── openai.py      # OpenAI Provider
│   │           ├── factory.py     # Provider 工厂
│   │           └── errors.py      # LLM 异常定义
│   │
│   ├── requirements.txt
│   └── .env.example
│
├── frontend/
│   ├── index.html                 # SPA 入口
│   ├── css/
│   │   └── style.css
│   ├── js/
│   │   ├── app.js                 # 主入口 + 状态管理
│   │   ├── api.js                 # API 调用层
│   │   ├── components/
│   │   │   ├── chat.js            # 聊天区域
│   │   │   ├── character-manager.js # 角色管理
│   │   │   ├── conversation-list.js # 对话历史
│   │   │   └── settings.js        # 设置面板
│   │   └── utils.js
│   └── assets/
│
├── docs/                          # 核心文档
│   ├── architecture.md
│   ├── api-design.md
│   ├── llm-integration.md
│   └── development-plan.md
│
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
    ├─ 2. Service 加载 conversation 及其角色 personality
    ├─ 3. 构建 messages: [system(角色设定), user(历史)... , user(新消息)]
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
| avatar | TEXT | 头像（base64 / 路径，可空） |
| personality | TEXT | **人设设定**（注入 system prompt） |
| greeting | TEXT | 开场白 |
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
| role | VARCHAR(20) | user / assistant / system |
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
