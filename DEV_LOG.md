# Conver System — 开发日志 (DEV_LOG)

> 只记「已做」与决策/避坑；待办一律进 [TICKETS.md](TICKETS.md)（唯一待办事实来源）。
> 格式：`YYYY-MM-DD | <操作> | <描述>`（倒序，最新在前）

---

## 滚动摘要（2026-08-09）

- **GUI 全功能验证**：Playwright 黑盒测试（角色/向导/对话/搜索/导出/设置/手册/响应式）+ vision 模型视觉核验，发现 4 个 bug 全部修复
- **BUG-2 停止内容未落库**：`stream_reply` 增加 finally 兜底保存（GeneratorExit/CancelledError 是 Starlette 取消 SSE 生成器的真实路径，原 except 捕获不到）+ saved 防重标志；+1 复现测试（aclose 模拟）
- **BUG-3 JSON 导出 500**：Content-Disposition 中文文件名 latin-1 编码失败 → RFC 5987（filename ASCII 兜底 + filename*=UTF-8''）；+2 复现测试
- **BUG-1 badge 显示错误**：`providerDisplayName()` 纯函数（model_data key→name 映射）替代硬编码 `'openai' ? 'OpenAI' : 'Claude'`；+5 vitest 用例
- **BUG-4 移动端 480px 错乱**：对话列表默认收起（display:none + .mobile-expanded 类），☰/toggleConvList 统一走类切换，.chat-messages min-height:0 防撑高，隐藏冗余「收起侧栏」按钮，删除 convListVisible 死代码
- **观察项 ①-④ 修复**（子代理并行）：① greeting 首轮显示（chat.js 发送完成后重载消息列表）；② 错误气泡红字红框（--danger 变量 + .message-error 类，深浅主题）；③ MD 导出 {{char}}/{{user}} 替换（复用 apply_template_vars，JSON/角色卡保留原始设定）；④ 角色卡片 4 按钮 emoji→SVG（作用域 CSS 16px）
- **导入路径错误引导（IMP-1）**：角色卡导入失败时，后端 422 错误消息附带支持格式说明（V2/data 信封/裸 data/V1 + 向导指引）；前端失败后弹「是否改用创建向导？」确认框；+3 路由层测试
- **测试**：pytest **181**（+6）+ 前端 Vitest **37**，全部通过

---

## 日志正文

### 2026-08-10 | 预检 | P6.5 多 tab 会话管理开工预检
- **知识库召回**：persona 已读（CLI 优先 / Vanilla JS / 深模块 / 评审驱动）；精读 3 条——SSE 流式前端状态陷阱、前端模块化拆分中的循环依赖处理、Conver System 高频小坑汇总；摘要带入——无框架前端 fetch seam、worktree 膨胀/CRLF 教训；守卫反查通过（无缺 summary）
- **preflight**：基线 d228fa8、worktree 可用、main 分支、pytest + Vitest 双框架齐备

### 2026-08-09 | 修复 | 导入路径错误引导（IMP-1）
- **背景**：GUI 验证时发现角色卡导入失败只有原因提示（如「无法识别的角色卡格式」），无修正引导；LLM 解析路径已有「请重试或手动创建」指引，导入路径引导程度不一致
- **后端**（`api/routes/characters.py`）：`_IMPORT_FORMAT_HINT` 常量（支持格式：V2 spec=chara_card_v2 / data 信封 / 裸 data（name）/ V1 旧卡（char_name）+ 向导指引）；`CardFormatError` 的 422 detail 追加说明；`CardValidationError`（名称空）保持纯原因（内容问题与格式无关）
- **前端**（`app.js`）：`promptUseWizardAfterImportFail()` 引导函数——失败后弹 showConfirm「是否改用创建向导？（智能导入/模板/手动）」→ 确认则 `showCharacterWizard()`；JSON 解析失败与后端 422 两条路径均触发
- **测试**：+3 路由层测试（格式错误含说明 / 不支持 spec 含说明 / 校验错误不含说明）
- **GUI 回归**：导入 `{"foo":"bar"}` → 后端 detail 完整（含格式说明与向导指引）→ 引导弹窗 →「打开向导」→ 向导第 1 步正常打开
- **测试**：pytest **181 passed**（+3）；Vitest 37 不变


### 2026-08-09 | 修复 | 观察项 ①-④（子代理并行 + GUI 回归）

- **① greeting 首轮显示**（代理 A）：`chat.js::handleSend` 流式 onDone 与非流式完成路径改为 `messages.list` 重载 + `renderMessages()`（失败退化本地 push），停止路径保持现状（保留「已停止」标记）。GUI 验证：Testbot 空对话首条消息后立即显示 greeting「1」+ 用户消息 + LLM 回复
- **② 错误气泡样式**（代理 A）：错误气泡加 `.message-error` 类；CSS 变量 `--danger-bg/--danger-text`（深色半透明暗红底，浅色 #fdf0ef 底 + #c0392b 字）+ 红边框。GUI 验证：无效 key 触发错误气泡显示红字红框，与正常气泡明显区分
- **③ MD 导出模板变量**（代理 B，TDD）：`conversation_export.py::export_conversation_markdown` 对 description/personality/scenario 调用 `apply_template_vars`（`char_name` 参数，user_name 一次读取）；JSON 导出与角色卡导出保留原始设定（防回归测试标注有意行为）。复现测试 2 failed→修复后全量 178 通过。GUI 验证：导出 MD 中 `{{char}}` 已替换为角色名
- **④ 卡片按钮 SVG**（代理 A）：`app.js::renderCharacters` 4 个操作按钮 emoji→inline SVG（气泡/铅笔/导出/垃圾桶，stroke currentColor 风格）；`.character-card-actions .btn-icon svg` 作用域 16px 规则（避免影响其他按钮）。GUI 验证：卡片按钮单色线条图标与导航统一
- **经验**：子代理修改后端代码后必须重启 uvicorn（无 --reload）才生效——首次 MD 导出验证因服务未重启误报失败


