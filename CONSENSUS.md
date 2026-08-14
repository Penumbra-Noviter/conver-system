# Conver System — 共识文档 (CONSENSUS)

> 记录所有需求定义与技术决策。修改设计前请先更新本文档。

---

## 1. 项目定位

- **类型**：个人娱乐/实验项目
- **形态**：本地优先的网页版 SPA（FastAPI 后端 + 纯前端）
- **受众**：自己用，后续可开源到 GitHub
- **数据主权**：所有数据（含 API Key）存本地 SQLite，不上传云端
- **扩展路径**：网页版 → Tauri 桌面版（Phase 6 按需推进）

## 2. 用户画像与安全模型

- **单用户设计**，不做多租户/多账号隔离
- API Key 通过 UI 设置面板写入 DB（settings 表），运行时可修改立即生效
- SQLite 数据库文件仅存本地，不上传/不共享
- `.env` 仅作配置模板，不存储真实密钥
- **模拟器同源信任边界已接受并文档化**（TD-57）：22 款模拟器与主应用同源运行、游戏可互读 localStorage 与调用 /api 端点 —— 自用威胁模型可接受，威胁模型 / 收缩措施 / 加固不可行论证见 [docs/architecture.md](docs/architecture.md)「模拟器信任边界（TD-57）」小节
- **跨源沙箱 / postMessage 隔离**列入探索文档未决事项 U11 跟踪（仅探索不立项，见 [docs/world-simulation-exploration.md](docs/world-simulation-exploration.md)）

## 3. 角色管理策略

- **手动创建**：所有字段在 UI 中可编辑；设定不完整（缺人格设定/开场白）时软提示引导补齐，不拦截保存
- **导入/导出**：兼容 SillyTavern Character Card V2 规范（全量映射），首期仅 JSON 卡（PNG 卡留待 P6.x）；导入容错 V1 旧卡与裸 data 格式
- **往返保真**：temperature / URL 头像 / lorebook 等非 V2 标准字段存 `extensions.conver_system.*` 命名空间，导出→导入不丢数据（详见 `docs/p2.5-character-import-export.md`）
- **创建向导**（2026-08-06）：新增 6 步角色创建向导（选择方式 → 文档导入/模板 → 基本信息 → 人格设定 → 对话风格 → 预览保存）；编辑角色仍使用原有简洁表单
- **LLM 文档智能解析**（2026-08-06）：`POST /api/characters/parse-document` 端点，使用用户配置的 LLM 从自由文本中自动提取角色卡字段（name / personality / first_mes 等），支持 3 种 JSON 提取策略；需先配置 API Key
- **角色模板**（2026-08-06）：内置 5 套通用角色模板（知性学姐/神秘旅人/毒舌助手/温柔管家/活力猫娘），用户可在向导中选择模板后自定义
- **字段设计**：DB 表完整映射 V2 字段（含 `scenario`、`mes_example`、`alternate_greetings`、`system_prompt`、`post_history_instructions` 等）
- **删除行为**：
  - Phase 2：级联删除（角色 + 关联对话 + 消息）
  - Phase 5：升级为确认对话框，提示用户有 N 条关联记录

## 4. 对话上下文管理

- **默认策略**：滑动窗口，保留最近 20-30 轮消息
- **用户可配**：设置面板中提供滑块调节轮数
- **高级策略**（Phase 6）：摘要压缩
- **对话标题自动生成**（2026-08-03 立项，P3.5）：
  - 创建对话时后端默认标题为「与 {角色名} 的对话」，前端不再传 `title: '新对话'`
  - 发出首条 user 消息后，同步替换为该消息的**规则截断**标题（折叠空白 + 截取 20 字 + 「…」，不剥离 Markdown）
  - 纯规则实现，零 LLM 调用、确定性、无感知延迟

## 5. LLM Provider 策略

