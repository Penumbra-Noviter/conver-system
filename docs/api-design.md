# API 接口设计

> 所有接口前缀 `/api`，请求和响应均为 JSON 格式。
> 后端启动后可通过 Swagger UI 交互测试: http://localhost:8000/docs

---

## 角色 API

### 获取角色列表

```
GET /api/characters
```

**响应** `200` — 角色对象含 V2 全字段（下为节选，完整字段见 `CharacterResponse`）
```json
[
  {
    "id": 1,
    "name": "林墨",
    "description": "一位流浪诗人",
    "personality": "你是林墨，一位流浪诗人...",
    "scenario": "月下竹林",
    "first_mes": "你来了。正好，陪我喝一杯？",
    "mes_example": "<START>\n{{user}}: 你好\n{{char}}: 欢迎",
    "system_prompt": "",
    "post_history_instructions": "",
    "alternate_greetings": [],
    "tags": [],
    "creator": "",
    "version": "1.0",
    "creator_notes": {},
    "extensions": {},
    "avatar": null,
    "temperature": 0.7,
    "conversation_count": 0,
    "created_at": "2026-07-30T10:00:00",
    "updated_at": "2026-07-30T10:00:00"
  }
]
```

### 获取单个角色

```
GET /api/characters/{character_id}
```

### 创建角色

```
POST /api/characters
```

**请求体** — 字段与响应一致（除 `id`/`conversation_count`/`created_at`/`updated_at` 计算字段），`name` 必填，其余默认空/默认值
```json
{
  "name": "林墨",
  "description": "一位流浪诗人",
  "personality": "你是林墨，一位流浪诗人...",
  "scenario": "月下竹林",
  "first_mes": "你来了。正好，陪我喝一杯？",
  "mes_example": "<START>\n{{user}}: 你好\n{{char}}: 欢迎",
  "system_prompt": "",
  "post_history_instructions": "",
  "alternate_greetings": [],
  "tags": [],
  "creator": "",
  "version": "1.0",
  "creator_notes": {},
  "extensions": {},
  "avatar": null,
  "temperature": 0.7
}
```

**响应** `201` — 返回创建后的角色对象

### 更新角色

```
PUT /api/characters/{character_id}
```

**请求体** — 同创建，所有字段可选更新（全量更新）

### 删除角色

```
DELETE /api/characters/{character_id}
```

**响应** `204` — 无内容
> 删除角色时级联删除其所有对话和消息

### 导出角色卡（V2）

```
GET /api/characters/{character_id}/export
```

**响应** `200` — `application/json` 附件（`Content-Disposition` 附件头，中文文件名 URL 编码），内容为 SillyTavern V2 信封（`spec`/`data`，见 [P2.5 规格](p2.5-character-import-export.md)）

### 导入角色卡

```
POST /api/characters/import
```

**请求体** — 角色卡原始 JSON（任意 dict，兼容 V2 信封 / 裸 data / V1 旧卡）

**响应** `201` — 导入后的角色对象；非法卡 → `422`「导入失败：<原因>」

---

## 对话 API

### 获取对话列表

```
GET /api/conversations?character_id=1
```

**查询参数**
| 参数 | 类型 | 说明 |
|------|------|------|
| character_id | int? | 可选，按角色筛选 |

**响应** `200`
```json
[
  {
    "id": 1,
    "character_id": 1,
    "title": "关于诗歌的讨论",
    "model_provider": "claude",
    "model_name": "claude-sonnet-4-20250514",
    "message_count": 12,
    "created_at": "2026-07-30T10:00:00",
    "updated_at": "2026-07-30T11:30:00"
  }
]
```

### 创建对话

```
POST /api/conversations
```

**请求体**
```json
{
  "character_id": 1,
  "title": "关于诗歌的讨论",
  "model_provider": "claude",
  "model_name": "claude-sonnet-4-20250514"
}
```

> **title 可选**：不传时后端默认「与 {角色名} 的对话」（角色存在时）；发出首条 user 消息后，服务端同步替换为该消息的规则截断标题（折叠空白 + 20 字 + 「…」），详见 CONSENSUS §4。

**响应** `201`
```json
{
  "id": 1,
  "character_id": 1,
  "title": "关于诗歌的讨论",
  "model_provider": "claude",
  "model_name": "claude-sonnet-4-20250514",
  "created_at": "2026-07-30T10:00:00"
}
```

### 更新对话

```
PUT /api/conversations/{conversation_id}
```

### 删除对话

```
DELETE /api/conversations/{conversation_id}
```