### 2026-08-09 | 修复 | GUI 全功能验证发现的 4 个 bug（复现测试先行）

- **背景**：Playwright 黑盒测试 + vision 模型逐图核验（当前模型不支持直接读图），覆盖 P0 主流程/P1 交互/P2 输入边界/P3 响应式
- **BUG-2**（停止内容未落库）：`services/chat.py::stream_reply` 原有 is_disconnected 轮询与 ClientDisconnect 两条保存路径，但前端 abort 时 Starlette 取消 async generator 抛 GeneratorExit（BaseException），`except Exception` 捕获不到 → 竞态丢失。修复：`finally` 兜底保存 + `saved` 标志防重复；`logger.exception` 兜底失败日志。复现测试 `test_stream_generator_exit_saves_partial`（aclose 模拟取消）
- **BUG-3**（JSON 导出 500）：`api/routes/conversations.py` 导出 header 的 `filename` 含中文角色名 → latin-1 编码失败。修复：RFC 5987 `filename`（ASCII）+ `filename*=UTF-8''`（urlencode）；浏览器优先中文名，兼容不支持 filename* 的客户端
- **BUG-1**（badge 显示 Claude）：`app.js` 硬编码 `model_provider === 'openai' ? 'OpenAI' : 'Claude'`，deepseek 被误显示。修复：`utils.js::providerDisplayName()` 从 `/api/models` providers 元数据解析 key→name，未匹配回退原始 key
- **BUG-4**（480px 布局错乱）：768px 断点下对话列表默认展开占 35vh 并挤压聊天区。修复：CSS 默认 `display:none` + `.mobile-expanded` 展开类；`.chat-messages { min-height: 0 }`；`btn-collapse-chat` 移动端隐藏；JS 两处 toggle 改类切换；删除 `convListVisible` 死代码
- **GUI 回归**：badge 显示 DeepSeek ✅；JSON 导出下载成功 ✅；停止生成部分内容落库（DB id=17 截断内容）✅；480px 列表收起/☰ 展开/消息可见/切换对话自动滚底 ✅
- **测试**：pytest **174 passed**（+3）；Vitest **37 passed**（+5）

---

## 日志正文

- **阶段**：架构摩擦分析 11 候选全部收官；P6.4 Tauri / P6.5 多 tab 待办（→ TICKETS）
- **前端模块化**：设置面板提取 `settings-panel.js`；模型选择统一 `model-utils.js`；SSE 解析器 `sse-reader.js`；state.js 收缩
- **Provider 标识符**：key/id 分离，data-index 退役，模型数据迁移 `services/model_data.py`
- **服务层解耦**：领域异常 `services/exceptions.py` + 角色卡异常层次
- **测试**：pytest **141** 用例 + 前端 Vitest **32** 用例，全部通过
- **数据**：清理测试数据（TestBot + 3 对话 + 6 消息）；`default_provider` 修正 openai→deepseek 对齐新 key 方案

---

## 日志正文

### 2026-08-06 | 重设计 | 温暖叙事 UI 全面升级
- **色板更换**：Linear 冷灰（lavender）→ Warm Stone 暖灰 + 琥珀金 accent（`#E8A33D`）；深色 `#0d0b08` 暖墨色基底，浅色 `#f4f0e9` 暖米白基底
- **SVG 图标**：导航栏/按钮全部 emoji 替换为 inline SVG（对话气泡、人物、放大镜、齿轮、＋、↓、垃圾桶等）
- **对话气泡**：圆角 8px→16px Telegram 风格；user 气泡琥珀填充 + 左下小圆角，assistant 气泡暖卡底色 + 细边框 + 右下小圆角；间距加大；头像缩小带边框
- **输入区**：包裹在 `border-radius:20px` 圆角容器内，聚焦琥珀发光，发送按钮 hover 辉光
- **角色卡片**：头像 44→52px 带边框阴影，hover 上移 2px，新增 accent 标签
- **空状态**：新增 SVG 图标 + 三段式布局 + 有温度文案「你的故事从这里开始」
- **思考指示器**：脉冲点灰色→琥珀色，匹配气泡样式
- **测试**：pytest 157 + 前端 32 全绿

### 2026-08-06 | 修复 | 流式对话空气泡问题
- **chat.js `handleSend`**：流式路径先创建空气泡→用户看到空白消息 → 改为先显示 thinking 指示器，第一个 token 到达时再创建 assistant 气泡
- **onError 保护**：错误发生在第一个 token 前时，移除 thinking 指示器并兜底创建气泡显示错误信息，防止 `assistantDiv` null 引用