| Provider | Phase | 方式 |
|----------|-------|------|
| Claude (Anthropic) | Phase 3 | 官方 anthropic SDK |
| OpenAI（含兼容 API） | Phase 4 | 官方 openai SDK，`base_url` 可配 |
| Ollama 本地模型 | Phase 6 | 可选 |

- Provider 通过 Factory 模式注册，扩展新 Provider 只需按接口实现
- 每个对话记录使用的 `model_provider` 和 `model_name`

## 6. 流式输出

- **两个模式都做**，用户可选择流式/非流式
- 非流式：`POST /api/chats` → 等待 → 完整回复
- 流式：`POST /api/chats/stream` → SSE → 打字机效果渲染
- Phase 3 同时实现两种模式
- **停止生成**（2026-08-03 立项，P3.5）：
  - 仅流式模式提供。流式生成中发送按钮两态变身停止按钮（`➤` ⇄ `⏹ 停止`）
  - 前端 `AbortController` 中止 fetch → SSE 连接断开
  - 后端 `stream_chat` 的 `event_generator` 轮询 `request.is_disconnected()` 感知客户端断开，**保存已生成的部分内容**为 assistant 消息
  - 前端气泡标记「（已停止）」，语义为「用户主动停止」而非错误
  - 非流式模式不提供停止按钮（无法真正中断后端请求，避免「点了停止但消息仍出现」的误导）

## 7. 前端布局与交互

- **布局**：左侧导航栏 + 右侧主内容区（Discord 风格）
  - 侧栏：角色列表 | 对话列表 | 设置入口
  - 主区：聊天界面 / 角色编辑 / 设置面板
- **技术栈**：Vanilla JS (ES Modules) + CSS 自定义变量
- **无构建工具链**：FastAPI Mount 同域服务，手动 F5 刷新

## 8. 配置管理分层

| 配置项 | 存储位置 | 运行时修改 |
|--------|---------|-----------|
| API Key | DB settings 表 | ✅ UI 中修改即时生效 |
| 默认模型 | DB settings 表 | ✅ |
| 滑窗轮数 | DB settings 表 | ✅ |
| UI 偏好 | DB settings 表 | ✅ |
| 每次对话模型 | conversations 表 | ✅ |

## 9. 开发规范

- Git 提交格式：`<type>: <中文说明>`（feat/fix/refactor/docs 等 Conventional Commits）
- **Git 策略**：项目初步完善后再执行 `git init` 及初始提交。在此之前不进行版本控制，不上传 GitHub 仓库。
- 代码规范见 `mem:conventions`（Python: PEP8 + 类型注解，JS: camelCase/ESM）
- 每个 Phase 完成时做 code-review 后提交
- 关键决策更新此 CONSENSUS.md

## 10. Phase 划分

| Phase | 名称 | 核心产出 |
|-------|------|---------|
| 1 | 项目骨架 | 可运行的 FastAPI + SQLite + 前端空壳 |
| 2 | 角色管理 | 角色 CRUD + 前端管理 + V2 导入/导出 |
| 3 | 对话核心 | LLM 接入 + 聊天 UI + 流式/非流式 |
| 4 | 多模型支持 | OpenAI Provider + 模型切换 + API Key 管理 |
| 5 | 体验完善 | 对话历史、UI 美化、快捷操作 |
| 6 | 增强功能 | Tauri 桌面版、导出、搜索等 |

## 11. 多 tab 会话管理（P6.5，2026-08-10 立项）

> 12 项共识决策的规格化表达已归档；实现决策以本 §11 与 TICKETS P6.5 归档为准。

**问题**：一次只能聚焦一个会话——切换后草稿/滚动/流式上下文全丢；流式生成中切会话会污染视图（onDone/onError 读写「当前活动」的既有竞态）；刷新后工作现场重置。

**决策**：

