# Conver System — Code Wiki

> 版本：Phase 1-5 + P6.1~6.5 + P2.5/3.5/4.3 + U7~U9 模拟器 + SIM-API-1 + 技术债区清零（TD-1~76，2026-08-14）全部完成
> 生成日期：2026-08-15
> 测试状态：<!--AUTO:tests_total:total-->1969<!--/AUTO--> 项全绿（pytest <!--AUTO:tests_total:pytest-->793<!--/AUTO--> + Vitest <!--AUTO:tests_total:vitest-->1106<!--/AUTO--> + cargo test <!--AUTO:tests_total:cargo-->70<!--/AUTO-->）
>

---

## 一、项目概述

**Conver System** 是一个本地优先、多模型可切换的角色对话应用：用户创建带人设的虚拟角色，与不同角色进行 AI 驱动的多轮对话。数据（含 API Key）全部存本地 SQLite，无云端依赖；形态为网页版 SPA + Tauri 桌面壳。

| 属性 | 说明 |
|------|------|
| 后端 | Python 3.12 + FastAPI + SQLAlchemy 2.0（**同步 ORM**）+ SQLite + Pydantic v2 |
| 前端 | Vanilla JS（ES Modules）+ 原生 Fetch，零构建步骤 |
| 桌面壳 | Tauri v2（Rust），子进程托管打包后端 + 系统托盘 |
| LLM 接入 | anthropic / openai 官方 SDK，Provider 工厂抽象 |
| 测试框架 | pytest（后端）/ Vitest（前端）/ cargo test（壳） |
| 打包 | PyInstaller（后端 exe）+ Tauri 构建（桌面安装器） |

## 二、项目架构总览

### 2.1 分层架构

```
┌────────────────────────────────────────────────────────────────────┐
│                    前端 SPA（frontend/，Vanilla JS ESM）             │
│  app.js 编排 → 视图模块（chat/tabs/search-view/simulator-*）        │
│  → api.js 统一请求层（fetch-seam 注入缝）→ StreamSession 流式会话   │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ HTTP / SSE
┌──────────────────────────────┴─────────────────────────────────────┐
│                    后端（backend/app/，FastAPI）                     │
│  main.py 装配（on_startup 初始化 DB + 模拟器种子，Provider 懒注册）→ api/routes/* 路由│
│  → services/* 业务服务（无手写 dict，response_model 驱动序列化）    │
│  → services/llm/* Provider 工厂（Claude / OpenAI 兼容）             │
│  → models/* ORM（SQLAlchemy 2.0 同步模式）→ SQLite                 │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ 子进程 + HTTP 探测 + runtime.json
┌──────────────────────────────┴─────────────────────────────────────┐
│                  Tauri 壳（src-tauri/，Rust）                        │
│  lib.rs ShellState（动态端口/数据目录/就绪状态机）→ server.rs        │
│  （spawn 后端进程 + 探活 + runtime.json）→ tray.rs / commands.rs     │
└────────────────────────────────────────────────────────────────────┘
```

### 2.2 关键数据流

```
非流式对话：chat.js handleSend → api.js request(POST /api/chats)
    → routes/chat.py create_chat → services/chat.py prepare_chat + complete_chat
    → llm/{provider}.generate → services/message.py create_message（落库）

流式对话：StreamSession.createStreamSession → api.js chatStream(SSE)
    → routes/chat.py stream_chat → services/chat.py stream_reply（逐块 yield）
    → sse-reader.js parseSSEStream → settleTurn 统一结算（防悬挂写回）

桌面启动：main.rs → lib.rs launch → server.rs probe_free_port + spawn_backend
    → http_probe 就绪轮询 → write_runtime_json → boot.html 跳转前端
```

### 2.3 架构不变量

- 路由只做 HTTP 映射，ORM 操作在 service 层；`response_model + from_attributes` 统一驱动序列化
- Provider 懒注册：`register_builtin_providers()` 由 `factory.py` 在首次 `get_provider`/`list_providers` 时经 `_ensure_builtins` 自动触发（启动不预热，SDK 推迟到首次 LLM 调用）
- 前端动态模板/状态图标一律走 `frontend/js/icons.js` 的 `iconHtml()` seam
- 静态挂载契约：API 路由须 `/api` 前缀且在静态挂载前注册
- 所有包 `__init__.py` 必须有 `__all__`；公开函数必须 type hints + docstring

---

## 三、文件结构

```
conver system/
├── backend/                        ← FastAPI 后端（可独立 PyInstaller 打包）
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py                 ← [入口] FastAPI 装配 + 静态挂载 + Provider 注册
│   │   ├── config.py               ← [配置] pydantic-settings 单源（.env + 环境变量）
│   │   ├── database.py             ← [持久化] 引擎/会话/建表（PRAGMA foreign_keys=ON）
│   │   ├── api/
│   │   │   ├── __init__.py
│   │   │   ├── errors.py           ← 统一异常处理器（领域 + LLM 双通道）
│   │   │   ├── headers.py          ← Content-Disposition 构建（ASCII/UTF-8 双名）
│   │   │   └── routes/
│   │   │       ├── __init__.py
│   │   │       ├── characters.py   ← 角色 CRUD + 导入导出 + 文档解析
│   │   │       ├── chat.py         ← 对话（含 SSE 流式端点）
│   │   │       ├── conversations.py← 会话 CRUD + 清空 + JSON/Markdown 导出
│   │   │       ├── messages.py     ← 消息读取 + 跨对话搜索
│   │   │       ├── models.py       ← Provider/模型清单
│   │   │       └── settings.py     ← 设置 CRUD + 凭证 + 连接测试
│   │   ├── models/                 ← SQLAlchemy ORM（4 实体）
│   │   │   ├── __init__.py
│   │   │   ├── character.py        ← 角色（V2 字段映射，JSON 列兼容存量）
│   │   │   ├── conversation.py     ← 会话
│   │   │   ├── message.py          ← 消息（Role 枚举按值存取）
│   │   │   └── setting.py          ← 设置键值
│   │   ├── schemas/                ← Pydantic v2 请求/响应模型
│   │   │   ├── __init__.py
│   │   │   ├── character.py
│   │   │   ├── conversation.py
│   │   │   ├── message.py
│   │   │   └── settings.py
│   │   └── services/               ← 业务服务层（路由 → service → ORM）
│   │       ├── __init__.py
│   │       ├── character.py        ← 角色服务
│   │       ├── character_card.py   ← Character Card V2 转换（导出/导入）
│   │       ├── character_fields.py   ← 角色字段常量映射深模块（C5）
│   │       ├── chat.py             ← 对话编排（准备/完成/流式/错误响应）
│   │       ├── conversation.py     ← 会话服务（标题生成/滑窗）
│   │       ├── conversation_export.py ← 会话 JSON/Markdown 导出
│   │       ├── data_dir.py         ← 数据目录契约（路径单源）
│   │       ├── document_parser.py  ← LLM 文档智能解析（六步向导）
│   │       ├── error_mapping.py    ← 领域异常 → HTTP 响应映射
│   │       ├── exceptions.py       ← 领域异常定义
│   │       ├── message.py          ← 消息服务（开场白/上下文构建/搜索）
│   │       ├── model_data.py       ← Provider/模型清单单一来源（AVAILABLE_MODELS）
│   │       ├── provider_registry.py ← Provider 派生元数据深模块（C6）
│   │       ├── setting.py          ← 设置服务（凭证槽位/滑窗轮数）
│   │       └── llm/                ← LLM 接入层（深模块）
│   │           ├── __init__.py     ← 包级导出零 SDK 副作用契约
│   │           ├── base.py         ← BaseLLM 抽象基类（generate/stream/test）
│   │           ├── claude.py       ← ClaudeProvider（anthropic SDK）
│   │           ├── openai.py       ← OpenAIProvider（openai SDK，兼容聚合平台）
│   │           ├── errors.py       ← SDK 错误翻译（认证/限流/超时/坏请求）
│   │           ├── factory.py      ← LLMFactory 注册表（显式注册 + 懒加载）
│   │           ├── prompt.py       ← 提示词构建（模板变量/mes_example/滑窗）
│   │           └── resolver.py     ← DB 配置 → Provider 实例解析
│   ├── run_backend.py              ← 独立启动脚本（日志/数据目录/端口）
│   ├── scripts/
│   │   └── migrate_data.py         ← 数据目录迁移工具（校验/标记/幂等）
│   ├── tests/                      ← pytest（25 个文件，见 §5.1）
│   ├── requirements.txt
│   ├── requirements-dev.txt
│   ├── conver_backend.spec         ← PyInstaller 打包配置
│   └── .env.example
├── frontend/                       ← 网页版 SPA
│   ├── js/
│   │   ├── api.js                  ← 统一请求层（超时守卫/SSE/Blob）
│   │   ├── app.js                  ← 应用编排（视图切换/初始化接线）
│   │   ├── cascade.js              ← 级联收口（清空会话联动）
│   │   ├── chat.js                 ← 对话视图（消息渲染/发送/流式接线）
│   │   ├── conversation-activation.js ← 会话激活（tab 视图恢复）
│   │   ├── fetch-seam.js           ← fetch 注入缝（测试替身）
│   │   ├── format.js               ← 展示契约（气泡/卡片/列表 HTML 生成）
│   │   ├── icons.js                ← 图标 seam（iconHtml 单源）
│   │   ├── key-injector.js         ← 模拟器 Key/模型注入（SIM-API-1）
│   │   ├── list-views.js           ← 角色/对话列表视图深模块（C4）
│   │   ├── markdown.js             ← Markdown 渲染（XSS 消毒）
│   │   ├── save-key-meta.js        ← 存档键契约单一来源（TD-67/68）
│   │   ├── save-manager.js         ← 模拟器存档管理（导出/导入/删除）
│   │   ├── search-view.js          ← 跨对话搜索视图
│   │   ├── simulator-contracts.js  ← 模拟器域契约单一来源（C8）
│   │   ├── simulator-adapt.js      ← 适配分析共享模块（映射记录/三面提取/覆盖比对，T-01）
│   │   ├── simulator-view.js       ← 模拟器运行视图（iframe/观察者/自动同步）
│   │   ├── simulators.js           ← 模拟器列表视图（manifest 解析/筛选）
│   │   ├── state.js                ← 全局 DOM 引用缓存
│   │   ├── stream-session.js       ← 流式会话深模块（结算收口）
│   │   ├── tabs.js                 ← tab 工作区深模块（sessionStorage 恢复）
│   │   ├── utils.js                ← 通用工具（escapeHtml/toast/下载）
│   │   ├── components/
│   │   │   ├── character-form.js   ← 角色编辑表单
│   │   │   ├── character-submit.js ← 提交状态机（payload 构建/成功失败态）
│   │   │   ├── character-wizard.js ← 六步创建向导
│   │   │   ├── confirm-dialog.js   ← 确认/提示对话框
│   │   │   ├── export-dialog.js    ← 会话导出对话框
│   │   │   ├── loading-button.js  ← 按钮 loading 态工具（spinner + 禁用 + restore）
│   │   │   ├── modal.js            ← 模态骨架（骨架收口 C3-DEFER）
│   │   │   ├── model-selector.js   ← 模型选择弹层
│   │   │   ├── settings-panel.js   ← 设置面板（Key/主题/侧栏）
│   │   │   └── tab-bar.js          ← 会话 tab 栏组件
│   │   ├── data/
│   │   │   └── character-templates.js ← 5 套角色创建模板数据
│   │   └── utils/
│   │       ├── model-utils.js      ← 模型下拉填充工具
│   │       └── sse-reader.js       ← SSE 流解析
│   ├── tests/                      ← Vitest（33 个文件，见 §5.2）
│   ├── vitest.config.js
│   ├── package.json
│   └── simulators/                 ← 22 款第三方单文件模拟器（HTML，非源码）
├── scripts/                        ← [F-01 文档同步工具链]（本仓库）
│   ├── check-simulator-css.mjs     ← 模拟器接入契约核对脚本（T-01，退出码 0=全绿）
│   ├── doc_sync.py                 ← CODE_WIKI 机械标记生成/校验（三渠道）
│   ├── pre-commit.sh               ← pre-commit 钩子源：跑 `doc_sync.py --check`
│   └── install-hooks.bat           ← 把 pre-commit.sh 复制到 `.git/hooks/pre-commit`
├── src-tauri/                      ← Tauri v2 桌面壳
│   ├── build.rs
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs                  ← ShellState 状态机（端口/数据目录/子进程）
│   │   ├── server.rs               ← 后端进程管理（探测/spawn/探活/runtime.json）
│   │   ├── commands.rs             ← Tauri 命令（backend_status / 关闭行为偏好读写）
│   │   ├── settings.rs             ← 壳级用户设置（关闭行为偏好 settings.json，D11）
│   │   ├── tray.rs                 ← 系统托盘（菜单路由/自启状态机）
│   │   └── main.rs                 ← 壳入口
│   └── tests/                      ← 集成测试（4 个文件，见 §5.3）
├── docs/                           ← 设计文档（架构/API/LLM/Tauri，见 PROJECT_REFERENCE §五）
├── CLAUDE.md                       ← 项目规则与当前状态
├── PROJECT_REFERENCE.md            ← 项目介绍书（介绍/决策/坑点）
├── TICKETS.md                      ← 唯一待办事实来源
├── DEV_LOG.md                      ← 开发日志（已做）
├── CONSENSUS.md                    ← 共识文档（需求定义与技术决策）
└── CODE_WIKI.md                    ← 本文档（技术细节单一权威源）
```

---

## 四、核心模块详细说明

### 4.1 `backend/app/main.py` — 应用入口（<!--AUTO:lines:backend/app/main.py-->~79 行<!--/AUTO-->）

**职责**：FastAPI 应用装配——注册统一异常处理器、on_startup 初始化 DB 与模拟器首启种子（Provider 懒注册，不预热 SDK）、API 路由挂载（须 `/api` 前缀且在静态挂载前）、`/simulators` 挂载（数据目录 simulators，T-02 外置，先于根挂载）、前端静态文件挂载。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/main.py:on_startup-->`on_startup()`<!--/AUTO--> | 启动钩子：`init_db()` + 模拟器首启种子（Provider 懒注册，不预热 SDK） |
| <!--AUTO:sig:backend/app/main.py:_frontend_dir-->`_frontend_dir()`<!--/AUTO--> | 定位前端静态目录（打包与源码双形态） |

### 4.2 `backend/app/config.py` — 配置单源（<!--AUTO:lines:backend/app/config.py-->~27 行<!--/AUTO-->）

**职责**：pydantic-settings 配置类——`DATABASE_URL`、`HOST`/`PORT` 等；`.env` 相对 CWD 读取（服务从项目根启动）。

> 无公开函数（纯配置常量）。注意 `DATABASE_URL` 默认值带 `+aiosqlite` 前缀，但 `database.py` 建引擎时剔除（同步 ORM，勿误判为异步）。

### 4.3 `backend/app/database.py` — 引擎与会话（<!--AUTO:lines:backend/app/database.py-->~50 行<!--/AUTO-->）

**职责**：SQLAlchemy 同步引擎（`PRAGMA foreign_keys=ON`）、`get_db` 会话依赖、`init_db` 建表。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/database.py:set_sqlite_pragma-->`set_sqlite_pragma(dbapi_connection, connection_record)`<!--/AUTO--> | 连接事件：启用外键约束 |
| <!--AUTO:sig:backend/app/database.py:get_db-->`get_db()`<!--/AUTO--> | FastAPI 依赖：每请求会话（yield + 关闭） |
| <!--AUTO:sig:backend/app/database.py:init_db-->`init_db()`<!--/AUTO--> | 建表（`Base.metadata.create_all`） |

### 4.4 `backend/app/api/errors.py` — 统一异常处理器（<!--AUTO:lines:backend/app/api/errors.py-->~44 行<!--/AUTO-->）

**职责**：两路异常处理器（ARC10 T-15）——领域异常 → 业务错误响应；LLM 异常 → Provider 标签化错误响应。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/api/errors.py:domain_error_handler-->`domain_error_handler(request, exc)`<!--/AUTO--> | 领域异常 → HTTP 响应（错误码 + 消息） |
| <!--AUTO:sig:backend/app/api/errors.py:llm_error_handler-->`llm_error_handler(request, exc)`<!--/AUTO--> | LLM 异常 → HTTP 响应（透传 Provider 错误分类） |

### 4.5 `backend/app/api/headers.py` — 下载响应头（<!--AUTO:lines:backend/app/api/headers.py-->~25 行<!--/AUTO-->）

**职责**：构建 `Content-Disposition`——ASCII 与 UTF-8 文件名双形态（RFC 5987 `filename*`）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/api/headers.py:build_content_disposition-->`build_content_disposition(ascii_filename, utf8_filename)`<!--/AUTO--> | 生成下载响应头值 |

### 4.6 `backend/app/api/routes/characters.py` — 角色路由（<!--AUTO:lines:backend/app/api/routes/characters.py-->~71 行<!--/AUTO-->）

**职责**：角色 CRUD + V2 角色卡导出/导入 + 文档智能解析端点（薄层，逻辑在 service）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/api/routes/characters.py:list_characters-->`list_characters(db)`<!--/AUTO--> | GET 角色列表 |
| <!--AUTO:sig:backend/app/api/routes/characters.py:get_character-->`get_character(character_id, db)`<!--/AUTO--> | GET 单角色 |
| <!--AUTO:sig:backend/app/api/routes/characters.py:create_character-->`create_character(data, db)`<!--/AUTO--> | POST 创建角色 |
| <!--AUTO:sig:backend/app/api/routes/characters.py:update_character-->`update_character(character_id, data, db)`<!--/AUTO--> | PUT 更新角色 |
| <!--AUTO:sig:backend/app/api/routes/characters.py:delete_character-->`delete_character(character_id, db)`<!--/AUTO--> | DELETE 删除角色 |
| <!--AUTO:sig:backend/app/api/routes/characters.py:export_character-->`export_character(character_id, db)`<!--/AUTO--> | GET 导出 V2 角色卡（JSON 文件下载） |
| <!--AUTO:sig:backend/app/api/routes/characters.py:parse_character_document-->`parse_character_document(request, db)`<!--/AUTO--> | POST 文档智能解析（LLM 提取角色字段） |
| <!--AUTO:sig:backend/app/api/routes/characters.py:import_character-->`import_character(card, db)`<!--/AUTO--> | POST 导入角色卡（V2/V1/裸 data） |

