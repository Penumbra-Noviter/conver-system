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

### P6.4 Tauri 桌面版

- [ ] Tauri 项目初始化
- [ ] Rust 后端作为 FastAPI 壳/替代
- [ ] 系统托盘 / 开机自启

> ⚠️ Ollama 本地模型支持 — **已封存**（2026-08-03 用户决定：发布获得用户反馈后再考虑）

---

## 已完成归档

### OPT-1 UI 克制化与图标协议收口（2026-08-11）

> 保留 Warm Stone 与现有应用壳，统一动态 SVG 图标 seam + emoji 清除 + 主题 token 单一来源；四轴 code-review + GUI 黑盒回归全部完成。GUI 验证发现 1 条 CSS 回归（错误气泡警示样式被后置 `.message.assistant .message-content` 顶层规则覆盖）→ 特异性修复（`message.assistant.message-error`）。验证采用本地 mock SSE（网络层拦截，未触发真实外部 API）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| OPT-1 | UI 克制化：`icons.js` 图标 seam（Object.hasOwn + 白名单防注入）、emoji 清除（用户数据保留）、深浅主题 token 单一来源、复制反馈竞态修复（WeakMap）；Vitest 186 + pytest 188 全绿；GUI 验证：375px 无横向滚动 / 侧栏折叠展开 / 多 tab 流式停止·错误·复制反馈 全过 | 2026-08-11 | `8ce17bd` |
| OPT-1-FIX | 错误气泡警示样式回归：CSS 顶层 `.message.assistant .message-content`（`background:transparent`）覆盖 `.message.message-error` → 特异性 (0,4,0) 修复，深浅主题 GUI 复验通过 | 2026-08-11 | （见提交） |

> ✅ **安全项（已结案 2026-08-11）**：GUI 自动化曾读取到本机库中真实 API Key 前缀（sk-1ZET…）；用户确认该 Key **早已过期**，无需轮换，停止读取约束继续保持。

### 架构深化 8 候选（2026-08-10，improve-codebase-architecture 全自动 kickoff）

> 两波并行（波 1：ARC-1/2/3/4；波 2：ARC-5/6/7/8，均文件互斥 worktree），期末三轴 code-review 放行 + 修复（`b78db1c`）。P6.5-R1~R3 候选由 ARC-4/ARC-1/ARC-5 分别关闭。规格决策已并入本归档与 DEV_LOG。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| ARC-1 | StreamSession 流式回合结算深模块：createStreamSession 状态机 + mergeFreshList 三分支（anchor 引用定位，stale 失配回退写回——兑现消息不丢失，根治 R2）；chat.js 变 DOM 适配器；40 用例、覆盖率 100%/97.9% | 2026-08-10 | `aba8335` |
| ARC-2 | doomed-tab 级联收口：tabs.js `closeTabs` 批量原语 + app.js `closeConversationsAndResettle`（仅 wasActive 重激活，消除 4 处手写分歧）；+10 用例 | 2026-08-10 | `3512378` |
| ARC-3 | 对话标题策略收口：message.py `_auto_title_on_first_user_message` → conversation.py `maybe_auto_title`（逐行等价迁移）；+5 pytest | 2026-08-10 | `522e88c` |
| ARC-4 | api.js seam 收口：`requestBlob` 走 doFetch seam + Content-Disposition 解析 + request/requestBlob 可选超时（关 R1）；+9 用例 | 2026-08-10 | `daa1e13` |
| ARC-5 | 展示契约 `getTabDisplay`（title/phase/generating/errored 纯派生），tab-bar 只消费契约（消隐 DISPLAY_KEYS 与 render 双清单漂移，关 R3）；+2 用例 | 2026-08-10 | `be1b3c8` |
| ARC-6 | app.js 拆分：渲染模板纯函数化（format.js characterCardHtml/conversationItemHtml/searchResultItemHtml）+ 激活编排深模块 conversation-activation.js（F-2 守卫/草稿滚动/懒加载，setActivationHooks 注入）；+19 用例 | 2026-08-10 | `c00c8f5` |
| ARC-7 | testApiKeys 轻量下沉：`resolveCredentialTarget` 纯函数（同协议优先→跨协议兜底，交叉引用后端 _slot_value）；+5 用例 | 2026-08-10 | `231370e` |
| ARC-8 | services/schemas `__init__.py` `__all__` 深模块清单（不 re-export，docstring 指 CONTEXT）+ 包导出冒烟测试 | 2026-08-10 | `432d89b` |

