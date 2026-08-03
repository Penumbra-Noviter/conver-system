# Conver System — 可执行任务清单 (TICKETS)

> 规则：本文件是**仓库内唯一的待办事实来源**。活跃表只保留「未完成」工单；每完成一项 → 移入「已完成归档」并记完成日期（+提交哈希）→ 同步 [DEV_LOG.md](DEV_LOG.md) → 与本提交一起 commit。
>
> 维护节奏（绑定现有流程节点，不新增习惯）：
> 1. 开始实现某工单前：📝 已录入 → 🔄 进行中（认领）
> 2. 每会话结束、commit 之前：完成 → ✅/❌ → 移入归档；新评审候选（含未拍板的 `Worth exploring` / `Speculative`）立即录入活跃表
> 3. 待办**不得写在 memory / DEV_LOG / 个人笔记里**——不落 TICKETS 就不算数
>
> 状态：⬜ 待办 | 🔄 进行中 | ✅ 完成

---

## 活跃工单

### P2.5 SillyTavern V2 导入/导出 🔄 进行中

> 立项完成 2026-08-03 — 详见 `docs/p2.5-character-import-export.md`
> 决策：仅 JSON 卡（D1）｜V2+裸data+V1 兼容导入（D2）｜重名直接新建（D3）｜头部导入+卡片导出（D4）｜extensions.conver_system 保真（D5）｜手动创建完整性引导（D6）

- [ ] **P2.5.6** 手动创建完整性引导 — character-form.js 软提示（姓名+人格+开场白缺项提醒，保存前汇总提示可跳过，仅手动表单；导入路径不参与）（spec §5.3 / D6）
- [ ] **P2.5.7** 转换层单元测试（V2 往返 / V1 归一化 / 裸 data / 非法卡 422 / 头像三形态）
- [ ] **P2.5.8** 文档同步 + 打包验证（CONSENSUS/TICKETS/DEV_LOG + 前端全流程手测）

### P3.5 对话过程交互增强 📝 已立项 2026-08-03（grill → to-spec 完成，规格见 CONSENSUS §4/§6）

- [ ] **停止生成按钮**（仅流式）— 后端 `api/routes/chat.py:stream_chat` 的 `event_generator` 接收 `request`，token 循环轮询 `request.is_disconnected()`，客户端断开时停止 LLM 调用并**保存已生成部分**为 assistant 消息；前端 `api.js:chatStream()` 支持 `AbortController.signal` 返回 abort 句柄，流式生成中发送按钮两态变身（`➤` → `⏹ 停止`），气泡标记「（已停止）」非错误
- [ ] **对话标题自动生成** — 后端 `create_conversation` 未传 title 时默认「与 {角色名} 的对话」；新增标题截断纯函数（折叠空白 + 截取 20 字 + 「…」，不剥离 Markdown）；保存首条 user 消息时若标题仍为占位默认值则同步替换；前端 `startChatWithCharacter` 移除 `title: '新对话'` 硬编码

### P4.3 增强（待后续）

- [ ] API Key 验证（保存时测试连接）

### P6.4 Tauri 桌面版

- [ ] Tauri 项目初始化
- [ ] Rust 后端作为 FastAPI 壳/替代
- [ ] 系统托盘 / 开机自启

### P6.5 其他

- [ ] 多 tab 会话管理
- [ ] Ollama 本地模型支持

### P0 手动项（非代码）

- [ ] 填写 API Key（用户手动填入 `.env` 模板 / 设置面板）
- [ ] 手动访问 http://localhost:8000/docs 与首页确认 Swagger / 前端加载正常

---

## 已完成归档

### Phase 0-5 + P6.1-6.3（2026-07-30，初始 commit `b5fe037`）