### 4.7 `backend/app/api/routes/chat.py` — 对话路由（<!--AUTO:lines:backend/app/api/routes/chat.py-->~57 行<!--/AUTO-->）

**职责**：非流式对话 + SSE 流式对话（`stream_chat`，POST /api/chats/stream）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/api/routes/chat.py:create_chat-->`create_chat(request, db)`<!--/AUTO--> | POST 非流式对话（prepare + complete） |
| <!--AUTO:sig:backend/app/api/routes/chat.py:stream_chat-->`stream_chat(request, raw_request, db)`<!--/AUTO--> | POST SSE 流式对话（断开感知 is_disconnected） |

### 4.8 `backend/app/api/routes/conversations.py` — 会话路由（<!--AUTO:lines:backend/app/api/routes/conversations.py-->~92 行<!--/AUTO-->）

**职责**：会话 CRUD + 清空 + JSON/Markdown 导出 + 重生成端点。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/api/routes/conversations.py:list_conversations-->`list_conversations(character_id, db)`<!--/AUTO--> | GET 会话列表（按角色筛选） |
| <!--AUTO:sig:backend/app/api/routes/conversations.py:get_conversation-->`get_conversation(conversation_id, db)`<!--/AUTO--> | GET 单会话 |
| <!--AUTO:sig:backend/app/api/routes/conversations.py:create_conversation-->`create_conversation(data, db)`<!--/AUTO--> | POST 创建会话 |
| <!--AUTO:sig:backend/app/api/routes/conversations.py:update_conversation-->`update_conversation(conversation_id, data, db)`<!--/AUTO--> | PUT 重命名/更新会话 |
| <!--AUTO:sig:backend/app/api/routes/conversations.py:delete_conversation-->`delete_conversation(conversation_id, db)`<!--/AUTO--> | DELETE 删除会话 |
| <!--AUTO:sig:backend/app/api/routes/conversations.py:delete_all_conversations-->`delete_all_conversations(db)`<!--/AUTO--> | DELETE 清空全部会话 |
| <!--AUTO:sig:backend/app/api/routes/conversations.py:export_conversation_json-->`export_conversation_json(conversation_id, db)`<!--/AUTO--> | GET JSON 导出 |
| <!--AUTO:sig:backend/app/api/routes/conversations.py:export_conversation_markdown-->`export_conversation_markdown(conversation_id, db)`<!--/AUTO--> | GET Markdown 导出 |
| <!--AUTO:sig:backend/app/api/routes/conversations.py:regenerate-->`regenerate(conversation_id, body=None, db)`<!--/AUTO--> | POST 重生成 AI 回复 |

### 4.9 `backend/app/api/routes/messages.py` — 消息路由（<!--AUTO:lines:backend/app/api/routes/messages.py-->~33 行<!--/AUTO-->）

**职责**：消息读取 + 跨对话关键词搜索。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/api/routes/messages.py:get_messages-->`get_messages(conversation_id, db)`<!--/AUTO--> | GET 会话消息列表 |
| <!--AUTO:sig:backend/app/api/routes/messages.py:search_messages-->`search_messages(q, limit, db)`<!--/AUTO--> | GET 跨对话搜索（关键词 + 上限） |

### 4.10 `backend/app/api/routes/models.py` — 模型路由（<!--AUTO:lines:backend/app/api/routes/models.py-->~11 行<!--/AUTO-->）

**职责**：暴露 Provider/模型清单（派生自 `model_data.py` 单源）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/api/routes/models.py:list_models-->`list_models()`<!--/AUTO--> | GET 可用模型/Provider 列表 |

### 4.11 `backend/app/api/routes/settings.py` — 设置路由（<!--AUTO:lines:backend/app/api/routes/settings.py-->~69 行<!--/AUTO-->）

**职责**：设置 CRUD + 凭证端点（U8-T1）+ 连接测试。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/api/routes/settings.py:get_credentials-->`get_credentials(db)`<!--/AUTO--> | GET 只读凭证端点（模拟器注入用） |
| <!--AUTO:sig:backend/app/api/routes/settings.py:get_settings-->`get_settings(db)`<!--/AUTO--> | GET 全部设置 |
| <!--AUTO:sig:backend/app/api/routes/settings.py:update_settings-->`update_settings(data, db)`<!--/AUTO--> | PUT 批量更新设置 |
| <!--AUTO:sig:backend/app/api/routes/settings.py:test_connection-->`test_connection(data, db)`<!--/AUTO--> | POST 连接测试（保存时校验 Key） |

### 4.11.5 `backend/app/api/routes/simulators.py` — 模拟器导入路由（工单 03 + 2026-08-26 重新识别）（<!--AUTO:lines:backend/app/api/routes/simulators.py-->~131 行<!--/AUTO-->）

**职责**：POST /api/simulators/import 单文件 HTML 游戏导入（multipart 字段名 `file`）；POST /api/simulators/reprobe 重新识别已有游戏（JSON `{id}`，重读 HTML → 三层探测 + 端点口径 → 原子更新 manifest 条目 type/config/endpointMode，条目或文件缺失 404）——仅 HTTP 映射（状态码 + 响应形状）；校验/去重/改名/探测/粗筛/manifest 注册全部委托 `services/simulator_store`。契约：import 200 `{ok, game{id,file,name,type,config?}, renamed, warnings}`；reprobe 200 `{ok, game}`。数据目录请求期解析（可 monkeypatch CONVER_DATA_DIR）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/api/routes/simulators.py:import_simulator-->`import_simulator(file)`<!--/AUTO--> | POST 导入端点（5MB+1 读取守卫；领域异常映射 400/409） |
| <!--AUTO:sig:backend/app/api/routes/simulators.py:reprobe_simulator-->`reprobe_simulator(body)`<!--/AUTO--> | POST 重新识别（probe_config + probe_endpoint_mode → update_manifest_entry；缺失 404） |

### 4.12 `backend/app/services/character.py` — 角色服务（<!--AUTO:lines:backend/app/services/character.py-->~77 行<!--/AUTO-->）

**职责**：角色 CRUD 业务逻辑 + 消息计数 + 不存在即抛领域异常。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/character.py:list_characters-->`list_characters(db)`<!--/AUTO--> | 角色列表（含计数） |
| <!--AUTO:sig:backend/app/services/character.py:get_character-->`get_character(db, character_id)`<!--/AUTO--> | 单角色 |
| <!--AUTO:sig:backend/app/services/character.py:get_character_with_count-->`get_character_with_count(db, character_id)`<!--/AUTO--> | 单角色 + 消息数 |
| <!--AUTO:sig:backend/app/services/character.py:require_character-->`require_character(db, character_id)`<!--/AUTO--> | 角色存在性守卫（404 领域异常） |
| <!--AUTO:sig:backend/app/services/character.py:create_character-->`create_character(db, data)`<!--/AUTO--> | 创建角色 |
| <!--AUTO:sig:backend/app/services/character.py:update_character-->`update_character(db, character_id, data)`<!--/AUTO--> | 更新角色 |
| <!--AUTO:sig:backend/app/services/character.py:delete_character-->`delete_character(db, character_id)`<!--/AUTO--> | 删除角色 |

### 4.13 `backend/app/services/character_card.py` — 角色卡 V2 转换（<!--AUTO:lines:backend/app/services/character_card.py-->~192 行<!--/AUTO-->）

**职责**：SillyTavern Character Card V2 信封导出/导入——兼容 V1 旧卡与裸 data；非 V2 标准字段存 `extensions.conver_system.*` 命名空间保证往返保真；头像 data URI 规范化。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/character_card.py:to_v2_card-->`to_v2_card(char)`<!--/AUTO--> | ORM 角色 → V2 信封 dict |
| <!--AUTO:sig:backend/app/services/character_card.py:from_v2_card-->`from_v2_card(card)`<!--/AUTO--> | V2 信封 → 创建数据（V1/裸 data 归一化） |
| <!--AUTO:sig:backend/app/services/character_card.py:_normalize_v1-->`_normalize_v1(card)`<!--/AUTO--> | V1 旧卡 → V2 字段形态 |
| <!--AUTO:sig:backend/app/services/character_card.py:_build_create-->`_build_create(data)`<!--/AUTO--> | 提取标准字段为创建数据 |
| <!--AUTO:sig:backend/app/services/character_card.py:_conver_system-->`_conver_system(extensions)`<!--/AUTO--> | 读写 `extensions.conver_system.*` 命名空间 |
| <!--AUTO:sig:backend/app/services/character_card.py:_clamp_temperature-->`_clamp_temperature(value)`<!--/AUTO--> | 温度值收敛到合法区间 |

### 4.13.5 `backend/app/services/character_fields.py` — 角色字段常量映射（<!--AUTO:lines:backend/app/services/character_fields.py-->~101 行<!--/AUTO-->）

**职责**：角色 V2 字段清单单一映射深模块（C5 架构评审）——CHARACTER_V2_FIELDS 16 字段全集 + 4 个具名投影子集 + V2_KEY_MAP / V1_TO_V2_MAP 映射。

| 元素 | 说明 |
|------|------|
| `CHARACTER_V2_FIELDS` | V2 内容字段全集（16 项） |
| `PROMPT_FIELDS` | Prompt 组装投影（6 字段） |
| `PARSE_FIELDS` | 文档解析投影（10 字段） |
| `EXPORT_FIELDS` | 导出投影（9 字段，含 id） |
| `V2_KEY_MAP` | DB 名 → V2 协议键名映射 |
| `V1_TO_V2_MAP` | V1 旧卡名 → DB 名映射 |

### 4.13.6 `backend/app/services/provider_registry.py` — Provider 派生元数据（<!--AUTO:lines:backend/app/services/provider_registry.py-->~64 行<!--/AUTO-->）

**职责**：Provider 清单的派生视图单一来源深模块（C6 架构评审）——协议映射 / 协议族模型集 / key 声明序在此收敛，替代 factory/setting 对 `AVAILABLE_MODELS["providers"]` 的多处独立遍历。

| 元素 | 说明 |
|------|------|
| `PROVIDER_KEYS` | Provider key 声明序（tuple，注册顺序契约） |
| `API_PROVIDER_MAP` | key → 协议 id（仅 key≠id 的协议共享者） |
| `OPENAI_PROTOCOL_MODELS` | openai 协议族模型集（id=="openai" 的 models 并集，TD-66） |
| `resolve_api_provider(key)` | key → 凭证槽位协议（映射者返回 id，否则自身） |

### 4.14 `backend/app/services/chat.py` — 对话编排（<!--AUTO:lines:backend/app/services/chat.py-->~385 行<!--/AUTO-->）

**职责**：对话核心——上下文准备（滑窗 + 开场白 + 模板变量）、非流式完成、重生成编排、SSE 流式回复（逐块结算 + 部分内容落库）、错误响应统一通道（`chat_error_response`，LLM 异常映射见 §4.19 error_mapping.py）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/chat.py:prepare_chat-->`prepare_chat(db, request)`<!--/AUTO--> | 构建对话上下文（角色/历史/滑窗 + 自动插开场白 + 落库用户消息） |
| <!--AUTO:sig:backend/app/services/chat.py:complete_chat-->`complete_chat(db, request)`<!--/AUTO--> | 非流式完成：生成 + 落库（含标题自动生成） |
| <!--AUTO:sig:backend/app/services/chat.py:chat_error_response-->`chat_error_response(e, provider=None)`<!--/AUTO--> | 对话异常 → 响应统一出口 |
| <!--AUTO:sig:backend/app/services/chat.py:stream_reply-->`stream_reply(db, conversation_id, ctx, is_disconnected)`<!--/AUTO--> | SSE 逐块生成（断开感知，部分内容落库） |
| <!--AUTO:sig:backend/app/services/chat.py:assemble_chat_context-->`assemble_chat_context(db, conversation_id, *, current_input=None)`<!--/AUTO--> | 下层组装函数（不插 user / greeting，重生成复用） |
| <!--AUTO:sig:backend/app/services/chat.py:regenerate_chat-->`regenerate_chat(db, conversation_id, message_id=None)`<!--/AUTO--> | 重生成编排：截断 → 组装 → 生成 → 单事务落库 |

### 4.15 `backend/app/services/conversation.py` — 会话服务（<!--AUTO:lines:backend/app/services/conversation.py-->~144 行<!--/AUTO-->）

**职责**：会话 CRUD + 默认标题（角色名派生）+ 自动标题（首条消息截断）+ 清空。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/conversation.py:list_conversations-->`list_conversations(db, character_id=None)`<!--/AUTO--> | 会话列表（可按角色过滤） |
| <!--AUTO:sig:backend/app/services/conversation.py:get_conversation-->`get_conversation(db, conversation_id)`<!--/AUTO--> | 单会话 |
| <!--AUTO:sig:backend/app/services/conversation.py:require_conversation-->`require_conversation(db, conversation_id)`<!--/AUTO--> | 会话存在性守卫 |
| <!--AUTO:sig:backend/app/services/conversation.py:truncate_title-->`truncate_title(text, max_len=20)`<!--/AUTO--> | 标题截断（默认 20 字符） |
| <!--AUTO:sig:backend/app/services/conversation.py:default_conversation_title-->`default_conversation_title(db, conversation_id)`<!--/AUTO--> | 默认标题 = 「与 {角色名} 的对话」 |
| <!--AUTO:sig:backend/app/services/conversation.py:maybe_auto_title-->`maybe_auto_title(db, conv, content)`<!--/AUTO--> | 首条消息自动生成标题 |
| <!--AUTO:sig:backend/app/services/conversation.py:create_conversation-->`create_conversation(db, data)`<!--/AUTO--> | 创建会话 |
| <!--AUTO:sig:backend/app/services/conversation.py:update_conversation-->`update_conversation(db, conversation_id, data)`<!--/AUTO--> | 更新（重命名等） |
| <!--AUTO:sig:backend/app/services/conversation.py:delete_conversation-->`delete_conversation(db, conversation_id)`<!--/AUTO--> | 删除会话 |
| <!--AUTO:sig:backend/app/services/conversation.py:delete_all_conversations-->`delete_all_conversations(db)`<!--/AUTO--> | 清空全部会话 |

### 4.16 `backend/app/services/conversation_export.py` — 会话导出（<!--AUTO:lines:backend/app/services/conversation_export.py-->~136 行<!--/AUTO-->）

**职责**：会话导出 JSON/Markdown 两种格式（含角色信息头）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/conversation_export.py:export_conversation_json-->`export_conversation_json(db, conversation_id)`<!--/AUTO--> | JSON 导出（结构化消息 + 角色元数据） |
| <!--AUTO:sig:backend/app/services/conversation_export.py:export_conversation_markdown-->`export_conversation_markdown(db, conversation_id)`<!--/AUTO--> | Markdown 导出（对话记录可读化） |

### 4.17 `backend/app/services/data_dir.py` — 数据目录契约（<!--AUTO:lines:backend/app/services/data_dir.py-->~67 行<!--/AUTO-->）

**职责**：数据目录路径单源（本地优先，桌面版重定向到 %APPDATA%）——目录解析、文件路径拼接、DB 路径、模拟器子目录（T-02 外置）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/data_dir.py:data_dir-->`data_dir()`<!--/AUTO--> | 数据目录（自动创建） |
| <!--AUTO:sig:backend/app/services/data_dir.py:data_dir_file-->`data_dir_file(file_name)`<!--/AUTO--> | 目录内文件路径 |
| <!--AUTO:sig:backend/app/services/data_dir.py:database_path-->`database_path()`<!--/AUTO--> | SQLite 文件路径 |
| <!--AUTO:sig:backend/app/services/data_dir.py:simulators_dir-->`simulators_dir()`<!--/AUTO--> | 模拟器游戏子目录（纯路径解析，创建归首启种子） |

### 4.18 `backend/app/services/document_parser.py` — 文档智能解析（<!--AUTO:lines:backend/app/services/document_parser.py-->~161 行<!--/AUTO-->）

**职责**：六步向导第一步——LLM 从用户文档提取角色字段（JSON 抽取 + 字段兜底 + 截断）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/document_parser.py:parse_document-->`parse_document(db, text, provider=None, model=None)`<!--/AUTO--> | 解析文档 → 角色字段 dict |
| <!--AUTO:sig:backend/app/services/document_parser.py:_extract_json-->`_extract_json(raw)`<!--/AUTO--> | 从 LLM 回复容错抽取 JSON |
| <!--AUTO:sig:backend/app/services/document_parser.py:_default_for-->`_default_for(field)`<!--/AUTO--> | 缺失字段兜底默认值 |
| <!--AUTO:sig:backend/app/services/document_parser.py:_truncate-->`_truncate(msg, max_len)`<!--/AUTO--> | 错误消息截断 |

### 4.19 `backend/app/services/error_mapping.py` — 错误映射（<!--AUTO:lines:backend/app/services/error_mapping.py-->~100 行<!--/AUTO-->）