### P6.5 多 tab 会话管理（2026-08-10）

> 应用内多会话工作区：tab 条切换、后台流式继续生成、完成/停止/出错按发起时捕获的 conversation id 写回、刷新后按 sessionStorage 恢复。12 项共识决策见 CONSENSUS §11。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| P6.5-1 | tabs 工作区状态深模块 + 单测：openTab/activateTab/closeTab/closeAllTabs/getActiveTab/getTab/getTabs/updateTab/serialize/restore/onTabsChanged；updateTab 幂等 no-op；32 用例、覆盖率 99%/96.6% | 2026-08-10 | `4cc4c2e` |
| P6.5-2 | state.js 会话级字段退役 + 活动 tab 派生改造：三入口收敛统一激活流程；流式防悬挂（onToken 活动归属分流 + onDone/onError 按捕获 id 写回）；停止写回 phase error + 「已停止」语义；删除会话/清空联动 | 2026-08-10 | `089de63` |
| P6.5-3 | tab 条 UI：`components/tab-bar.js` presentational 组件（注入激活处理器 + ✕ 直接 closeTab 含 abort）；脉冲点/警示标记指示；<768px 隐藏 | 2026-08-10 | `f71dffc` |
| P6.5-4 | 标题同步 + sessionStorage 恢复 + 空态：`restoreFromStorage` 集成辅助（损坏/无记录/全失效 → 空集）；init 在 conversations 加载后恢复；重命名/自动标题联动 tab | 2026-08-10 | `c4c2fd3` |
| P6.5-5 | GUI 回归 + 文档归档：jsdom 冒烟 81 项全过（无 JS 错误）；Vitest 69 + pytest 181 全绿；TICKETS/DEV_LOG/CONSENSUS 归档 | 2026-08-10 | `811645e` |


### GUI 全功能验证修复（2026-08-09）

> Playwright 黑盒测试（P0-P3 全级别 + vision 视觉核验）发现 4 个 bug，全部修复：复现测试先行（pytest +3 / vitest +5），GUI 回归逐项确认。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| FIX-1 | 停止生成的部分内容未落库：`stream_reply` finally 兜底保存（GeneratorExit/CancelledError 路径）+ saved 防重标志；+1 复现测试（aclose 模拟 Starlette 取消） | 2026-08-09 | `eaf3456` |
| FIX-2 | 对话 JSON 导出 500：Content-Disposition 中文文件名 latin-1 编码失败 → RFC 5987（filename ASCII + filename*=UTF-8''）；+2 复现测试 | 2026-08-09 | `eaf3456` |
| FIX-3 | 聊天头部模型 badge provider 显示错误：`providerDisplayName()` 纯函数替代硬编码二元映射（deepseek 误显示 Claude）；+5 vitest 用例 | 2026-08-09 | `eaf3456` |
| FIX-4 | 移动端 480px 布局错乱：对话列表默认收起（display:none + .mobile-expanded 类切换）、.chat-messages min-height:0 防撑高、隐藏冗余收起按钮、删 convListVisible 死代码 | 2026-08-09 | `eaf3456` |

### GUI 观察项修复 ①-④（2026-08-09）