1. **新深模块 tab 工作区状态**（`frontend/js/tabs.js`，唯一新增测试 seam，纯逻辑零 DOM）：协议 `openTab`/`activateTab`/`closeTab`/`closeAllTabs`/`getActiveTab`/`getTab`/`getTabs`/`updateTab`/`serialize`/`restore`/`restoreFromStorage`/`onTabsChanged`；tab 形态 `{ conversationId, characterId, title, messages, scrollTop, draft, isStreaming, activeStream, phase('idle'|'thinking'|'streaming'|'done'|'error') }`；openTab 按 id 去重；closeTab 激活右邻居（无则左），关最后 → null；**updateTab 对不存在 id 幂等 no-op**（关流式中的 tab 后异步写回兜底）；serialize 只存 ids+activeId；restore 经 isValidId 过滤失效 id；任何结构性变更写 sessionStorage + 通知，updateTab 内容更新仅通知不写盘（避免流式逐 token 写存储）
2. **state.js 契约收缩**：退役 currentConversationId/currentCharacterId/messages/isStreaming/activeStream 五个会话级字段，只留全局配置；toggleStream 流式开关是全局偏好、不随 tab
3. **会话 UI 单一事实来源 = 活动 tab**：消息渲染读活动 tab 缓存；头部（标题/模型 badge/导出）按活动 tab 派生；发送按钮两态（➤/⏹）只由活动 tab isStreaming 派生；切 tab 保存旧 tab 草稿/滚动、恢复新 tab
4. **流式防悬挂核心设计**：handleSend 发送时捕获 conversationId；onToken 按活动归属分流（活动 tab DOM 增量 + 缓存同步，后台 tab 只累积 per-tab 缓存不碰 DOM）；**onDone/onError 一律经 updateTab(捕获的 conversationId) 写回发起 tab，绝不读「当前活动」**；停止（AbortError）写回 phase 'error'（警示标记，气泡保持「已停止」语义），正常完成写回 phase 'done'；停止是显式动作（点停止按钮 = 活动 tab；关流式中的 tab = 显式停止并 abort）
5. **激活流程收敛**：app.js 单一内部函数承接「切到某会话」（openTab/activateTab + 补全 title/characterId + 懒加载消息 + 刷新发送按钮/列表高亮）；三入口（侧栏点击/角色「开始对话」/搜索结果跳转）与 tab 条共用；「新对话」按钮保持现状（切角色视图）
6. **联动**：删除会话（开着）→ 先 abort 其中流式再 closeTab；「清空所有对话」→ closeAllTabs + 清 sessionStorage；关闭不弹确认
7. **tab 条 UI**：presentational 组件订阅 onTabsChanged 重渲染；事件委托（点击激活 / ✕ 关闭）；激活经 app.js 注入处理器（复用 setConversationsRefresher 式注入模式），✕ 直接 closeTab；生成中（thinking/streaming）脉冲小圆点、后台出错/停止（error）警示标记、完成无提示；无 tab 不渲染；<768px 隐藏（行为不变）
8. **恢复（restore）时序契约**：init() 在 conversations 加载完成后调 restoreFromStorage；isValidId 以已加载列表判定（过滤已删会话）；恢复的 tab 一律非流式（phase idle、isStreaming false、activeStream null）；消息激活时懒加载；无记录/全失效 → 现有空态，不报错
9. **标题同步**：双击重命名与首条消息自动标题替换后，经 updateTab 同步 tab 标题
10. **后端零改动**：全部按既有 conversation_id 寻址；对话历史列表仍是持久事实来源，tab 集只是 UI 工作区；单用户本地使用，无并发写冲突风险
11. **执行串行单代理**：改造集中在同一前端协调层（chat.js 与 app.js 互相调用 + 共享 state），五张工单按阻塞链串行执行
12. **测试**：新增 tabs.test.js 32 用例（jsdom 提供 sessionStorage，零 DOM 断言）；现有 37 用例不动；pytest 零新增 181 保持；Playwright GUI 回归场景以 jsdom 集成冒烟（81 项）替代落地