**职责**：领域与 LLM 异常 → 标准错误响应结构（错误码/消息）单源（T-01 迁入 LLM 映射）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/error_mapping.py:domain_error_response-->`domain_error_response(exc)`<!--/AUTO--> | 领域异常 → 响应 dict |
| <!--AUTO:sig:backend/app/services/error_mapping.py:llm_error_response-->`llm_error_response(e, provider)`<!--/AUTO--> | LLM 异常 → (HTTP 状态码, 消息)（映射表单源） |

### 4.20 `backend/app/services/exceptions.py` — 领域异常（<!--AUTO:lines:backend/app/services/exceptions.py-->~40 行<!--/AUTO-->）

**职责**：领域异常定义（404/409/422 类），供 service 层抛出、errors.py 统一处理。

> 无公开函数（异常类层次）。

### 4.21 `backend/app/services/message.py` — 消息服务（<!--AUTO:lines:backend/app/services/message.py-->~193 行<!--/AUTO-->）

**职责**：消息读取/写入/写入（不提交）/截断/开场白自动插入/上下文构建（滑窗）/跨对话搜索。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/message.py:get_messages-->`get_messages(db, conversation_id)`<!--/AUTO--> | 会话消息列表 |
| <!--AUTO:sig:backend/app/services/message.py:create_message-->`create_message(db, conversation_id, role, content)`<!--/AUTO--> | 写入消息（自动提交） |
| <!--AUTO:sig:backend/app/services/message.py:create_message_no_commit-->`create_message_no_commit(db, conversation_id, role, content)`<!--/AUTO--> | 写入消息（不提交，供事务原子性） |
| <!--AUTO:sig:backend/app/services/message.py:delete_messages_from-->`delete_messages_from(db, conversation_id, target_id)`<!--/AUTO--> | 截断：删除 target_id 起全部消息（锚定 PK id，不提交） |
| <!--AUTO:sig:backend/app/services/message.py:auto_insert_greeting-->`auto_insert_greeting(db, conversation_id, user_name='User')`<!--/AUTO--> | 新会话自动插入开场白 |
| <!--AUTO:sig:backend/app/services/message.py:build_message_list-->`build_message_list(db, conversation, user_content, max_rounds=30, user_name='User')`<!--/AUTO--> | 构建 LLM 上下文（滑窗 + 模板变量） |
| <!--AUTO:sig:backend/app/services/message.py:search_messages-->`search_messages(db, query, limit=50)`<!--/AUTO--> | 跨对话关键词搜索 |

### 4.22 `backend/app/services/model_data.py` — Provider 清单单源（<!--AUTO:lines:backend/app/services/model_data.py-->~127 行<!--/AUTO-->）

**职责**：`AVAILABLE_MODELS` Provider/模型清单唯一声明源（ARC10 T-14）——factory 注册与 setting API map 自动派生；`_OPENAI_PROTOCOL_MODELS` 门控单源（TD-66）。

> 无公开函数（数据表 + 派生逻辑）。

### 4.23 `backend/app/services/setting.py` — 设置服务（<!--AUTO:lines:backend/app/services/setting.py-->~172 行<!--/AUTO-->）

**职责**：DB settings 表读写——凭证槽位（按 Provider 存取 Key/base_url）、滑窗轮数、用户名、默认模型；凭证通用解析（填任一 key 全局可用）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/setting.py:get_value-->`get_value(db, key, default='')`<!--/AUTO--> | 读设置项 |
| <!--AUTO:sig:backend/app/services/setting.py:get_int-->`get_int(db, key, default)`<!--/AUTO--> | 读整型设置 |
| <!--AUTO:sig:backend/app/services/setting.py:get_all-->`get_all(db)`<!--/AUTO--> | 读全部设置 |
| <!--AUTO:sig:backend/app/services/setting.py:set_many-->`set_many(db, data)`<!--/AUTO--> | 批量写设置 |
| <!--AUTO:sig:backend/app/services/setting.py:api_key-->`api_key(db, provider)`<!--/AUTO--> | 读指定 Provider 的 API Key |
| <!--AUTO:sig:backend/app/services/setting.py:base_url-->`base_url(db, provider)`<!--/AUTO--> | 读指定 Provider 的 base_url |
| <!--AUTO:sig:backend/app/services/setting.py:user_name-->`user_name(db)`<!--/AUTO--> | 用户名（模板变量 {{user}}） |
| <!--AUTO:sig:backend/app/services/setting.py:sliding_window_rounds-->`sliding_window_rounds(db)`<!--/AUTO--> | 滑窗轮数（默认 30） |
| <!--AUTO:sig:backend/app/services/setting.py:default_provider-->`default_provider(db)`<!--/AUTO--> | 默认 Provider |
| <!--AUTO:sig:backend/app/services/setting.py:default_model-->`default_model(db)`<!--/AUTO--> | 默认模型 |
| <!--AUTO:sig:backend/app/services/setting.py:credentials-->`credentials(db)`<!--/AUTO--> | 全部凭证（只读端点用） |

### 4.24 `backend/app/services/llm/base.py` — LLM 抽象基类（<!--AUTO:lines:backend/app/services/llm/base.py-->~90 行<!--/AUTO-->）

**职责**：`BaseLLM` 协议——generate/stream_generate/test_connection 骨架 + 错误翻译钩子（`_translate_error` 子类覆写）+ `_prepare_messages` 统一消息形态。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/llm/base.py:BaseLLM.__init__-->`__init__(api_key, base_url=None)`<!--/AUTO--> | 构造（密钥 + 可选 base_url） |
| <!--AUTO:sig:backend/app/services/llm/base.py:BaseLLM._translate_error-->`_translate_error(error)`<!--/AUTO--> | SDK 错误翻译钩子（子类覆写） |
| <!--AUTO:sig:backend/app/services/llm/base.py:BaseLLM.generate-->`generate(messages, temperature=0.7, max_tokens=2048, model=None)`<!--/AUTO--> | 非流式生成 |
| <!--AUTO:sig:backend/app/services/llm/base.py:BaseLLM.stream_generate-->`stream_generate(messages, temperature=0.7, max_tokens=2048, model=None)`<!--/AUTO--> | 流式生成（迭代器） |
| <!--AUTO:sig:backend/app/services/llm/base.py:BaseLLM.test_connection-->`test_connection(model=None)`<!--/AUTO--> | 连接测试（保存 Key 时校验） |

### 4.25 `backend/app/services/llm/claude.py` — Claude Provider（<!--AUTO:lines:backend/app/services/llm/claude.py-->~75 行<!--/AUTO-->）

**职责**：`ClaudeProvider(BaseLLM)`——anthropic SDK 实现（generate/stream_generate + 错误翻译）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/llm/claude.py:ClaudeProvider.__init__-->`__init__(api_key, base_url=None)`<!--/AUTO--> | 构造 |
| <!--AUTO:sig:backend/app/services/llm/claude.py:ClaudeProvider._translate_error-->`_translate_error(error)`<!--/AUTO--> | anthropic 异常 → LLMError 分类 |
| <!--AUTO:sig:backend/app/services/llm/claude.py:ClaudeProvider.generate-->`generate(messages, temperature=0.7, max_tokens=2048, model=None)`<!--/AUTO--> | 非流式生成 |
| <!--AUTO:sig:backend/app/services/llm/claude.py:ClaudeProvider.stream_generate-->`stream_generate(messages, temperature=0.7, max_tokens=2048, model=None)`<!--/AUTO--> | 流式生成 |

### 4.26 `backend/app/services/llm/errors.py` — SDK 错误翻译（<!--AUTO:lines:backend/app/services/llm/errors.py-->~63 行<!--/AUTO-->）

**职责**：`LLMError` 领域异常 + `translate_sdk_error` 通用翻译器（认证/限流/超时/坏请求四类，Provider 标签化）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/llm/errors.py:LLMError.__init__-->`__init__(message, original_error=None)`<!--/AUTO--> | 构造（保留原始异常） |
| <!--AUTO:sig:backend/app/services/llm/errors.py:translate_sdk_error-->`translate_sdk_error(error, provider_label, *, auth_cls, rate_cls, timeout_cls, bad_request_cls)`<!--/AUTO--> | SDK 异常 → LLMError 分类映射 |

### 4.27 `backend/app/services/llm/factory.py` — Provider 工厂（<!--AUTO:lines:backend/app/services/llm/factory.py-->~78 行<!--/AUTO-->）

**职责**：`LLMFactory` 注册表——显式注册 + 内置 Provider 批量注册 + 懒加载兜底 + 清单查询。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/llm/factory.py:LLMFactory.register-->`register(name, provider_cls)`<!--/AUTO--> | 注册 Provider 类 |
| <!--AUTO:sig:backend/app/services/llm/factory.py:LLMFactory.register_builtin_providers-->`register_builtin_providers()`<!--/AUTO--> | 批量注册内置 Provider（首次 `get_provider`/`list_providers` 时经 `_ensure_builtins` 懒触发） |
| <!--AUTO:sig:backend/app/services/llm/factory.py:LLMFactory.get_provider-->`get_provider(name, api_key, base_url=None)`<!--/AUTO--> | 按名取实例（未注册则懒加载兜底） |
| <!--AUTO:sig:backend/app/services/llm/factory.py:LLMFactory.list_providers-->`list_providers()`<!--/AUTO--> | 已注册 Provider 清单 |

### 4.28 `backend/app/services/llm/openai.py` — OpenAI Provider（<!--AUTO:lines:backend/app/services/llm/openai.py-->~87 行<!--/AUTO-->）

**职责**：`OpenAIProvider(BaseLLM)`——openai SDK 实现（兼容 base_url 聚合平台，`_normalize_base_url` 端点形态归一）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/llm/openai.py:OpenAIProvider.__init__-->`__init__(api_key, base_url=None)`<!--/AUTO--> | 构造（base_url 归一化） |
| <!--AUTO:sig:backend/app/services/llm/openai.py:OpenAIProvider._translate_error-->`_translate_error(error)`<!--/AUTO--> | openai 异常 → LLMError 分类 |
| <!--AUTO:sig:backend/app/services/llm/openai.py:OpenAIProvider.generate-->`generate(messages, temperature=0.7, max_tokens=2048, model=None)`<!--/AUTO--> | 非流式生成 |
| <!--AUTO:sig:backend/app/services/llm/openai.py:OpenAIProvider.stream_generate-->`stream_generate(messages, temperature=0.7, max_tokens=2048, model=None)`<!--/AUTO--> | 流式生成 |

### 4.29 `backend/app/services/llm/prompt.py` — 提示词构建（<!--AUTO:lines:backend/app/services/llm/prompt.py-->~137 行<!--/AUTO-->）

**职责**：模板变量替换（`{{user}}`/`{{char}}`）、mes_example 解析、system prompt 组装（角色设定注入）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/llm/prompt.py:apply_template_vars-->`apply_template_vars(text, user_name='User', char_name='Character')`<!--/AUTO--> | 模板变量替换 |
| <!--AUTO:sig:backend/app/services/llm/prompt.py:parse_mes_example-->`parse_mes_example(mes_example, user_name='User', char_name='Character')`<!--/AUTO--> | 对话示例解析（<START> 分隔） |
| <!--AUTO:sig:backend/app/services/llm/prompt.py:build_messages-->`build_messages(character, history, user_content, max_rounds=30, user_name='User')`<!--/AUTO--> | 组装完整消息序列（system + 滑窗历史 + 当前） |

### 4.30 `backend/app/services/llm/resolver.py` — LLM 解析器（<!--AUTO:lines:backend/app/services/llm/resolver.py-->~59 行<!--/AUTO-->）

**职责**：DB 设置 → Provider 实例解析（凭证通用解析：填任一 key 全局可用）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/llm/resolver.py:resolve_llm-->`resolve_llm(db, provider, model=None, *, api_key=None, base_url=None)`<!--/AUTO--> | 解析 Provider 实例（显式覆盖优先） |

### 4.31 `backend/run_backend.py` — 独立启动脚本（<!--AUTO:lines:backend/run_backend.py-->~104 行<!--/AUTO-->）

**职责**：不依赖 uvicorn 命令行的启动入口——日志文件/数据目录/端口解析 + uvicorn 启动（桌面版打包形态复用）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/run_backend.py:data_dir-->`data_dir()`<!--/AUTO--> | 数据目录 |
| <!--AUTO:sig:backend/run_backend.py:log_file_path-->`log_file_path()`<!--/AUTO--> | 日志文件路径 |
| <!--AUTO:sig:backend/run_backend.py:build_parser-->`build_parser()`<!--/AUTO--> | 命令行参数（--port/--host/--log 等） |
| <!--AUTO:sig:backend/run_backend.py:build_log_config-->`build_log_config(log_file)`<!--/AUTO--> | 日志配置 dict |
| <!--AUTO:sig:backend/run_backend.py:main-->`main(argv=None)`<!--/AUTO--> | 入口（uvicorn.run） |

### 4.32 `backend/scripts/migrate_data.py` — 数据迁移工具（<!--AUTO:lines:backend/scripts/migrate_data.py-->~299 行<!--/AUTO-->）

**职责**：旧数据目录 → 新目录迁移——数据库校验/等价性比对/幂等标记（`.migrated`）/尽力而为写入。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/scripts/migrate_data.py:default_source_path-->`default_source_path()`<!--/AUTO--> | 默认源路径 |
| <!--AUTO:sig:backend/scripts/migrate_data.py:default_target_path-->`default_target_path()`<!--/AUTO--> | 默认目标路径 |
| <!--AUTO:sig:backend/scripts/migrate_data.py:verify_database-->`verify_database(path)`<!--/AUTO--> | 数据库完整性校验 |
| <!--AUTO:sig:backend/scripts/migrate_data.py:databases_equivalent-->`databases_equivalent(left, right)`<!--/AUTO--> | 两份库等价性比对 |
| <!--AUTO:sig:backend/scripts/migrate_data.py:check_source-->`check_source(source)`<!--/AUTO--> | 源目录检查 |
| <!--AUTO:sig:backend/scripts/migrate_data.py:migrate-->`migrate(source, target, force=False)`<!--/AUTO--> | 执行迁移（幂等 + 标记） |
| <!--AUTO:sig:backend/scripts/migrate_data.py:main-->`main(argv=None)`<!--/AUTO--> | CLI 入口 |

### 4.33 `frontend/js/api.js` — 统一请求层（<!--AUTO:lines:frontend/js/api.js-->~292 行<!--/AUTO-->）

**职责**：Fetch 封装——超时守卫（AbortController + 15s 兜底，TD-51/55/72）、错误归一化、SSE 流式、Blob 下载（Content-Disposition 文件名解析）。T6 重生成：`conversations.regenerate(id, { message_id? })` 封装 `POST /api/conversations/{id}/regenerate`（缺省末条 assistant），客户端错误处理与 `messages.chat` 同走 `request` 错误通道。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/api.js:buildApiUrl-->`buildApiUrl(path)`<!--/AUTO--> | 构建 API URL（/api 前缀） |
| <!--AUTO:sig:frontend/js/api.js:request-->`request(method, path, body = null, { timeout } = {})`<!--/AUTO--> | 通用请求（JSON + 错误提取） |
| `conversations.regenerate(id, { message_id? })` | 重生成对话末条 AI 回复（POST；响应同构 ChatResponse，message_id 为新消息 id） |
| <!--AUTO:sig:frontend/js/api.js:createTimeoutController-->`createTimeoutController(timeout)`<!--/AUTO--> | 超时控制器 |
| <!--AUTO:sig:frontend/js/api.js:normalizeTimeoutError-->`normalizeTimeoutError(err, timeoutCtl)`<!--/AUTO--> | 超时错误归一化 |
| <!--AUTO:sig:frontend/js/api.js:extractErrorMessage-->`extractErrorMessage(res)`<!--/AUTO--> | 响应错误消息提取 |
| <!--AUTO:sig:frontend/js/api.js:parseContentDispositionFilename-->`parseContentDispositionFilename(headers)`<!--/AUTO--> | 下载文件名解析 |
| <!--AUTO:sig:frontend/js/api.js:requestBlob-->`requestBlob(path, { timeout } = {})`<!--/AUTO--> | Blob 下载请求 |
| <!--AUTO:sig:frontend/js/api.js:chatStream-->`chatStream(data, { onToken, onDone, onError })`<!--/AUTO--> | SSE 流式对话（解析 + 回调） |

### 4.34 `frontend/js/app.js` — 应用编排（<!--AUTO:lines:frontend/js/app.js-->~396 行<!--/AUTO-->）

**职责**：初始化接线（init）——视图切换、设置面板/搜索/模拟器装配、列表视图接线（list-views 注入）、T1 凭证协议检测（init 数据加载序列后调 `settings.credentials()`，结果缓存到 `state.credentialsProtocol` 供引导卡判定）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/app.js:init-->`init()`<!--/AUTO--> | 应用初始化（模块接线） |
| <!--AUTO:sig:frontend/js/app.js:switchView-->`switchView(viewName)`<!--/AUTO--> | 视图切换 |
| <!--AUTO:sig:frontend/js/app.js:loadModels-->`loadModels()`<!--/AUTO--> | 加载模型清单 |

### 4.35 `frontend/js/cascade.js` — 级联收口（<!--AUTO:lines:frontend/js/cascade.js-->~88 行<!--/AUTO-->）

**职责**：清空会话的级联收口（ARC9 T-01）——关闭相关 tab + 重结算 + 列表刷新，`setCascadeHooks` 注入缝接线。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/cascade.js:setCascadeHooks-->`setCascadeHooks(h)`<!--/AUTO--> | 注入级联钩子（tab 关闭/列表刷新） |
| <!--AUTO:sig:frontend/js/cascade.js:closeConversationsAndResettle-->`closeConversationsAndResettle({ ids = 'all', reloadList = false } = {})`<!--/AUTO--> | 关闭会话并重结算 |

### 4.36 `frontend/js/chat.js` — 对话视图（<!--AUTO:lines:frontend/js/chat.js-->~734 行<!--/AUTO-->）

