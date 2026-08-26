# UX 调研：Conver System 用户体验改进研究

> 调研方式：代码事实盘点（前端 JS 全模块 + 后端 routes 契约 + Tauri 壳源代码）+ 外部对标（一手官方资料，5 来源）。全程只读，未修改任何业务代码。
> 结论摘要：Conver 的工程韧性（防悬挂流式、错误兜底、状态机）远超同尺度产品，但 **UX 缺在「主路径的引导与闭环」**——无 Key 首启无引导、搜索跳转不定位到消息、对话内不能切模型/重生成。这三件事改动面小、价值最高，建议作为下一波迭代主题。

---

## 1. 产品现状速览

本地优先 AI 角色对话桌面应用（Tauri 壳 + FastAPI + Vanilla JS）。三大域：角色对话（多模型、多 tab 并行流式、搜索、模板变量）、模拟器（22 款文字游戏 iframe + AI 生成 + 第三方导入 + 存档管理）、设置。代码工程质量高：深模块拆分、注入钩子统一、流式状态机（`stream-session.js`）与级联删除（`cascade.js`）均做了防悬挂/幂等/竞态防护。但从「用户旅程」角度，产品更接近"功能齐备但缺少引导层"——空态文案、错误提示、首启路径没有形成对新用户的闭环指引，部分核心功能（搜索定位、模型切换）停在"能用"而没到"好用"。

---

## 2. 代码事实：UX 薄弱点清单（按影响力排序）

### P1. 首启无引导，无 API Key 时主路径在"首次发送"才失败
- **证据**：`frontend/js/app.js:193-231` `init()` 依次加载角色/对话/模型/设置，全程**不检查**是否已配置 API Key；入口视图是聊天空态 `index.html:136`「选择一个角色开始对话」，与"先配置 AI 接口"的真实前置条件脱节。
- **摩擦链**：新用户 角色→创建→开始对话（弹模型选择）→输入→发送 → 才在后端以 400 失败，错误以系统气泡形式展示 `frontend/js/chat.js:479` `发送失败: ${err.message}`（裸错误文案，无"去设置"引导）。
- **流式错误同理**：`frontend/js/stream-session.js:332` 把 `[错误] ${err.message}` 写成一条 **assistant 消息落进消息列表**（不可关闭、混入对话记录）。
- **建议方向**：init 后检测 `GET /settings/credentials` 三态（protocol ∈ openai/claude/none，契约见 `backend/app/api/routes/settings.py:30-39`）；none 态在聊天空态/角色页顶栏挂"先配置 AI 接口"引导卡 + 失败路径的展示改为可关闭错误条（不落消息列表）并附"前往设置"按钮。

### P2. 搜索跳转不定位到命中消息
- **证据**：`frontend/js/search-view.js:151-155` 点击结果只带 `conversationId` 调 `activateConversation`；`frontend/js/format.js:200` 采集了 `data-message-id` 但**无人消费**；`frontend/js/conversation-activation.js:79-107` `loadTabMessages` 激活后经 `chat.js:124` `scrollToBottom()` 永远滚到底——即"搜到结果 → 跳进对话顶部/底部，看不到命中消息"。
- **建议方向**：`activateConversation` 支持可选 `messageId`，加载后按 id 定位 `scrollIntoView` + 临时高亮（复用现有 `.search-highlight` 样式即可）。

### P3. 对话内无法切换模型，也无法重生成/编辑消息
- **证据**：模型只在创建对话时经 `model-selector` 弹窗选定一次（`frontend/js/list-views.js:245` 每次"开始对话"都强制弹窗选模型）；header 的模型 badge（`frontend/js/chat.js:262`）纯展示不可点击。后端**已支持**改模型（`PUT /api/conversations/{id}`，`backend/app/api/routes/conversations.py:43-47`；`frontend/js/api.js:220`），前端欠一个入口。
- 重生成/编辑能力整个缺失（无"重新生成上一条回复"、无"编辑重发最后一条消息"）。
- **建议方向**：header badge 变为按钮 → 复用 `model-selector`；"重生成"= 驳回上条 assistant 消息后重发（本地即可实现，后端可不动）。