> GUI 验证报告的 4 个观察项评估后全部值得修；前端 ①②④ 与后端 ③ 子代理并行落地，GUI 回归逐项确认。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| OBS-1 | greeting 开场白首轮发送后不显示：chat.js 发送完成路径改为重载消息列表（流式 onDone / 非流式；停止路径保留「已停止」标记） | 2026-08-09 | `dd1d07d` |
| OBS-2 | 错误气泡无错误样式：`.message-error` 类 + `--danger-bg/--danger-text` CSS 变量（红字红框，深浅主题适配） | 2026-08-09 | `dd1d07d` |
| OBS-3 | MD 导出保留 {{char}}/{{user}} 字面量：export_conversation_markdown 复用 apply_template_vars 替换（JSON/角色卡导出保留原始设定为有意设计）；+4 复现测试（含 JSON 防回归） | 2026-08-09 | `dd1d07d` |
| OBS-4 | 角色卡片操作按钮 emoji：4 按钮换 inline SVG（作用域 .character-card-actions .btn-icon svg 16px） | 2026-08-09 | `dd1d07d` |

### 导入路径错误引导（2026-08-09）

> 角色卡导入失败只有原因提示、无修正引导（与 LLM 解析路径「请重试或手动创建」不一致）→ 后端错误消息带支持格式说明 + 前端失败后引导到创建向导。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| IMP-1 | 导入失败引导：后端 `_IMPORT_FORMAT_HINT`（V2 spec=chara_card_v2 / data 信封 / 裸 data / V1 旧卡 + 向导指引）追加到 CardFormatError 的 422 detail（CardValidationError 保持纯原因）；前端 `promptUseWizardAfterImportFail()` 失败后弹「是否改用创建向导？」→ 打开向导；+3 路由层测试 | 2026-08-09 | `beec1a5` |


### 架构摩擦分析 11 候选（第三轮收官，2026-08-05）

> 依据 architecture-review 报告（/improve-codebase-architecture）候选 ①–⑪ 全部落地。
> 行为逐项保持，双端测试全绿（pytest 141 + Vitest 32）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| ① | 设置面板提取：`components/settings-panel.js`（协议表面 initSettingsPanel/loadSettings/initProviderDropdown）；app.js 1050→~700 行 | 2026-08-05 | `a69c53e` |
| ② | 模型选择逻辑统一：`utils/model-utils.js`（fillModelSelect/createCustomModelHandler），settings-panel 与 model-selector 共享 | 2026-08-05 | `a69c53e` |
| ③ | Provider 标识符重构：key/id 分离（8 provider 唯一 key），前端 value 用 key，data-index 退役；factory 注册第三方；setting 经 _PROVIDER_API_MAP 映射存储键 | 2026-08-05 | `429b075` |
| ④ | 服务层异常解耦：`services/exceptions.py` 领域异常替换 HTTPException，路由层 _prepare_or_raise 转换 | 2026-08-05 | `abd8920` |
| ⑤ | 模型数据迁移：`services/model_data.py`，路由 131→18 行纯化 | 2026-08-05 | `429b075` |
| ⑥ | state.js 职责收缩：convListVisible/searchTimeout 移入 app.js | 2026-08-05 | `a69c53e` |
| ⑦ | BaseLLM 死代码清理：移除无调用方 provider_name 抽象属性 | 2026-08-05 | `29da016` |
| ⑧ | 角色卡异常层次：CardFormatError/CardValidationError 精确捕获，路由转 422 | 2026-08-05 | `abd8920` |
| ⑨ | SSE 流解析器提取：`utils/sse-reader.js` parseSSEStream 纯函数 + 4 用例 | 2026-08-05 | `a69c53e` |
| ⑩ | 查询逻辑 DRY：`_base_character_query` + `_attach_count` | 2026-08-05 | `29da016` |
| ⑪ | 静态文件路由冲突：/ 挂载点注册顺序契约注释 | 2026-08-05 | `29da016` |

### 架构深化候选 ②③④⑤（第二轮收官，2026-08-03）