| 阶段 | 内容 | 完成日期 | 提交 |
|------|------|----------|------|
| Phase 0 | 基础设施（P0.1 `.env` 模板 / P0.2 依赖 / P0.4 启动验证；P0.3 Git 按决策暂缓） | 2026-07-30 | `b5fe037` |
| Phase 1 | 项目骨架（后端 8 模块 + 前端 4 文件） | 2026-07-30 | `b5fe037` |
| Phase 2 | 角色管理前端（P2.1 表单 / P2.2 编辑 / P2.3 删除确认 / P2.4 卡片增强） | 2026-07-30 | `b5fe037` |
| Phase 3 | 对话核心（P3.1 Claude Provider / P3.2 聊天 API / P3.3 上下文管理 / P3.4 流式渲染） | 2026-07-30 | `b5fe037` |
| Phase 4 | 多模型（P4.1 OpenAI Provider / P4.2 模型切换 UI / P4.4 Provider 路由） | 2026-07-30 | `b5fe037` |
| Phase 5 | 体验完善（P5.1 历史管理 / P5.2 UI-UX / P5.3 主题视觉 / P5.4 设置面板） | 2026-07-30 | `b5fe037` |
| P6.1 | 对话导出（JSON+Markdown API + 前端导出弹窗） | 2026-07-30 | `b5fe037` |
| P6.2 | 搜索历史消息（API + 前端搜索视图） | 2026-07-30 | `b5fe037` |
| P6.3 | Prompt 模板变量（`{{user}}`/`{{char}}`） | 2026-07-30 | `b5fe037` |

### Code Review — CR 项（2026-07-30 ~ 2026-08-03 全部清零）

> 两轮审计均在 `b5fe037` 前完成；CR.4 编号在初轮（死代码）与 Phase5 轮（严重 Bug）共用，此处保留原始标签便于对照。

| CR | 标题 | 完成日期 | 提交 |
|----|------|----------|------|
| CR.1 | 初轮严重 Bug：滑窗轮数不生效 + SSE 错误前端静默丢弃 | 2026-07-30 | `b5fe037` |
| CR.3.3 | 路由层 LLM 错误映射抽取 `_LLM_ERROR_MAP` | 2026-07-30 | `b5fe037` |
| CR.4.1 (Phase5) | SSE 流中断 → 按钮永久禁用 | 2026-07-30 | `b5fe037` |
| CR.4.2 (Phase5) | V2 字段未用于 prompt 组装 | 2026-07-30 | `b5fe037` |
| CR.4.3 (Phase5) | theme_mode 设置不生效 | 2026-07-30 | `b5fe037` |
| CR.8 | 流式消息计数短暂不准确 | 2026-07-30 | `b5fe037` |
| CR.9 | 数据加载无用户可见错误（toast） | 2026-07-30 | `b5fe037` |
| CR.10 | 范围蔓延标记更新（P5.1 / P4.2 / P5.2） | 2026-07-30 | `b5fe037` |
| CR.2 | 硬性违规：类型注解 / 命名 / 局部导入 / 旧式 typing（3/4 复核确认已就绪） | 2026-08-03 | `7d892ed` |
| CR.3.1 + CR.6.4 | 删除 deps.py 浅模块，路由直连 get_db | 2026-08-03 | `ad141fb` |
| CR.6.1 + CR.3.2 + CR.4.1(初轮) | `_prepare_chat` 抽取 / `_translate_error` / stream 死代码复核 | 2026-08-03 | `0d2edbb` |
| CR.5.1 + CR.5.2 | 27+ 处类型注解补齐；`/api/chat` → `/api/chats` | 2026-08-03 | `fa1f411` |
| CR.5.5 + CR.7 | 默认模型回退链重构（`model_fields_set`） | 2026-08-03 | `fa1f411` |
| CR.6.2 | 前端头像 / 复制按钮构造去重 | 2026-08-03 | `ef56fbf` |
| CR.5.3 + CR.5.4 | `stream_*` 前缀决策；`save_message` → `create_message` | 2026-08-03 | `6bdb1ca` |
| CR.6.3 | Character JSON 列 + Message.role 枚举 | 2026-08-03 | `6bdb1ca` |
| CR.6.5 | messages.py 职责分离（chat.py 拆出） | 2026-08-03 | `6bdb1ca` |

### P2.5.1-5.5（2026-08-03，本提交）

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| P2.5.1 | 后端转换层 `services/character_card.py`（to_v2_card / from_v2_card） | 2026-08-03 | 本提交 |
| P2.5.2 | 导出 API `GET /api/characters/{id}/export` | 2026-08-03 | 本提交 |
| P2.5.3 | 导入 API `POST /api/characters/import` | 2026-08-03 | 本提交 |
| P2.5.4 | 前端导入 UI（「导入角色」按钮 + toast） | 2026-08-03 | 本提交 |
| P2.5.5 | 前端导出 UI（📤 卡片按钮 + `downloadBlob` 复用） | 2026-08-03 | 本提交 |

---

> 创建者: to-tickets 阶段 (2026-07-30) · 本文件维护规则见 [docs/documentation-standards.md](docs/documentation-standards.md)