### P4. 模拟器「重新同步」按钮语义不透明 + AI 生成前置条件后置
- **证据**：按钮文案常量 `TEXT_RESYNC = '重新同步'`（`frontend/js/key-injector.js:79`）；SIM-API-1 后 load 即自动静默同步，按钮成为手动兜底，但**按钮旁无一句说明"同步什么"**（说明只藏在用户手册）。`simulator-view.js:371-376` 按钮条只渲染"重新同步"三字。
- **AI 生成**：`frontend/js/components/game-generator.js:288-368` 打开模态框前置**不检查凭证**（`GET /settings/credentials` 现成可用），未配 Key 的用户要填完世界观、点生成、等失败（`game-generator.js:255` 才报错）。
- **建议方向**：按钮条加一个 title/副文案（如"将主应用的接口 Key 写入游戏"）；AI 生成模态框打开时预检 credentials，none/claude 态顶部提示"需先配置 OpenAI 兼容 Key"并提供设置页链接（复用 `key-injector.js:396-408` 的禁用文案/引导模式）。

### P5. 保存设置强制触发连接测试，反馈通道混用
- **证据**：`frontend/js/components/settings-panel.js:278-304` `testApiKeys`——只要任一 Key 非空，**每次**点"保存设置"都会先测连接，失败则弹确认"仍然保存吗"；即使用户只改了主题/昵称也会被阻塞。（主题本身另有独立切换即时保存 `settings-panel.js:121-139`。）成功/失败反馈用 **modal alert**（`settings-panel.js:413/415`），全局其余操作用 **toast**（`frontend/js/utils.js:24-30`），通道不一致。
- **建议方向**：保留"保存时测试"但移到显式"测试连接"按钮（P4.3 语义），theme 等非凭证保存跳过测试；统一成功反馈为 toast。

### P6. 长对话无上下文可见性，渲染是整区重绘
- **证据**：上下文轮数=滑窗 `index.html:271-273`（默认 30，5-100），**无 token 估算、无"接近窗口上限"提示**；`renderMessages`（`chat.js:97-125`）每次激活整容器 `innerHTML` 重绘，流式逐 token 走 `renderMarkdown(content)` 全文重渲染（`chat.js:449`）+ `stream-session.js:258-259` 逐 token 重建数组——超长响应/超长历史下有可感知掉帧风险。
- **建议方向**：轻量 token 估算 + 会话头部显示"上下文使用度"；长会话列表增量渲染（气泡复用已部分存在，可扩展到历史加载分页）。

### P7. 可访问性与键盘可用性基础薄弱
- **证据**：导航按钮仅 `title`（`index.html:23-62`），无 `aria-label`/`aria-current`；模态框无焦点陷阱、无关闭后焦点还原（`frontend/js/components/modal.js:76-102` 只有 Escape/遮罩/关闭按钮三条路径）；消息区无 `aria-live`；toast 无 `role=status`。正面例外：模拟器筛选有 `role="group"`（`simulators.js:277`）、key 反馈有 `role="status"`。
- **键盘**：聊天 Enter/Shift+Enter、搜索 Enter/Escape、弹窗 Enter/Escape 已具备，但无全局快捷键（如 Ctrl/⌘+K 搜索、Ctrl+N 新对话）。
- **建议方向**：modal 焦点陷阱 + 还原（改动集中在 `modal.js` 单点）；导航加 `aria-current`；补 2 个高频快捷键。

### P8. Toast 无队列、会叠加
- **证据**：`frontend/js/utils.js:24-30` 每次 `showToast` 都 `appendChild` 到 body，5 秒后自行移除，**无上限/无队列**。导入成功（toast）→ 安全警告（modal）→ 适配提示（modal）等串联流程会连续叠加 toast。
- **建议方向**：toast 上限（如 3 条）+ 顶部新条挤掉最旧；或同类文案合并。

### P9. 加载失败只有 toast，无页面级重试
- **证据**：角色/对话列表加载失败 → `console.error` + toast（`list-views.js:82-84` / `279-281`）；模型列表失败只 `console.error`（`app.js:184-186`）。对比模拟器域有完整的四态+重试（`simulators.js:338-348`）。若后端启动落后于前端（web 模式），主界面只有短暂 toasts，用户不知道发生了什么。
- **建议方向**：启动期加载失败时在对应视图渲染轻量错误+重试（复用模拟器错误态模式）。

### P10. 桌面壳无更新提示
- **证据**：`src-tauri/Cargo.toml` 仅 `tray-icon` feature，无 updater；版本号硬编码于 `index.html:71`（v0.3.0）与 `tauri.conf.json`。托盘只有 显示/隐藏、开机自启、退出（`src-tauri/src/tray.rs:161-180`）。
- **建议方向**：中期接入 Tauri updater 或至少"检查新版本"托盘项（版本号改为构建注入）。