**职责**：消息渲染（气泡/思考指示/复制按钮/空态与 T1 首启引导卡）、发送流程（handleSend → StreamSession，失败经 error-bar 深模块渲染错误条）、标题同步、重命名、T3 对话内模型切换（openModelSwitch）、T6 末条 AI 回复重生成（regenerateLastReply → conversations.regenerate → settleTurn 重载，在途守卫与 handleSend 非流式共用）。T2 搜索定位：`renderMessages({ messageId })` 在消息加载/渲染后把目标气泡 `scrollIntoView({block:'center'})` 定位到视口中央 + 应用 `.search-highlight` 高亮约 3s 自动清除（`locateAndHighlight`），并与既有 `scrollToBottom` 互斥（定位不被滚动到底覆盖）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/chat.js:renderMessages-->`renderMessages({ messageId } = {})`<!--/AUTO--> | 渲染消息列表（可选 `{ messageId }`：定位 + 高亮，见 T2） |
| <!--AUTO:sig:frontend/js/chat.js:locateAndHighlight-->`locateAndHighlight(messageId)`<!--/AUTO--> | T2 定位目标消息 + search-highlight 高亮 + 3s 清除 |
| <!--AUTO:sig:frontend/js/chat.js:appendMessage-->`appendMessage(role, content, meta = {})`<!--/AUTO--> | 追加消息气泡 |
| <!--AUTO:sig:frontend/js/chat.js:showThinkingIndicator-->`showThinkingIndicator(convId)`<!--/AUTO--> | 思考指示 |
| <!--AUTO:sig:frontend/js/chat.js:handleSend-->`handleSend()`<!--/AUTO--> | 发送入口（流式/非流式） |
| <!--AUTO:sig:frontend/js/chat.js:regenerateLastReply-->`regenerateLastReply()`<!--/AUTO--> | T6 末条 assistant 重生成（MVP 非流式 → settleTurn 重载；失败走错误条） |
| <!--AUTO:sig:frontend/js/chat.js:isActiveStream-->`isActiveStream()`<!--/AUTO--> | 是否有活跃流 |
| <!--AUTO:sig:frontend/js/chat.js:renderChatHeader-->`renderChatHeader(conversationId)`<!--/AUTO--> | 会话头部渲染（含 T3 模型徽标按钮） |
| <!--AUTO:sig:frontend/js/chat.js:syncChatHeaderTitle-->`syncChatHeaderTitle()`<!--/AUTO--> | 标题同步（tab 视图联动） |
| <!--AUTO:sig:frontend/js/chat.js:startRename-->`startRename(conv)`<!--/AUTO--> | 重命名会话 |
| <!--AUTO:sig:frontend/js/chat.js:openModelSwitch-->`openModelSwitch(conv)`<!--/AUTO--> | T3 对话内模型切换（徽标按钮 → 选择器 → 保存 → 同步） |
| <!--AUTO:sig:frontend/js/chat.js:save-->`save()`<!--/AUTO--> | 保存当前状态（TD-13 守卫入口） |
| <!--AUTO:sig:frontend/js/chat.js:setChatHooks-->`setChatHooks(h)`<!--/AUTO--> | 注入会话列表刷新器与标题同步器（options-object 方言） |
| <!--AUTO:sig:frontend/js/chat.js:scrollToBottom-->`scrollToBottom()`<!--/AUTO--> | 滚动到底部 |
| <!--AUTO:sig:frontend/js/chat.js:attachCopyButton-->`attachCopyButton(btn)`<!--/AUTO--> | 复制按钮接线 |

### 4.36.5 `frontend/js/list-views.js` — 角色/对话列表视图（<!--AUTO:lines:frontend/js/list-views.js-->~370 行<!--/AUTO-->）

**职责**：角色/对话两个列表视图深模块（C4，search-view 先例）——角色网格渲染与四类按钮事件委托、对话列表渲染与打开/删除委托、角色导入（含失败引导向导）、开始对话全流程（模型选择→创建→切视图→激活→聚焦）、列表标题同步 DOM 手术；协调层经 `initListViews({ switchView })` 接线。T3 模型切换的对话列表同步经 chat.js 注入的 `refreshConversations` 钩子（重渲染列表，meta 显示新模型），本模块零改动（`showModelSelector(charName)` 调用点保持向后兼容）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/list-views.js:initListViews-->`initListViews({ switchView: sw } = {})`<!--/AUTO--> | 初始化列表视图（注入 switchView） |
| <!--AUTO:sig:frontend/js/list-views.js:loadCharacters-->`loadCharacters()`<!--/AUTO--> | 加载角色列表 |
| <!--AUTO:sig:frontend/js/list-views.js:renderCharacters-->`renderCharacters()`<!--/AUTO--> | 渲染角色列表 |
| <!--AUTO:sig:frontend/js/list-views.js:loadConversations-->`loadConversations()`<!--/AUTO--> | 加载会话列表 |
| <!--AUTO:sig:frontend/js/list-views.js:renderConversations-->`renderConversations()`<!--/AUTO--> | 渲染会话列表 |
| <!--AUTO:sig:frontend/js/list-views.js:syncConversationListTitle-->`syncConversationListTitle(convId, newTitle)`<!--/AUTO--> | 重命名后列表标题同步（DOM 手术） |
| <!--AUTO:sig:frontend/js/list-views.js:startChatWithCharacter-->`startChatWithCharacter(characterId)`<!--/AUTO--> | 发起角色对话 |
| <!--AUTO:sig:frontend/js/list-views.js:handleCharacterImport-->`handleCharacterImport()`<!--/AUTO--> | 角色卡导入处理 |
| <!--AUTO:sig:frontend/js/list-views.js:promptUseWizardAfterImportFail-->`promptUseWizardAfterImportFail()`<!--/AUTO--> | 导入失败 → 引导使用向导 |

### 4.36.6 `frontend/js/error-bar.js` — 错误条深模块（<!--AUTO:lines:frontend/js/error-bar.js-->~126 行<!--/AUTO-->）

**职责**：聊天错误条深模块（T1 — 首启引导与无 Key 主路径闭环）——发送失败（非流式/流式）统一经此承载：独立可关闭、约 `ERROR_BAR_DISMISS_MS` 自动消失、含「前往设置」按钮；none 态文案引导配 Key，其余态显示原始错误；错误不再写入消息列表或 tab 缓存。渲染位置挂到调用方容器（chat.js 传 `#chat-messages` 父级，不随 innerHTML 重建消失）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/error-bar.js:renderErrorBar-->`renderErrorBar({ container, message, protocol, onNavigateSettings, conversationId } = {})`<!--/AUTO--> | 渲染错误条（文案分流 / 关闭 / 自动消失） |
| `ERROR_BAR_DISMISS_MS` | 错误条自动消失时长（毫秒；约 8s） |

### 4.37 `frontend/js/components/character-form.js` — 角色编辑表单（<!--AUTO:lines:frontend/js/components/character-form.js-->~204 行<!--/AUTO-->）

**职责**：创建/编辑模式的角色表单（含完整性提示）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/character-form.js:showCharacterForm-->`showCharacterForm(mode = 'create', characterData = null, onSuccess = null)`<!--/AUTO--> | 打开表单（创建/编辑） |

### 4.38 `frontend/js/components/character-submit.js` — 提交状态机（<!--AUTO:lines:frontend/js/components/character-submit.js-->~149 行<!--/AUTO-->）

**职责**：角色提交收敛（ARC10 T-12）——payload 构建、提交按钮三态（进行中/成功/失败）统一入口。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/character-submit.js:splitTags-->`splitTags(text)`<!--/AUTO--> | 标签拆分 |
| <!--AUTO:sig:frontend/js/components/character-submit.js:tagsToComma-->`tagsToComma(tags)`<!--/AUTO--> | 标签转逗号串 |
| <!--AUTO:sig:frontend/js/components/character-submit.js:formatTemperature-->`formatTemperature(value)`<!--/AUTO--> | 温度值格式化 |
| <!--AUTO:sig:frontend/js/components/character-submit.js:avatarPreviewHtml-->`avatarPreviewHtml(src)`<!--/AUTO--> | 头像预览 HTML |
| <!--AUTO:sig:frontend/js/components/character-submit.js:buildCharacterPayload-->`buildCharacterPayload(fields = {})`<!--/AUTO--> | 构建提交 payload |
| <!--AUTO:sig:frontend/js/components/character-submit.js:beginSubmit-->`beginSubmit(btn, statusEl)`<!--/AUTO--> | 提交开始（禁用 + 状态） |
| <!--AUTO:sig:frontend/js/components/character-submit.js:succeedSubmit-->`succeedSubmit(statusEl, successMsgHtml, close, onSuccess = null)`<!--/AUTO--> | 提交成功态 |
| <!--AUTO:sig:frontend/js/components/character-submit.js:failSubmit-->`failSubmit(btn, statusEl, err, restoreLabel)`<!--/AUTO--> | 提交失败态（恢复按钮） |

### 4.39 `frontend/js/components/character-wizard.js` — 六步创建向导（<!--AUTO:lines:frontend/js/components/character-wizard.js-->~584 行<!--/AUTO-->）

**职责**：六步创建向导（模板选择/文档导入/自定义…）——步骤渲染 + 事件绑定 + 校验 + 保存；6 步渲染函数分离。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/character-wizard.js:showCharacterWizard-->`showCharacterWizard(onSuccess = null)`<!--/AUTO--> | 打开向导 |
| <!--AUTO:sig:frontend/js/components/character-wizard.js:render-->`render()`<!--/AUTO--> | 向导整体渲染 |
| <!--AUTO:sig:frontend/js/components/character-wizard.js:renderStep-->`renderStep(step, state)`<!--/AUTO--> | 步骤分发渲染 |
| <!--AUTO:sig:frontend/js/components/character-wizard.js:renderStep1-->`renderStep1(state)`<!--/AUTO--> | 第 1 步（方式选择） |
| <!--AUTO:sig:frontend/js/components/character-wizard.js:renderStep3-->`renderStep3(state)`<!--/AUTO--> | 第 3 步（人设编辑） |
| <!--AUTO:sig:frontend/js/components/character-wizard.js:bindStepEvents-->`bindStepEvents(step, state, body, nextBtn, prevBtn, statusEl, close, render)`<!--/AUTO--> | 步骤事件绑定 |
| <!--AUTO:sig:frontend/js/components/character-wizard.js:validateStep-->`validateStep(step, state, statusEl)`<!--/AUTO--> | 步骤校验 |
| <!--AUTO:sig:frontend/js/components/character-wizard.js:handleSave-->`handleSave(state, statusEl, submitBtn, close, onSuccess)`<!--/AUTO--> | 保存提交 |
| <!--AUTO:sig:frontend/js/components/character-wizard.js:getTemplateIcon-->`getTemplateIcon(templateId)`<!--/AUTO--> | 模板图标 |
| <!--AUTO:sig:frontend/js/components/character-wizard.js:updateProgress-->`updateProgress()`<!--/AUTO--> | 进度更新 |
| <!--AUTO:sig:frontend/js/components/character-wizard.js:_applyCharacterData-->`_applyCharacterData(state, data)`<!--/AUTO--> | 文档解析结果回填 |

### 4.40 `frontend/js/components/confirm-dialog.js` — 确认对话框（<!--AUTO:lines:frontend/js/components/confirm-dialog.js-->~82 行<!--/AUTO-->）

**职责**：确认/提示对话框（Promise 化）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/confirm-dialog.js:showConfirm-->`showConfirm(options = {})`<!--/AUTO--> | 确认对话框（resolve 布尔） |
| <!--AUTO:sig:frontend/js/components/confirm-dialog.js:showAlert-->`showAlert(message)`<!--/AUTO--> | 提示对话框 |

### 4.41 `frontend/js/components/export-dialog.js` — 导出对话框（<!--AUTO:lines:frontend/js/components/export-dialog.js-->~68 行<!--/AUTO-->）

**职责**：会话导出格式选择 + 下载。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/export-dialog.js:showExportDialog-->`showExportDialog(conversationId)`<!--/AUTO--> | 打开导出对话框 |
| <!--AUTO:sig:frontend/js/components/export-dialog.js:downloadExport-->`downloadExport(conversationId, format)`<!--/AUTO--> | 按格式下载导出 |

### 4.42 `frontend/js/components/modal.js` — 模态骨架（<!--AUTO:lines:frontend/js/components/modal.js-->~154 行<!--/AUTO-->）

**职责**：模态骨架（ARC10 T-11 收口）——打开/关闭/结果传递；`close` 为对象方法（骨架内部）。T4 快赢：打开时记录 `document.activeElement`，三条关闭路径（关闭按钮/遮罩/Escape）关闭后焦点还原到打开前元素；框内 Tab/Shift+Tab 焦点循环不跳出框（可聚焦元素 button/input/select/textarea/a[href]/tabindex，hidden/disabled 过滤）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/modal.js:openModal-->`openModal(options = {})`<!--/AUTO--> | 打开模态（返回结果 Promise；含焦点陷阱 + 关闭焦点还原） |

### 4.43 `frontend/js/components/model-selector.js` — 模型选择（<!--AUTO:lines:frontend/js/components/model-selector.js-->~111 行<!--/AUTO-->）

**职责**：创建对话选 Provider/模型；T3 扩展为对话内模型切换复用 —— `showModelSelector(characterName, options)` 支持预选当前 provider/model 与可定制标题（签名向后兼容，既有「创建对话」调用点零行为变化）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/model-selector.js:showModelSelector-->`showModelSelector(characterName, options = {})`<!--/AUTO--> | 打开模型选择（options：`{ preselected, title }`；缺省创建对话语义） |

### 4.44 `frontend/js/components/settings-panel.js` — 设置面板（<!--AUTO:lines:frontend/js/components/settings-panel.js-->~424 行<!--/AUTO-->）

**职责**：设置面板——Provider 下拉初始化、模型联动、凭证测试（testApiKeys）、主题切换、侧栏开关、清空会话接线。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/settings-panel.js:initSettingsPanel-->`initSettingsPanel({ onConversationsCleared } = {})`<!--/AUTO--> | 面板初始化接线 |
| <!--AUTO:sig:frontend/js/components/settings-panel.js:initProviderDropdown-->`initProviderDropdown()`<!--/AUTO--> | Provider 下拉初始化 |
| <!--AUTO:sig:frontend/js/components/settings-panel.js:refreshModelOptions-->`refreshModelOptions()`<!--/AUTO--> | 模型选项刷新 |
| <!--AUTO:sig:frontend/js/components/settings-panel.js:getSelectedModel-->`getSelectedModel()`<!--/AUTO--> | 当前选中模型 |
| <!--AUTO:sig:frontend/js/components/settings-panel.js:loadSettings-->`loadSettings()`<!--/AUTO--> | 加载设置 |
| <!--AUTO:sig:frontend/js/components/settings-panel.js:resolveCredentialTarget-->`resolveCredentialTarget(formFields)`<!--/AUTO--> | 凭证目标解析 |
| <!--AUTO:sig:frontend/js/components/settings-panel.js:testApiKeys-->`testApiKeys(data)`<!--/AUTO--> | 连接测试（TD-17 收口） |
| <!--AUTO:sig:frontend/js/components/settings-panel.js:applyTheme-->`applyTheme(mode)`<!--/AUTO--> | 应用主题 |
| <!--AUTO:sig:frontend/js/components/settings-panel.js:toggleTheme-->`toggleTheme()`<!--/AUTO--> | 切换主题 |
| <!--AUTO:sig:frontend/js/components/settings-panel.js:toggleSidebar-->`toggleSidebar()`<!--/AUTO--> | 侧栏开关 |
| <!--AUTO:sig:frontend/js/components/settings-panel.js:toggleChatSidebar-->`toggleChatSidebar()`<!--/AUTO--> | 会话侧栏开关 |

### 4.44.1 `frontend/js/components/loading-button.js` — 按钮 loading 态工具（<!--AUTO:lines:frontend/js/components/loading-button.js-->~59 行<!--/AUTO-->）

**职责**：异步操作按钮的统一「执行中」反馈 —— 禁用 + 内联 spinner + 文字切换，
按 HTML 快照还原（含 SVG icon）。用于 `settings-panel`（保存/清空）、
`list-views`（编辑/导出/删除角色、删除对话）等异步按钮的防双击与进度反馈。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/loading-button.js:beginButtonLoading-->`beginButtonLoading(btn, loadingText = '')`<!--/AUTO--> | 置 loading 态，返回 restore |
| <!--AUTO:sig:frontend/js/components/loading-button.js:clearButtonLoading-->`clearButtonLoading(btn)`<!--/AUTO--> | 未持 restore 引用时的还原 |


### 4.44.2 `frontend/js/components/game-generator.js` — AI 游戏生成器（<!--AUTO:lines:frontend/js/components/game-generator.js-->~385 行<!--/AUTO-->）

**职责**：从用户提供的世界观文本（textarea 粘贴或 .txt/.md 文件上传）生成 HTML 模拟器游戏。模态框输入 → POST /api/simulators/generate → 成功自动刷新列表 / 失败显示错误与重试按钮。T4 凭证预检：`openGenerateFlow` 打开时后台读取凭证端点，none/claude 态模态框顶部提示「需先配置 OpenAI 兼容 Key」+ 设置链接（沿用 key-injector 的 `LINK_NAV_SETTINGS` 文案常量，类名用生成器自有 `SEL_GG_WARNING_NAV`——F-63 已与模拟器专属 `SEL_NAV_SETTINGS` 解耦，点击经 `onNavigateSettings` 钩子 → `switchView('settings')`）；openai 态无提示；请求失败静默降级（不阻塞打开）。F-55：预检续体带提交态守卫（已提交生成则丢弃迟到响应）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/game-generator.js:initGameGenerator-->`initGameGenerator({ onGenerated: hook, getCredentials, onNavigateSettings } = {})`<!--/AUTO--> | 注册钩子（onGenerated / getCredentials 凭证预检 / onNavigateSettings 设置导航，幂等） |
| <!--AUTO:sig:frontend/js/components/game-generator.js:openGenerateFlow-->`openGenerateFlow()`<!--/AUTO--> | 打开生成模态框（工具栏/菜单入口；含凭证预检） |
| <!--AUTO:sig:frontend/js/components/game-generator.js:resetGameGenerator-->`resetGameGenerator()`<!--/AUTO--> | 切走视图复位 |