### 2026-08-06 | 实现 | 用户手册视图
- 导航栏新增「手册」按钮（📄 文档图标），移动端同步
- `#view-guide` 7 章节完整内容：快速开始、角色管理、对话功能、搜索消息、设置说明、支持模型、小贴士
- 路由通过通用 `switchView` 模式自动生效，零 JS 改动
- 卡片式布局，`max-width:1000px` 居中展示

### 2026-08-05 | 重构 | 架构摩擦分析 11 候选全部落地
- **① 设置面板提取**（`a69c53e`）：app.js ~320 行设置逻辑（Provider/模型下拉、主题、侧栏、保存/清空/API Key 测试）迁入 `components/settings-panel.js`，协议表面 `initSettingsPanel`/`loadSettings`/`initProviderDropdown`；app.js 1050→~700 行
- **② 模型选择统一**（`a69c53e`）：`utils/model-utils.js` 暴露 `fillModelSelect`/`createCustomModelHandler`，settings-panel 与 model-selector 共享，消除重复
- **③ Provider 标识符重构**（`429b075`）：8 provider 各配唯一 `key`，`id` 保留为 API 协议标识符；前端下拉 value 用 key，`data-index` 匹配逻辑退役；factory 注册第三方 OpenAI 兼容 Provider；`setting.api_key`/`base_url` 经 `_PROVIDER_API_MAP` 将 key 映射到协议存储键（如 deepseek→openai_api_key）
- **④ 服务层异常解耦**（`abd8920`）：`services/exceptions.py` 定义领域异常（ConversationNotFound/ApiKeyMissing/ProviderNotSupported），`prepare_chat` 不再抛 HTTPException，路由层 `_prepare_or_raise` 捕获转 HTTP 状态码
- **⑤ 模型数据迁移**（`429b075`）：`AVAILABLE_MODELS` 移至 `services/model_data.py`，models 路由 131→18 行纯化
- **⑥ state.js 职责收缩**（`a69c53e`）：`convListVisible`/`searchTimeout` 移至 app.js 模块级，state.js 仅留应用级数据
- **⑦ BaseLLM 死代码清理**（`29da016`）：移除无调用方引用的 `provider_name` 抽象属性
- **⑧ 角色卡异常层次**（`abd8920`）：`CardFormatError`/`CardValidationError` 精确区分格式与校验错误，路由统一转 422；测试断言同步迁移
- **⑨ SSE 流解析器提取**（`a69c53e`）：`utils/sse-reader.js` `parseSSEStream` 纯函数，api.js 解析逻辑收敛为 1 行调用；新增 4 用例
- **⑩ 查询逻辑 DRY**（`29da016`）：`_base_character_query` + `_attach_count` 消除 list/get 重复 outerjoin/group_by
- **⑪ 静态文件路由冲突**（`29da016`）：`/` 挂载点添加注册顺序契约注释（API 路由须 /api 前缀且在挂载前注册）
- **数据清理**：删除测试角色 TestBot 及其 3 对话 6 消息（备份 `conver_system.backup-20260805-233559.db`）；`default_provider` 修正 `openai`→`deepseek` 对齐新 key 方案（default_provider_name=DeepSeek）
- **测试**：pytest **141 passed**；前端 Vitest **32 passed**（4 文件，新增 sse-reader 4 用例）

### 2026-08-05 | 重构 | API 凭证通用解析 — 填任一字段即可全局使用
- **需求**：通用系统，key/url 填 claude 或 openai 任一字段，选择任意模型即可直接用（聚合平台场景：一个 key + 一个平台 url 全协议通吃）
- **setting.py 解析链重构**：`_slot_value` 统一凭证解析「provider 特定键 → 同协议槽位 → 跨协议兜底」；`api_key` 再叠 .env 兜底（同协议 → 另一协议）；`base_url` 同链
- **效果**：用户只填 `claude_api_key`+`claude_base_url` 时，claude/openai/deepseek/qwen/kimi 全部解析到同一 key+url，协议由所选 provider 的 id 决定（SDK 自动加 /v1/chat/completions 或 /v1/messages）
- **前端**：设置页 API 密钥 group 加通用提示文案
- **测试**：+8 用例（同协议回退 / 跨协议兜底 / 同协议优先 / provider 特定优先 / base_url 同链）；pytest **149 passed**
- **ADR 取舍**：不做 key/url 强制配对（多平台双字段场景少见）；跨协议兜底是默认行为，同协议槽位优先保证双字段场景仍正确路由

### 2026-08-05 | 重构 | 连接测试通用化 + OpenAI base_url 自动补 /v1
- **需求澄清**：relay 能力由用户自控，系统只需保证「填对 key + url + 模型名 → 能对话」，不做模型假设
- **test-connection 回退链**（settings.py）：未显式传 Key/URL/模型时，全部回退通用解析（key/url → setting_service；model → 默认模型），避免用硬编码模型（claude-sonnet-5）导致用户 key 无权限而误报
- **前端 testApiKeys 重写**：只测「默认 Provider + 默认模型」（用户实际将使用的配置），Key/URL 取表单同协议优先 → 跨协议兜底；未填 Key 则跳过测试
- **OpenAI base_url 规范化**（openai.py `_normalize_base_url`）：用户只填面板根地址（`https://api.kukuit.com`）时，SDK 拼接 `/chat/completions` 会打到 HTML 面板 → 自动补 `/v1` 版本段（已含 v1/v1beta 不误改）
- **实测**：用户配置（default=deepseek, model=deepseek-v4-flash, base_url 根地址）规范化后 `/v1/chat/completions` 连接成功
- **测试**：+8 用例（model 回退 / base_url 回退 / normalize 5 例）；pytest **157 passed**

