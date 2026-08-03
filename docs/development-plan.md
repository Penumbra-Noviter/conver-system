# 开发路线图

## 阶段总览

| Phase | 名称 | 产出 | 预计工作量 |
|-------|------|------|-----------|
| 1 | 项目骨架 | 可运行的空壳（FastAPI + 数据库 + 前端布局） | ★☆☆ |
| 2 | 角色管理 | 角色 CRUD + 前端管理界面 | ★☆☆ |
| 3 | 对话核心 | **能聊天** — LLM 接入 + 聊天 UI + 流式输出 | ★★★ |
| 4 | 多模型支持 | 模型切换 + API Key 管理 | ★★☆ |
| 5 | 体验完善 | 对话历史、UI 美化、快捷键 | ★★☆ |
| 6 | 增强功能 | 导出、桌面版、搜索等（按需） | ★☆☆ |

每个 Phase 完成时都可以独立运行和测试。

---

## Phase 1 — 项目骨架

> 目标：搭建好项目基础结构，能启动服务并看到空白页面

### 后端

- [ ] 创建项目目录结构
- [ ] 编写 `requirements.txt`（依赖清单）
- [ ] 编写 `.env.example`（环境变量模板）
- [ ] 实现 `config.py`（pydantic-settings 配置）
- [ ] 实现 `database.py`（SQLAlchemy 引擎 + Session）
- [ ] 定义所有 ORM 模型（character / conversation / message / settings）
- [ ] 实现 `main.py`（FastAPI 应用入口 + 静态文件挂载 + 数据库初始化）
- [ ] 创建 `api/deps.py`（依赖注入）

### 前端

- [ ] 编写 `index.html`（SPA 基础布局：侧栏 + 主内容区 + 设置面板）
- [ ] 编写 `css/style.css`（CSS 自定义变量主题、基础样式）
- [ ] 编写 `js/app.js`（空壳：基础状态 + 事件绑定）
- [ ] 编写 `js/api.js`（API 调用层骨架）

### 验证

- [ ] `uvicorn` 启动无报错
- [ ] `http://localhost:8000/docs` Swagger 正常
- [ ] `http://localhost:8000` 前端页面正常加载
- [ ] `conver_system.db` 自动创建且表结构正确

---

## Phase 2 — 角色管理

> 目标：可以创建、编辑、删除角色，设好 personality

### 后端

- [ ] 实现 `schemas/character.py`（Pydantic 请求/响应模型）
- [ ] 实现 `services/character.py`（角色 CRUD 业务逻辑）
- [ ] 实现 `api/routes/characters.py`（角色 REST 接口）

### 前端

- [ ] 实现 `components/character-manager.js`（角色列表 + 创建/编辑表单 + 删除确认）
- [ ] 侧栏渲染角色列表
- [ ] 角色表单（name, personality 多行文本区, greeting, temperature 滑块）
- [ ] 删除角色确认对话框

### 验证

- [ ] Swagger 中角色 CRUD 接口正常
- [ ] 前端角色列表展示
- [ ] 创建角色成功
- [ ] 编辑保存后字段更新
- [ ] 删除后列表移除

---

## Phase 3 — 对话核心 ⭐

> 目标：**能真正聊天** — 这个阶段是整个项目的核心

### 后端

- [ ] 实现 `services/llm/base.py`（BaseLLM 抽象基类）
- [ ] 实现 `services/llm/claude.py`（Claude Provider）
- [ ] 实现 `services/llm/errors.py`（异常定义）
- [ ] 实现 `services/llm/factory.py`（Provider 工厂）
- [ ] 实现 `services/llm/__init__.py`（注册 Provider）
- [ ] 实现 `schemas/conversation.py` + `services/conversation.py`
- [ ] 实现 `schemas/message.py` + `services/message.py`（含聊天逻辑）
- [ ] 实现 `api/routes/conversations.py`（对话 CRUD）
- [ ] 实现聊天接口: `POST /api/chats`（非流式）
- [ ] 实现聊天接口: `POST /api/chats/stream`（SSE 流式）

### 前端

- [ ] 实现 `components/conversation-list.js`（对话列表）
- [ ] 实现 `components/chat.js`：
  - 消息气泡渲染
  - 输入框（自动调整高度）
  - 发送交互
  - 流式打字机效果

### 验证

- [ ] 选择角色 → 创建对话 → 发送消息 → 获得 AI 回复
- [ ] 流式输出逐字显示
- [ ] 刷新页面后历史消息保留
- [ ] 切换角色后对话隔离

---

## Phase 4 — 多模型支持

> 目标：可以在不同模型间自由切换

### 后端

- [ ] 实现 `services/llm/openai.py`（OpenAI Provider，含 `base_url` 兼容）
- [ ] 在 Factory 中注册 OpenAI
- [ ] 实现 `api/routes/models.py`（返回可用模型列表）
- [ ] 实现 `api/routes/settings.py`（API Key + 默认配置管理）
- [ ] 对话支持 `model_provider` + `model_name` 字段

### 前端

- [ ] 实现 `components/settings.js`：
  - API Key 输入框（Claude / OpenAI）
  - 默认 Provider 和模型选择
  - 保存按钮
- [ ] 对话创建/切换时可选模型
- [ ] 当前对话使用的模型标识展示

### 验证

- [ ] 配置 Claude API Key → 能用 Claude 聊天
- [ ] 配置 OpenAI API Key → 能用 GPT 聊天
- [ ] 同一角色不同模型分别对话
- [ ] API Key 持久化（重启后保留）

---

## Phase 5 — 体验完善

> 目标：让用起来顺手

### 核心任务

- [ ] 对话历史管理：列表浏览、重命名、删除、清空
- [ ] 选择角色后自动创建对话 + 触发 greeting
- [ ] 发送快捷键（Enter 发送、Shift+Enter 换行）
- [ ] 消息加载动画 / 状态指示器
- [ ] UI 主题配色打磨（亮/暗模式）
- [ ] 响应式布局（至少桌面 + 平板可用）
- [ ] 对话列表按时间排序（最新的靠前）

### 细节体验

- [ ] 空状态展示（没有角色时提示创建、没有对话时提示开始聊天）
- [ ] 角色头像显示（默认用首字母头像）
- [ ] 消息自动滚动到底部
- [ ] 网络/API 错误提示

---

## Phase 6 — 增强功能（按需推进）

> 目标：锦上添花，有兴趣时做

### 功能候选

- [ ] 对话导出为 Markdown / JSON
- [ ] 角色人设导入/导出（分享角色）
- [ ] 多 Tab 会话管理（同时开多个对话）
- [ ] 历史消息搜索
- [ ] 消息重新生成（重新生成 AI 回复）
- [x] Prompt 模板变量（`{{user}}`、`{{char}}` 等动态插入）
- [ ] 角色 personality 提示词模板库
- [ ] 对话 token 用量统计
- [ ] Tauri 桌面版封装