### 4.45 `frontend/js/components/tab-bar.js` — 会话 tab 栏（<!--AUTO:lines:frontend/js/components/tab-bar.js-->~86 行<!--/AUTO-->）

**职责**：会话 tab 栏组件（容器 + 激活回调，渲染/点击分发）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/components/tab-bar.js:initTabBar-->`initTabBar({ container, onActivate } = {})`<!--/AUTO--> | 初始化 tab 栏 |

### 4.46 `frontend/js/conversation-activation.js` — 会话激活（<!--AUTO:lines:frontend/js/conversation-activation.js-->~154 行<!--/AUTO-->）

**职责**：会话激活流程——tab 视图状态保存/恢复、空态、消息加载（P6.5 多 tab 联动）。T2 搜索定位：`activateConversation` / `loadTabMessages` 支持可选 `messageId`，透传 `renderMessages` 触发定位 + 高亮（缓存命中时定位覆盖滚动恢复，不被覆盖）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/conversation-activation.js:activateConversation-->`activateConversation(conversationId, { saveCurrent = true, messageId } = {})`<!--/AUTO--> | 激活会话（先存当前；可选 messageId 触发定位） |
| <!--AUTO:sig:frontend/js/conversation-activation.js:loadTabMessages-->`loadTabMessages(conversationId, { messageId } = {})`<!--/AUTO--> | 加载 tab 消息（可选 messageId 透传渲染） |
| <!--AUTO:sig:frontend/js/conversation-activation.js:saveTabViewState-->`saveTabViewState()`<!--/AUTO--> | 保存当前 tab 视图状态 |
| <!--AUTO:sig:frontend/js/conversation-activation.js:restoreTabViewState-->`restoreTabViewState(tab)`<!--/AUTO--> | 恢复 tab 视图状态 |
| <!--AUTO:sig:frontend/js/conversation-activation.js:showEmptyState-->`showEmptyState()`<!--/AUTO--> | 空态显示 |
| <!--AUTO:sig:frontend/js/conversation-activation.js:setActivationHooks-->`setActivationHooks(h)`<!--/AUTO--> | 注入激活钩子 |

### 4.47 `frontend/js/data/character-templates.js` — 角色模板数据（<!--AUTO:lines:frontend/js/data/character-templates.js-->~94 行<!--/AUTO-->）

**职责**：六步向导的 5 套内置角色模板（纯数据模块）。

> 无公开函数（模板数据常量）。

### 4.48 `frontend/js/fetch-seam.js` — fetch 注入缝（<!--AUTO:lines:frontend/js/fetch-seam.js-->~43 行<!--/AUTO-->）

**职责**：fetch 单源注入缝（TD-51 收口）——测试替身注入 + 全局超时守卫统一入口。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/fetch-seam.js:setFetch-->`setFetch(fn)`<!--/AUTO--> | 注入 fetch 实现（测试用） |
| <!--AUTO:sig:frontend/js/fetch-seam.js:doFetch-->`doFetch(...args)`<!--/AUTO--> | 统一 fetch 出口（超时守卫） |

### 4.49 `frontend/js/format.js` — 展示契约（<!--AUTO:lines:frontend/js/format.js-->~223 行<!--/AUTO-->）

**职责**：展示 HTML 生成单源（ARC 展示契约）——消息气泡/角色卡片/会话项/搜索结果/头像/关键词高亮。T2 搜索定位：`messageBubbleHtml` 接受可选 `messageId` 选项 → 渲染 `data-message-id` 属性（供定位选择器消费）；`buildMessagesHtml` 透传 `m.id`。T6 重生成：`buildMessagesHtml` 的 `context.canRegenerate`（聊天域开关）为真且末条为已结算 assistant 时，该气泡经 `messageBubbleHtml` 渲染「重生成」操作按钮。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/format.js:messageBubbleHtml-->`messageBubbleHtml(role, content, opts = {})`<!--/AUTO--> | 消息气泡 HTML（可选 `{ messageId }` → data-message-id；`{ regenerate }` → 重生成按钮） |
| <!--AUTO:sig:frontend/js/format.js:buildMessagesHtml-->`buildMessagesHtml(messages, context = {})`<!--/AUTO--> | 消息列表 HTML（透传消息 id → data-message-id；`context.canRegenerate` → 末条 assistant 重生成按钮） |
| <!--AUTO:sig:frontend/js/format.js:characterCardHtml-->`characterCardHtml(c)`<!--/AUTO--> | 角色卡片 HTML |
| <!--AUTO:sig:frontend/js/format.js:conversationItemHtml-->`conversationItemHtml(c, { activeId = null } = {})`<!--/AUTO--> | 会话项 HTML |
| <!--AUTO:sig:frontend/js/format.js:searchResultItemHtml-->`searchResultItemHtml(r, query)`<!--/AUTO--> | 搜索结果项 HTML（高亮） |
| <!--AUTO:sig:frontend/js/format.js:highlightText-->`highlightText(text, keyword)`<!--/AUTO--> | 关键词高亮 |
| <!--AUTO:sig:frontend/js/format.js:avatarImgHtml-->`avatarImgHtml(src, alt, fallbackHtml)`<!--/AUTO--> | 头像 HTML（占位回退） |
| <!--AUTO:sig:frontend/js/format.js:assistantAvatarHtml-->`assistantAvatarHtml(characters, currentCharacterId)`<!--/AUTO--> | 助手头像 |
| <!--AUTO:sig:frontend/js/format.js:userAvatarHtml-->`userAvatarHtml()`<!--/AUTO--> | 用户头像 |

### 4.50 `frontend/js/icons.js` — 图标 seam（<!--AUTO:lines:frontend/js/icons.js-->~60 行<!--/AUTO-->）

**职责**：动态模板/状态图标单源（OPT-1 图标协议收口）——`iconHtml` seam，禁止手写 emoji/SVG 碎片。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/icons.js:iconHtml-->`iconHtml(name, options = {})`<!--/AUTO--> | 图标 HTML 生成（名称 + 选项） |

### 4.51 `frontend/js/key-injector.js` — 模拟器 Key 注入（<!--AUTO:lines:frontend/js/key-injector.js-->~613 行<!--/AUTO-->）

**职责**：SIM-API-1 核心——把主应用凭证/模型注入第三方模拟器 iframe（endpointMode 端点口径转换、受管 model option、幂等写入、同步编排、防抖 + **写回环状态机收口（C1）**——冷却/熔断状态单一持有者，`autoSyncIntoGame` 原子完成状态迁移）。T4：导出禁用文案/引导链接常量 `MSG_CLAUDE_ONLY` / `MSG_NO_CREDENTIALS` / `LINK_NAV_SETTINGS` / `SEL_NAV_SETTINGS`，`LINK_NAV_SETTINGS` 文案由游戏生成器凭证预检复用（`SEL_NAV_SETTINGS` 自 F-63 起为模拟器专属，生成器不再借用）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/key-injector.js:initKeyInjector-->`initKeyInjector({ getCredentials, onNavigateSettings } = {})`<!--/AUTO--> | 注入器初始化 |
| <!--AUTO:sig:frontend/js/key-injector.js:resolveButtonState-->`resolveButtonState(credentials)`<!--/AUTO--> | 按钮状态解析 |
| <!--AUTO:sig:frontend/js/key-injector.js:convertEndpoint-->`convertEndpoint(endpoint, mode)`<!--/AUTO--> | 端点口径转换（full/base） |
| <!--AUTO:sig:frontend/js/key-injector.js:ensureSelectOption-->`ensureSelectOption(selectEl, value)`<!--/AUTO--> | 模型下拉选项保障 |
| <!--AUTO:sig:frontend/js/key-injector.js:injectCredentialsIntoGame-->`injectCredentialsIntoGame({ doc, config, credentials, endpointMode } = {})`<!--/AUTO--> | 向游戏文档注入凭证 |
| <!--AUTO:sig:frontend/js/key-injector.js:syncGameCredentials-->`syncGameCredentials({ doc, config, endpointMode } = {})`<!--/AUTO--> | 同步游戏凭证 |
| <!--AUTO:sig:frontend/js/key-injector.js:runSync-->`runSync({ bar, getDoc, getConfig, getEndpointMode, feedback })`<!--/AUTO--> | 执行同步（状态栏驱动） |
| <!--AUTO:sig:frontend/js/key-injector.js:autoSyncIntoGame-->`autoSyncIntoGame(params = {})`<!--/AUTO--> | 自动同步状态机（path load/observer + cooled/breaker） |
| <!--AUTO:sig:frontend/js/key-injector.js:resetSyncLoop-->`resetSyncLoop()`<!--/AUTO--> | 复位写回环状态（冷却+熔断） |
| <!--AUTO:sig:frontend/js/key-injector.js:attachKeyInject-->`attachKeyInject(params = {})`<!--/AUTO--> | 注入按钮接线 |
| <!--AUTO:sig:frontend/js/key-injector.js:handleKeyClick-->`handleKeyClick(e)`<!--/AUTO--> | 注入按钮点击 |

### 4.52 `frontend/js/markdown.js` — Markdown 渲染（<!--AUTO:lines:frontend/js/markdown.js-->~203 行<!--/AUTO-->）

**职责**：消息 Markdown 渲染（代码块保护 + URL 消毒 XSS 防护）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/markdown.js:renderMarkdown-->`renderMarkdown(text)`<!--/AUTO--> | Markdown → 安全 HTML |
| <!--AUTO:sig:frontend/js/markdown.js:sanitizeUrl-->`sanitizeUrl(url)`<!--/AUTO--> | URL 协议消毒 |
| <!--AUTO:sig:frontend/js/markdown.js:createCodeBlockToken-->`createCodeBlockToken(html, tokenId)`<!--/AUTO--> | 代码块占位保护 |
| <!--AUTO:sig:frontend/js/markdown.js:escapeRegExp-->`escapeRegExp(str)`<!--/AUTO--> | 正则转义 |

### 4.53 `frontend/js/save-key-meta.js` — 存档键契约（<!--AUTO:lines:frontend/js/save-key-meta.js-->~119 行<!--/AUTO-->）

**职责**：模拟器存档键契约单一来源（TD-67/68）——`WG_SESSION_ONLY_IDS` 等常量 + 键名转义工具，五处消费点共用。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/save-key-meta.js:escapeRegExp-->`escapeRegExp(str)`<!--/AUTO--> | 键名正则转义 |
| <!--AUTO:sig:frontend/js/save-key-meta.js:saveKeyIsPattern-->`saveKeyIsPattern(entry)`<!--/AUTO--> | 判定 saveKeys 条目是否正则模式 |
| <!--AUTO:sig:frontend/js/save-key-meta.js:saveKeyIsValidPattern-->`saveKeyIsValidPattern(entry)`<!--/AUTO--> | 验证 saveKeys 条目为可编译模式 |
| <!--AUTO:sig:frontend/js/save-key-meta.js:saveKeyMatches-->`saveKeyMatches(entry, keyName)`<!--/AUTO--> | saveKeys 白名单条目匹配键名 |

### 4.54 `frontend/js/save-manager.js` — 存档管理器（<!--AUTO:lines:frontend/js/save-manager.js-->~608 行<!--/AUTO-->）

**职责**：模拟器存档面板（U9-T2）——localStorage 键收集、导出/导入（白名单过滤 + 校验）/删除；`buildExportPayload` 为跨行复杂签名（名称列引用）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/save-manager.js:initSaveManager-->`initSaveManager({ savePanel: sp, listPanel: lp, runPanel: rp, getGames: hook } = {})`<!--/AUTO--> | 存档管理器初始化 |
| <!--AUTO:sig:frontend/js/save-manager.js:collectGameKeys-->`collectGameKeys(game, storage)`<!--/AUTO--> | 收集游戏存档键 |
| <!--AUTO:sig:frontend/js/save-manager.js:whitelistHits-->`whitelistHits(saveKeys, keyName)`<!--/AUTO--> | 白名单命中判定 |
| <!--AUTO:sig:frontend/js/save-manager.js:validateImportPayload-->`validateImportPayload(payload, game)`<!--/AUTO--> | 导入 payload 校验 |
| <!--AUTO:sig:frontend/js/save-manager.js:applyImportPayload-->`applyImportPayload(game, keys, storage)`<!--/AUTO--> | 应用导入数据 |
| <!--AUTO:sig:frontend/js/save-manager.js:deleteGameKeys-->`deleteGameKeys(game, storage)`<!--/AUTO--> | 删除游戏存档 |
| <!--AUTO:sig:frontend/js/save-manager.js:exportGame-->`exportGame(gameId)`<!--/AUTO--> | 导出游戏存档 |
| <!--AUTO:sig:frontend/js/save-manager.js:deleteGame-->`deleteGame(gameId)`<!--/AUTO--> | 删除游戏存档 |
| <!--AUTO:sig:frontend/js/save-manager.js:handleImportChange-->`handleImportChange(e)`<!--/AUTO--> | 导入文件变更 |
| <!--AUTO:sig:frontend/js/save-manager.js:getGamesList-->`getGamesList()`<!--/AUTO--> | 游戏列表 |
| <!--AUTO:sig:frontend/js/save-manager.js:getGameById-->`getGameById(gameId)`<!--/AUTO--> | 按 id 取游戏 |
| <!--AUTO:sig:frontend/js/save-manager.js:openSavePanel-->`openSavePanel()`<!--/AUTO--> | 打开存档面板 |
| <!--AUTO:sig:frontend/js/save-manager.js:closeSavePanel-->`closeSavePanel()`<!--/AUTO--> | 关闭存档面板 |
| <!--AUTO:sig:frontend/js/save-manager.js:buildExportPayload-->`buildExportPayload`<!--/AUTO--> | 构建导出 payload（跨行签名） |
| <!--AUTO:sig:frontend/js/save-manager.js:renderSavePanel-->`renderSavePanel()`<!--/AUTO--> | 渲染存档面板 |
| <!--AUTO:sig:frontend/js/save-manager.js:renderGameRow-->`renderGameRow(game)`<!--/AUTO--> | 渲染游戏行 |

### 4.55 `frontend/js/search-view.js` — 搜索视图（<!--AUTO:lines:frontend/js/search-view.js-->~146 行<!--/AUTO-->）

**职责**：跨对话搜索视图（输入防抖 + 结果渲染 + 跳转导航）。T2 搜索定位：结果点击读取 `dataset.messageId`，把 `{ messageId }` 一并传给跳转钩子（签名 `(conversationId, { messageId })`），激活流程据此定位命中消息并高亮。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/search-view.js:initSearchView-->`initSearchView({ navigateToConversation: nav } = {})`<!--/AUTO--> | 搜索视图初始化（跳转钩子签名含 messageId） |
| <!--AUTO:sig:frontend/js/search-view.js:performSearch-->`performSearch(query)`<!--/AUTO--> | 执行搜索 |
| <!--AUTO:sig:frontend/js/search-view.js:renderSearchResults-->`renderSearchResults(results, query)`<!--/AUTO--> | 渲染搜索结果 |

### 4.56 `frontend/js/simulator-view.js` — 模拟器运行视图（<!--AUTO:lines:frontend/js/simulator-view.js-->~505 行<!--/AUTO-->）

**职责**：模拟器 iframe 运行视图（U7/U8）——加载/超时/错误态、配置控件 MutationObserver 重建再同步（TD-75 attributeFilter 收窄）、load 自动同步、PC 阅读共享覆盖层 + per-game CSS 覆盖注入（T-02 决策 12：共享层先、per-game 后，数据目录 `<game-id>.css` 经 /simulators 挂载同源提供）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/simulator-view.js:initSimulatorRun-->`initSimulatorRun({ listPanel: lp, runPanel: rp } = {})`<!--/AUTO--> | 运行视图初始化 |
| <!--AUTO:sig:frontend/js/simulator-view.js:openSimulator-->`openSimulator(game)`<!--/AUTO--> | 打开模拟器 |
| <!--AUTO:sig:frontend/js/simulator-view.js:closeSimulator-->`closeSimulator()`<!--/AUTO--> | 关闭模拟器 |
| <!--AUTO:sig:frontend/js/simulator-view.js:startOpening-->`startOpening(game)`<!--/AUTO--> | 开始打开流程（加载态） |
| <!--AUTO:sig:frontend/js/simulator-view.js:handleLoad-->`handleLoad(e)`<!--/AUTO--> | iframe load 处理（自动同步） |
| <!--AUTO:sig:frontend/js/simulator-view.js:handleTimeout-->`handleTimeout()`<!--/AUTO--> | 加载超时处理 |
| <!--AUTO:sig:frontend/js/simulator-view.js:autoSyncAfterLoad-->`autoSyncAfterLoad()`<!--/AUTO--> | load 后自动同步 |
| <!--AUTO:sig:frontend/js/simulator-view.js:observeConfigControls-->`observeConfigControls()`<!--/AUTO--> | 配置控件观察 |
| <!--AUTO:sig:frontend/js/simulator-view.js:mutationTouchesConfig-->`mutationTouchesConfig(mutations, config)`<!--/AUTO--> | 变更是否触及配置 |
| <!--AUTO:sig:frontend/js/simulator-view.js:handleConfigMutation-->`handleConfigMutation(mutations)`<!--/AUTO--> | 配置变更处理（再同步） |
| <!--AUTO:sig:frontend/js/simulator-view.js:disconnectObserver-->`disconnectObserver()`<!--/AUTO--> | 断开观察者 |
| <!--AUTO:sig:frontend/js/simulator-view.js:injectPerGameCss-->`injectPerGameCss(doc)`<!--/AUTO--> | per-game CSS 覆盖注入（共享层之后） |
| <!--AUTO:sig:frontend/js/simulator-view.js:renderShell-->`renderShell(game)`<!--/AUTO--> | 渲染运行壳 |
| <!--AUTO:sig:frontend/js/simulator-view.js:renderError-->`renderError(reason)`<!--/AUTO--> | 错误态渲染 |
| <!--AUTO:sig:frontend/js/simulator-view.js:isValidGame-->`isValidGame(game)`<!--/AUTO--> | 游戏合法性校验 |
| <!--AUTO:sig:frontend/js/simulator-view.js:clearTimer-->`clearTimer()`<!--/AUTO--> | 清理超时定时器 |