### P11. 聊天/角色空态缺行动入口
- **证据**：聊天空态 `index.html:129-138` 只有文案；角色空态 `list-views.js:92`「暂无角色，点击上方按钮创建」未内联创建/导入/模板快捷入口。相比 `simulators.js` 有完整空态与工具条，聊天域空态是"死页面"。
- **建议方向**：空态内联 2-3 个行动按钮（创建角色 / 从模板导入 / 配置 AI 接口——P1 引导的落地载体）。

---

## 3. 外部对标：可借鉴机制（全部为官方一手资料）

### 3.1 SillyTavern（AI 角色扮演标杆，官方文档）
- 来源：[SillyTavern Docs](https://docs.sillytavern.app/)（2026-08-26 获取，高置信）
  - **欢迎屏即入口**：在欢迎屏输入框直接输入一句 prompt 就能创建一张可后续定制的"Assistant"角色卡——把"创建角色"从表单流程降为一行输入。Conver 对应：聊天空态可直接收"想聊什么"并落入角色创建向导。
  - **上下文管理是显式资产**：World Info（设定即 token 预算条目）、内置 RAG、"Auto-Summary"扩展用于长对话——即 P6 的成熟解法：长对话不只靠滑窗，还给用户"压缩/摘要"的控制权。
  - **零门槛后端选项**：AI Horde "out of the box 无需任何设置"即可开聊（见下）。
- 来源：[SillyTavern — API Connections](https://docs.sillytavern.app/usage/api-connections/)（2026-08-26 获取，高置信）
  - **单一"连接配置页"+ 类型下拉**：所有后端（OpenAI 兼容 / Kobold / Ollama / Tabby）都在一个页面按"Chat Completion / Text Completion"口径配置 base_url；并明确标注若干 **免配置即用** 选项（AI Horde、Pollinations 无需 Key）。启示：Conver 设置页可增加"无 Key 试用/本地演示"档位，让首启体验不被 Key 卡死。

### 3.2 Open WebUI（自托管聊天，官方文档）
- 来源：[Open WebUI — Getting Started](https://docs.openwebui.com/getting-started/quick-start/)（2026-08-26 获取，高置信）
  - **首启所有权仪式**：第一个注册账号获得管理员权，后续注册需审批——把"单人首启"变成一次有仪式感的设置。
  - **显式把 Provider 设为聊天前置条件**："Open WebUI needs at least one model provider to start chatting"——在正式文档里把"配好提供商"列为聊天前提，并紧跟各类 Provider 接入指南。启示：Conver 应在**主界面**（而非文档）显式表达同一前提（对应 P1）。
  - **隐私承诺话术**："All data, including login details, is stored locally on your device by default" / "does not make external requests by default"——首启信任文案，Conver 设置页已有类似一句（`index.html:328`），可升级为首启引导卡。

### 3.3 Cherry Studio（国产多模型桌面客户端，开源仓库 + 官方文档）
- 来源：[CherryHQ/cherry-studio README](https://github.com/CherryHQ/cherry-studio)（2026-08-26 获取，高置信）
  - **多模型同答对比**："Multi-model Simultaneous Conversations" / README 主打多模型并行——同一问题多模型同时回答，直击"选模型困难症"。Conver 已有多 tab 后台并行流式能力，**天然可升级为"同问多模型对比"**。
  - **开箱即用**："📦 Ready to Use - No Environment Setup Required"；300+ 预置助手 + 自建助手（= Conver 的角色模板库思路的成熟印证）。
  - **全局搜索 + 话题（Topic）管理系统**列为核心特性——印证搜索在本地多模型应用中是高频主功能（对应 P2）。
- 来源：[Cherry Studio 官方文档](https://docs.cherryai.com.cn/docs/en-us)（2026-08-26 获取，高置信）
  - **一键拉取模型列表**："Get the complete model list with one click, no manual configuration required"——对照 Conver 的模型清单是硬编码（`docs/architecture.md:88`「可用模型硬编码清单」）+ 手动输入自定义模型（`settings-panel.js`），这是**最直接的差距**。
  - **多 Key 轮换**：同一 Provider 支持多个 API Key 轮换避免限流。
  - **多模型自动选中对比 + 模型自动匹配头像**：模型识别可视化。

---

## 4. 综合建议（分档）

### 4.1 快赢（低风险 / 高价值，改动集中单个模块）
| 标题 | 现状证据 | 目标体验 | 改动面 | 风险 |
|---|---|---|---|---|
| 搜索跳转定位到命中消息 | P2：`search-view.js:151` 丢弃 messageId | 点结果→滚到该消息+高亮 | `search-view.js` / `conversation-activation.js` / `chat.js` | 低（无新接口） |
| 首启 Key 引导 + 聊天错误条化 | P1：`app.js:193` 无检查、错误落消息列表 | none 态空态挂引导卡；错误改为可关闭条 + "去设置" | `app.js` / `chat.js` / `stream-session.js` / `index.html` | 低 |
| toast 队列 + 统一成功反馈 | P5/P8：`utils.js:24`、`settings-panel.js:413` modal alert | 不叠加、同通道 | `utils.js` / `settings-panel.js` | 低 |
| 模拟器生成前置 Key 检查 | P4：`game-generator.js:288` 无预检 | 无 Key 打开即提示+引导 | `components/game-generator.js` | 低 |
| Modal 焦点陷阱 + 关闭还原 | P7：`modal.js:76` | 键盘用户不丢焦点 | `components/modal.js` 单点 | 低 |

### 4.2 中期（风险可控，涉及跨模块或新端点）
| 标题 | 现状证据 | 目标体验 | 改动面 | 风险 |
|---|---|---|---|---|
| 对话内切换模型 | P3：badge 仅展示（`chat.js:262`）；后端 PUT 已就绪（`conversations.py:43`） | 点 badge→选新模型→后续消息用新模型 | `chat.js` / `model-selector.js` / `list-views.js` | 中（需处理流式中断与标题联动） |
| 重生成 / 编辑重发上一条消息 | P3：能力缺失 | 悬停消息出"重生成/编辑"操作 | `chat.js` / `format.js` / `chat.py`(可选) | 中 |
| 模型列表一键拉取 | P9/3.3：硬编码清单（`architecture.md:88`） | 设置页"获取模型列表"按钮（OpenAI 兼容 `/models`） | `model_data.py` / `routes/models.py` / `settings-panel.js` | 中（格式兼容与超时） |
| 长对话上下文指示 | P6：无 token 可见性 | 头部显示上下文占用、接近上限提示 | `format.js` / `chat.js` / `prompt.py`(估算) | 中 |
| 启动失败页面级重试 | P9：仅 toast | 列表视图错误态+重试 | `list-views.js` / `app.js` | 低-中 |
| 桌面更新检查 | P10：无 updater | 托盘"检查更新" / 启动静默检查 | `Cargo.toml` / `tray.rs` / `lib.rs` | 中 |

### 4.3 远期（方向性，需设计）
| 标题 | 现状证据 | 目标体验 | 改动面 | 风险 |
|---|---|---|---|---|
| 同问多模型对比 | P3+3.3：多 tab 并行已具备 | 一个输入→多模型并答→横向比较 | `chat.js` / `tabs.js` / 新 UI | 高（状态机扩展） |
| 欢迎屏 Quick-create | P11+3.1：空态是死页面 | 空态收一句 prompt 即建角色 | `conversation-activation.js` / `character-wizard.js` | 中-高 |
| 可访问性基线 | P7：aria 稀疏 | aria-current/aria-live、全局快捷键 | 全局小步 | 低-中（面广） |
| 无 Key 试用模式 / 免配置后端 | 3.1：AI Horde 零门槛先例 | 没 Key 也能先体验本地游戏与 UI | 设置 + 模拟器域 | 中 |

---

## 5. 推荐下一波迭代的 3 个候选主题

1. **首启引导与无 Key 主路径闭环**（P1 为核心）：零成本高收益——新用户的第一个 5 分钟决定留存，当前主路径以"发送失败"收场；改动集中在空态/错误条/一处引导卡。
2. **搜索定位跳转 + 消息高亮**（P2）：核心功能的一处断点补齐，`data-message-id` 已采集只差消费，是"数据已验证、改动最小、用户感知最明显"的一票。
3. **对话内模型切换与重生成**（P3）：角色扮演场景的高频诉求（试模型、改回复），后端 `PUT /conversations/{id}` 已就绪，前端补入口即可串通闭环，也为远期"多模型对比"铺路。