### 2026-08-04 | 实现 | Linear 设计语言 UI 重设计（`f83ec2f`）
- **设计系统**：CSS 全面重写为 Linear 风格（near-black `#010102` canvas + 薰衣草蓝 `#5e6ad2` accent）；4 层 surface 阶梯（page → bg → panel-2 → panel-3 → panel-4）+ hairline 半透明边框
- **Token 化**：全部颜色、间距、圆角、字号通过 CSS 自定义属性管理；深色模式优先，浅色模式从同一色板推导
- **组件**：新增 SVG logo 图标 + 发送按钮箭头；skeleton 骨架屏加载状态类（`.skeleton` / `.skeleton-line` / `.skeleton-card` / `.skeleton-circle`）
- **合规**：Inter 字体使用系统栈替代（无云依赖）；移除 backdrop-filter glassmorphism、纯黑/纯白、accent 色超范围使用
- **遗留**：是非 Ticket 驱动的一次性视觉改进，不影响已有功能
- **② 导出收拢**：新 `services/conversation_export.py` 深模块（`__all__` 仅 `export_conversation_json`/`export_conversation_markdown`）收纳导出逻辑；`conversation.py` 257→134 行；角色字段提取由新增 `ConversationExportCharacter` Schema（`from_attributes=True`，9 字段）唯一驱动，service 层零手写字段映射（弃用初稿「手写 frozenset + model_dump(include=) 混合方案」，字段清单单点化）
- **④ 搜索结果 Schema**：`search_messages` 返回 `list[SearchResult]`（9 字段与旧 dict 契约逐字段一致：role `.value` / created_at isoformat / 空 query `[]`）；路由 `GET /api/messages/search` 声明 `response_model=list[SearchResult]`；与 ④ 序列化主线（response_model 驱动）汇合
- **③ 前端模态框抽象**：`components/modal.js` 通用工厂 `openModal`（遮罩/标题转义/body/actions/关闭三路径/结果回传）；`showConfirm`/`showAlert` 对外 API 不变、内部复用工厂；`showModelSelector`/`createExportDialog` 迁入 `model-selector.js`/`export-dialog.js`，函数体从 app.js 删除；`downloadBlob`/`showToast` 移入 utils.js（`showError`/`showSuccess` 1 行委托，解 app.js↔组件循环依赖）；app.js 1080→864 行；Playwright 冒烟三弹窗开合 + 消息渲染无 JS 错误
- **⑤ 前端测试基建**：Vitest ^3 + jsdom ^26（`frontend/package.json` + `vitest.config.js`）；纯函数模块 `format.js`（`highlightText`/`buildMessagesHtml`/头像 HTML）数据→HTML 映射与 DOM 分离；`renderMessages` 改 `container.innerHTML = buildMessagesHtml(...)`；api.js 注入 `setFetch(fn)` seam（`doFetch` 默认 `globalThis.fetch`，浏览器行为不变）；`.gitignore` 补 `node_modules/`
- **测试**：pytest **141 passed**；前端 `npm test` **28 passed**（3 文件：format 15 / utils 8 / api 5，mock fetch 测字符列表/创建/search URL 编码/422 错误/204 空）
- **ADR 取舍**：导出角色段用专用 Schema 而非 `to_v2_card`——后者输出 SillyTavern V2 信封（spec 包裹 + 字段改名 + 头像去 data-URI 前缀）会破坏既有导出契约；Schema 放 `schemas/conversation.py`（唯一消费方是对话导出，保 locality）
- **遗留**：`schemas/__init__.py` / `services/__init__.py` 空导出（与 `models/`、`services/llm/` 不一致，属存量问题），留待统一清理

### 2026-08-03 | 实现 | 架构深化 ④：response_model 统一驱动序列化，退役手写 dict（character + conversation）
- **character.py**：删除 `_char_to_dict()`（23 行手写字段映射，与 `CharacterResponse` 完全重复）；`list_characters` / `get_character_with_count` 返回 ORM `Character` 对象 + 瞬态属性 `conversation_count`
- **conversation.py**（第二轮架构评审候选 ①）：`list_conversations` 返回 `list[dict]` → `list[Conversation]` + 瞬态属性 `message_count`，删除 13 行手写字段映射；`ConversationResponse` 已有 `message_count` + `from_attributes`，schema/路由零改动
- FastAPI `response_model=*(from_attributes=True)` 统一驱动序列化，后端所有 list 端点不再有手写 dict 落在 service 层
- 新增字段只需改 ORM model + Schema，不再需要同步改手写 dict
- 测试：117 项全过；端到端冒烟 `GET /api/conversations` 返回正确（`message_count` 正确填充：有消息=3 / 空对话=0）