### 4.57 `frontend/js/simulators.js` — 模拟器列表（<!--AUTO:lines:frontend/js/simulators.js-->~501 行<!--/AUTO-->）

**职责**：模拟器列表视图（U7 + 2026-08-26 重新识别）——manifest 解析（v2）、类型筛选、渲染 + 事件绑定 + 刷新、local 卡片「重新识别」按钮（data-action="reprobe" → `reprobeGame(id)` POST JSON 到 reprobe 端点 → 刷新列表 + 反馈）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/simulators.js:initSimulatorsView-->`initSimulatorsView({ container: el, onOpenGame: hook, onOpenSaveManager: saveHook, onImportGame: importHook, onGenerateGame: generateHook } = {})`<!--/AUTO--> | 列表视图初始化 |
| <!--AUTO:sig:frontend/js/simulators.js:parseManifest-->`parseManifest(rawJson)`<!--/AUTO--> | manifest 解析（v1/v2） |
| <!--AUTO:sig:frontend/js/simulators.js:normalizeSaveKeys-->`normalizeSaveKeys(value)`<!--/AUTO--> | 存档键归一化 |
| <!--AUTO:sig:frontend/js/simulators.js:filterGames-->`filterGames(games, type)`<!--/AUTO--> | 类型筛选 |
| <!--AUTO:sig:frontend/js/simulators.js:refreshSimulators-->`refreshSimulators()`<!--/AUTO--> | 刷新列表 |
| <!--AUTO:sig:frontend/js/simulators.js:fetchManifestText-->`fetchManifestText()`<!--/AUTO--> | 拉取 manifest 文本 |
| <!--AUTO:sig:frontend/js/simulators.js:getGames-->`getGames()`<!--/AUTO--> | 获取游戏列表 |
| <!--AUTO:sig:frontend/js/simulators.js:bindEvents-->`bindEvents()`<!--/AUTO--> | 事件绑定（含重新识别拦截） |
| <!--AUTO:sig:frontend/js/simulators.js:renderShell-->`renderShell()`<!--/AUTO--> | 渲染壳 |
| <!--AUTO:sig:frontend/js/simulators.js:renderList-->`renderList()`<!--/AUTO--> | 渲染列表（local 卡片含重新识别按钮） |
| <!--AUTO:sig:frontend/js/simulators.js:renderLoading-->`renderLoading()`<!--/AUTO--> | 加载态渲染 |
| <!--AUTO:sig:frontend/js/simulators.js:renderError-->`renderError(reason)`<!--/AUTO--> | 错误态渲染 |
| <!--AUTO:sig:frontend/js/simulators.js:reprobeGame-->`reprobeGame(id)`<!--/AUTO--> | 重新识别（POST → 刷新 → 反馈） |

### 4.58 `frontend/js/state.js` — 全局状态（<!--AUTO:lines:frontend/js/state.js-->~36 行<!--/AUTO-->）

**职责**：全局 DOM 引用缓存（P6.5 后字段退役，仅存 DOM 句柄）。T1：`state.credentialsProtocol`（凭证协议缓存，app.js init 检测后写入，供首启引导卡判定）。

> 无公开函数（DOM 引用常量）。

### 4.59 `frontend/js/stream-session.js` — 流式会话（<!--AUTO:lines:frontend/js/stream-session.js-->~352 行<!--/AUTO-->）

**职责**：流式会话深模块（ARC 级联收口）——创建会话/SSE 接线/统一结算 `settleTurn`（ARC9 T-02：按发起会话写回、防悬挂）+ 中止错误归一化。T1：普通（非 AbortError）流式错误不再写 `[错误]` 进消息缓存，经注入回调 `deps.onError` 上抛给聊天域渲染错误条（保持零 DOM）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/stream-session.js:createStreamSession-->`createStreamSession({ convId, getTab, updateTab, isActiveStream, renderMessages, refreshSendButton, refreshConversations, onError: errorSink })`<!--/AUTO--> | 创建流式会话 |
| <!--AUTO:sig:frontend/js/stream-session.js:settleTurn-->`settleTurn({ convId, getTab, updateTab, isActive, render, revision, settleIndex = -1, anchor = null, messageId = null, content = '' })`<!--/AUTO--> | 统一结算（完成/停止/出错写回） |
| <!--AUTO:sig:frontend/js/stream-session.js:settleByPosition-->`settleByPosition(tab, anchor, message)`<!--/AUTO--> | 按位置结算 |
| <!--AUTO:sig:frontend/js/stream-session.js:mergeFreshList-->`mergeFreshList(tab, revision, msgs, { settleIndex = -1, anchor = null, messageId = null, content = '' } = {})`<!--/AUTO--> | 合并刷新消息列表 |
| <!--AUTO:sig:frontend/js/stream-session.js:isAbortError-->`isAbortError(err)`<!--/AUTO--> | 中止错误判定 |
| <!--AUTO:sig:frontend/js/stream-session.js:isSettled-->`isSettled()`<!--/AUTO--> | 是否已结算 |
| <!--AUTO:sig:frontend/js/stream-session.js:onToken-->`onToken(token)`<!--/AUTO--> | 流式 token 回调 |
| <!--AUTO:sig:frontend/js/stream-session.js:onDone-->`onDone(messageId)`<!--/AUTO--> | 完成回调 |
| <!--AUTO:sig:frontend/js/stream-session.js:onError-->`onError(err)`<!--/AUTO--> | 错误回调 |
| <!--AUTO:sig:frontend/js/stream-session.js:captureAnchor-->`captureAnchor()`<!--/AUTO--> | 捕获锚点 |
| <!--AUTO:sig:frontend/js/stream-session.js:captureSettleIndex-->`captureSettleIndex()`<!--/AUTO--> | 捕获结算索引 |

### 4.60 `frontend/js/tabs.js` — tab 工作区深模块（<!--AUTO:lines:frontend/js/tabs.js-->~340 行<!--/AUTO-->）

**职责**：多 tab 会话工作区状态（P6.5 深模块）——tab 集合/视图状态/流式句柄；结构性变更自动写 sessionStorage（只存 ids + activeId）+ 变更通知；恢复校验。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/tabs.js:createTab-->`createTab(conversationId)`<!--/AUTO--> | 创建 tab |
| <!--AUTO:sig:frontend/js/tabs.js:openTab-->`openTab(conversationId)`<!--/AUTO--> | 打开 tab |
| <!--AUTO:sig:frontend/js/tabs.js:activateTab-->`activateTab(conversationId)`<!--/AUTO--> | 激活 tab |
| <!--AUTO:sig:frontend/js/tabs.js:closeTab-->`closeTab(conversationId)`<!--/AUTO--> | 关闭 tab |
| <!--AUTO:sig:frontend/js/tabs.js:closeTabs-->`closeTabs(ids)`<!--/AUTO--> | 批量关闭 tab |
| <!--AUTO:sig:frontend/js/tabs.js:closeAllTabs-->`closeAllTabs()`<!--/AUTO--> | 关闭全部 tab |
| <!--AUTO:sig:frontend/js/tabs.js:getActiveTab-->`getActiveTab()`<!--/AUTO--> | 当前激活 tab |
| <!--AUTO:sig:frontend/js/tabs.js:getTab-->`getTab(conversationId)`<!--/AUTO--> | 取 tab |
| <!--AUTO:sig:frontend/js/tabs.js:getTabs-->`getTabs()`<!--/AUTO--> | 全部 tab |
| <!--AUTO:sig:frontend/js/tabs.js:getTabDisplay-->`getTabDisplay(tab)`<!--/AUTO--> | tab 展示信息 |
| <!--AUTO:sig:frontend/js/tabs.js:updateTab-->`updateTab(conversationId, patch)`<!--/AUTO--> | 更新 tab（patch） |
| <!--AUTO:sig:frontend/js/tabs.js:abortStream-->`abortStream(conversationId)`<!--/AUTO--> | 中止 tab 流式 |
| <!--AUTO:sig:frontend/js/tabs.js:serialize-->`serialize()`<!--/AUTO--> | 序列化（ids + activeId） |
| <!--AUTO:sig:frontend/js/tabs.js:restore-->`restore(serialized, { isValidId } = {})`<!--/AUTO--> | 反序列化恢复 |
| <!--AUTO:sig:frontend/js/tabs.js:restoreFromStorage-->`restoreFromStorage({ isValidId } = {})`<!--/AUTO--> | 从 sessionStorage 恢复 |
| <!--AUTO:sig:frontend/js/tabs.js:onTabsChanged-->`onTabsChanged(fn)`<!--/AUTO--> | 变更通知订阅 |
| <!--AUTO:sig:frontend/js/tabs.js:persist-->`persist()`<!--/AUTO--> | 写 sessionStorage |
| <!--AUTO:sig:frontend/js/tabs.js:commit-->`commit()`<!--/AUTO--> | 提交（持久化 + 通知） |

### 4.61 `frontend/js/utils.js` — 通用工具（<!--AUTO:lines:frontend/js/utils.js-->~120 行<!--/AUTO-->）

**职责**：通用工具——HTML 转义、Toast（T4 队列上限：`MAX_TOASTS≈3`，新条挤最旧）、Blob 下载、头像首字母、标签格式化、输入框自适应。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/utils.js:escapeHtml-->`escapeHtml(str)`<!--/AUTO--> | HTML 转义 |
| <!--AUTO:sig:frontend/js/utils.js:showToast-->`showToast(message, type = 'success')`<!--/AUTO--> | Toast 提示（队列上限，新条挤最旧） |
| <!--AUTO:sig:frontend/js/utils.js:showError-->`showError(message)`<!--/AUTO--> | 错误提示（showToast 薄封装） |
| <!--AUTO:sig:frontend/js/utils.js:showSuccess-->`showSuccess(message)`<!--/AUTO--> | 成功提示（showToast 薄封装） |
| <!--AUTO:sig:frontend/js/utils.js:downloadBlob-->`downloadBlob(url, filename, errorPrefix = '导出失败')`<!--/AUTO--> | Blob 下载 |
| <!--AUTO:sig:frontend/js/utils.js:getInitials-->`getInitials(name)`<!--/AUTO--> | 首字母 |
| <!--AUTO:sig:frontend/js/utils.js:formatTags-->`formatTags(tags)`<!--/AUTO--> | 标签格式化 |
| <!--AUTO:sig:frontend/js/utils.js:autoResizeInput-->`autoResizeInput(el)`<!--/AUTO--> | 输入框自适应高度 |

### 4.62 `frontend/js/utils/model-utils.js` — 模型下拉工具（<!--AUTO:lines:frontend/js/utils/model-utils.js-->~98 行<!--/AUTO-->）

**职责**：模型下拉填充（Provider 联动 + 自定义模型处理）+ 展示名解析。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/utils/model-utils.js:fillModelSelect-->`fillModelSelect(selectEl, provider, defaultModel, customInputEl, options = {})`<!--/AUTO--> | 填充模型下拉 |
| <!--AUTO:sig:frontend/js/utils/model-utils.js:createCustomModelHandler-->`createCustomModelHandler(selectEl, customInputEl)`<!--/AUTO--> | 自定义模型输入联动 |
| <!--AUTO:sig:frontend/js/utils/model-utils.js:providerDisplayName-->`providerDisplayName(modelData, providerKey)`<!--/AUTO--> | Provider 展示名解析 |

### 4.63 `frontend/js/utils/sse-reader.js` — SSE 解析（<!--AUTO:lines:frontend/js/utils/sse-reader.js-->~57 行<!--/AUTO-->）

**职责**：SSE 流解析（`data:` 行 → token/done/error 回调，TD-52 契约）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/utils/sse-reader.js:parseSSEStream-->`parseSSEStream(reader, { onToken, onDone, onError })`<!--/AUTO--> | 解析 SSE 流 |

### 4.64 `src-tauri/src/lib.rs` — 壳状态机（<!--AUTO:lines:src-tauri/src/lib.rs-->~355 行<!--/AUTO-->）

**职责**：`ShellState`——动态端口、数据目录、后端子进程生命周期（Drop 兜底无残留）、就绪轮询线程、就绪超时（环境变量可配）、`run()` 装配（含单实例/托盘）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:src-tauri/src/lib.rs:ShellState.new-->`new(port: u16, data_dir: PathBuf) -> ShellState`<!--/AUTO--> | 构造 |
| <!--AUTO:sig:src-tauri/src/lib.rs:ShellState.launch-->`launch(resource_dir: Option<PathBuf>) -> ShellState`<!--/AUTO--> | 探测端口 + 构造 |
| <!--AUTO:sig:src-tauri/src/lib.rs:ShellState.try_start-->`try_start(&self, resource_dir: Option<PathBuf>) -> Result<(), String>`<!--/AUTO--> | 启动后端（配置解析 + 超时） |
| <!--AUTO:sig:src-tauri/src/lib.rs:ShellState.try_start_with-->`try_start_with(&self, config: BackendConfig) -> Result<(), String>`<!--/AUTO--> | 按配置启动 |
| <!--AUTO:sig:src-tauri/src/lib.rs:ShellState.try_start_inner-->`try_start_inner(&self, config: BackendConfig, timeout: Duration) -> Result<(), String>`<!--/AUTO--> | 启动内层（spawn + 探活） |
| <!--AUTO:sig:src-tauri/src/lib.rs:ShellState.status-->`status(&self) -> BackendStatus`<!--/AUTO--> | 状态上报（命令轮询） |
| <!--AUTO:sig:src-tauri/src/lib.rs:ShellState.child_pid-->`child_pid(&self) -> Option<u32>`<!--/AUTO--> | 子进程 PID |
| <!--AUTO:sig:src-tauri/src/lib.rs:ShellState.kill_child-->`kill_child(&self)`<!--/AUTO--> | 终止子进程 |
| <!--AUTO:sig:src-tauri/src/lib.rs:readiness_loop-->`readiness_loop(inner: Arc<ShellStateInner>, timeout: Duration)`<!--/AUTO--> | 就绪轮询线程（写 runtime.json） |
| <!--AUTO:sig:src-tauri/src/lib.rs:ready_timeout_from_env-->`ready_timeout_from_env() -> Duration`<!--/AUTO--> | 就绪超时（环境变量） |
| <!--AUTO:sig:src-tauri/src/lib.rs:run-->`run()`<!--/AUTO--> | 壳入口（Tauri 装配） |

### 4.65 `src-tauri/src/server.rs` — 后端进程管理（<!--AUTO:lines:src-tauri/src/server.rs-->~487 行<!--/AUTO-->）

**职责**：壳的后端托管——空闲端口探测、命令行解析、生产 exe 定位（目录形态回退）、`DATABASE_URL` 注入、子进程启停（Windows 进程树收割）、HTTP 就绪探测、runtime.json 原子读写、数据目录/URL 编码工具。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:src-tauri/src/server.rs:probe_free_port-->`probe_free_port() -> io::Result<u16>`<!--/AUTO--> | 探测空闲端口 |
| <!--AUTO:sig:src-tauri/src/server.rs:parse_command_line-->`parse_command_line(line: &str) -> Result<Vec<String>, String>`<!--/AUTO--> | 命令行解析（引号处理） |
| <!--AUTO:sig:src-tauri/src/server.rs:prod_backend_exe_candidates-->`prod_backend_exe_candidates(resource_dir: &Path) -> Vec<PathBuf>`<!--/AUTO--> | 生产 exe 候选路径 |
| <!--AUTO:sig:src-tauri/src/server.rs:find_prod_backend_exe-->`find_prod_backend_exe(resource_dir: &Path) -> Option<PathBuf>`<!--/AUTO--> | 定位生产 exe |
| <!--AUTO:sig:src-tauri/src/server.rs:database_url-->`database_url(data_dir: &Path) -> String`<!--/AUTO--> | 注入 DATABASE_URL（正斜杠） |
| <!--AUTO:sig:src-tauri/src/server.rs:spawn_arguments-->`spawn_arguments(port: u16) -> Vec<String>`<!--/AUTO--> | spawn 参数组装 |
| <!--AUTO:sig:src-tauri/src/server.rs:ManagedChild.pid-->`pid(&self) -> Option<u32>`<!--/AUTO--> | 子进程 PID |
| <!--AUTO:sig:src-tauri/src/server.rs:ManagedChild.kill-->`kill(&mut self)`<!--/AUTO--> | 终止（含 Windows 进程树） |
| <!--AUTO:sig:src-tauri/src/server.rs:Drop.drop-->`drop(&mut self)`<!--/AUTO--> | Drop 兜底终止 |
| <!--AUTO:sig:src-tauri/src/server.rs:http_probe-->`http_probe(port: u16, timeout: Duration) -> bool`<!--/AUTO--> | HTTP 就绪探测 |
| <!--AUTO:sig:src-tauri/src/server.rs:write_runtime_json-->`write_runtime_json(path: &Path, info: &RuntimeInfo) -> io::Result<()>`<!--/AUTO--> | 原子写 runtime.json |
| <!--AUTO:sig:src-tauri/src/server.rs:read_runtime_json-->`read_runtime_json(path: &Path) -> io::Result<RuntimeInfo>`<!--/AUTO--> | 读 runtime.json |
| <!--AUTO:sig:src-tauri/src/server.rs:data_dir_path-->`data_dir_path(base: &Path) -> PathBuf`<!--/AUTO--> | 数据目录拼接 |
| <!--AUTO:sig:src-tauri/src/server.rs:default_data_dir-->`default_data_dir() -> PathBuf`<!--/AUTO--> | 默认数据目录（%APPDATA% 优先） |
| <!--AUTO:sig:src-tauri/src/server.rs:encode_url_path-->`encode_url_path(path: &str) -> String`<!--/AUTO--> | URL 路径编码（契约表 v2） |

