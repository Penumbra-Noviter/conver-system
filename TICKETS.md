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

> 当前无未完成工单。P6.4 已全部归档（见下）。评审遗留见下方技术债区。

---

## 技术债区

> 期末/波次审核的非阻断发现落盘于此（带推荐强度），供未来会话与下一轮 kickoff 可见。修复时机自由，不影响当前交付。

| 编号 | 遗留项 | 来源 | 推荐强度 |
|------|--------|------|----------|
| ARC9-1 | search-view.js `initSearchView` docstring 声称幂等但实现无条件重复 addEventListener（重复调用双绑事件；当前 app.js 单调用点无实际影响）——改 docstring 或加绑定守卫 | ARC-9 期末 Standards | Worth exploring |
| ARC9-2 | settings-panel.js `initProviderDropdown`/`initSettingsPanel` 缺 DOM 元素守卫（设置面板元素缺失时抛 TypeError，与 search-view 的 no-op 惯例不一致；基线既有） | ARC-9 T-06 记录 | Worth exploring |
| ARC9-3 | build-desktop `-SkipBackendBuild` 由「警告后继续（tauri-build 资源校验兜底）」改为 helper 提前 throw——终态同为失败、注释已声明，但参数语义严格说微变 | ARC-9 期末 Standards | Speculative |
| ARC9-4 | smoke 验收 6 清理后无复查等待窗口（force-kill 关闭 LISTEN 即时；若未来后端改多 worker/继承 socket 形态可能短暂假阴性） | ARC-9 波 2 Falsify F4 | Speculative |
| ARC9-5 | run_backend.py 直执行形态 `log_file_path()` 在 try 外，ImportError 无 traceback 落盘（该形态本就不受支持，`python -m backend.run_backend` 正常） | ARC-9 波 2 Falsify F5 | Speculative |
| ARC9-6 | app.js `toggleConvList`/`convListToggle` 死代码（无调用方，基线既有；coverage 唯一未覆盖行）——清理 | ARC-9 T-06 记录 | Speculative |
| ARC9-7 | settleTurn 五件套依赖参数（convId/getTab/updateTab/isActive/render）Data Clumps——可捆成 session-deps 对象，共识固定签名，不急于改 | ARC-9 期末 Architecture | Speculative |
| ARC9-8 | `?` 编码跨平台边界：非 Windows 平台若真出现含 `?` 路径，SQLAlchemy 零解码会把 `%3F` 当字面文件名（Windows 下 `?` 非法不可达，防御编码非回归；部署前知晓） | ARC-9 T-04 修复说明 | Speculative |
| ARC10-1 | llm_error_handler 401 分支消息含前导空格（provider="" 模板形态）——当前无请求路径可达（parse_document 包 422/test-connection 局部 400/complete_chat 显式带 provider/stream 走 error 帧）；若未来新路径漏出 LLMError 会产出带空格消息——建议 handler 侧 strip 或占位 | ARC-10 期末 Falsify | Speculative |
| ARC10-2 | 未知 DomainError 子类 → handler 400 vs `chat_error_response` 兜底 502 语义不一致（异常层次冻结声明下无生产者；未来新增异常需同步映射表） | ARC-10 期末 Falsify | Speculative |
| ARC10-3 | wizard modal-body 嵌套结构（同元素双 class → modal-body > wizard-body）+40px padding 差，当前被 `.wizard-modal` min-height:480px 掩蔽——未来调整向导高度约束会显形（可留 CSS `:has()` 修复预案） | ARC-10 期末 Falsify | Speculative |
| ARC10-4 | 领域错误映射双址（services/chat.py::chat_error_response 与 api/errors.py::_domain_error_response 同表维护 404/400）——spec 明令两路并存（B1 只读约束）为规格背书；未来可合并为单一映射表 | ARC-10 期末 Architecture | Speculative |
| ARC10-5 | register_builtin_providers 派生中途抛错（数据畸形）留半注册状态（`_builtins_loaded=False`，下次调用重试补齐）——fail-fast 设计意图，当前数据合法 | ARC-10 波 1 Falsify | Speculative |
| T-04 | run_backend 端口越界 SystemExit 在 try 外，CREATE_NO_WINDOW 下不留日志（经壳不可达，壳恒传合法 u16） | 波 2 降配审核遗留 5 | Speculative |
| T-05 | setup_tray 失败即整体启动失败（响亮失败、低概率；图标产物齐全） | 波 2 降配审核遗留 4 | Speculative |
| T-06 | CONVER_DATA_DIR 为 POSIX 路径（`/c/...`）不做归一化（三方行为自洽但落位不合预期；文档已警告） | 波 2 降配审核遗留 2 | Speculative |

