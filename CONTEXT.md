# 领域词汇表 (CONTEXT)

> 领域术语登记，供新入参与者与架构评审对齐概念。术语即事实：修改命名 / 职责前先更新本表。
> 本表供后续架构评审使用（见 `/improve-codebase-architecture`），术语须保持可承载（load-bearing），不得写成「仅供查阅」的装饰性词汇。

## 核心术语

| 术语 | 定义 | 归属（模块 / 接口） |
|------|------|---------------------|
| **聊天回合 (chat turn)** | 一次 user→assistant 交互周期：prepare_chat → generate → persist（客户端断开时保存已生成部分收尾）。协议表面小、实现丰富，属**深模块**。 | `backend/app/services/chat.py`：`ChatContext` / `prepare_chat` / `llm_error_response` / `stream_reply`；`api/routes/chat.py` 仅保留 HTTP 映射与 SSE `data:` 帧包装。 |
| **运行时设置 (runtime settings)** | 基于 DB `settings` 表的键值配置（区别于 `.env` 启动配置）；读 / 写 / 白名单 / 默认回退链 / 整型容错（防 500）全部收口。属**深模块**。 | `backend/app/services/setting.py`：`ALLOWED_KEYS` / `get_value` / `get_int` / `get_all` / `set_many` / `api_key` / `user_name` / `sliding_window_rounds` / `default_provider` / `default_model`。 |
| **角色 (character)** | SillyTavern V2 角色卡（V2 信封 + V1 / 裸 data 归一化 + `extensions.conver_system` 往返保真），导入 / 导出经转换层。 | `backend/app/services/character_card.py`：`to_v2_card` / `from_v2_card`。 |
| **对话 (conversation)** | 绑定单角色的会话，持有消息序列 + 模型选择（provider / model），默认标题「与 {角色名} 的对话」。 | `backend/app/services/conversation.py`。 |
| **消息 (message)** | 对话内的一条 user / assistant / system 轮次（ORM 层 `Role` 枚举按值存取）。 | `backend/app/services/message.py`：`create_message` / `build_message_list` / `auto_insert_greeting` / 检索。 |
| **Provider (LLM 适配器)** | 对 LLM SDK 的**适配器**（adapter），实现 `BaseLLM` 抽象基类（`Seam`）；经 `LLMFactory.register_builtin_providers()` **显式注册**（无 import 副作用），`get_provider` / `list_providers` 首次调用懒加载兜底。 | `backend/app/services/llm/`：`base.py`（BaseLLM + test_connection）/ `claude.py` / `openai.py` / `factory.py`（LLMFactory + 注册）/ `errors.py`。 |