> 并行两路落地：后端路（②④）收拢导出 + 搜索结果 Schema；前端路（③⑤）模态框抽象 + Vitest 测试基建。前端 ③⑤ 共用 `app.js` 故在同一代理内串行，后端 ②④ 共享 response_model/序列化约定在同一代理内串行。行为逐项保持，双端测试全绿（pytest 141 + npm 28）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| ② | 抽 `services/conversation_export.py` 收拢导出逻辑：`export_conversation_json` / `export_conversation_markdown` 迁入新深模块（`__all__` 仅两函数）；conversation.py 257→134 行；角色字段提取**不复用手写字段列表**，改由新增 `ConversationExportCharacter` Schema（`from_attributes=True`，9 字段）唯一驱动；路由 import 改走 `export_service` | 2026-08-03 | `8098114` |
| ③ | 抽 `components/modal.js` 通用模态框工厂 `openModal`（遮罩/标题转义/body/actions/关闭三路径/结果回传）；`showConfirm`/`showAlert` 对外 API 不变、内部复用工厂；`showModelSelector`/`createExportDialog` 迁入 `model-selector.js`/`export-dialog.js`，函数体从 app.js 删除；`downloadBlob`/`showToast` 移入 utils.js（解 app.js↔组件循环依赖）；app.js 1080→864 行；Playwright 冒烟三弹窗开合正常、无 JS 错误 | 2026-08-03 | `8098114` |
| ④ | 搜索结果走 Schema：`message.py::search_messages` 返回 `list[dict]` → `list[SearchResult]`（9 字段与旧 dict 契约逐字段一致，role `.value`/created_at isoformat）；路由 `GET /api/messages/search` 声明 `response_model=list[SearchResult]`；空 query 返回 `[]` | 2026-08-03 | `8098114` |

### UI 重设计（2026-08-04）

> Linear 设计语言全面重写 CSS，非 Ticket 驱动的一次性视觉改进。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| — | Linear 设计语言 UI 重设计：深色产品 UI + 薰衣草蓝 accent；Token 化设计系统、surface 4 层阶梯、hairline 边框、skeleton 骨架屏；0 行 JS 修改；code-review 8 项问题全部修复 | 2026-08-04 | `f83ec2f` |
| ⑤ | 前端测试基础设施：Vitest ^3 + jsdom ^26（`frontend/package.json` `"type":"module"` + `"test":"vitest run"` + `vitest.config.js`）；纯函数模块 `format.js`（`highlightText`/`buildMessagesHtml`/头像 HTML）从 DOM 分离；`renderMessages` 改 `innerHTML=buildMessagesHtml(...)`；api.js 注入 `setFetch` seam（`doFetch` 默认 `globalThis.fetch`）；`.gitignore` 补 `node_modules/`；28 用例全过（format 15 / utils 8 / api 5） | 2026-08-03 | `8098114` |

### 架构深化候选 ①②⑥（2026-08-03）

> 依据架构评审（候选 ① 聊天回合 / ② 运行时设置 / ⑥ Provider 注册显式化）把两大概念沉淀为单一所有权的**深模块**，并消除 import 副作用。候选 ③⑤ 后续批次落地（见下方「架构深化候选 ③⑤」），候选 ④ 后续落地（见下方「架构深化候选 ④」）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| ① | 抽 `services/chat.py` 聊天回合深模块：`ChatContext` / `prepare_chat` / `llm_error_response` / `stream_reply`；路由层仅留 HTTP 映射 + SSE `data:` 帧包装（已接受「service 层带 HTTPException 原样上移」取舍） | 2026-08-03 | `25bf5a4` |
| ② | 抽 `services/setting.py` 运行时设置深模块：读 / 写 / 白名单 / 默认回退链 / 整型容错（防 500）收口 | 2026-08-03 | `25bf5a4` |
| ⑥ | Provider 注册显式化：`main.py` on_startup 调 `register_builtin_providers()`，`factory.py` 懒加载兜底，去 import 副作用 | 2026-08-03 | `25bf5a4` |

### 架构深化候选 ③⑤（2026-08-03）