> ✅ 已结清（2026-08-12 ARC-9）：T-01 兜底三分歧 → 统一 `home\AppData\Roaming`（契约表 v2）；T-02 URL 编码 → 壳侧编码收窄至仅 `?`（SQLAlchemy 零解码语义，v1 全量编码为回归教训）；T-03 全局进程名清理 → `desktop-common.ps1::Stop-ConverPortListeners` 端口限定。
>
> ✅ 已结清（2026-08-12 ARC-10）：**C3-DEFER**（modal 工厂落地 + character-modal.test.js 36 用例骨架级测试兑现）；**ARC9-9~15**（未选候选 C4/C6/C7/B2/B3/D3/D4 全部落地为 T-12/T-16/T-13/T-14/T-15/T-17/T-18）。

---

## 已完成归档

### ARC-10 架构深化批次：剩余 8 候选（2026-08-12 全自动 kickoff）

> 来源：/improve-codebase-architecture 审查报告未选候选（用户下令「剩余候选也做完」）。规格 v1.0 无修订（一次性产物已清场，决策见合并链 4ffc1d2/241a7b6 与共识要点）+ 共识（13 项决策带推荐默认，含关键裁定：C7 注入三制统一明确不做、test-connection 保 400 语义、C3-DEFER 承诺纳入 T-11）。两波执行：波 1 并行 3（前端链 T-11→T-12→T-13 同代理 + T-14 + T-15，merge `4ffc1d2`）、波 2 并行 3（T-16/T-17/T-18，merge `241a7b6`）；merge 零回退冲突；T-16 首代理 setup 后空返回失败 → 降级重派复用 worktree 完成。波末降配增量审核两轮均无阻断（波 1：26 Falsify 构造 + 5/5 工单档 A；波 2：15 构造含 CSS 多重集对比/漂移注入 9/9 捕获）。**期末四轴 code-review（固定点 a453e75）：0 阻断**——8 工单 Spec 全过、深模块达标（character-submit.js/api/errors.py/factory 派生/modal.js）、Falsify 10 项构造无击穿；5 项非阻断观察落技术债区（ARC10-1~5）。GUI 冒烟（浏览器，隔离库）：wizard/form modal 骨架（headerExtra/Escape/预填）✓ 创建/编辑提交 ✓ 错误气泡深浅主题（OPT-1-FIX 压制保持 + --on-danger 生效）✓ 输入框复位 ✓ 删除级联 ✓。测试同步：pytest **356 + 1 skip** / Vitest **362** / cargo test **52**，全部全绿。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| T-11 | C3 modal 骨架收口到通用工厂 + C3-DEFER 兑现（openModal headerExtra 插槽；36 新用例，form/wizard 覆盖 ~100%） | 2026-08-12 | `8b690bf` |
| T-12 | C4 角色提交逻辑收敛为角色域深模块（character-submit.js 5 导出；19 新用例） | 2026-08-12 | `0851379` |
| T-13 | C7 微重复收口（auto-resize/空态文案/avatar onerror 参数化；注入三制不做；10 新用例） | 2026-08-12 | `24a678d` |
| T-14 | B2 Provider 清单单一来源（AVAILABLE_MODELS 派生 + 包导出收缩零 SDK 副作用；17 新用例，覆盖 99.05%） | 2026-08-12 | `1854fb3` |
| T-15 | B3 统一 exception handler（api/errors.py 两枚 handler + 路由薄化；27 新用例，涉改 100% 覆盖） | 2026-08-12 | `16efce2` |
| T-16 | C6 style.css 覆盖区归位 + --on-danger token（70 规则归位零内容改动 + 37 项保序断言） | 2026-08-12 | `d5120bd` |
| T-17 | D3 schema 快照 + 漂移检测（schema.sql 19 列快照 + 漂移 9/9 捕获 + spec 行为断言） | 2026-08-12 | `b980861` |
| T-18 | D4 聚焦序列收口 + 就绪超时契约测试（focus_main_window + cfg(test) 6 用例） | 2026-08-12 | `26ea54a` |

### ARC-9 架构深化批次：6 Strong 候选（2026-08-12 全自动 kickoff）