**响应** `204`

### 清空所有对话

```
DELETE /api/conversations
```

**响应** `204` — 级联删除所有对话及消息

### 导出对话（JSON）

```
GET /api/conversations/{conversation_id}/export/json
```

**响应** `200` — `application/json` 附件，结构 `{ conversation, character, messages[] }`（`role` 为纯字符串 `user`/`assistant`/`system`）

### 导出对话（Markdown）

```
GET /api/conversations/{conversation_id}/export/markdown
```

**响应** `200` — `text/markdown` 附件（标题 + 角色信息 + 按日期分组消息）

---

## 消息 API

### 获取消息历史

```
GET /api/conversations/{conversation_id}/messages
```

**响应** `200`
```json
[
  {
    "id": 1,
    "conversation_id": 1,
    "role": "assistant",
    "content": "你来了。正好，陪我喝一杯？",
    "created_at": "2026-07-30T10:00:00"
  },
  {
    "id": 2,
    "conversation_id": 1,
    "role": "user",
    "content": "今天心情不错",
    "created_at": "2026-07-30T10:01:00"
  }
]
```

### 搜索消息

```
GET /api/messages/search?q=关键词&limit=50
```

**查询参数**
| 参数 | 类型 | 说明 |
|------|------|------|
| q | str | 搜索关键词（SQL LIKE 跨对话匹配） |
| limit | int | 最大返回条数，默认 50 |

**响应** `200`
```json
[
  {
    "message_id": 3,
    "conversation_id": 1,
    "conversation_title": "关于诗歌的讨论",
    "character_id": 1,
    "character_name": "林墨",
    "character_avatar": null,
    "role": "user",
    "content_preview": "…今天心情不错…",
    "created_at": "2026-07-30T10:01:00"
  }
]
```

---

## 聊天 API（核心）

### 非流式聊天

```
POST /api/chats
```

**请求体**
```json
{
  "conversation_id": 1,
  "content": "今天心情不错"
}
```

**响应** `200`
```json
{
  "reply": "哈哈，心情好就该浪费在美好的事情上。比如…跟我聊聊天？",
  "message_id": 3,
  "conversation_id": 1
}
```

### 流式聊天

```
POST /api/chats/stream
```

**请求体** 同非流式

**响应** `200` — `text/event-stream` (SSE)

```
data: {"type": "token", "content": "哈哈"}
data: {"type": "token", "content": "，心情"}
data: {"type": "token", "content": "好就该"}
data: {"type": "token", "content": "浪费在美好的事情上"}
data: {"type": "done", "message_id": 3}
```

**前端处理**
```javascript
const eventSource = fetch('/api/chats/stream', { /* POST */ });
const reader = response.body.getReader();
// 逐块解码渲染，实现打字机效果
```

**停止生成**（流式模式）
- 前端持 `AbortController`，点击停止按钮 → `controller.abort()` → fetch 中断 → SSE 连接断开
- 后端 `event_generator` 在 token 循环中轮询 `request.is_disconnected()`：检测到客户端断开即停止继续调用 LLM，**将已生成的部分内容保存为 assistant 消息**后正常收尾
- 停止语义为「用户主动停止」，非错误；前端气泡标记「（已停止）」
- 非流式端点 `POST /api/chats` 不提供停止（请求不可真正中断）

---

## 模型 API

### 获取可用模型列表

```
GET /api/models
```

**响应** `200`
```json
{
  "providers": [
    {
      "id": "claude",
      "name": "Claude (Anthropic)",
      "models": [
        "claude-sonnet-4-20250514",
        "claude-opus-4-8-20250514",
        "claude-haiku-4-5-20251001"
      ]
    },
    {
      "id": "openai",
      "name": "OpenAI / 兼容 API",
      "models": [
        "gpt-4o",
        "gpt-4o-mini",
        "gpt-4-turbo"
      ]
    }
  ]
}
```

> 可用模型列表可以硬编码在后端配置中，前端只做展示。
> 未来可考虑通过 SDK 实时查询各 Provider 的可用模型。

---

## 设置 API

### 获取所有设置

```
GET /api/settings
```

**响应** `200`
```json
{
  "claude_api_key": "sk-ant-...",
  "openai_api_key": "sk-...",
  "openai_base_url": "https://api.example.com/v1",
  "default_provider": "claude",
  "default_model": "claude-sonnet-4-20250514",
  "sliding_window_rounds": "30",
  "theme_mode": "auto",
  "user_name": "User"
}
```

### 更新设置