> Prompt 组装纯函数化（③）与前端 app.js 拆分（⑤）并行落地。③ 把 Prompt 组装从 `message.py` 抽离为纯函数模块（去 db 依赖，独立可测）；⑤ 把 1380 行 `app.js` 拆为 `chat.js` + `state.js`，行为保持机械重构，Playwright 冒烟通过。候选 ④ 后续落地（见下方「架构深化候选 ④」）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| ③ | 抽 `services/llm/prompt.py` 纯函数化 Prompt 组装：`CharacterData` frozen dataclass + `apply_template_vars` / `parse_mes_example` / `build_messages` 纯函数；`message.py::build_message_list` 签名与行为不变（查角色+查历史→委托纯函数）；26 项单测，新模块 100% 行覆盖 | 2026-08-03 | `98e0c29` |
| ⑤ | 前端 `app.js` 拆分（1380→1080 行）：`js/state.js`（全局状态+模块级状态，54 行）、`js/chat.js`（聊天域渲染+交互+chatDom，328 行，通过 `setConversationsRefresher` 钩子避免反向依赖）；`index.html` 无变更（ESM 内部 import）；Playwright 冒烟通过，无 JS 错误 | 2026-08-03 | `98e0c29` |

### 架构深化候选 ④（2026-08-03）

> 线上形状统一：`response_model` 驱动序列化，退役 service 层手写 dict（character + conversation）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| ④ | 退役 service 层手写 dict，由 FastAPI `response_model=*(from_attributes=True)` 统一驱动序列化：`character.py::_char_to_dict` 删除（`list_characters`/`get_character_with_count` 返回 ORM 对象 + 瞬态 `conversation_count`）；`conversation.py::list_conversations` 返回 `list[dict]`→`list[Conversation]` + 瞬态 `message_count`（13 行手写映射删除，第二轮评审候选 ①）；schema/路由已就绪零改动。消除字段列表重复维护，后端所有 list 端点不再有手写 dict | 2026-08-03 | `5ee1ba8` |

### Phase 0-5 + P6.1-6.3（2026-07-30，初始 commit `b5fe037`）

| 阶段 | 内容 | 完成日期 | 提交 |
|------|------|----------|------|
| Phase 0 | 基础设施（P0.1 `.env` 模板 / P0.2 依赖 / P0.4 启动验证；P0.3 Git 按决策暂缓） | 2026-07-30 | `b5fe037` |
| Phase 1 | 项目骨架（后端 8 模块 + 前端 4 文件） | 2026-07-30 | `b5fe037` |

> **P0 手动项（非代码，2026-08-03 归档）**：填写 API Key（P4.3 设置面板 + 保存时测试连接已完成）；手动访问 `/docs` 与首页确认（Phase 0 P0.4 验收，已在 `b5fe037` 完成）。
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

### 文档/测试专项审查 CR（2026-08-03，双轴 code-review）

> 依据《文档规范》单点原则 + 防漂移速查的专项审查。双轴：Standards（规范符合度）+ Spec（文档/测试与代码一致性）。全部在本次会话修复归档。

| CR | 标题 | 完成日期 | 提交 |
|----|------|----------|------|
| CR-D1 | `api-design.md` 契约漂移：`greeting`→`first_mes` + V2 字段；conversation 响应去 `character_name`；模型列表补 `claude-opus-4-8`/`gpt-4-turbo`；补 6 个缺失端点（角色 import/export、对话 export json/markdown、`DELETE /api/conversations`、消息 search、settings test-connection）；settings 键补全；错误码补 401/429/504 | 2026-08-03 | `8259266` |
| CR-D2 | `architecture.md` 漂移：`/api/convs`→`/api/conversations`；角色表补 V2 全列；目录树补 `models/setting.py`/`schemas/settings.py`/`services/character_card.py`/前端组件/`tests`；数据流同步 `build_message_list` | 2026-08-03 | `8259266` |
| CR-D3 | `llm-integration.md` 过时：`generate_reply`→`build_message_list`；BaseLLM 签名 + `test_connection`；Factory 带 `base_url`；Prompt 构建/滑窗策略；新 Provider 添加步骤对齐代码 | 2026-08-03 | `8259266` |
| CR-D4 | `p2.5` 规格偏差闭环：§4.2 `get_character_with_count`→`get_character`（DEV_LOG 已记偏差但规格文档未同步） | 2026-08-03 | `8259266` |
| CR-D5 | 测试规范整改：`db_session` fixture 移入 `conftest.py`（消除 test_p35 / test_settings_connection 重复副本）+ 清理失效 import | 2026-08-03 | `8259266` |
| CR-D6 | 文档规范强化：`documentation-standards.md` 新增 §三 测试规范（共享 fixture / 覆盖率声明可复现 / 测试数同步）+ §六 防漂移新增 4 检查项（契约完整性 / 字段名以 schema 为准 / 规格偏差闭环 / 覆盖率有产物） | 2026-08-03 | `8259266` |
| CR-D7 | 杂项清理：`CONSENSUS` 更新记录补 2026-08-03；TICKETS P0 手动项归档；`character_card` 100% 覆盖声明补可复现命令 | 2026-08-03 | `8259266` |