### 4.66 `src-tauri/src/commands.rs` — Tauri 命令（<!--AUTO:lines:src-tauri/src/commands.rs-->~29 行<!--/AUTO-->）

**职责**：Tauri 命令——`backend_status` 状态查询（boot.html 轮询用）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:src-tauri/src/commands.rs:backend_status-->`backend_status(state: State<'_, ShellState>) -> BackendStatus`<!--/AUTO--> | 后端状态命令 |

### 4.67 `src-tauri/src/tray.rs` — 系统托盘（<!--AUTO:lines:src-tauri/src/tray.rs-->~230 行<!--/AUTO-->）

**职责**：托盘（D5/D6）——菜单路由（显示/隐藏、自启勾选、退出）、窗口显隐决策、自启开关状态机（插件回读同步）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:src-tauri/src/tray.rs:action_for_menu_id-->`action_for_menu_id(id: &str) -> TrayAction`<!--/AUTO--> | 菜单 id → 动作路由 |
| <!--AUTO:sig:src-tauri/src/tray.rs:decide_window_intent-->`decide_window_intent(window_visible: bool) -> WindowIntent`<!--/AUTO--> | 窗口显隐决策 |
| <!--AUTO:sig:src-tauri/src/tray.rs:TrayStatus.new-->`new() -> Self`<!--/AUTO--> | 初始状态（可见 + 自启关） |
| <!--AUTO:sig:src-tauri/src/tray.rs:TrayStatus.sync_autostart-->`sync_autostart(&mut self, enabled: bool)`<!--/AUTO--> | 自启状态回读同步 |
| <!--AUTO:sig:src-tauri/src/tray.rs:TrayStatus.toggle_autostart-->`toggle_autostart(&mut self) -> AutostartIntent`<!--/AUTO--> | 切换自启（返回插件意图） |
| <!--AUTO:sig:src-tauri/src/tray.rs:TrayStatus.apply_window_intent-->`apply_window_intent(&mut self, intent: WindowIntent)`<!--/AUTO--> | 应用显隐意图 |
| <!--AUTO:sig:src-tauri/src/tray.rs:setup_tray-->`setup_tray(app: &AppHandle<Wry>) -> tauri::Result<()>`<!--/AUTO--> | 托盘装配 |
| <!--AUTO:sig:src-tauri/src/tray.rs:handle_menu_event-->`handle_menu_event(app: &AppHandle<Wry>, menu_id: &str)`<!--/AUTO--> | 菜单事件处理 |
| <!--AUTO:sig:src-tauri/src/tray.rs:focus_main_window-->`focus_main_window(window: &WebviewWindow<Wry>)`<!--/AUTO--> | 聚焦主窗口 |

### 4.68 `src-tauri/src/main.rs` — 壳入口（<!--AUTO:lines:src-tauri/src/main.rs-->~5 行<!--/AUTO-->）

**职责**：Tauri 入口（调用 lib 的 `run()`）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:src-tauri/src/main.rs:main-->`main()`<!--/AUTO--> | 壳入口 |

### 4.69 `frontend/js/desktop-settings.js` — 桌面壳设置（<!--AUTO:lines:frontend/js/desktop-settings.js-->~146 行<!--/AUTO-->）

**职责**：D11 关闭行为偏好——Tauri 桥检测 + 偏好读写（settings.json）+ 首次运行选择弹窗 + 设置页「关闭窗口」分组即时保存；无桥（纯网页模式）全模块 no-op。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/desktop-settings.js:hasDesktopBridge-->`hasDesktopBridge()`<!--/AUTO--> | Tauri 桥可用性检测 |
| <!--AUTO:sig:frontend/js/desktop-settings.js:getCloseAction-->`getCloseAction()`<!--/AUTO--> | 读取关闭行为偏好（null=未设置） |
| <!--AUTO:sig:frontend/js/desktop-settings.js:setCloseAction-->`setCloseAction(action)`<!--/AUTO--> | 写入关闭行为偏好（非法取值忽略） |
| <!--AUTO:sig:frontend/js/desktop-settings.js:ensureCloseActionChoice-->`ensureCloseActionChoice()`<!--/AUTO--> | 首次运行引导（未设置 → 弹窗选择并持久化） |
| <!--AUTO:sig:frontend/js/desktop-settings.js:initCloseActionSetting-->`initCloseActionSetting()`<!--/AUTO--> | 设置页分组回填 + 即时保存绑定 |

### 4.70 `src-tauri/src/settings.rs` — 壳级用户设置（<!--AUTO:lines:src-tauri/src/settings.rs-->~83 行<!--/AUTO-->）

**职责**：D11 关闭行为偏好持久化——`CloseAction` 枚举（Tray/Quit）解析/`decide_close` 决策纯逻辑（Seam 1 可注入测试）+ settings.json 原子读写（镜像 `server.rs::write_runtime_json`）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:src-tauri/src/settings.rs:decide_close-->`decide_close(action: Option<CloseAction>) -> CloseDecision`<!--/AUTO--> | 偏好 → 关闭决策（未设置/损坏回退托盘） |
| <!--AUTO:sig:src-tauri/src/settings.rs:load_close_action-->`load_close_action(data_dir: &Path) -> Option<CloseAction>`<!--/AUTO--> | 读取偏好（缺失/损坏 → None） |
| <!--AUTO:sig:src-tauri/src/settings.rs:save_close_action-->`save_close_action(data_dir: &Path, action: CloseAction) -> Result<(), String>`<!--/AUTO--> | 原子写入偏好 |
### 4.71 `frontend/js/simulator-adapt.js` — 适配分析共享模块（<!--AUTO:lines:frontend/js/simulator-adapt.js-->~405 行<!--/AUTO-->）

**职责**：新游戏接入覆盖层把关的分析逻辑（T-01）——映射记录解析 / 游戏 HTML 三面提取（日志条目类名 / CSS 变量体系 / 显式字号声明）/ 覆盖比对输出「未覆盖清单」。CLI 消费者 `scripts/check-simulator-css.mjs` 与工单 04 导入未覆盖提示共用；顶层零 DOM（Node ESM 直 import，冒烟先例）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/simulator-adapt.js:parseCoverageRecords-->`parseCoverageRecords(cssText)`<!--/AUTO--> | 解析 `# sim-pc:` 映射记录 + 推导已覆盖集合（类/变量/字号规则） |
| <!--AUTO:sig:frontend/js/simulator-adapt.js:extractGameClasses-->`extractGameClasses(htmlText)`<!--/AUTO--> | 游戏三面提取（classes/vars/fonts，零 DOM 正则） |
| <!--AUTO:sig:frontend/js/simulator-adapt.js:compareCoverage-->`compareCoverage(game, gameName, coverage)`<!--/AUTO--> | 覆盖比对 → 未覆盖清单（记录缺失必报） |

### 4.72 `scripts/check-simulator-css.mjs` 接入契约核对脚本（T-01）

**职责**：新游戏接入把关 CLI（T-01）——对指定游戏 HTML（默认 `frontend/simulators/` 全部 22 款）运行适配分析，输出「未覆盖清单」；退出码 0 = 全绿、非 0 = 有未覆盖（含映射记录缺失）。分析逻辑全部委托 `simulator-adapt.js`（`runCheck` / `main` 为导出 seam，Node 直调测试覆盖），本文件仅 CLI 编排。

### 4.73 模拟器新游戏接入流程（T-01 强制校验）

新游戏接入把关注入点：`node scripts/check-simulator-css.mjs <新游戏>.html` —— 脚本解析 `simulator-pc.css` 的映射记录（`# sim-pc:` 段）后与该游戏 HTML 三面提取结果比对：

1. **补映射记录**：在 `simulator-pc.css` 末尾 `# sim-pc:` 段按语法加一行（游戏名 = HTML 文件干名）；日志条目类/变量/字号覆盖项须与覆盖层实际规则一致（契约测试锁）；刻意保留的原始样式（元数据/标签小字号、决策面变量）以豁免项 `选择器:字号!` / `--变量!` 记录在案。
2. **跑核对**：`check-simulator-css` 全绿（退出码 0、输出无「未覆盖」）方可放行；无记录 = 未接入核对必红（适配盲区强制校验，T-01 补的短板）。
3. **04 导入提示**：工单 04 导入成功后以同一分析模块对已上传 HTML 运行比对，未覆盖清单非空则提示并引导 per-game CSS 微调。


### 4.74 `backend/app/services/simulator_store.py` — 模拟器数据存储（<!--AUTO:lines:backend/app/services/simulator_store.py-->~116 行<!--/AUTO-->）

**职责**：T-02 拆分后保留 `ensure_seeded`（首启种子）+ 顶层 re-export（`__all__` 21 符号不变，`from simulator_store import sanitize_filename` 等仍可用）。manifest 工具与导入族已迁入 `simulator_manifest.py` / `simulator_import.py`（见 §4.74.1 / §4.74.2）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:backend/app/services/simulator_store.py:ensure_seeded-->`ensure_seeded(builtin_dir, target_dir)`<!--/AUTO--> | 首启种子（路径参数化；返回 True=本次拷贝 / False=已种子或源缺失） |

### 4.74.1 `backend/app/services/simulator_manifest.py` — manifest 读写工具（<!--AUTO:lines:backend/app/services/simulator_manifest.py-->~128 行<!--/AUTO-->）

**职责**：T-02 从 `simulator_store` 拆分。manifest.json 读取/原子写入/追加/按 id 更新（缺失/损坏自愈重建）。stdlib only。

| 元素 | 说明 |
|------|------|
| `MANIFEST_FILE` | manifest.json 文件名 |
| `MANIFEST_TMP_SUFFIX` | 原子写临时文件后缀 |
| <!--AUTO:sig:backend/app/services/simulator_manifest.py:read_manifest-->`read_manifest(sim_dir)`<!--/AUTO--> | 读取 manifest.json → dict（缺失抛 FileNotFoundError） |
| <!--AUTO:sig:backend/app/services/simulator_manifest.py:write_manifest-->`write_manifest(sim_dir, manifest)`<!--/AUTO--> | 原子写 manifest（同目录临时文件 + os.replace，中文保真） |
| <!--AUTO:sig:backend/app/services/simulator_manifest.py:append_manifest_entry-->`append_manifest_entry(sim_dir, entry)`<!--/AUTO--> | manifest 原子追加（缺失/损坏 → 磁盘 .html 自愈重建后追加） |
| <!--AUTO:sig:backend/app/services/simulator_manifest.py:update_manifest_entry-->`update_manifest_entry(sim_dir, entry_id, **updates)`<!--/AUTO--> | 按 id 原子更新条目字段（缺失抛 KeyError；重新识别端点消费） |

### 4.74.2 `backend/app/services/simulator_import.py` — 模拟器导入管线（<!--AUTO:lines:backend/app/services/simulator_import.py-->~415 行<!--/AUTO-->）

**职责**：T-02 从 `simulator_store` 拆分。导入校验（.html/≤5MB/非空）、SHA-256 去重、文件名净化/冲突改名、类型探测（三层：L1 严格 cfg- 三元组 → L2 关键词启发 endpoint|url|base/key/model → L3 local，2026-08-26 补强）、端点口径推断（probe_endpoint_mode，SIM-API-1）、恶意模式粗筛（不拦截）、manifest 追加注册；T-03 新增 `ScanResult` / `scan_generated_html` 单次扫描。`scan_input_ids` 双层扫描（HTMLParser 静态层 input/select + 脚本层 raw-regex 捕获 JS 模板字符串渲染的运行时控件）。stdlib only。

| 元素 | 说明 |
|------|------|
| `MAX_IMPORT_BYTES` | 导入文件大小上限（5MB） |
| `SUSPICIOUS_PATTERNS` | 恶意模式键集（eval/document.cookie/cross-origin-fetch） |
| `ImportResult` | 导入结果 dataclass（game 条目 + warnings/rename） |
| `ScanResult` | 预计算扫描结果 dataclass（game_type/config/warnings/endpoint_mode，T-03） |
| `SimulatorDuplicateError` | 内容重复异常（→ 409） |
| `SimulatorImportError` | 导入校验失败异常（→ 400） |
| `CFG_REQUIRED_IDS` | cfg- 三元组必需 id 集 |
| <!--AUTO:sig:backend/app/services/simulator_import.py:sha256_bytes-->`sha256_bytes(content)`<!--/AUTO--> | 内容 SHA-256 摘要（去重主键） |
| <!--AUTO:sig:backend/app/services/simulator_import.py:sanitize_filename-->`sanitize_filename(raw)`<!--/AUTO--> | 文件名净化（取末段/剔非法字符与 %#/空名回退，防穿越） |
| <!--AUTO:sig:backend/app/services/simulator_import.py:slugify-->`slugify(stem)`<!--/AUTO--> | id slug（[a-z0-9-] 折叠，空回退 imported-game） |
| <!--AUTO:sig:backend/app/services/simulator_import.py:find_duplicate-->`find_duplicate(sim_dir, content)`<!--/AUTO--> | SHA-256 去重（仅比对 *.html，命中返回现存文件名） |
| <!--AUTO:sig:backend/app/services/simulator_import.py:next_available_filename-->`next_available_filename(sim_dir, desired)`<!--/AUTO--> | 冲突自动改名 xxx-2.html（大小写不敏感） |
| <!--AUTO:sig:backend/app/services/simulator_import.py:probe_config-->`probe_config(html_text)`<!--/AUTO--> | 三层类型探测（cfg- 三元组 / 关键词启发 / local 降级） |
| <!--AUTO:sig:backend/app/services/simulator_import.py:probe_endpoint_mode-->`probe_endpoint_mode(html_text)`<!--/AUTO--> | 默认端点口径推断（/chat/completions 结尾 → full；否则 base；无则 None） |
| <!--AUTO:sig:backend/app/services/simulator_import.py:scan_suspicious-->`scan_suspicious(html_text)`<!--/AUTO--> | 恶意模式粗筛（SUSPICIOUS_PATTERNS 键集，不拦截） |
| <!--AUTO:sig:backend/app/services/simulator_import.py:scan_input_ids-->`scan_input_ids(html_text)`<!--/AUTO--> | 控件 id 双层扫描（静态 input/select + 脚本模板字符串） |
| <!--AUTO:sig:backend/app/services/simulator_import.py:import_game-->`import_game(sim_dir, filename, content, source='imported', *, precomputed_scan=None)`<!--/AUTO--> | 导入编排（校验→净化→去重→改名→探测→粗筛→落盘→注册） |

---


### 4.75 `frontend/js/simulator-import.js` — 模拟器导入（<!--AUTO:lines:frontend/js/simulator-import.js-->~394 行<!--/AUTO-->）

**职责**：列表页导入游戏（工单 04，T-02 决策 9/11）——安全警告确认（「第三方游戏可读取本地数据并调用 API」）、文件选择 + 拖拽双通道、multipart 上传（fetch-seam + FormData 字段 `file`，对接 03 端点）、不确定态「正在导入…」、结果反馈（成功 toast + 改名提示 / 409-400 detail 原样 / warnings 警告不拦截 / 未覆盖适配提示 + per-game CSS 引导）。未覆盖分析复用 `frontend/js/simulator-adapt.js` 共享模块（同源 fetch 覆盖层 CSS 文本 + 已上传 HTML 文本比对；映射记录缺失项为导入预期状态，过滤不计入）。

| 元素 | 说明 |
|------|------|
| <!--AUTO:sig:frontend/js/simulator-import.js:initSimulatorImport-->`initSimulatorImport({ container: el, onImported: hook } = {})`<!--/AUTO--> | 导入初始化（文件选择器 + 拖拽绑定） |
| <!--AUTO:sig:frontend/js/simulator-import.js:openImportFlow-->`openImportFlow()`<!--/AUTO--> | 按钮入口（警告确认 → 文件选择器） |
| <!--AUTO:sig:frontend/js/simulator-import.js:importFile-->`importFile(file)`<!--/AUTO--> | 拖拽入口（校验 → 警告确认 → 上传） |
| <!--AUTO:sig:frontend/js/simulator-import.js:resetSimulatorImport-->`resetSimulatorImport()`<!--/AUTO--> | 切走视图复位（导入中状态 / 拖拽高亮） |


### 4.75.1 `backend/app/services/game_generator.py` — AI 游戏生成编排（<!--AUTO:lines:backend/app/services/game_generator.py-->~516 行<!--/AUTO-->）

**职责**：AI 文本 → HTML 模拟器游戏的主编排——构造 prompt（种子模板 + 用户描述 + 重试反馈）→ resolve_llm 获取 LLM → 生成 → 6 项校验闸门（结构/模板标记/cfg 契约/可解析性/安全/游戏数据）→ 通过复用 `simulator_import.import_game`（经 `simulator_store` re-export）落盘；失败返回结构化错误 + 重试建议（最多 3 次自动重试）。T-04 重试参数内化为私有辅助。