**关键假设**：① 多 tab = 应用内会话工作区，非跨浏览器标签页；② 同一会话至多一个 tab（按 id 去重）；③ tab 集是 UI 态不是数据，sessionStorage 仅存 id + activeId；④ 流式/非流式完成一律按发起时捕获的 conversationId 写回；⑤ 后台 tab 流式 token 只累积 per-tab 缓存不碰 DOM；⑥ 发送按钮/停止状态 = 活动 tab isStreaming 单一事实来源；⑦ 单用户本地使用。

**边界**：关闭 tab 只关视图、不删会话；恢复不恢复草稿/滚动/流式状态；同一会话在 tab 条与对话列表并存（去重开一个 tab）。

**不做清单（Out of Scope）**：跨浏览器标签页同步；草稿持久化（刷新不保留）；流式恢复；tab 上限/驱逐策略；多 DOM 挂载；后端任何改动；tab 拖拽排序/固定/「+」快捷建会话；关闭确认弹窗。

## 12. UI 克制化与动态 SVG 图标协议（OPT-1，2026-08-11）

**问题**：现有 Warm Stone 视觉经过多轮增量后出现常驻琥珀发光、重复圆角卡片和 UI emoji/glyph 混用；静态 HTML 已使用 SVG，但运行时 JS 会把部分按钮重新覆盖为 emoji，导致图标体系与状态反馈漂移。

**决策**：

1. **保留应用壳与信息架构**：继续使用左侧导航 + 主工作区、对话列表、会话 tab、聊天输入区和既有六步角色向导；本次只优化产品组件底层和视觉层级，不改造成仪表盘、营销页或新的三栏 workflow shell。
2. **保留 Warm Stone，降低模板化特征**：暖中性色仍是识别基础，单一琥珀色只用于主操作、活动状态、焦点和真实流式状态；移除常驻 glow，减少边框与圆角卡片套娃，以背景明度、间距、半透明分隔线和轻阴影建立层级。
3. **动态 SVG 图标单一 seam**：新增本地纯函数图标模块，动态模板和状态切换只通过该接口获取一致的 `currentColor` SVG；图标带稳定 `data-icon` 供样式与测试按语义定位，未知名称显式失败。
4. **emoji 边界**：清除应用自身控件、状态和说明文案中的 emoji 图标；用户消息、角色名称、角色设定等用户数据不做过滤或改写。没有必要图标的位置优先使用明确文字，而不是补装饰图形。
5. **行为协议不变**：所有现有 DOM ID、事件委托 class、data 属性与 `EMPTY_STATE_HTML` 保持；发送/停止状态继续只由活动 tab 的 `isStreaming` 派生；多 tab、防悬挂写回和流式结算不进入本次重构范围。
6. **验证按语义而非 path 字节**：前端测试断言按钮标题、状态 class、`data-icon` 和可见文字，不绑定具体 SVG path；GUI 同时验证深浅主题、桌面/移动、向导和多 tab 流式状态。

**关键假设**：现有 HTML 壳和业务流程已通过全功能 GUI 回归，视觉问题主要位于 token、组件样式和动态图标一致性；Vanilla JS 无构建链继续保留。

**边界**：不引入 React/Vue、云端字体或图标 CDN；不更换主字体家族；不修改后端、数据库、API 或 Tauri 路线。

**不做清单（Out of Scope）**：新信息架构；向导状态机重写；聊天业务语义调整；流式生命周期优化；全新主题系统；品牌营销页面。

## 13. Tauri 桌面版（P6.4，2026-08-11 立项）

> 规格化表达见 `.scratch/p64-tauri/spec.md`（approved；D1-D10 为固定前提，spike 结论折回修订日志 v0.2）。桌面版以「壳」形态交付：前端/后端业务代码零改动，数据与网页版完全独立。

**决策**：