### 2026-08-03 | 基础设施 | Rust 工具链安装（Tauri 桌面端前置）
- **Rust 工具链**：rustup 1.29.0 + rustc/cargo 1.97.1（stable-x86_64-pc-windows-msvc）安装完成
  - 工具链目录：`C:\Users\Administrator\.rustup`
  - Cargo 目录：`C:\Users\Administrator\.cargo\bin\`（已加 PATH）
  - 组件：clippy、rustfmt
- **MSVC 工具**：14.50.35717（link.exe）已就位
- **Windows SDK**：10.0.22621.0 已安装（`C:\Program Files (x86)\Windows Kits\10\`）
- **验证**：`cargo build` 冒烟测试通过 ✅
- **文档**：`PROJECT_REFERENCE.md` 新增「五、桌面端准备」章节；memory 新增 `rust-toolchain.md`
- **避坑**：Git Bash 的 `/usr/bin/link.exe`（GNU coreutils）会遮蔽真正的 MSVC `link.exe`，需在 **cmd.exe** 或 **PowerShell** 中运行 `cargo build`

### 2026-08-03 | 实现 | 架构深化 ③⑤：Prompt 纯函数化 + 前端 app.js 拆分
- **③ Prompt 纯函数化**：新建 `services/llm/prompt.py`，把模板变量替换（`apply_template_vars`）、mes_example 解析（`parse_mes_example`）、完整消息列表组装（`build_messages`）从 `message.py` 迁移为纯函数；`CharacterData` frozen dataclass 作为角色纯数据容器（去 db Session 依赖）；`message.py::build_message_list` 签名与行为不变（查角色+查历史→委托纯函数）；26 项单测，新模块 100% 行覆盖（62 stmts 0 miss）
- **⑤ 前端 app.js 拆分**：1380 行 → `chat.js`（328 行，聊天域渲染+交互+chatDom）+ `state.js`（54 行，全局状态+模块级状态）+ `app.js`（1080 行，视图/角色/对话/设置/搜索/init）；`setConversationsRefresher` 钩子解决 handleSend 对 loadConversations 的反向依赖（避免循环 import）；`index.html` 无变更（ESM 内部 import）；Playwright 冒烟通过（流式/非流式/主题/设置/搜索），无 JS 错误
- **测试**：pytest **117 passed**（原 91 + prompt 26）

### 2026-08-03 | 实现 | 架构深化 ①②⑥：聊天回合 + 运行时设置深模块 + Provider 注册显式化
- **① 聊天回合深模块**：`services/chat.py` 收拢一次聊天回合全生命周期（插开场白 → 存用户消息 → 组装上下文 → 取 Key / Provider → 生成 → 保存 / 断开保存部分）；`ChatContext` / `prepare_chat` / `llm_error_response` / `stream_reply` 四接口，`api/routes/chat.py` 仅留 HTTP 映射 + SSE `data:` 帧包装（-199 行）
- **② 运行时设置深模块**：`services/setting.py` 收口三处手写点（chat 路由 `_get_api_key` 等 / settings 路由 `ALLOWED_KEYS` / conversation `_get_setting_value`）；白名单 + DB→config 默认回退链 + 整型容错（防 500）；`ALLOWED_KEYS` 主位移至 service（`docs/llm-integration.md` step 3 路径同步）
- **⑥ Provider 注册显式化**：`main.py` on_startup 调 `LLMFactory.register_builtin_providers()`，`factory.py` `_ensure_builtins` 懒加载兜底（`get_provider` / `list_providers` 首次调用自动注册）；`llm/__init__.py` 导出 `register_builtin_providers`，去 import 副作用
- **取舍（架构评审已接受，不重构）**：`services/chat.py` 仍抛 `HTTPException` 并 import fastapi / starlette 类型——service 层未做到 HTTP-agnostic，按「原样上移」设计保留，文档化不重构
- **测试**：test_p35 改用 service 层 patch（`setting_service.api_key` / `chat_service.LLMFactory`）；test_settings_connection 新增 `services/setting.py` 深模块语义 8 用例（整型回退防 500 / 默认回退链 / api_key 未配置空串）；pytest **91 passed**

### 2026-08-03 | 审计 | 文档/测试专项审查（Standards + Spec 双轴）
- **范围**：`b5fe037..HEAD` 全部文档与测试。双轴 = Standards（对照《文档规范》/CLAUDE.md 惯例/嗅探基线）+ Spec（文档/测试 vs 实际代码一致性）
- **Spec 轴修复**：`api-design.md`（`greeting`→`first_mes` + V2 字段、conversation 误含 `character_name`、模型列表缺 `claude-opus-4-8`/`gpt-4-turbo`、补 6 个缺失端点：角色 import/export、对话 export json/markdown、`DELETE /api/conversations`、消息 search、settings test-connection、settings 键补全、错误码补 401/429/504）；`architecture.md`（`/api/convs`→`/api/conversations`、角色表 V2 全列、目录树补 `setting.py`/`settings.py`/`character_card.py`/前端组件/`tests`、数据流同步 `build_message_list`）；`llm-integration.md`（`generate_reply` 函数不存在→`build_message_list`、BaseLLM 签名 + `test_connection`、Factory 带 `base_url`、Prompt 构建/滑窗策略对齐代码、新 Provider 添加步骤）；`p2.5` SPEC §4.2 偏差只记 DEV_LOG 未改规格文档（闭环修正）
- **Standards 轴修复**：`db_session` fixture 在 test_p35 / test_settings_connection 各复制一份 → 移入 `conftest.py`（删重复 + 清理失效 import）；`character_card` 100% 覆盖声明原无 `.coverage` 产物 → 补可复现命令实测（101 stmts 0 miss）；TICKETS P0 手动项（P4.3 完成后过时）归档；CONSENSUS 更新记录过期
- **规范强化**：`docs/documentation-standards.md` 新增 §三 测试规范（共享 fixture 入 conftest / 覆盖率声明可复现 / 测试数同步）+ §六 防漂移新增 4 检查项（API 契约完整性 / 字段名以 schema 为准 / 规格偏差闭环 / 覆盖率有产物）
- 新增 CR-D1~D7 全部修复归档；83 用例通过

### 2026-08-03 | 实现 | P4.3 API Key 保存时测试连接
- **后端**：`BaseLLM.test_connection()` 默认实现（发起最小生成请求 max_tokens=1，连接无效抛出 Provider `_translate_error` 映射的 LLMError，Provider 可覆写）；`POST /api/settings/test-connection` 端点（请求 Key 为空回退 DB 已存 Key；不支持的 provider / 未提供 Key / LLMError / 通用异常均 400 + 可读原因）
- **前端**：`api.js:settings.testConnection()`；`app.js:testApiKeys()` 保存设置前对每个非空 Key 并发测试，任一失败弹 `showConfirm`「仍然保存？」由用户决定（Key 无误但网络不可达可继续保存），取消则不落库
- 单测 11 项（`tests/test_settings_connection.py`：BaseLLM 默认实现参数断言 / 端点成功 / 鉴权失败 / 不支持 provider / 空 Key 回退已存 Key / base_url 透传 / 通用异常 / GET+PUT 设置 CRUD）；settings 路由 + schemas.settings + llm.base **100% 行覆盖**
- Playwright 前端验证：无效 Claude Key 保存 → 确认框「API Key 连接测试未通过」→「仍然保存」→「设置已保存」；验证后清理临时 DB 写入（dev 库还原至 `default_provider/user_name` 两行）
- 避坑：schema 类名带 `Test` 前缀会被 pytest 误认为测试类告警，命名 `ConnectionTestRequest/Response` 规避；Playwright 需显式 `executablePath` 指向 ms-playwright 已装 chromium（MCP 默认 channel=chrome 未装系统 Chrome）

### 2026-08-03 | 实现 | P3.5 停止生成按钮 + 对话标题自动生成
- **停止生成（仅流式）**：后端 `chat.py:stream_chat` 的 `event_generator` 每 token 轮询 `request.is_disconnected()`，客户端断开即停止 LLM 调用并**保存已生成部分**为 assistant 消息（另 `except ClientDisconnect` 兜底）；前端 `api.js:chatStream()` 重构为返回 `{abort, done}`（内部 AbortController），发送按钮流式生成中两态变身 `➤` ⇄ `⏹ 停止`，停止的气泡追加「（已停止）」标记（非错误语义）
- **标题自动生成**：`create_conversation` 未传 title 时默认「与 {角色名} 的对话」；新增 `truncate_title` 纯函数（折叠空白 + 截 20 字 + 「…」，不剥离 Markdown）；`create_message` 保存首条 user 消息且标题仍为占位默认值时同步替换；前端移除 `startChatWithCharacter` 的 `title:'新对话'` 硬编码，并新增 `syncChatHeaderTitle()` 让头部标题跟随后端替换
- 后端 19 项单测（`tests/test_p35.py`：truncate_title 纯函数 / 默认标题 / 首条替换 / 流式断开保存部分内容 / ClientDisconnect / LLM 错误）；Playwright 前端验证：停止按钮两态 + 「已停止」标记 + 标题联动（头部/侧栏同步截断标题）
- 避坑：Playwright stub 伪造 SSE 流需显式 `controller.close()`，否则 `reader.read()` 永不返回 done、`stream.done` 悬挂，正常完成路径无法验证（停止路径因 abort error 仍可达）

### 2026-08-03 | 验证 | P2.5.8 打包验证 + 文档同步
- Playwright 前端全流程手测（临时 DB，验证后清理）：V2 卡导入（base64 头像 / temperature / lorebook / custom_ext 全保真）、导出为合法 V2 信封（data 15 键）、导出→导入往返不丢数据、V1 旧卡导入（含 description 直通）、裸 data 导入（temperature 0.5 兜底生效）、非法卡 → 422、非 JSON 文件前端拦截不发请求
- 文档同步：TICKETS P2.5 全部归档、DEV_LOG、PROJECT_REFERENCE、SPEC 状态 ✅、memory project-status

### 2026-08-03 | 测试 | P2.5.7 转换层单元测试
- 新建 pytest 基础设施：`pytest.ini`（`pythonpath=.` 使 `backend.app.*` 可导入）+ `backend/requirements-dev.txt` + `backend/tests/`（conftest `make_character` 工厂 + test_character_card.py）
- 53 用例覆盖：V2 往返 / V1 归一化 / 裸 data / 非法卡 ValueError（路由转 422）/ 头像三形态 + MIME 魔数推断 / temperature 默认与裁剪 / extensions 保真 / 脏数据容错；character_card.py **100% 行覆盖**
- 测试驱动发现并修复 2 个 bug：V1 卡 `description` 字段被归一化丢弃（`_V1_TO_V2` 缺 `description` 映射，违反 spec §3.4）；裸 data 顶层 `temperature` 被忽略（`_build_create` 补 data 兜底读取，命名空间仍优先）

### 2026-08-03 | 实现 | P2.5.6 手动创建完整性引导
- character-form.js 软提示：姓名/人格设定/开场白缺项时 label 旁「建议填写」badge + 汇总 field-hint「完整角色建议包含：人格设定 + 开场白」，输入实时刷新
- 保存时缺项 → `showConfirm` 软确认「设定不完整…仍要保存吗？」（仍要保存/返回修改），软提示不拦截；仅手动表单，导入路径不参与（D6）
- `confirm-dialog.js` 修复：只清已有确认弹窗（`.modal-overlay .confirm-modal`），不再误删其它模态框，角色表单与确认弹窗可叠放
- Playwright E2E 验证：空名硬校验、软提示文案、返回修改后表单保留、填齐保存无确认、badge/hint 实时状态
- 避坑：测试时发现 Playwright 浏览器配置文件缓存旧模块，需用 `newContext()` 全新上下文验证（非代码问题）

### 2026-08-03 | 文档 | 文档规范改造
- 依据 Profit Calculator 经验 + 知识库沉淀《文档规范》（`docs/documentation-standards.md`）
- PROJECT_REFERENCE 修正「同步 ORM」错误（原误写 async/aiosqlite）、删除与 README/CONSENSUS 重复的技术栈/路线图
- README 修正 `.env` 复制路径（应为根目录）、删除重复内容
- DEV_LOG 瘦身 579 → ~100 行：待办项移 TICKETS、审计快照压缩为一行、历史改倒序滚动条目
- TICKETS 新增「已完成归档」区，CR 项按生命周期归档（记日期 + 提交哈希）
- `database.py` docstring 同步化；`.serena` tech_stack 记忆修正 aiosqlite → 同步

### 2026-08-03 | 实现 | P2.5.5 前端导出 UI
- 角色卡片操作区新增 📤 导出按钮（`.export-char`，置于编辑与删除之间，D4）
- 抽取通用 `downloadBlob(url, filename, errorPrefix)`；对话导出 `downloadExport()` 重构复用，消除两处 Blob 下载重复（与 CR.6.2 去重思路一致）
- Playwright E2E：中文文件名正确、V2 信封完整（data 15 键）、temperature 入 `extensions.conver_system` 命名空间

### 2026-08-03 | 实现 | P2.5.4 前端导入 UI
- 角色视图「导入角色」按钮 + 隐藏文件输入 + `characters.import()` + toast 反馈（D4/D6）
- Playwright E2E：V2 卡导入、非法 JSON 前端拦截（不发请求）、后端 422 单前缀展示

### 2026-08-03 | 实现 | P2.5.3 角色导入 API
- `POST /api/characters/import`：`from_v2_card` 归一化 → create_character 落库（D3 重名直接新建）
- `ValueError` → 422 友好 detail；非 dict body 自动 422；路由零业务逻辑（复用 character_card 深模块）
- 验证：V2/裸 data/V1 旧卡导入 201、非法卡 422、导出→导入往返保真

### 2026-08-03 | 实现 | P2.5.2 角色导出 API
- `GET /api/characters/{id}/export`：`to_v2_card` → JSONResponse + `Content-Disposition` 附件头（中文名 URL 编码）
- 规格偏差：SPEC §4.2 用 `get_character_with_count` 校验，实际需 ORM 对象 → 改用 `get_character`（同源校验，语义等价）

### 2026-08-03 | 实现 | P2.5.1 后端转换层
- `services/character_card.py`：`to_v2_card` / `from_v2_card`（V2 信封 + 裸 data + V1 归一化 + `extensions.conver_system` 往返保真）

### 2026-08-03 | 实现 | CR.6.5 messages.py 职责分离
- 聊天端点拆出 `api/routes/chat.py`（POST /api/chats + /api/chats/stream + LLM 辅助），`messages.py` 仅留消息检索；路由 tags 拆「聊天」/「消息」

### 2026-08-03 | 实现 | CR.5.3 + CR.5.4 + CR.6.3 命名规范 + Primitive Obsession
- 决策：允许 `stream_*` 特殊动词前缀（SSE 流式端点）；`save_message` → `create_message`，`auto_insert_greeting` 保留原名
- Character JSON 字段（tags/alternate_greetings/creator_notes/extensions）→ SQLAlchemy JSON 列，存量 TEXT 兼容
- Message.role → `Role` 枚举（`Enum` 列 `values_callable` 按值存取，存量 VARCHAR 兼容），LLM 消息/导出输出 `.value` 纯字符串

### 2026-08-03 | 实现 | CR.5.5 + CR.7 默认模型回退链重构
- 移除硬编码 `"claude"`/`"claude-sonnet-4-20250514"` → 引用 config 默认；删除靠字符串比较判断「是否覆盖」的脆弱逻辑
- 改用 Pydantic v2 `model_fields_set`：显式传参 → settings 默认 → config 默认；修复「显式选择=默认值时被静默覆盖」边界

### 2026-08-03 | 实现 | CR.6.2 前端头像/复制按钮构造去重
- 新增 `createAvatarElement(role)` + `attachCopyButton(btn, content)`，renderMessages/appendMessage/流模式复用；最小 DOM shim 测试 12 用例通过

### 2026-08-03 | 实现 | CR.5.1 + CR.5.2 类型注解 + API 路径重命名
- 全部路由/服务函数补返回类型注解（27+ 处）；`/api/chat` → `/api/chats`（前端 api.js + 4 份文档同步）

### 2026-08-03 | 实现 | CR.6.1 + CR.3.2 + CR.4.1 代码质量收尾
- `_prepare_chat()` + `_ChatContext` 收敛 ~90 行共同前置逻辑；Provider 新增 `_translate_error()` 共用 SDK 异常映射；ChatRequest.stream 复核无死代码

### 2026-08-03 | 实现 | CR.3.1 + CR.6.4 deps.py 清理
- 删除纯转发浅模块 `api/deps.py`，4 个路由直连 `database.get_db`

### 2026-08-03 | 实现 | CR.2 代码质量硬性违规清理
- 复核确认 3/4 子项在现行代码已就绪（类型注解/命名/typing 语法），仅补齐冗余局部导入清理（见 `经验/审计快照过期需复核`）

### 2026-07-30 | 实现 | P6.3 Prompt 模板变量
- `_apply_template_vars()`：`{{user}}` → 用户昵称、`{{char}}` → 角色名，作用于 greeting/scenario/mes_example/系统提示/用户输入
- 前端设置面板「模板变量」分组 + 表单字段提示

### 2026-07-30 | 实现 | P6.2 搜索历史消息
- `search_messages()`：SQL LIKE 跨对话搜索 + JOIN 上下文 + 关键词前后 50 字截取；`GET /api/messages/search?q=&limit=50`
- 前端搜索视图（防抖 300ms、关键词高亮、结果跳转）

### 2026-07-30 | 修复 | CR.4.3 theme_mode 设置不生效
- 根因：值保存/加载但从未应用 DOM，CSS 只认 `@media` 不认强制模式
- 修复：`applyTheme(mode)` 设置/移除 `<html data-theme>` + `:root[data-theme="dark"/"light"]` 选择器

### 2026-07-30 | 修复 | CR.4.2 V2 字段未用于 prompt 组装
- 根因：`build_message_list()` 忽略 scenario/mes_example/post_history_instructions
- 修复：scenario → `[场景设定]` 系统消息；mes_example 解析 `<START>` 对话为 few-shot；post_history_instructions 置于历史后；空字段跳过

### 2026-07-30 | 修复 | CR.4.1 SSE 流中断 → 按钮永久禁用
- 根因：`reader.read()` 返回 done 时直接 break，从不触发 onDone/onError，`isStreaming`/`btnSend.disabled` 永不重置
- 修复：`completed` 标记，流结束未收 done → `onDone(null)` 重置状态，有部分内容仍保存

### 2026-07-30 | 实现 | P6.1 对话导出
- `export_conversation_json/markdown`；`GET /{id}/export/json|markdown`（附件头）+ 前端导出弹窗 + Blob 下载
- CR.9 toast 通知（showError/showSuccess），数据加载失败用户可见

### 2026-07-30 | 实现 | Phase 5 体验完善
- 对话历史/重命名/删除确认/清空、Markdown 渲染、复制按钮、Toast、快捷键、主题切换（auto/light/dark）、响应式、设置面板（滑窗/默认模型/base_url）

### 2026-07-30 | 实现 | Phase 4 多模型支持
- OpenAIProvider（generate/stream_generate、base_url 可配、异常映射）+ Factory 注册；前端模型选择器 + model badge + 设置集成

### 2026-07-30 | 实现 | Phase 3 对话核心
- ClaudeProvider generate/stream_generate + LLM 异常映射；POST /api/chats + /api/chats/stream（SSE）
- 上下文管理：system prompt + 滑窗（轮数从 settings 读）+ greeting 自动插入；Key 动态读取；temperature 生效；前端流式渲染 + 思考指示器

### 2026-07-30 | 实现 | Phase 2 角色管理前端
- character-form.js（完整字段）、编辑预填、删除确认（关联对话数）、角色卡片增强

### 2026-07-30 | 实现 | Phase 1 项目骨架
- config / database（同步 ORM + PRAGMA FK）/ models（V2 完整字段）/ schemas / LLM 层（BaseLLM+Factory+桩）/ API Routes / main.py
- 前端 index.html 三栏 + style.css 主题 + api.js（fetch+SSE）+ app.js

### 2026-07-30 | 审计 | 全量代码审查（Phase 5 后）
- 发现 27 处缺类型注解、/api/chat 命名、头像/复制按钮重复、JSON 字段、Message.role、deps.py、messages.py 职责混杂 → CR 项已入 TICKETS（CR.1-CR.10）

### 2026-07-30 | 审计 | 全量代码审查（初轮）
- Standards + Spec 双轴：滑窗不生效、SSE 错误静默丢弃、类型注解缺失、异常映射重复 → CR 项已入 TICKETS
- 决策：Git 延迟初始化（项目完善后再 `git init`）

### 2026-07-30 | 立项 | to-tickets 阶段
- grill → to-spec（CONSENSUS + 4 份设计文档）→ to-tickets（TICKETS 全量任务分解）→ implement