| 元素 | 说明 |
|------|------|
| `MAX_RETRIES` | 最大重试次数（常量，3） |
| <!--AUTO:sig:backend/app/services/game_generator.py:generate_game-->`generate_game(db, description, title=None)`<!--/AUTO--> | 生成主编排（异步，含校验重试循环） |
| <!--AUTO:sig:backend/app/services/game_generator.py:validate_generated_html-->`validate_generated_html(html, *, precomputed_scan=None)`<!--/AUTO--> | 校验闸门：6 项检查返回错误列表 |


### 4.75.2 `backend/app/services/game_template.py` — 叙事游戏种子模板（<!--AUTO:lines:backend/app/services/game_template.py-->~209 行<!--/AUTO-->）

**职责**：自包含 HTML 叙事选择游戏种子模板，LLM 通过替换两个模板标记（`<!-- GEN:config -->` / `<!-- GEN:scenes -->`）填充数据。`MARKER_PATTERN` 供校验闸门检测替换完整性。

| 元素 | 说明 |
|------|------|
| `MARKER_PATTERN` | 模板标记正则（常量，校验闸门复用） |
| `SEED_TEMPLATE` | 种子模板 HTML 全文（常量） |


---

## 五、测试

三层测试体系：后端 pytest（25 文件）、前端 Vitest（33 文件）、壳 cargo test（4 集成文件 + lib.rs 单元）。覆盖率基线：后端 `pytest --cov`（目标 ≥90%）、前端 `npm run test:coverage`。

### 5.1 后端 pytest（backend/tests）

| 文件 | 用例数 | 覆盖主题 |
|------|--------|----------|
| `backend/tests/test_character_card.py` | <!--AUTO:tests:backend/tests/test_character_card.py-->56<!--/AUTO--> | 角色卡 V2 导入导出/往返保真 |
| `backend/tests/test_character_fields.py` | <!--AUTO:tests:backend/tests/test_character_fields.py-->26<!--/AUTO--> | 角色字段常量映射契约锁 |
| `backend/tests/test_character_import_avatar.py` | <!--AUTO:tests:backend/tests/test_character_import_avatar.py-->2<!--/AUTO--> | 角色导入非 ASCII avatar 500 回归（服务层 ValueError 缺陷路径 + API 层全路径） |
| `backend/tests/test_chat_service.py` | <!--AUTO:tests:backend/tests/test_chat_service.py-->36<!--/AUTO--> | 对话编排（准备/完成/错误响应） |
| `backend/tests/test_conversation_export.py` | <!--AUTO:tests:backend/tests/test_conversation_export.py-->20<!--/AUTO--> | 会话 JSON/Markdown 导出 |
| `backend/tests/test_conversation_service.py` | <!--AUTO:tests:backend/tests/test_conversation_service.py-->13<!--/AUTO--> | 会话服务/标题生成 |
| `backend/tests/test_data_dir.py` | <!--AUTO:tests:backend/tests/test_data_dir.py-->19<!--/AUTO--> | 数据目录契约（UNC/尾分隔符） |
| `backend/tests/test_data_dir_connection.py` | <!--AUTO:tests:backend/tests/test_data_dir_connection.py-->7<!--/AUTO--> | 数据目录/DB 连接集成 |
| `backend/tests/test_document_parser.py` | <!--AUTO:tests:backend/tests/test_document_parser.py-->15<!--/AUTO--> | 文档智能解析 |
| `backend/tests/test_error_handler.py` | <!--AUTO:tests:backend/tests/test_error_handler.py-->40<!--/AUTO--> | 统一异常处理器 |
| `backend/tests/test_error_mapping_export.py` | <!--AUTO:tests:backend/tests/test_error_mapping_export.py-->12<!--/AUTO--> | 错误映射协议表面（__all__ 导出/逐字保值） |
| `backend/tests/test_game_generator.py` | <!--AUTO:tests:backend/tests/test_game_generator.py-->62<!--/AUTO--> | 游戏生成（校验闸门/场景提取/标题净化/prompt 构造/异步编排） |
| `backend/tests/test_llm_shared.py` | <!--AUTO:tests:backend/tests/test_llm_shared.py-->18<!--/AUTO--> | LLM 基类共享行为 |
| `backend/tests/test_migrate_data.py` | <!--AUTO:tests:backend/tests/test_migrate_data.py-->53<!--/AUTO--> | 数据迁移工具 |
| `backend/tests/test_p35.py` | <!--AUTO:tests:backend/tests/test_p35.py-->25<!--/AUTO--> | P3.5 阶段功能回归 |
| `backend/tests/test_package_exports.py` | <!--AUTO:tests:backend/tests/test_package_exports.py-->4<!--/AUTO--> | 包级导出契约（__all__） |
| `backend/tests/test_packaging.py` | <!--AUTO:tests:backend/tests/test_packaging.py-->27<!--/AUTO--> | PyInstaller 打包形态 |
| `backend/tests/test_prompt.py` | <!--AUTO:tests:backend/tests/test_prompt.py-->26<!--/AUTO--> | 提示词构建/模板变量 |
| `backend/tests/test_provider_registry.py` | <!--AUTO:tests:backend/tests/test_provider_registry.py-->24<!--/AUTO--> | Provider 注册表 |
| `backend/tests/test_regenerate.py` | <!--AUTO:tests:backend/tests/test_regenerate.py-->28<!--/AUTO--> | regenerate 端点（截断/事务/错误矩阵） |
| `backend/tests/test_regenerate_spike.py` | <!--AUTO:tests:backend/tests/test_regenerate_spike.py-->22<!--/AUTO--> | regenerate truncation×滑窗边界实证（T0 spike） |
| `backend/tests/test_resolve_llm.py` | <!--AUTO:tests:backend/tests/test_resolve_llm.py-->7<!--/AUTO--> | LLM 解析器 |
| `backend/tests/test_schema_snapshot.py` | <!--AUTO:tests:backend/tests/test_schema_snapshot.py-->1<!--/AUTO--> | schema 快照漂移检测（T-17） |
| `backend/tests/test_search.py` | <!--AUTO:tests:backend/tests/test_search.py-->13<!--/AUTO--> | 跨对话搜索 |
| `backend/tests/test_settings_connection.py` | <!--AUTO:tests:backend/tests/test_settings_connection.py-->55<!--/AUTO--> | 设置/凭证/连接测试 |
| `backend/tests/test_simulator_import.py` | <!--AUTO:tests:backend/tests/test_simulator_import.py-->149<!--/AUTO--> | 模拟器导入（校验矩阵/去重/改名/探测/粗筛/manifest 注册/路由 wire） |
| `backend/tests/test_simulator_store.py` | <!--AUTO:tests:backend/tests/test_simulator_store.py-->33<!--/AUTO--> | 模拟器首启种子矩阵 + manifest 工具 + append 原子写/损坏自愈 |

运行：`cd backend && python -m pytest`（pytest.ini 在根：`testpaths = backend/tests`，`pythonpath = .`；共享夹具见 `backend/tests/conftest.py`）。

### 5.2 前端 Vitest（frontend/tests）

| 文件 | 用例数 | 覆盖主题 |
|------|--------|----------|
| `frontend/tests/api.test.js` | <!--AUTO:tests:frontend/tests/api.test.js-->19<!--/AUTO--> | 请求层/超时/SSE/Blob |
| `frontend/tests/app.test.js` | <!--AUTO:tests:frontend/tests/app.test.js-->38<!--/AUTO--> | 应用编排接线 |
| `frontend/tests/cascade.test.js` | <!--AUTO:tests:frontend/tests/cascade.test.js-->12<!--/AUTO--> | 级联收口 |
| `frontend/tests/character-modal.test.js` | <!--AUTO:tests:frontend/tests/character-modal.test.js-->39<!--/AUTO--> | 角色表单/模态 |
| `frontend/tests/character-submit.test.js` | <!--AUTO:tests:frontend/tests/character-submit.test.js-->30<!--/AUTO--> | 提交状态机 |
| `frontend/tests/chat.test.js` | <!--AUTO:tests:frontend/tests/chat.test.js-->73<!--/AUTO--> | 对话视图 |
| `frontend/tests/components-icons.test.js` | <!--AUTO:tests:frontend/tests/components-icons.test.js-->4<!--/AUTO--> | 组件图标一致性 |
| `frontend/tests/conversation-activation.test.js` | <!--AUTO:tests:frontend/tests/conversation-activation.test.js-->16<!--/AUTO--> | 会话激活 |
| `frontend/tests/desktop-settings.test.js` | <!--AUTO:tests:frontend/tests/desktop-settings.test.js-->20<!--/AUTO--> | 桌面壳设置（关闭行为偏好，D11） |
| `frontend/tests/error-bar.test.js` | <!--AUTO:tests:frontend/tests/error-bar.test.js-->17<!--/AUTO--> | 错误条渲染/交互/生命周期（T1） |
| `frontend/tests/loading-button.test.js` | <!--AUTO:tests:frontend/tests/loading-button.test.js-->7<!--/AUTO--> | 按钮 loading 态工具 |
| `frontend/tests/format.test.js` | <!--AUTO:tests:frontend/tests/format.test.js-->49<!--/AUTO--> | 展示契约 |
| `frontend/tests/game-generator.test.js` | <!--AUTO:tests:frontend/tests/game-generator.test.js-->29<!--/AUTO--> | AI 游戏生成器（模态框/错误/重试/T4 凭证预检） |
| `frontend/tests/icons.test.js` | <!--AUTO:tests:frontend/tests/icons.test.js-->7<!--/AUTO--> | 图标 seam |
| `frontend/tests/key-injector.test.js` | <!--AUTO:tests:frontend/tests/key-injector.test.js-->70<!--/AUTO--> | Key 注入/端点口径 |
| `frontend/tests/list-views.test.js` | <!--AUTO:tests:frontend/tests/list-views.test.js-->21<!--/AUTO--> | 角色/对话列表视图 |
| `frontend/tests/markdown.test.js` | <!--AUTO:tests:frontend/tests/markdown.test.js-->52<!--/AUTO--> | Markdown 渲染/消毒 |
| `frontend/tests/modal.test.js` | <!--AUTO:tests:frontend/tests/modal.test.js-->15<!--/AUTO--> | 模态框焦点陷阱/关闭还原 |
| `frontend/tests/model-selector.test.js` | <!--AUTO:tests:frontend/tests/model-selector.test.js-->13<!--/AUTO--> | 模型选择 |
| `frontend/tests/model-utils.test.js` | <!--AUTO:tests:frontend/tests/model-utils.test.js-->5<!--/AUTO--> | 模型下拉工具 |
| `frontend/tests/save-key-meta.test.js` | <!--AUTO:tests:frontend/tests/save-key-meta.test.js-->25<!--/AUTO--> | 存档键契约 |
| `frontend/tests/save-manager.test.js` | <!--AUTO:tests:frontend/tests/save-manager.test.js-->64<!--/AUTO--> | 存档管理 |
| `frontend/tests/search-view.test.js` | <!--AUTO:tests:frontend/tests/search-view.test.js-->18<!--/AUTO--> | 搜索视图 |
| `frontend/tests/settings-panel.test.js` | <!--AUTO:tests:frontend/tests/settings-panel.test.js-->33<!--/AUTO--> | 设置面板 |
| `frontend/tests/simulator-contracts.test.js` | <!--AUTO:tests:frontend/tests/simulator-contracts.test.js-->21<!--/AUTO--> | 模拟器域契约 |
| `frontend/tests/simulator-import.test.js` | <!--AUTO:tests:frontend/tests/simulator-import.test.js-->40<!--/AUTO--> | 模拟器导入（工单 04） |
| `frontend/tests/simulator-adapt.test.js` | <!--AUTO:tests:frontend/tests/simulator-adapt.test.js-->39<!--/AUTO--> | 适配分析共享模块 + 核对脚本 CLI（T-01） |
| `frontend/tests/simulator-manifest.test.js` | <!--AUTO:tests:frontend/tests/simulator-manifest.test.js-->19<!--/AUTO--> | manifest 解析 |
| `frontend/tests/simulator-pc-css.test.js` | <!--AUTO:tests:frontend/tests/simulator-pc-css.test.js-->24<!--/AUTO--> | 模拟器 PC 覆盖层契约（验收标准 + F1/F2 回归锁） |
| `frontend/tests/simulator-view.test.js` | <!--AUTO:tests:frontend/tests/simulator-view.test.js-->67<!--/AUTO--> | 模拟器运行视图 |
| `frontend/tests/simulators.test.js` | <!--AUTO:tests:frontend/tests/simulators.test.js-->79<!--/AUTO--> | 模拟器列表 |
| `frontend/tests/sse-reader.test.js` | <!--AUTO:tests:frontend/tests/sse-reader.test.js-->4<!--/AUTO--> | SSE 解析 |
| `frontend/tests/stream-session.test.js` | <!--AUTO:tests:frontend/tests/stream-session.test.js-->54<!--/AUTO--> | 流式会话结算 |
| `frontend/tests/tabs.test.js` | <!--AUTO:tests:frontend/tests/tabs.test.js-->68<!--/AUTO--> | tab 工作区 |
| `frontend/tests/utils.test.js` | <!--AUTO:tests:frontend/tests/utils.test.js-->15<!--/AUTO--> | 通用工具（含 toast 队列上限，T4） |

运行：`cd frontend && npm test`（= `vitest run`）。

### 5.3 壳 cargo test（src-tauri/tests + lib 单元）

| 文件 | 用例数 | 覆盖主题 |
|------|--------|----------|
| `src-tauri/tests/server_test.rs` | <!--AUTO:tests:src-tauri/tests/server_test.rs-->35<!--/AUTO--> | 端口探测/命令行/启停/探活/runtime.json |
| `src-tauri/tests/settings_test.rs` | <!--AUTO:tests:src-tauri/tests/settings_test.rs-->12<!--/AUTO--> | 关闭行为偏好解析/决策/settings.json 读写（D11） |
| `src-tauri/tests/tray_test.rs` | <!--AUTO:tests:src-tauri/tests/tray_test.rs-->8<!--/AUTO--> | 菜单路由/窗口显隐/自启状态机 |
| `src-tauri/tests/shell_state_test.rs` | <!--AUTO:tests:src-tauri/tests/shell_state_test.rs-->9<!--/AUTO--> | ShellState 状态机/完整启动链 |
| `src-tauri/src/lib.rs`（`mod tests` 单元） | <!--AUTO:tests:src-tauri/src/lib.rs-->6<!--/AUTO--> | 就绪超时环境变量解析 |

运行：`cd src-tauri && cargo test`（cmd.exe/PowerShell，Git Bash 的 coreutils `link.exe` 会遮蔽 MSVC linker）。

---

## 六、依赖与数据格式

### 6.1 后端依赖（backend/requirements.txt）

`fastapi` / `uvicorn[standard]` / `sqlalchemy[asyncio]>=2.0.30`（**同步模式使用**，`+aiosqlite` 前缀在建引擎时剔除）/ `aiosqlite` / `pydantic>=2.0` / `pydantic-settings` / `anthropic` / `openai` / `python-dotenv`。开发依赖：`pytest` + `pytest-cov`。

### 6.2 前端依赖（frontend/package.json）

devDependencies：`vitest` + `@vitest/coverage-v8` + `jsdom`（测试）+ `@tauri-apps/cli` + `playwright`。`npm test` = `vitest run`。

### 6.3 壳依赖（src-tauri/Cargo.toml）

`tauri` v2（tray-icon）+ `tauri-plugin-single-instance` + `tauri-plugin-autostart` + `serde` + `serde_json`。lib 名 `conver_app_lib`（staticlib/cdylib/rlib）。

### 6.4 SQLite 数据格式

| 表 | 关键列 | 说明 |
|----|--------|------|
| `characters` | name/description/personality/scenario/first_mes/mes_example/system_prompt/post_history_instructions/alternate_greetings(JSON)/tags(JSON)/creator/version/creator_notes(JSON)/extensions(JSON) | V2 字段映射；JSON 列兼容存量 TEXT |
| `conversations` | character_id(FK CASCADE)/title | 会话（角色外键） |
| `messages` | conversation_id(FK CASCADE)/role(user/assistant/system 枚举按值)/content | 消息 |
| `settings` | key/value | 运行时配置键值 |

### 6.5 关键外部格式

- **Character Card V2 信封**：`{spec: "chara_card_v2", spec_version: "2.0", data: {...}}`；导出兼容 V1 旧卡与裸 data；非标准字段存 `extensions.conver_system.*` 命名空间。
- **runtime.json**（桌面壳，%APPDATA%\ConverSystem\）：`RuntimeInfo`——端口/数据目录/就绪时间等，boot.html 跳转依据。
- **simulators/manifest.json**：22 款模拟器清单（v2 含 `endpointMode`: `full`/`base`）。
- **保存键契约**：`save-key-meta.js` 单源（`WG_SESSION_ONLY_IDS` 等）。

---

## 七、测试基线

> 三层合计：**<!--AUTO:tests_total:total-->1969<!--/AUTO-->** 项全绿。
>
> - pytest（后端，含 1 skip）：<!--AUTO:tests_total:pytest-->793<!--/AUTO-->
> - Vitest（前端）：<!--AUTO:tests_total:vitest-->1106<!--/AUTO-->
> - cargo test（壳）：<!--AUTO:tests_total:cargo-->70<!--/AUTO-->

基线同步机制：`scripts/doc_sync.py` 机械维护上表与 §5 各文件用例数、§4 行数/签名标记；`pre-commit` 钩子拦截漂移提交（`python scripts/doc_sync.py --check`）。手动刷新：`python scripts/doc_sync.py`。