> 来源：/improve-codebase-architecture 审查报告（14 候选）→ 用户选中 6 Strong 全自动执行。规格 v1.0 无修订（一次性产物已清场，决策见 merge 链 4e48750/dcff674/2430bc6）+ 共识（17 项决策带推荐默认，frontier 空）。两波执行：波 1 并行 3（T-01/T-02/T-03，merge `4e48750`）、波 2 并行 2（T-04→T-05 同代理串行链 + T-06，merge `dcff674`）；merge 零回退冲突；波末降配增量审核两轮（Falsify + 文件范围三档核验）均无阻断。**期末四轴 code-review（固定点 b65e9b3）**：1 阻断——T-04 URL 全量百分号编码破坏 SQLAlchemy 连接（sqlite 方言零解码 `%XX` vs migrate_data sqlite3 URI 会解码——镜像契约盲点）→ `d3a833b` 修复（编码收窄至仅 `?` → `%3F`，契约表 v1→v2 双端同步 + 连接级消费者测试 `test_data_dir_connection.py`）→ 复审放行。运行态冒烟（浏览器，隔离库）：空态首启 / 6 步创建角色 / 模型选择 / 非流式失败路径（400 错误气泡 + 标题更新 + 按钮复位）/ 搜索防抖高亮 / 级联删除（确认框→tab 关闭→列表联动）全过。测试同步：pytest **310 + 1 skip** / Vitest **297** / cargo test **46**，全部全绿。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| T-01 | C1 搜索视图与级联删除收口为深模块（search-view.js/cascade.js，app.js 735→610 行，-125；26 新用例） | 2026-08-12 | `cef6ed9` |
| T-02 | C2 流式/非流式统一结算入口 settleTurn（chat.js 结算 -14 行，12 新用例） | 2026-08-12 | `03d0163` |
| T-03 | B1 非流式回合收进 service（complete_chat + chat_error_response 单一错误源；26 新用例，覆盖 97%） | 2026-08-12 | `9d6e579` |
| T-04 | D1 数据目录四套统一 + URL 编码契约（data_dir.py 纯 stdlib + 契约表 v2 双端镜像 + 连接级测试；期末阻断修复 `d3a833b`） | 2026-08-12 | `6097a08` + `d3a833b` |
| T-05 | D2 冒烟进程清理收口（desktop-common.ps1 端口限定 + 注释一致，grep 零残留） | 2026-08-12 | `ac8004e` |
| T-06 | C5 编排区测试挂网 + coverage 接线（+73 用例，涉改文件行覆盖全 ≥90%，C3-DEFER 登记） | 2026-08-12 | `abdeb0f` |

### P6.4 Tauri 桌面版（2026-08-11 波次收官）

> 规格 v0.2（approved，D1-D10 共识 + spike 结论折回；一次性产物已清场）。三波执行：波 1 并行 4（SPK-R1/SPK-R2 spike + P6.4-1/P6.4-3）、波 2 并行 3（P6.4-2/P6.4-4/P6.4-5）、波 3 串行 1（P6.4-6）；merge 零回退冲突；波 1 降配增量审核 5 findings（F1/F2 派回修复，F3-F5 非阻断）。spike#01（PyInstaller onedir 一次成型 + 三项硬契约）、spike#02（WebView2 不拦截 blob 下载 → 无导出回退条件分支）。**期末四轴 code-review**：2 阻断（壳 prod 无条件 spawn python 干净机启动失败 → `722ba4c` 随包资源定位 + 干净环境冒烟回归；spec `datas=[]` 打包态 UI 404 → `a29c501` 前端运行子集随包挂载）→ 修复复审放行 + 整改三项（`217385f`：build-backend 前置 cargo test 前 / datas 接线断言 / smoke 清除残留 env）。安装器形态冒烟 5 项全过（prod 随包定位 + GET / 200 应用标记 + 空库首启 + 退出无残留）。测试同步（文档规范 §三）：pytest **261 + 1 skip** / Vitest **186** / cargo test **43**，全部全绿。
>
> 人工项（R6）：验收 8（托盘/自启注册表）与验收 9（导出下载）由 docs/tauri-desktop.md §6 人工清单记录。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| SPK-R1 | PyInstaller onedir 打包可行性 spike（配方成品 backend/conver_backend.spec） | 2026-08-11 | `4226b27` |
| SPK-R2 | WebView2 blob 下载拦截实测 spike（结论：不拦截，无导出回退） | 2026-08-11 | `691f658` |
| P6.4-1 | Tauri v2 初始化 + Rust 壳（动态端口子进程/就绪页/capabilities，Seam 1） | 2026-08-11 | `4b56168` |
| P6.4-3 | 数据迁移脚本（复制非移动+完成标记+幂等，Seam 3） | 2026-08-11 | `213f6b1` |
| P6.4-2 | 后端 PyInstaller onedir 打包固化（启动器+spec+_MEIPASS+日志落盘契约） | 2026-08-11 | `b9e4eba` |
| P6.4-4 | 托盘/开机自启/单实例 + 波 1 审核 F1/F2 修复（CONVER_DATA_DIR 对齐 + runtime.json 原子写） | 2026-08-11 | `e1fbc96` + `908ff5a` |
| P6.4-5 | 品牌图标全套（SVG → Playwright 1024 PNG → tauri icons） | 2026-08-11 | `94f21c3` |
| P6.4-6 | 安装器 + 一键构建冒烟 + 文档归档（NSIS currentUser；build-desktop.ps1/smoke-desktop.ps1；验收 1-7 自动化） | 2026-08-11 | `1e93a97` |

> ⚠️ Ollama 本地模型支持 — **已封存**（2026-08-03 用户决定：发布获得用户反馈后再考虑）

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
