# 领域词汇表 (CONTEXT)

> 领域术语登记，供新入参与者与架构评审对齐概念。术语即事实：修改命名 / 职责前先更新本表。
> 本表供后续架构评审使用（见 `/improve-codebase-architecture`），术语须保持可承载（load-bearing），不得写成「仅供查阅」的装饰性词汇。

## 核心术语

| 术语 | 定义 | 归属（模块 / 接口） |
|------|------|---------------------|
| **聊天回合 (chat turn)** | 一次 user→assistant 交互周期：prepare_chat → generate → persist（客户端断开时保存已生成部分收尾）。协议表面小、实现丰富，属**深模块**。非流式完整回合收口为 `complete_chat`（prepare 内嵌，错误/持久化/响应构造全在 service 内）；错误映射单一来源 `chat_error_response`（领域 + LLM 两族并置，状态码/消息与旧两轨逐字一致）。 | `backend/app/services/chat.py`：`ChatContext` / `prepare_chat` / `complete_chat` / `chat_error_response` / `stream_reply`；`api/routes/chat.py` 仅保留 HTTP 映射与 SSE `data:` 帧包装（`_DOMAIN_ERRORS` 转换）。 |
| **运行时设置 (runtime settings)** | 基于 DB `settings` 表的键值配置（区别于 `.env` 启动配置）；读 / 写 / 白名单 / 默认回退链 / 整型容错（防 500）全部收口。属**深模块**。 | `backend/app/services/setting.py`：`ALLOWED_KEYS` / `get_value` / `get_int` / `get_all` / `set_many` / `api_key` / `user_name` / `sliding_window_rounds` / `default_provider` / `default_model`。 |
| **角色 (character)** | SillyTavern V2 角色卡（V2 信封 + V1 / 裸 data 归一化 + `extensions.conver_system` 往返保真），导入 / 导出经转换层。 | `backend/app/services/character_card.py`：`to_v2_card` / `from_v2_card`。 |
| **对话 (conversation)** | 绑定单角色的会话，持有消息序列 + 模型选择（provider / model），默认标题「与 {角色名} 的对话」。 | `backend/app/services/conversation.py`。 |
| **消息 (message)** | 对话内的一条 user / assistant / system 轮次（ORM 层 `Role` 枚举按值存取）。 | `backend/app/services/message.py`：`create_message` / `build_message_list` / `auto_insert_greeting` / 检索。 |
| **Provider (LLM 适配器)** | 对 LLM SDK 的**适配器**（adapter），实现 `BaseLLM` 抽象基类（`Seam`）；经 `LLMFactory.register_builtin_providers()` **显式注册**（无 import 副作用），`get_provider` / `list_providers` 首次调用懒加载兜底。 | `backend/app/services/llm/`：`base.py`（BaseLLM + test_connection）/ `claude.py` / `openai.py` / `factory.py`（LLMFactory + 注册）/ `errors.py`。 |
| **会话 tab 工作区 (tab workspace)** | 多 tab 会话工作区：每个 tab 持有独立会话视图状态（消息缓存 / 输入草稿 / 滚动位置 / 流式阶段 / 流式句柄）；结构性变更（开/关/激活/恢复）自动写 sessionStorage（只存 ids + activeId）并通知；tab 条只消费展示契约。属**深模块**。 | `frontend/js/tabs.js`：`openTab` / `activateTab` / `closeTab` / `closeTabs` / `getActiveTab` / `updateTab`（幂等 no-op）/ `getTabDisplay`（展示契约）/ `serialize` / `restore` / `onTabsChanged` / `abortStream`。 |
| **防悬挂写回 (anti-dangling writeback)** | 流式/非流式完成、错误、停止的回调一律按**发起时捕获的 conversationId** 写回，绝不读「当前活动」；发起 tab 可能已被关闭 → `updateTab` 幂等 no-op 兜底。这是 P6.5 的核心不变量。 | `frontend/js/stream-session.js`（`createStreamSession` 构造捕获 convId + anchor）；`frontend/js/chat.js`（handleSend 捕获 convId）。 |
| **数据目录 (data dir)** | 桌面版数据落点解析，契约表 v2（2026-08-12 双端镜像钉住）：`CONVER_DATA_DIR`（非空）→ `%APPDATA%\ConverSystem` → `home\AppData\Roaming\ConverSystem` 兜底统一；壳注入 `DATABASE_URL` 仅对 `?` 做 `%3F` 编码（SQLAlchemy sqlite 方言**零解码** `%XX`——v1 全量编码回归教训，连接级消费者测试防复发），migrate_data `_open_readonly` 的 sqlite3 URI 编码（uri=True 会解码）语义不同、保持独立。 | `backend/app/services/data_dir.py`（纯 stdlib：`data_dir` / `data_dir_file` / `database_path`）；`src-tauri/src/server.rs`：`default_data_dir` / `encode_url_path`（Rust 镜像实现）；契约表 v2：`backend/tests/test_data_dir.py` + `test_data_dir_connection.py` + `src-tauri/tests/server_test.rs` 双端互引。 |
| **流式结算 (stream settlement)** | 流完成后消息列表重载的合并策略：fresh（长度未变）整体替换 / stale（长度变了）按 settleIndex 位置结算本流 streaming 标记 / 失败按 anchor（本流 user 消息对象引用，indexOf 定位不受插入漂移影响）写回本流内容。幂等：同 id 已存在或该位置已非 streaming 则不重复操作。流式（onDone 主体）与非流式（chat.js 完成分支）统一走 `settleTurn` 单一入口（内部 try/catch 双分支；非流式成功 `{settleIndex:-1}`、失败兜底 `{content: reply}` 不带 messageId——逐字复刻，不得"顺手改进"）。 | `frontend/js/stream-session.js`：`settleTurn` / `mergeFreshList` / `settleByPosition`。 |