### P2.5.1-5.8（2026-08-03）

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| P2.5.1 | 后端转换层 `services/character_card.py`（to_v2_card / from_v2_card） | 2026-08-03 | `bb4e7ba` |
| P2.5.2 | 导出 API `GET /api/characters/{id}/export` | 2026-08-03 | `bb4e7ba` |
| P2.5.3 | 导入 API `POST /api/characters/import` | 2026-08-03 | `bb4e7ba` |
| P2.5.4 | 前端导入 UI（「导入角色」按钮 + toast） | 2026-08-03 | `bb4e7ba` |
| P2.5.5 | 前端导出 UI（📤 卡片按钮 + `downloadBlob` 复用） | 2026-08-03 | `bb4e7ba` |
| P2.5.6 | 手动创建完整性引导（字段缺项 badge + 保存前软确认，仅手动表单） | 2026-08-03 | `585e5f9` |
| P2.5.7 | 转换层单元测试（pytest 基础设施 + 53 用例 / character_card 100% 覆盖；修复 V1 description 丢失 + 裸 data temperature 兜底） | 2026-08-03 | `c5f014b` |
| P2.5.8 | 文档同步 + 打包验证（Playwright 前端全流程手测 + 文档归档） | 2026-08-03 | `5902ee2` |

### P3.5 对话过程交互增强（2026-08-03）

> 规格见 CONSENSUS §4（标题）+ §6（停止生成）；后端 19 项单测（`backend/tests/test_p35.py`）+ Playwright 前端验证（停止按钮两态 / 「已停止」标记 / 标题联动）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| P3.5.1 | 停止生成按钮（仅流式）：后端 `stream_chat` 轮询 `is_disconnected()` 停止 LLM 并保存部分内容；前端 `chatStream()` 返回 `{abort, done}`（AbortController），发送按钮两态变身（`➤` ⇄ `⏹ 停止`），气泡「（已停止）」非错误 | 2026-08-03 | `4053e38` |
| P3.5.2 | 对话标题自动生成：未传 title 默认「与 {角色名} 的对话」；`truncate_title` 规则截断纯函数；首条 user 消息同步替换占位标题；前端移除 `title:'新对话'` 硬编码 + 头部标题联动 | 2026-08-03 | `4053e38` |

### P4.3 API Key 保存时测试连接（2026-08-03）

> 单测 11 项（`backend/tests/test_settings_connection.py`，新增模块 100% 行覆盖）+ Playwright 前端验证（无效 Key 保存 → 确认框「仍然保存？」→ 保存完成）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| P4.3 | API Key 验证（保存时测试连接）：后端 `BaseLLM.test_connection()` 默认实现（最小请求 max_tokens=1）+ `POST /api/settings/test-connection` 端点（空 Key 回退已存值，失败 400 + 可读原因）；前端保存设置前并行测试已填 Key，失败弹确认框由用户决定是否继续保存 | 2026-08-03 | `c0b6505` |

---

> 创建者: to-tickets 阶段 (2026-07-30) · 本文件维护规则见 [docs/documentation-standards.md](docs/documentation-standards.md)