```
PUT /api/settings
```

**请求体** — 键为白名单内设置项（如上），可部分更新；白名单外的键被忽略

```json
{
  "claude_api_key": "sk-ant-...",
  "openai_api_key": "sk-...",
  "default_provider": "claude",
  "default_model": "claude-sonnet-4-20250514"
}
```

> API Key 同时支持 `.env` 文件注入和运行时设置面板修改。
> 运行时设置优先于 `.env` 默认值。

### 测试 API Key 连接

```
POST /api/settings/test-connection
```

**请求体**
```json
{
  "provider": "claude",
  "api_key": "sk-ant-...",
  "base_url": null,
  "model": null
}
```

| 字段 | 说明 |
|------|------|
| provider | Provider 标识（claude / openai） |
| api_key | 要测试的 Key；**留空则回退到已保存的 Key** |
| base_url | 自定义 API 地址（OpenAI 兼容服务用） |
| model | 测试用模型名；留空用 Provider 默认模型 |

**响应** `200`
```json
{
  "ok": true,
  "provider": "claude",
  "message": "连接成功"
}
```

**错误** `400` — 不支持的 Provider / 未提供 Key / Key 无效 / 网络不可达（detail 为可读原因）

### 获取模拟器凭证（只读）

```
GET /api/settings/credentials
```

**响应** `200` — 只读凭证查询（无写入副作用），供模拟器「使用主应用 Key」注入用

```json
{
  "key": "",
  "endpoint": "",
  "model": "",
  "protocol": "none"
}
```

| 字段 | 说明 |
|------|------|
| key | openai 协议槽位解析到的 key；仅 `protocol=openai` 时非空（claude key 值**绝不回传**） |
| endpoint | openai 协议槽位 base_url（复用跨协议兜底链）；为空时前端保持游戏默认地址 |
| model | 默认 provider 为 openai 协议且存在 openai key 时返回，否则空串（游戏保持默认模型） |
| protocol | 协议能力标志 ∈ `openai` \| `claude` \| `none`（供前端按钮禁用 / 提示文案判断） |

> 解析链复用设置服务既有语义（openai 协议槽位优先，DB → .env）；无 openai key 时 key/endpoint/model 均为空串，只读查询不报错（非 404/401）。

### 导入模拟器

```
POST /api/simulators/import
```

multipart 表单字段 `file`（单文件 `.html`）上传第三方模拟器游戏到数据目录（T-02 外置：`CONVER_DATA_DIR` 可覆盖，默认 `%APPDATA%\ConverSystem\simulators\`）。处理链：校验（.html / ≤5MB / 非空）→ 文件名净化（`sanitize_filename` 剔非法字符与 `%`/`#`）→ SHA-256 去重 → 冲突改名 `xxx-2.html` 递增 → cfg- 配置三元组探测 → 恶意模式静态粗筛（eval / document.cookie / cross-origin-fetch，命中仅警告不拦截）→ manifest 原子注册（缺失/损坏自愈重建）。

**响应** `200`

```json
{
  "ok": true,
  "game": { "id": "<game-id>", "file": "xxx.html", "name": "游戏名", "type": "类型", "config": {} },
  "renamed": false,
  "warnings": []
}
```

| 字段 | 说明 |
|------|------|
| game | 注册后的游戏条目（manifest 原子注册产物；config 为 cfg- 探测到的配置三元组，无则缺省） |
| renamed | 文件名冲突时是否已自动改名为 `xxx-2.html` 递增后缀 |
| warnings | 恶意模式粗筛命中集 ∈ `eval` \| `document.cookie` \| `cross-origin-fetch`（知情提示，不拦截导入） |

**错误** `400` — 非 .html / 超过 5MB / 空文件（detail 为可读原因）；`409` — SHA-256 内容与已有游戏重复（detail 含「已存在」）；`500` — 落盘失败（如数据目录不可写）。

---

## 错误响应格式

所有错误统一返回:

```json
{
  "detail": "错误描述信息"
}
```

| HTTP 状态码 | 含义 |
|-------------|------|
| 200 | 成功 |
| 201 | 创建成功 |
| 204 | 删除成功（无内容） |
| 400 | 请求参数错误 |
| 401 | API Key 无效或未配置 |
| 404 | 资源不存在 |
| 422 | 请求体验证失败 / 角色卡导入失败 |
| 429 | LLM API 请求频率超限 |
| 500 | 服务器内部错误 |
| 502 | LLM API 调用失败 |
| 504 | LLM API 请求超时 |
