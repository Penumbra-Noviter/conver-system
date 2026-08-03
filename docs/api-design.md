# API 接口设计

> 所有接口前缀 `/api`，请求和响应均为 JSON 格式。
> 后端启动后可通过 Swagger UI 交互测试: http://localhost:8000/docs

---

## 角色 API

### 获取角色列表

```
GET /api/characters
```

**响应** `200`
```json
[
  {
    "id": 1,
    "name": "林墨",
    "avatar": null,
    "personality": "你是林墨，一位流浪诗人...",
    "greeting": "你来了。正好，陪我喝一杯？",
    "temperature": 0.7,
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

**请求体**
```json
{
  "name": "林墨",
  "avatar": null,
  "personality": "你是林墨，一位流浪诗人...",
  "greeting": "你来了。正好，陪我喝一杯？",
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
    "character_name": "林墨",
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
        "claude-haiku-4-5-20251001"
      ]
    },
    {
      "id": "openai",
      "name": "OpenAI / 兼容 API",
      "models": [
        "gpt-4o",
        "gpt-4o-mini"
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
  "default_provider": "claude",
  "default_model": "claude-sonnet-4-20250514"
}
```

### 更新设置

```
PUT /api/settings
```

**请求体**
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
| 404 | 资源不存在 |
| 422 | 请求体验证失败 |
| 500 | 服务器内部错误 |
| 502 | LLM API 调用失败 |