1. **D1 壳方案**：Tauri 主进程以 CREATE_NO_WINDOW 启动 PyInstaller 打包后端 exe（uvicorn 子进程，`TcpListener::bind(0)` 动态端口），webview 加载 `http://127.0.0.1:\<port\>`；前端/后端业务代码零改动。
2. **D2 PyInstaller onedir**（优于 onefile：启动快、无重复解压）；入口为脚本启动器 `backend/run_backend.py`（uvicorn.run 直传 app 对象规避 frozen import-string 差异），spec `pathex` 指向仓库根（PEP 420 namespace package）。
3. **D3 数据目录** `%APPDATA%\ConverSystem\`（`CONVER_DATA_DIR` 环境变量覆盖；壳/后端/迁移脚本三方同一契约）；数据库连接串由壳注入 `DATABASE_URL`（Windows 绝对路径，环境变量为权威通道——打包后 .env 相对路径语义失效）。
4. **D4 迁移脚本**：复制非移动 + `.migrated` 完成标记 + 不删源 + 幂等 + 防覆盖（不一致须 `--force`）；独立命令行工具，不进产品 UI。
5. **D5 托盘**：关闭窗口 = 最小化到托盘；菜单 [显示/隐藏窗口、开机自启勾选、退出]；单实例（二次启动同步退出，防双后端与 SQLite 并发写）。
6. **D6 开机自启默认关** + 托盘菜单勾选。
7. **D7 交付 NSIS .exe 安装器单产物**：`installMode: currentUser`（装到 `%LOCALAPPDATA%\Programs\`，免管理员）；卸载不动 `%APPDATA%` 数据（数据分离铁律）。
8. **D8 测试**：cargo test 纯逻辑（Seam 1）+ 自动化冒烟（Seam 2）；tauri-driver E2E 本轮不做。
9. **D9 图标**：内联 SVG logo → Playwright 渲染 1024px PNG → `tauri icon` 全套（含 .ico）。
10. **D10 迁移脚本独立形态**（独立脚本 + 独立测试，pytest Seam 3）。

**接口契约**：就绪契约 = 后端就绪后写 `%APPDATA%\ConverSystem\runtime.json`（port + ready 标记 + pid，原子写 F2）；就绪页（Tauri 资产页）经 `backend_status` 命令轮询就绪后 `location.replace` 到后端地址；壳-后端环境变量通道（DATABASE_URL / CONVER_BACKEND_CMD / CONVER_EXIT_AFTER_SECS 自动化 seam）；构建链必须在 cmd/PowerShell 执行（Git Bash link.exe 遮蔽 MSVC linker）；数据独立性（网页版根 DB + 8000 端口 ↔ 桌面版 %APPDATA% DB + 动态端口并存互不干扰）。

**spike 结论**：SPK-R1 = PyInstaller onedir 一次成型（启动 2.27s、25M、零 hiddenimports；三项硬契约：脚本启动器入口 / pathex 仓库根 / DATABASE_URL 绝对路径 + 日志落盘）；SPK-R2 = WebView2 不拦截 blob:URL + a.click() 下载（三种机制全放行）→ **无导出回退条件分支**，验收 9 人工点一次导出闭合。

**边界**：不重写 Rust 后端（Rust 仅作壳）；不改现有前端/后端业务代码；不做 tauri-driver E2E、自动更新、便携版、MSI、macOS/Linux；不删除网页版根数据库；不碰 Ollama（已封存）。

---

> 更新记录：2026-07-30 初始版本，经 grilling skill 深度讨论后确认；2026-08-03 补充 P3.5（§4 标题自动生成、§6 停止生成）、P4.3（API Key 保存时测试连接）决策；2026-08-06 补充角色创建向导、LLM 文档智能解析、5 套内置模板；2026-08-10 补充 §11 多 tab 会话管理（P6.5，12 项决策）；2026-08-11 补充 §12 UI 克制化与动态 SVG 图标协议（OPT-1）；2026-08-11 补充 §13 Tauri 桌面版（P6.4，D1-D10 共识决策 + spike 结论 + 接口契约）
