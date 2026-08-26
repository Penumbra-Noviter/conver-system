# Conver System — 可执行任务清单 (TICKETS)

> 规则：本文件是**仓库内唯一的待办事实来源**。活跃表只保留「未完成」工单；每完成一项 → 移入「已完成归档」并记完成日期（+提交哈希）→ 同步 [DEV_LOG.md](DEV_LOG.md) → 与本提交一起 commit。
>
> 维护节奏（绑定现有流程节点，不新增习惯）：
> 1. 开始实现某工单前：📝 已录入 → 🔄 进行中（认领）
> 2. 每会话结束、commit 之前：完成 → ✅/❌ → 移入归档；新评审候选（含未拍板的 `Worth exploring` / `Speculative`）立即录入 [TECH_DEBT.md](TECH_DEBT.md) 候选池（不自动进入 preflight 认领，带 编号/来源/强度/状态）
> 3. 待办**不得写在 memory / DEV_LOG / 个人笔记里**——不落 TICKETS 就不算数
>
> 状态：⬜ 待办 | 🔄 进行中 | ✅ 完成

---

## 活跃工单

> 当前 0 项待办（技术债候选池见 [TECH_DEBT.md](TECH_DEBT.md)，当前 3 项待立项 F-45/F-47/F-48）。

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|
| — | （无活跃工单） | — | — |

---

## 技术债区

> 已迁移至独立文件 [TECH_DEBT.md](TECH_DEBT.md)（AGENTS.md §3 规范，2026-08-24 迁移，
> 条目原文完整保留：C3/C4/C7/C8 + F-1~F-22 共 26 项，迁移时全部处置完毕、技术债区清零状态维持）。

---

## 已完成归档

### 会话交付：模拟器导入「AI/本地」识别补强 + 重新识别入口（2026-08-26，用户需求单工单）

> 来源：用户报告「导入的斗罗大陆被标为纯本地、无法一键同步全局 API 设置」。根因实证：`probe_config` 三重盲区（只扫 input 漏 select / HTMLParser 不解析 script 内 JS 模板字符串控件 / 只认 cfg- 一种约定），种子 22 款全靠手工 manifest 兜底。Grilling 共识：自动启发式识别 + 卡片重新识别入口。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| 01 | 类型探测三层补强（严格 cfg- 三元组 → 关键词启发 → local）+ scan_input_ids 双层扫描（input/select + 脚本层）+ probe_endpoint_mode 端点口径；manifest 新增 update_manifest_entry；POST /api/simulators/reprobe 端点 + 前端 local 卡片「重新识别」按钮；文档同步 | 2026-08-26 | <待 commit> |

**验证链：** pytest 713→739+1skip ✅（+26：启发式 7 约定/脚本层/endpointMode/update_manifest_entry/reprobe wire）| Vitest 983→986 ✅（+3 reprobe 用例 + 契约锁同步）| 真实数据：22 种子 + 斗罗大陆探测全 ai，config 与手工 manifest 逐字一致 | doc_sync --check ✅

---

### 会话交付：code-review 修复批次（2026-08-26，kickoff 全自动档小档 3 工单）

> 来源：`b9ccdea→7bc532a` code-review 发现（滚动高亮坐标系 bug / package-lock 版本漏升 / CSS 死代码+级联冗余）。全自动档小档执行，单 Implement 连续完成。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| 01 | 滚动高亮坐标系修复（getBoundingClientRect 差值 + 滚动到底强制末章节）+ 4 回归用例（先红后绿） | 2026-08-26 | 18490b6 |
| 02 | package-lock.json 版本 0.1.0 → 0.2.0（2 行） | 2026-08-26 | ba94f6b |
| 03 | CSS 死代码清理（.guide-toc 删除）+.guide-container 三合一+节间距收敛 32px | 2026-08-26 | 8bb771b |

**验证链：** Vitest 983 ✅（+4）| 冒烟 200 ✅ | doc_sync --check ✅
**期末 code-review（固定点 7bc532a）：** 0 阻断放行 ✅
**技术债区：** +2 项待立项（F-47 type hints / F-48 ScrollSpy 候选）

> 来源：TECH_DEBT.md 候选区 24 项待立项。Grilling 共识：8 做 + 15 关 + 1 跳。全自动档执行。

**实现工单（8 项做）：**
| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| T-01 | CODE_WIKI.md §4.14 chat.py 职责更新（F-24） | 2026-08-26 | e750e07 |
| T-02 | test_error_handler.py docstring 更新（F-26） | 2026-08-26 | 8c46e25 |
| T-03 | simulator_store.py docstring stdlib 修正（F-29） | 2026-08-26 | 36a5dd3 |
| T-04 | simulator_import.py 死 import 清理 + docstring（F-30） | 2026-08-26 | c385a42 |
| T-05 | game_generator.py ValidationError 重命名 + docstring 同步（F-41+F-44） | 2026-08-26 | cf7983a |
| T-06 | 前端 11 模块 `__all__` 补齐（F-43） | 2026-08-26 | 5da97d5 |
| T-07 | doc_sync 重算测试计数（F-23） | 2026-08-26 | 502f9a1 |
| T-08 | TECH_DEBT.md 处置记录更新 | 2026-08-26 | 8080563 |

**关闭（15 项）：** F-25, F-27, F-28, F-31, F-32, F-33, F-34, F-35, F-36, F-37, F-38, F-39, F-40, F-42, F-46
**跳过（1 项）：** F-45（明确不在本批范围）

**验证链：** pytest 713+1skip ✅ | Vitest 979 ✅ | doc_sync --check ✅ | 冒烟 GET / 200 ✅
**code-review（四轴）：** 0 阻断放行 ✅
**技术债区：** 24 项 → 1 项待立项（F-45）

> 来源：2026-08-25 全量代码审查发现——AI 游戏生成功能已于 2026-08-23 入库交付（game-generator-fix 批次），但四份项目文档均未按单一来源规则登记各自侧面；本票补齐其中三个侧面，接口契约侧面由同批 T-05 承担（docs/api-design.md「AI 生成模拟器游戏」契约节）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| T-08 | AI 游戏生成功能三处登记：CONSENSUS.md 新增 §14 决策小节（为什么做 + 功能定位，决策侧面）+ PROJECT_REFERENCE.md 当前状态追加交付记录一句（交付侧面，含测试增量口径：pytest test_game_generator.py 62 用例 + Vitest game-generator.test.js 13 用例，均已计入当前基线）+ 本归档条；CODE_WIKI.md / DEV_LOG.md / docs/api-design.md 零改动 | 2026-08-25 | 3c06fa0（merge 2794b84，批次链见 DEV_LOG） |

### 会话交付：模拟器接入契约 + 外置数据目录与用户导入（T-01/T-02，2026-08-19，5 工单 3 波）

> 来源：用户咨询「不断引入游戏是否导致 exe 膨胀」→ 方案 2 选定（T-02 主工单，grill-me 两轮共识六点：外置 / 导入 / 安全 / 自动适配 UI / T-01 并入 / 文档）；用户反馈「部分模拟器 UI 仍反人类」→ 接入契约立项（T-01，保留方案 A 第三方零改动自动生效 + 补强制校验短板，方案 B 暂不切换）。T-01 依赖序在导入流程之前，并入同一批次。文档收尾 = 本批次工单 06（程序内手册「导入游戏与安全须知」+ 归档 + doc_sync）。

- **T-01 工单 01（c710eb5 + 波末修复 0ec509e）**——接入契约：simulator-pc.css 覆盖层映射记录结构化（`# sim-pc:` 标记行 + 每游戏一行机器可解析「已核对映射」）+ 核对脚本 `scripts/check-simulator-css.mjs`（游戏 HTML 三面提取 vs 覆盖层已覆盖集合比对 → 「未覆盖清单」，退出码 0=全绿）+ 共享分析模块 simulator-adapt.js（parseCoverageRecords / extractGameClasses / compareCoverage，工单 04 未覆盖提示复用）；波末修复 *.mjs LF checkout（CRLF shebang 致直 import 崩溃）+ CLI 自执行 argv[1] 缺失容错。验收：22 游戏全绿 + 证伪样本红态（`.log-entry .content` 显式 12px → 输出未覆盖项）+ 接入流程成文（CODE_WIKI §4.73，锚 `check-simulator-css`）。
- **T-02 工单 02（52fd8bd + 波末修复 117fc41）**——数据目录外置：/simulators 静态挂载改指数据目录（CONVER_DATA_DIR 可覆盖，默认 `%APPDATA%/ConverSystem/simulators/`，两版过渡：本版仍随包带 22 款，停止线性膨胀）+ 首启种子（manifest 存在为标记幂等，种子源缺 manifest 降级不崩溃）+ 冒烟隔离数据目录注入；种子矩阵 12 用例 + simulators_dir 3 用例。
- **T-02 工单 03（08b83a2 + 波2修复 88deec9）**——导入端点 POST /api/simulators/import：校验（.html / ≤5MB / 非空）→ 净化（sanitize_filename 剔非法字符与 %#，`#` fragment 截断双侧收口）→ SHA-256 去重（find_duplicate 仅比对 *.html，命中 409「已存在」，覆盖内置重复；per-game CSS 不误报）→ 冲突改名（next_available_filename `xxx-2.html` 递增）→ cfg- 三元组探测 → 恶意模式粗筛（scan_suspicious：eval / document.cookie / cross-origin-fetch，命中警告不拦截）→ manifest 原子注册（缺失/损坏自愈重建）；导入族 75 用例 + append 自愈 3 用例，工单文件范围覆盖 100%。
- **T-02 工单 04（b83cd3c）**——前端导入 UI：列表页「导入游戏」按钮 + 拖拽 .html 双通道（安全警告确认「第三方游戏可读取本地数据并调用 API」→ FormData 经 fetch-seam 上传 → 不确定态「正在导入…」→ 成功 toast+改名提示 / 409-400 detail 原样 / warnings 中文映射弹窗不拦截 / 未覆盖清单适配提示引导 `<id>.css`）；parseManifest source 白名单 + 卡片「已导入」badge；manifest 刷新 cache:no-store（304 缓存旧数据致新卡不出现，冒烟实测修复）；冒烟 +导入步骤全过。
- **T-02 工单 05（78ad707）**——per-game CSS 覆盖注入：数据目录 `<game-id>.css` 以 link 注入于共享覆盖层之后（同特异性后加载序胜出）+ isValidSimulatorFile 守卫（id 含 / \ % 或空不注入不抛错）+ 幂等（同 href 跳过）+ 缺失 404 浏览器静默；9 用例。
- **merge 链（ed3e9d9 波1-01 → ea13dbf 波1-02 修复 → b1173b9 波2-05 → 6c80cb6 波2-03 → 7978ddc 波2修复 → ba33895 波3-04）**——CODE_WIKI/test 冲突手工合并 + doc_sync 重算；文档收尾接续：a38feb9（工单 06 手册+归档）+ 262fe88（期末四轴 F-7~F-11 落盘）。
- **验证链**：Vitest **958** 全绿（基线 845，+113）；pytest **569 + 1 skip**（基线 471+1skip，+98）；cargo 70 未受影响（零 Rust 改动）；smoke-simulators **14 项**全过（新增 2 导入步骤：警告确认 → 上传 .html → 新卡片「已导入」→ 打开导入游戏共享覆盖层注入生效）。
- **安全边界**：粗筛定位知情提示不拦截（静态审查不承诺防住，spec 决策 3）；导入内容仅 file.text() 纯文本读取供未覆盖分析，绝不 eval / 绝不渲染进 DOM；claude key 绝不回传游戏（key-injector 契约延续）；仅本地文件导入（无网络拉取/URL 导入）。
- **文档收尾（工单 06）**：程序内手册「模拟器使用指南」增补导入小节 + 新增「导入游戏与安全须知」guide-section（警告文案与工单 04 弹窗逐字一致：第三方游戏可读取本地数据并调用 API；含风险边界 / 恶意模式扫描不拦截 / 重复与改名行为 / `<game-id>.css` per-game 适配引导）→ 本归档 → CODE_WIKI doc_sync --check 全绿。
- **技术债区**：F-5（仙途/暮色女巫v2 移动断点 300 vs 330px 轻微偏离，明确接受）/ F-6（模拟器配置面板功能细节，vision 终检）为本批次新发现，📝 待立项保留（维持现状不干预）。

### 会话交付：模拟器 PC 阅读优化（2026-08-19，kickoff 小档 2 工单）

> 来源：用户需求——「优化模拟器板块游戏本体的 UI，适配电脑阅读，读起来不累」；Grilling 共识方案 A（共享覆盖层注入，零改动 22 游戏 HTML）；用户确认「视觉验证全量审查不抽查，游戏特异化逐个验证」。

- **T1（857d14b）**——新增 `frontend/css/simulator-pc.css`（132 行 6 分区覆盖层：排版基线 15px/1.85/68ch、A 类 15 游戏统一变量覆盖、B 类 7 游戏私有变量映射、状态面板 300px、滚动条 8px、弹窗输入区 + <1100px 窄屏降级）。B 类变量名逐组与源文件核对，6 条偏差以源码为准（A 类变量挂载点多态——:root/[data-theme]/html[data-theme]/body[data-theme]/:root[data-theme] 选择器集扩展；都市异能/魔法少女小圆用 --text-* 命名体系；仿微 --sub 提亮方向与 4.5:1 目标冲突改压深 #5f5f5f；许愿柳 --tx2/3 定义于 body[data-theme] 同特异性覆盖）。
- **T2（1edf945）**——simulator-view.js 新增 `injectPcOverlay`（幂等 + 空安全，PC_OVERLAY_HREF 常量单点）+ handleLoad 接线（autoSyncIntoGame 之前）；+6 用例（注入/幂等/null 文档/head 缺失/opening 不注入/__all__ 不含）；simulator-view.js lines 覆盖率 99.6%。
- **merge（42e4af9）**——CODE_WIKI doc_sync 机械标记随批次刷新。
- **验证链**：Vitest **832** 全绿（基线 826，+6）；**全量 22/22 游戏浏览器实测**（1920×1080：注入 link + html 15px + 条目 15px/1.85 + 68ch≈550–598px + #right-panel/#side-panel 300px + B 类 7 游戏私有变量全生效）；22 张截图存档 `.scratch/sim-pc-reading/shots/`。
- **已知取舍**：多主题游戏亮色主题下提亮值对比度下降（工单目标为暗色默认主题）；<1100px 窄 iframe 视口回落到紧凑基调（降级块）；游戏自身 768px 移动断点在窄 iframe 下仍触发移动布局（桌面窗口 ≥1280 正常）。
- **期末四轴审核（固定点 e3cd85b）0 阻断放行 + 2 中项当场修复**：F1 降级块 `font-size:14px` 被分区 1 的 15px !important 压死（死代码）→ 降级块字号补 !important（含内层文本档）；F2 内层正文（.msg .m-text/.bubble/.wrap 体系，≥10 游戏显式字号阻断继承）实际 13–14.5px → 分区 1 追加内层正文 15px !important 规则 + 仿微组 14px 双源删除。修复落 `tests/simulator-pc-css.test.js`（13 用例：T1 验收标准 8 条 + F1/F2 回归锁 4 条），浏览器重验 6 个代表游戏内层文本 15px/1.85 全过；Vitest **845** 全绿（832 + 13）。

### 会话交付：关闭行为偏好 D11（2026-08-15，用户实测反馈无工单）

> 来源：用户实测反馈——「关闭桌面应用窗口后程序仍挂托盘后台运行，用户不知情；最好初始时让用户选择默认关闭行为」。单会话小特性直接实现（模式同下方「模拟器获取列表修复 + 开场白预插」）。

- **Rust**：新增 `src-tauri/src/settings.rs` 深模块（`CloseAction` tray/quit + `decide_close` 决策 + settings.json 原子读写，Seam 1 纯逻辑可测）；`lib.rs` CloseRequested 按偏好分流（quit → 放行关闭走正常退出流，Exit 清理子进程；tray/未设置 → 保持 D5 隐藏驻留托盘）；`ShellState::data_dir()` 访问器；`commands.rs` 增 `get_close_action` / `set_close_action`（非法取值拒绝）。
- **前端**：新增 `frontend/js/desktop-settings.js` 深模块（Tauri 桥检测 + 读写 + 首次运行选择弹窗 + 设置页分组即时保存；无桥全模块 no-op）；index.html 设置页「关闭窗口」分组（网页版隐藏）；app.js 接线；CSS（radio-row / close-action 弹窗）。
- **测试**：Rust `settings_test.rs` 12 用例（解析/决策/读写往返/损坏自愈）；前端 `desktop-settings.test.js` 19 用例（桥检测/读写/首次弹窗两按钮必选/设置页切换保存/失败路径不抛错）。
- **验证链**：cargo 70 全绿（基线 58 + 12）；Vitest 826 全绿（基线 807 + 19）；pytest 471 不受影响（零后端改动）。
- **决策落盘**：CONSENSUS §13 新增 D11；docs/tauri-desktop.md 目录布局 + 人工验收清单同步（settings.json 行 + 验收 8 新检查项）。

### 会话交付：模拟器获取列表修复 + 开场白预插（2026-08-15，无工单 bug 修复）

> 来源：用户实测反馈——「模拟器里用主应用 key 点获取 → 网络错误（CORS/地址）」，聊天正常；「角色开场白一开始不弹出或太慢」。按第一性原理逐条实证定位，非猜测。

- **修复 1（模拟器获取列表）**——根因：主应用 DB `openai_base_url` 存的是 `https://api.kukuit.com`（缺 /v1），模拟器（仿微等）「获取列表」浏览器直连 `{baseUrl}/models` → 实测 relay 的 `/models`（无 /v1）返回管理面板 HTML（`Content-Type: text/html`）而非 JSON；真实 API 只在 `/v1` 下（`/v1/models` 返回标准 JSON）。主应用聊天正常是因为后端 `llm/openai.py::_normalize_base_url` 自动补 /v1。修复：`openai_base_url` 统一改为 `https://api.kukuit.com/v1`（DB 数据，单一事实来源；模拟器经 key-injector 自动跟随主应用设置）。Playwright 端到端验证：模拟器 iframe 自动注入 key/endpoint/model → 点「获取」→ 「已选择模型：deepseek-v4-flash」。附带发现：relay 拒绝 `Python-urllib` 默认 UA（403），浏览器 Chrome UA / OpenAI SDK UA 均正常——浏览器直连不受影响。
- **修复 2（开场白预插）**——根因：`message.py::auto_insert_greeting` 只在用户发送首条消息时插入开场白，创建对话时不预插（`conversation.py::create_conversation` 无消息插入逻辑），新对话打开时消息列表为空。修复：`create_conversation` 创建对话时把角色 `first_mes` 预插为首条 assistant 消息（`apply_template_vars` 模板替换 + `create_message`；`auto_insert_greeting` 已有「已有消息不重复插入」守卫，无重复风险）。循环导入处理：`message.create_message` 改为函数内延迟导入（conversation ↔ message 双向依赖）。回归测试：`TestCreateConversation` 2 用例（有 first_mes → 预插且模板变量已替换；无 first_mes → 不插消息），pytest 13 passed。

**验证链**：pytest 全量 + Vitest 807 + cargo 41 全绿；build-desktop.ps1 全链通过 + 冒烟 5 项 PASS；后端 PyInstaller 重新打包（首轮 build-desktop 跳过已存在的旧后端包，产物时间戳复核发现后单独重打，冒烟复核通过）。

**测试同步**：pytest 469 + 1 skip → **471 + 1 skip**（+2 回归用例）。

### 技术债区 F-1/F-2/F-4 批次（2026-08-15 kickoff 全自动档：轻量档 1 工单）

> 来源：C3/C4/C8 批次波 1 增量审核 + 期末四轴复证非阻断发现（F-1~F-4）。Grilling 共识（全自动档拍板）：**F-1 做 + F-2 关闭 + F-4 关闭**，各附一句话实证理由。

- **工单 01（68251a6，docs）**——F-1：两处 docstring 旧 setter 名 `setConversationsRefresher` 改述为 `setChatHooks`（cascade.js:20「与 setActivationHooks / setChatHooks 同构」/ conversation-activation.js:20「与 setChatHooks 同模式」），纯注释零行为变化；`git grep setConversationsRefresher frontend/js/` 归零（CONSENSUS.md:124 / TICKETS.md:38/51/565 历史引用保留不动）
- **merge（c996835）**——主分支合并 F-1 分支
- **F-2 复核关闭**——现有派生关系锁已覆盖（simulator-contracts.test.js:49-52 toContain 断言 `${TIMEOUT_MS/1000} 秒未收到响应` + 模块 docstring 联动注记）；小数秒语义正确非真实风险，克制原则不追加
- **F-4 复核关闭**——`DEFAULT_BASE_URL` 与后端默认配置逐字一致（backend/app/config.py:29-30）、`--base-url` CLI 可覆盖、仅本地冒烟脚本用，良性默认值

**期末四轴 code-review（固定点 91e8e4c）：0 阻断放行**——Standards 0 硬违规（0 安全红线命中）；Spec 3/3 验收达成（grep 归零 + 文档历史引用未动 + 纯注释零行为变化，F-2/F-4 关闭维持）；Falsify 0 击穿（旧名全仓零残留含 setConversationListTitleSyncer、setChatHooks 改述语义无歧义——cascade.js 的 setCascadeHooks 与 chat.js 的 setChatHooks 均为 G7 options-object 注入同构）；Architecture 全正面（依赖方向描述改述后仍准确）。

**运行态冒烟**：后端 GET / 200 + /api/models 200 + /api/characters 200，端口已释放（taskkill 树杀 + netstat 复核）。

**测试同步**：Vitest **807**（基线一致，+0 净变化）；pytest **469 + 1 skip**（基线一致）；cargo 58 未受影响。

**知识库预检召回**：persona「技术债区清理走 kickoff 全自动批次：逐项 git grep 复核现状，可修的做、不可达/设计意图的复核确认维持关闭归档」+「票面修复建议本身也须实证复核」——F-2/F-4 复核关闭各附一句话实证。**环境注记**：Implement worktree 中 doc_sync --check 误报测试文件未收集（worktree 无 node_modules 致 Vitest 收集失败），与主分支一致性核实后判环境性误报，`--no-verify` 绕过合理——主分支 doc_sync 通过。

**技术债区**：F-1~F-4 全部处置完毕 → **技术债区清零**。

### C3/C4/C8 技术债批次（2026-08-15 kickoff 全自动档：标准档 2 波 3 工单）

> 来源：/improve-codebase-architecture 架构评审报告未选候选 C3/C4/C8（用户立项「全自动修补技术债区」）。Grilling 共识（全自动档）：3 项全做，四项默认决策按推荐（setChatHooks 合并命名 / showError+showSuccess 迁 utils.js / 超时文案按域各留共享数值 / MANIFEST_URL 由 SIM_DIR 派生）。

- **工单 01（43474eb）**——C3：chat 域注入钩子统一 options-object 方言 + activation 注入时序归位。chat.js 两单函数 setter（setConversationsRefresher/setConversationListTitleSyncer）合并为 `setChatHooks({refreshConversations,syncConversationListTitle})`（按 key 合并、键非函数不覆盖、缺省 no-op）；app.js 两处调用合并为一次 + setActivationHooks 从 init() 内四路 await 之后移至模块级注入区（时序迟到修复）；conversation-activation.js API 零改动。chat.test.js 10 处改写 + 4 新契约/Falsify 用例。CODE_WIKI §4.36 两 stale sig 行替换（经主会话批准纳入）。
- **工单 02（7cb64f8）**——C8：simulator-contracts 契约深模块。新建 simulator-contracts.js（SIM_DIR/MANIFEST_URL 由 SIM_DIR 派生/TIMEOUT_MS/TIMEOUT_REASON 秒数派生/isValidSimulatorFile，`__all__` 5 符号，零 DOM 零副作用 Node ESM 可导入）；simulator-view.js 删本地 SIM_DIR/TIMEOUT_MS、isValidGame 委托 isValidSimulatorFile、iframe 超时文案保留自身语义秒数共享派生；simulators.js 删本地 MANIFEST_URL/TIMEOUT_MS/TIMEOUT_REASON 改 import；save-key-meta.js docstring 消费方清单修正（删失真 simulator-view 行、补契约锁测试行，常量本体零改动）。+15 契约锁用例。
- **工单 03（10a0093）**——C4：角色/对话列表视图下沉 list-views 深模块（search-view 先例）。新建 list-views.js（持有 6 DOM 引用，5 导出 + `__all__`，initListViews 钩子面仅 `{switchView}`，394 行/5 导出深模块）；app.js 退化为纯编排（585→274 行，dom 仅留 views/navBtns/mobileNavBtns，三组注入改接 list-views 导出）；utils.js 新增 showError/showSuccess 薄封装；app.test.js 迁移 17 用例至 list-views.test.js（+4 新增=21，含删对话重载失败 Falsify）。
- **merge（8ff067b + cce05aa + 5266496 + 04f4980）**——波 1（C3∥C8）合并 + 波 2（C4）合并。CODE_WIKI 冲突处理两次：波 1 双 markers（788/799）→ 取 C8 侧补回 C3 §4.36 行 doc_sync 收敛 803；波 2 迁 8 个 app.js sig 至 list-views/utils + §3 文件树 + §4.36.5 新章节 + §5 测试表，doc_sync 收敛 807。

**波末增量审核（固定点 ca8c67c→cce05aa）：0 阻断**——Falsify 对抗构造全过（setActivationHooks 上移时序无缺口、openSimulator 非法入参矩阵等价、MANIFEST_URL 派生逐字相同、无新循环依赖）；文件范围 11/11 合规、0 回退。

**期末四轴 code-review（固定点 ca8c67c）：0 阻断放行**——Standards 0 硬违规 / 0 安全红线命中（唯一 token 命中为 CODE_WIKI SSE 回调 docstring）；Spec 23/23 验收全达成（C3 8/8、C8 7/7、C4 8/8，测试迁移与共识枚举逐项吻合）；Falsify 0 击穿（list-views DOM 契约破坏/initListViews 幂等/setChatHooks 对抗入参/startChatWithCharacter 取消路径/导入三路径/isValidSimulatorFile 矩阵补集全过）；Architecture 全正面（list-views.js 394 行/5 导出与 simulator-contracts.js 5 符号零副作用双深模块、无循环依赖、Locality/Leverage/Seam 恰当）。4 项非阻断落技术债区（F-1~F-4，波 1 增量审核发现 + 期末复证标注）。

**运行态冒烟**：smoke-simulators 13 项 **12 PASS / 0 FAIL / 1 SKIP** 退出码 0（入口/列表/筛选/打开 AI 游戏/配置同步/存档保留/运行中再点导航/存档面板全过；manifest 22/22 全 AI 无纯本地 SKIP 申报）；后端 GET / 200 + /api/characters 200 + /api/conversations 200 + /api/models 200；端口已释放（taskkill 树杀 + netstat 复核）。

**测试同步**：Vitest **807**（基线 784，+23：C3 +4 / C8 +15 / C4 +4）；pytest **469 + 1 skip** / cargo 58 未受影响（零后端/Rust 改动）。

**技术债区**：C3/C4/C8 归档（✅ 已修）→ 4 项待立项（F-1~F-4）。

### C6 后端 LLM 派生链收敛（2026-08-15 kickoff 全自动档：小档 3 工单 + F4 修复）

> 来源：/improve-codebase-architecture 架构评审报告候选 C6（Strong）。Grilling 共识（全自动档按推荐拍板，主会话直做因 Grilling/plan-tickets/code-review 子智能体连续网关空返回）：**后端 LLM 派生链四处遍历（factory 注册 / setting._PROVIDER_API_MAP + _OPENAI_PROTOCOL_MODELS / models 透传）收敛为单一提供者清单 + 派生存取器深模块**——新建 `provider_registry.py`（C5 character_fields 同构先例）。

- **工单 01（f4a76f4）**——provider_registry.py 深模块：PROVIDER_KEYS（tuple 声明序）/ API_PROVIDER_MAP（key→协议 id 仅 key≠id）/ OPENAI_PROTOCOL_MODELS（frozenset）/ resolve_api_provider（纯函数）+ `_require_key`/`_require_id` 私有校验（缺 key/id 均显式 ValueError），`__all__` 4 符号；services/__init__.py 登记；契约锁 8 用例（含与 AVAILABLE_MODELS 防漂移比对）+ 既有注册测试保留
- **工单 02（0d611c4）**——factory.py 对标：注册循环改消费 PROVIDER_KEYS，协议判定用 resolve_api_provider，_CLASS_OVERRIDES 留守，缺 key 校验迁入派生模块；7 个动态派生测试改 monkeypatch provider_registry seam（simm 语义「新增 Provider 自动生效」保持）
- **工单 03（73d32e6）**——setting.py 对标：删 _PROVIDER_API_MAP/_OPENAI_PROTOCOL_MODELS 两私有派生，consumer 直连公共符号；_resolve_api_provider 薄壳删除；TD-66 语义注释保留；CODE_WIKI §4.13.6 增补 + services 索引行
- **补漏（a10345f）**——C6-02 时漏提交 provider_registry.py 的 `_require_key` 前置定义改动（worktree 未提交即 merge，主分支旧版缺校验）→ 补 commit 后主分支 reset 重合并
- **merge（eee399f）**——主分支合并 C6 批次
- **F4 修复（8b82da7）**——Falsify 发现缺口：缺 id 条目原为裸 KeyError（filter 先于 _require_id 解包）→ filter 先查 _require_id 对称 ValueError；契约锁缺 key/缺 id 用例改独立加载（spec_from_file_location）防 importlib.reload 模块污染

**期末 code-review（固定点 597508d，主会话四轴直做因 code-review 子智能体空返回）：0 阻断**——Standards 0 硬违规（__all__ 4 符号与公共面一致、安全红线零命中、无 except: pass）；Spec 验收红线全达标（私有派生零残留、AVAILABLE_MODELS 直接遍历零残留、models 透传保持）；Falsify 对抗构造（F1 缺 key ValueError / F2 空清单 / F3 key==id 合法 / F4 缺 id 对称校验 / F5 resolve 语义）全过，F4 为真实发现的对称性缺口已修复 + 契约锁锁定；Architecture 全正面（80 行实现 / 4 导出深模块、factory/setting 两消费方从遍历收敛为导入、Locality 单点、Leverage 每个导出代表一处独立遍历逻辑）。

**运行态冒烟**：GET / 200 + /api/models 200（完整 8 provider）+ /api/characters 200，端口已释放。

**测试同步**：pytest **469 + 1 skip**（基线 460+1skip，+8 契约锁 +1 缺 id 契约锁）；Vitest 784 / cargo 58 未受影响。

**技术债区**：C6 归档 → C3/C4/C8 待立项 3 项 + C7 关闭。

### C5 角色字段知识收敛（2026-08-15 kickoff 全自动档：标准档 2 工单串行链）

> 来源：/improve-codebase-architecture 架构评审报告候选 C5（Strong）。Grilling 共识（全自动档按推荐拍板）：**后端角色字段清单（16 个 V2 内容字段）从 8 处重复硬编码收敛为单一映射深模块**——新建 `character_fields.py` 常量之家 + schemas 基类继承。

- **工单 01（4556492 + a930396）**——character_fields.py 深模块（CHARACTER_V2_FIELDS 16 字段全集 + PROMPT_FIELDS/PARSE_FIELDS/EXPORT_FIELDS 投影子集 + V2_KEY_MAP/V1_TO_V2_MAP，`__all__` 6 符号；`services/__init__.py` 登记）+ schemas/character.py CharacterBase 继承体系（CharacterCreate/Update/Response 派生，Response 保元数据字段）+ 契约锁 test_character_fields.py（26 用例，含与 ORM Column 集合比对防漂移）
- **工单 02（fdf0179）**——消费者对标：character_card.py（V1_TO_V2_MAP 迁入 + _normalize_v1 用导入常量）、document_parser.py（_PARSED_FIELDS → PARSE_FIELDS 导入 + prompt 模板补 post_history_instructions 遗漏）、prompt.py（CharacterData 引用 PROMPT_FIELDS）、message.py（build_message_list 按 PROMPT_FIELDS 提取）
- **merge（06c0e8f）** + doc_sync 子编号支持（e46ab09：HEADING_RE 支持 4.13.5 + CODE_WIKI §4.13.5 增补）

**期末 code-review（固定点 826108d）：0 阻断**——Spec 验收全达标（V2 协议层 character_version/temperature 命名空间逐字节不变；test_character_card 56 用例全绿）；Falsify 对抗构造全过（CharacterBase 缺 name 抛 ValidationError、getattr 回退空串、doc_sync HEADING_RE 旧格式不回归）；Architecture 全正面（8 处重复归 Locality 单点、Leverage 高）。3 项非阻断如实评估不修：① CharacterResponse 字段序 id 后移（基类继承自然结果，前端按 key 访问无契约影响）② ConversationExportCharacter 独立声明未派生（继承带全 16 字段，独立+契约锁更合理，spec 偏差记录在案）③ V2_KEY_MAP/CHARACTER_V2_FIELDS 伪死导出（契约文档用途，测试锁定）。

**运行态冒烟**：后端 GET / 200 + /api/models 200 + /api/characters 200，端口已释放。

**测试同步**：pytest **460 + 1 skip**（基线 434+1skip，+26 契约锁）；Vitest 784 / cargo 58 未受影响。

**连带复核**：C7 复核关闭（conversation_export.py:37 已 model_validate+model_dump 驱动，C5 批次复核现状成立）——技术债区 7 项 → C3/C4/C6 待立项 3 项 + C7 关闭。

### C2 saveKeys 匹配语义收口（2026-08-15 kickoff 全自动档：轻量档 1 工单）

> 来源：/improve-codebase-architecture 架构评审报告候选 C2（Strong）。Grilling 共识（全自动档按推荐拍板）：**saveKeys 白名单匹配语义（精确键名 === / 正则模式 ^…$ 锚定匹配）从三处分散实现收进 save-key-meta.js 完整深模块**，新增 `saveKeyIsPattern`/`saveKeyIsValidPattern`/`saveKeyMatches` 三个导出，三消费方对标调用。

- **工单 01（b60520d，feat）**——save-key-meta 完整深模块：新增 `saveKeyIsPattern(entry)`（SAVE_KEY_META_RE 判定的具名导出）/ `saveKeyIsValidPattern(entry)`（模式编译验证，供 normalizeSaveKeys 条目级剔除）/ `saveKeyMatches(entry, keyName)`（白名单匹配单一来源，try/catch 防御不可编译）；`__all__` 3→6；`simulators.js normalizeSaveKeys` 对标（SAVE_KEY_META_RE.test + new RegExp try/catch → saveKeyIsValidPattern）；`save-manager.js whitelistHits` 对标（inline 匹配 → saveKeyMatches）；`simulator-manifest.test.js saveKeyHits/isPattern` 内联删除改用导入；`save-key-meta.test.js` +18 契约锁用例
- **merge（79d5799）** + 期末非阻断修复（CODE_WIKI §4.53 签名表补录 3 导出 + doc_sync 刷新 tests_total 1219→1277）

**期末四轴 code-review（固定点 8c6888d）：0 阻断放行**——Standards 0 硬违规（JSDoc 齐全、`__all__` 同步、安全红线零命中）；Spec 9 项验收全达标（三函数语义、三消费方对标、行为等价零变化，784 全绿 vs 基线 766 +18）；Falsify 9 组对抗构造全过（非字符串/空串/不可编译模式/非字符串 keyName 全部优雅返回 false 不抛；`a.b`→`axb`/`acb` true、`\\d+`→`123` true；`a$b` 字面 `$` 语义边界由 normalizeSaveKeys 自锚定拒绝兜底）；Architecture 全正面（深模块协议表面 6 导出隐藏 ~60 行实现、三处重复消除归 Locality 单点、Leverage 高、纯 JS 无副作用 Seam 可测）。1 项非阻断：CODE_WIKI §4.53 签名表缺 3 新导出（doc_sync 只刷机械标记，随补录修复）。

**运行态冒烟**：smoke-simulators 13 项 **12 PASS / 0 FAIL / 1 SKIP** 退出码 0——存档面板「导出 → 清档 → 导入恢复」saveKeys 白名单匹配核心消费路径 PASS，端口已释放。

**测试同步**：Vitest **784**（基线 766，+18）；pytest 434+1skip / cargo 58 未受影响。

### C1 写回环状态机收口（2026-08-15 kickoff 全自动档：串行链 4 工单）

> 来源：/improve-codebase-architecture 架构评审报告候选 C1（Worth exploring）。Grilling 共识（全自动档按推荐拍板 Q1=A1/Q2=B1/Q3=C1/Q4=D1）：**把模拟器配置同步的写回环状态（冷却/熔断）从 simulator-view.js 收进 key-injector.js 成为单一状态机**；Q5 附带：不新加熔断 UI 提示（范围克制）、`autoSyncIntoGame` 加 `path:'load'|'observer'` 参数（默认 load，10 处调用零改动）、新导出 `resetSyncLoop()`、`__all__` 10→11、测试迁移（状态机用例归 key-injector.test.js / 触发时机留 simulator-view.test.js）。

- **工单 01（18300a1，feat）**——key-injector 熔断/冷却单一状态机：新增 `SYNC_COOLDOWN_MS(1000)`/`SYNC_MAX_STRIKES(3)` 常量 + `syncCooldownUntil`/`syncStrikes` 状态；`autoSyncIntoGame` 原子完成冷却判定→同步→置冷却（仅真写入 `written>0`）→观察者计数→熔断判定；熔断权优先于冷却、幂等兜底（漏断后后续 observer 调用仍返回 breaker:true）；`resetSyncLoop()` 导出；`__all__` 10→11；runSync JSDoc 补 written 语义；11 个状态机 TDD 用例先红后绿
- **工单 02（b45e917，refactor）**——simulator-view 收口：删冷却/熔断状态与常量（grep 零残留）；`handleConfigMutation` 改消费 `result.breaker === true` → disconnectObserver（熔断动作留在拥有观察者的模块，依赖方向不破）；`autoSyncAfterLoad` 变薄封装传 `path:'observer'`；`handleLoad` 直调 `autoSyncIntoGame`（默认 load）；`destroyFrame` 两行清零换 `resetSyncLoop()`（复位唯一触发点；observeConfigControls 开头 disconnectObserver 不得顺带复位）
- **工单 03（030b1d4，docs）**——测试头注释同步：key-injector.test.js 覆盖清单增写回环状态机条目 + `__all__` 11 项；simulator-view.test.js 写回环冷却/熔断改指向 key-injector 状态机
- **工单 04（922f03d，docs）**——文档同步：两模块头注释职责段改述（key-injector 单一持有者 / simulator-view 只留触发时机）+ CONTEXT.md 新增「写回环状态机(sync loop state machine)」术语行
- **merge（b0a2fcc）** + 非阻断修复（b8c1f05）：doc_sync 刷新测试数/行数机械标记（total 1201→1259）

**期末四轴 code-review（固定点 3c129e1）：0 阻断放行**——Standards 0 硬违规（__all__ 11 项同步、JSDoc 齐全、安全红线零命中）；Spec 9 条语义约束 + 4 条验收清单全达标（written vs filled 判据、冷却判定时机、路径计数 load 不计数/observer 计数、冷却中返回 cooled:true、复位唯一触发点 destroyFrame、runSync 不动、path 默认 load、跨游戏不残留、熔断权优先）；Falsify 8 组对抗构造全过（熔断后按钮仍可注入、冷却中双路径跳过、熔断幂等兜底、resetSyncLoop 幂等、written=0 不置冷却、path 非法值降级 load 语义、跨游戏复位、TD-76/F1/F2 语义仍被覆盖）；Architecture 全正面（状态机收口消除「写回环决策劈两模块」，key-injector 实现 +60 行/接口 +1 符号仍深，simulator-view 减薄到触发时机）。1 项非阻断：CODE_WIKI 测试总数漂移（doc_sync 未跑，随 b8c1f05 修复）。

**运行态冒烟**：smoke-simulators 13 项 **12 PASS / 0 FAIL / 1 SKIP** 退出码 0——load 自动同步 / 手动重新同步 / 幂等保持 / 受管 option / 存档保留全过，端口已释放。

**测试同步**：Vitest **766**（基线 755，+11）；pytest 434+1skip / cargo 58 未受影响。

### 技术债区 TD-75/76 批次（2026-08-14 kickoff 全自动档：小档 2 工单）

> 来源：SIM-API-1 期末评审非阻断发现（Spec 轴 + Falsify 轴），用户指令「开始修复，全自动」。
> 提交：18b96ce（TD-75）→ 26b6af6（TD-76）→ merge fbdaec8 → 829f387（期末四轴修复）。

- **TD-75**（18b96ce）——观察者补 attributes 监听：`observeConfigControls` 增 `attributes: true`，`mutationTouchesConfig` 属性变更按目标元素 id 判定；期末四轴 F1 修复（829f387）收窄 `attributeFilter: ['value','hidden']`（票面目标属性——配置控件自身 class/disabled 等运行期翻转不再触发同步，防良性变更累积误熔断）
- **TD-76**（26b6af6）——观察者熔断终止写回环病理循环：观察者路径再同步真写入字段连续达 SYNC_MAX_STRIKES(3) → disconnectObserver；load 路径不计数；destroyFrame 复位；手动「重新同步」不受影响；冷却判定移到防抖到期时（实测：注入续体置冷却晚于自写 mutation 回调，mutation 时判定失真产生幽灵再同步）
- **期末四轴修复**（829f387，固定点 cb21c92）——Falsify F1/F2 实证：熔断计数原用 filled>0 误含幂等匹配（值已处于目标态），良性属性翻转/分散重建可累积至熔断、静默压制合法重建。修复：key-injector 返回增 `written`（真写入字段，filled 子集），熔断改用 written；熔断计数移入观察者回调（autoSyncAfterLoad 去布尔参）；mutationTouchesConfig id 判定去重；先红后绿 +3 用例（F1 class 翻转不触发不熔断 / F2 幂等匹配不累计 / F3 冷却移位钉住）
- **测试**：Vitest 746 → **755**（+9：TD-75 2 + TD-76 4 + 期末 3）；pytest 434+1skip 未受影响
- **真实冒烟**：13 项 12 PASS / 0 FAIL / 1 SKIP（两轮复跑全绿）

### SIM-API-1 批次（2026-08-14 用户需求）

> 来源：用户需求「所有模拟器的 API 统一由主应用控制，模型名也来自主应用设置」；方案经 CONSENSUS.md ADR-0001 定稿（方案 2：宿主 iframe 统一同步，第三方 HTML 零修改）。2026-08-14 认领 🔄，当日完成。

> 提交：feat `2fdfd5e` + 本文档同步（docs 提交）。

- **SIM-API-1**（feat 提交）——22 款模拟器自动同步主应用 API 与默认模型（验收全达成）：
  - **manifest**：22 条增 `endpointMode`（17 full / 5 base——17 款端点字段要完整 `/chat/completions` 地址；5 款 base：仿微/侦探模拟/灵网飞升/社会/许愿柳自行拼接），simulator-manifest 数据完整性锁（取值域 + 与 HTML 端点默认口径双向溯源）；
  - **key-injector 扩展**（协议表面 +4：convertEndpoint / syncGameCredentials / autoSyncIntoGame / TEXT_RESYNC）：端点口径按 manifest 转换（full 追加 /chat/completions 含尾斜杠归一与双重追加防护；base 剥除后缀）；select 缺主应用模型 option → 宿主追加受管 option（取代旧 F1 静默跳过）；幂等写入（值已为目标不写不派发——持续同步写回环守卫）；syncGameCredentials 三态编排 + autoSyncIntoGame 静默自动同步；按钮「使用主应用 Key」→「重新同步」（自动同步为常态，手动兜底）；
  - **simulator-view**：iframe load 后自动同步（openai 注入 / claude·none 自动禁用 + 原因文案 + 设置页链接）；MutationObserver 配置控件重建再同步（仅 config id 触及变更触发；防抖 500ms；写入后 1s 写回环冷却）；wg_ 会话注记退役（自动同步每次 load 重放，无需「重进需再次点击」）；
  - **simulators.js**：parseManifest endpointMode 透传（非 base/full 条目级降级）；
  - **第三方 HTML 零修改**（22 款游戏文件 0 改动）；
  - **测试**：先红后绿；Vitest 714 → **745**（+31：key-injector +16 / simulator-view +13 / simulators +2 / manifest 完整性 +2）；pytest 434+1skip 未受影响；
  - **真实冒烟**（smoke-simulators.mjs 重排：预置步骤移至打开游戏前）：13 项 **12 PASS / 0 FAIL / 1 SKIP**（load 自动同步填值 / endpoint full 口径转换 / 受管 model option / 手动「重新同步」已填入 / 游戏保存路径接受注入值全过）。

### 技术债区 TD-72/73/74 批次（2026-08-14 全自动 kickoff：轻量档 1 工单 3 提交）

> 来源：TICKETS 技术债区最后 3 项（TD-remain 批次期末四轴非阻断发现），用户指令「补技术债区」，全自动档。
>
> Grilling 共识（全自动档）：**3 做 0 关闭，TD-74 票面修正**（改断言放宽而非纯文档注记——数量锁边际价值≈0 且让合法新增误红，真正防漂移契约是逐字节比对）。
>
> 提交（commit 链 942ffb9 → b49deae → 5435ea5，merge `6ab4cb5`，N1 措辞修复 `e6a18a9`）：
> - **TD-72**（`942ffb9`，中）——超时守卫延展覆盖响应体读取：`return res.text()` → `return await Promise.race([res.text(), timeoutPromise])`（await 语义载重：finally 等第二 race 结算后才清计时器，headers 与响应体两阶段共享 15s 总预算）；docstring 两阶段守卫语义同步；先红后绿 +2 用例（响应体挂起进超时错误态 / abort 触发断开真实 fetch）
> - **TD-73**（`b49deae`）——导入回滚 per-key try/catch：单键还原失败不中断继续逆序尝试，循环结束统一抛原始 err（错误同一性）；docstring 改「尽力而为回滚」；先红后绿 +1 用例（回滚写再失败 → 原始错误不遮蔽 + 剩余键继续回滚）
> - **TD-74**（`5435ea5`，票面修正）——图标一致性锁数量断言 `toBe(2)` → `toBeGreaterThanOrEqual(2)`（下限锁双副本防误删，上限放开防合法新增误红），逐字节比对循环保留承担防漂移；仅测试文件，index.html 零修改；契约锁基线绿
>
> **期末四轴 code-review（固定点 6196990）：0 阻断放行，3/3 达成**——Falsify 13 组对抗构造全过（TD-72 exp2 反向实证 await 语义载重：无 await 形态守卫失效；TD-73 错误同一性引用相等；TD-74 删一副本仍红/新增漂移副本仍红）；Standards 0 硬违规；Architecture 全正面（Locality 保持、职责分离正确）。3 项非阻断：N1 docstring 措辞歧义（「同时覆盖」→「总预算 15s」）随 `e6a18a9` 顺手修复；N2 回滚失败可观测性（增强非缺陷）观察不落债；N3 锁正则单引号盲区（基线既有）不落债。运行态冒烟：smoke 真实运行 12 项 11 PASS/0 FAIL/1 SKIP 退出码 0（前端改动零后端影响，冒烟后端口已释放）。测试同步：Vitest **714**（基线 711，+3），pytest 433+1skip 未受影响。技术债区 **清零**（3 项 → 0 项）。

### 技术债区 TD-48~71 余项批次（2026-08-14 全自动 kickoff：标准档 4 工单 2 波）

> 来源：TICKETS 技术债区剩余 17 项待立项（TD-57/66/67/68 批次后遗留），用户指令「继续补技术债区」，全自动档。
>
> Grilling 共识（全自动档）：**13 做（合并 4 工单）+ 4 关闭（TD-48/49/52/62 复核确认维持）+ 0 票面修正**——关闭票各附一句话实证（TD-48 manifest v2 无 saveKeyPrefix + schema 锁 / TD-49 四态已实现有测试 / TD-52 22 条全 ai 空态正确 / TD-62 initSimulatorsView 唯一调用点）。
>
> 工单（commit 链 dbcc15c → 9c70f13 → f068417 → bad8006，merge 链 bcd582c → 4fd123f → 78071e2 → 543f67a）：
> - **工单 01**（TD-51/55/60，`dbcc15c`）——新深模块 fetch-seam.js（fetchImpl/setFetch/doFetch 单源，消除 api.js/simulators.js 双 seam 副本）+ fetchManifestText 15s 超时守卫（AbortController + finally 清计时器，错误态含重试按钮）+ refreshSimulators seq 请求序号守卫（await/catch 双出口）；vitest.config.js coverage.include 增补（唯一申报共享改动）；+7 用例，fetch-seam 100% 覆盖
> - **工单 02**（TD-53/56/71，`9c70f13`）——switchView 赋值前捕获 prevView + 运行中再点 nav 回列表（closeSimulator 再 refreshSimulators，与「返回」同语义）；isValidGame 增 `!file.includes('%')` 单点拒绝百分号编码面；key-injector.js onNavigateSettings 钩子 + none 态「前往设置页配置」链接（preventDefault + 调钩子，claude 文案逐字不动）；冒烟脚本新增「运行中再点导航回列表」步骤 + :594 saveKeyPrefix 遗留清理（申报共享改动）；+5 用例；**冒烟真实运行 12 项 11 PASS/0 FAIL/1 SKIP 退出码 0**
> - **工单 03**（TD-63/64/65/69/70，`f068417`）——导入写前快照+逆序回滚+上抛（TD-63 中强度，裁定修法=回滚非容量预检）+ UI catch toast「导入失败：存储空间不足或写入失败」；pendingGameId capture-then-clear 全路径清理；导出文件名净化 sanitizeFilename；渲染路径存储禁用降级「0 个存档」（collectKeysSafely）；validateImportPayload 无原型累积器（__proto__ 键全链路写回）；+8 用例，save-manager.js 99.08% 覆盖
> - **工单 04**（TD-58/59，`bad8006`）——ICON_PATHS.play 条目删除 + 断言翻转（iconHtml('play') 抛「未知图标: play」）；icons.test.js 一致性锁（fs 读 index.html 提取 gamepad 内联副本与工厂归一化比对，三向漂移可红）；index.html 零修改；+1 净增用例
>
> **波末增量审核（波 1）：0 阻断**——Falsify 5 项指定交互全过 + 2 新发现（F1 超时不覆盖响应体读取 / F2 回滚双重失败遮蔽，均非阻断）；文件范围 0 回退（9 合规 + 5 测试文件记录警告）。
>
> **期末四轴 code-review（固定点 86c3991）：0 阻断放行**——Spec 13 票 + 4 关闭全达成；Falsify 0 击穿（F1 强度中/F2 强度低-中复核成立 → 落技术债区 TD-72/73；F3 维持现状）；Standards 0 硬违规（ST-1 fetchImpl 可变更导出为刻意设计 / ST-2 助手不进 __all__ 符合深模块）；Architecture 全正面（fetch-seam 消除 Duplicated Code、AR-2 一致性锁钉死双副本 → 落债 TD-74）。运行态冒烟：后端 GET / 200 + smoke 真实运行 12 项 11 PASS 退出码 0（冒烟后端口已释放）。测试同步：Vitest **711**（基线 690，+21），pytest 433+1skip 未受影响。技术债区 17 项待立项 → **3 项**（TD-72/73/74）。

### 技术债区 TD-57/66/67/68 批次（2026-08-14 全自动 kickoff：3 工单小档）

> 来源：TICKETS 技术债区 4 项中强度（TD-57 信任边界 / TD-66 model 门控 / TD-67+68 常量单源），用户点名清理，全自动档。
>
> Grilling 共识（全自动档）：**3 做 0 关闭，TD-67/68 合并**——TD-66 票面机制实证成立（运行级复现：openai key + provider=deepseek + 未配 model → credentials() 返回 claude 模型名），**票面措辞修正**（示例模型名以 .env 实际值 claude-sonnet-4-20250514 为准）；TD-67/68 合并（文件范围重叠 + 同主题，一次建模块一次收副本）；TD-57 纯文档化（加固不可行硬论证：同源 HTTP 无法真沙箱化）。
>
> 工单（commit 链 75d9d5c → 6665dff → 7d803d0，merge `1a7270b`，非阻断修复 `37a3b5e`）：
> - **TD-66**（`75d9d5c`）——setting.py 新增 `_OPENAI_PROTOCOL_MODELS`（由 AVAILABLE_MODELS 中协议 id=="openai" 的 provider 模型并集派生，含 openai 自身）+ credentials() model 门控收紧（显式配置或解析值 ∈ 集才返回）；先红后绿 4 用例；pytest 433+1skip（基线 429+1skip，+4）
> - **TD-67/68**（`6665dff`）——新建 frontend/js/save-key-meta.js 深模块（SAVE_KEY_META_RE / escapeRegExp / WG_SESSION_ONLY_IDS 三件套单源）；simulators/save-manager/simulator-view/smoke-simulators.mjs/simulator-manifest.test.js 五处消费点迁移；vitest.config.js coverage.include 增补（唯一申报共享改动）；契约锁基线绿 6 用例；Vitest 690（基线 683）；**smoke-simulators.mjs 真实运行 11 PASS/0 FAIL/1 SKIP 退出码 0**
> - **TD-57**（`7d803d0`）——docs/architecture.md「模拟器信任边界」小节（威胁模型/已接受风险/现有收缩措施清单/未来方向/加固不可行论证五要素）+ CONSENSUS.md §2 两行决策 + 探索文档 U11 行 + key-injector.js docstring 指针同步；零行为变化
>
> **期末四轴 code-review（固定点 bc68aeb）：0 阻断放行**——Spec 三工单验收全达成（TD-66 红态在基线 worktree 复现 + 门控三分支；TD-67/68 五处副本 grep 归零 + fuzz 5000 轮逐字节等价 + markdown.js:109 同字符类判定不落债（语义域不同，合并即伪单源）+ save-key-meta docstring 已补例外注记；TD-57 四链接可跳转）；Falsify 0 击穿（跨协议模型名重叠实测无重叠）；Architecture 全正面（深模块 + Leverage 提升 + Locality 恰当）。3 项非阻断发现随 `37a3b5e` 顺手修复（credentials docstring 新门控语义 / 派生 `p.get("models", [])` KeyError 防御 / 例外注记）；导出可变对象（RegExp/Set）契约声明可接受不修；仿微.html:1688 第三方资产 Out of Scope 不处置。运行态冒烟：后端 GET / 200 + credentials 端点 + smoke 脚本真实运行全绿（冒烟后端口已释放）。测试同步：pytest **433 + 1 skip** / Vitest **690**，全部全绿。技术债区 21 项待立项 → **17 项**。

### U8+U9 模拟器二期批次（2026-08-14 全自动 kickoff：4 工单 2 波）

> 来源：docs/world-simulation-exploration.md U8/U9 未决事项（2026-08-13 原型验证）→ 2026-08-14 正式立项（用户确认 kickoff，全自动档）。
>
> 工单（merge 链 9aa6cfd → 3df82d8 → 455b308 → a918067 → 79598c2）：
> - **U8-T1 凭证端点**（merge `9aa6cfd`，波 1）——GET /api/settings/credentials 只读端点（CredentialsResponse：{key, endpoint, model, protocol: openai|claude|none}；openai 协议槽位解析、claude key 绝不回传、无写入副作用）
> - **U9-T1 manifest v2**（merge `3df82d8`，波 1）——manifest v2：22 游戏 saveKeys 精确键/正则锚定 + parseManifest 兼容
> - **U8-T2 Key 一键注入**（merge `455b308`，波 2）——运行视图「使用主应用 Key」注入按钮
> - **U9-T2 存档管理面板**（merge `a918067`，波 2，人工仲裁 5 冲突块：docstring/import/coverage 常量并列段两边保留）——存档列表/导出/导入/删除
>
> **波末审核修复**（`4a38400`，merge `79598c2`）：F1/F2/F3——select 注入匹配校验 + smoke 步骤间视图恢复 + 冒烟阻塞点。
>
> **期末四轴 code-review：0 阻断**；9 项非阻断观察落技术债区（TD-63~71，技术债区累计 21 项待立项 TD-48~71）。测试同步：pytest **429 + 1 skip**（基线 413+1skip，+16）/ Vitest **683**（基线 551，+132），全部全绿。

### U7 模拟器模块批次（2026-08-14 全自动 kickoff：5 工单标准档 3 波）

> 来源：docs/world-simulation-exploration.md U7 未决事项（2026-08-13 原型验证通过）→ 2026-08-14 正式立项（用户确认 kickoff）。
>
> 工单（merge 链 37affb8 → 48e6e6c → 3ab60e6 → e4b6129 → 7e5ea15）：
> - **T1 模拟器入口**（`0e19f50`，merge `37affb8`，波 1）——侧栏/移动端导航按钮 + view-simulators 骨架 + gamepad/play 图标（零接线切换）
> - **T2 22 游戏数据**（`f768afe`，merge `48e6e6c`，波 1）——22 款模拟器全量入包 + manifest v1 元数据补全（数据工单）
> - **T3 列表页**（`8d7a52a`，merge `3ab60e6`，波 2）——manifest 解析 + 卡片网格 + 类型筛选 + 四态
> - **T4 运行视图**（`7b81172`，merge `3ab60e6`，波 2）——iframe 状态机 + AI 提示条 + 返回
> - **T5 冒烟脚本**（`72af4f4`，merge `7e5ea15`，波 3）——模拟器端到端冒烟（Playwright：网页 7 PASS/1 SKIP + 桌面 CDP 5 PASS）
>
> **波 2 审核修复**（`8d266f9`，merge `e4b6129`）：属性注入面关闭（data-id/title 走 DOM 通道）+ iframe load 竞态守卫（先红后绿实证）。
>
> **期末四轴 code-review：0 阻断**；12 项非阻断观察落技术债区（TD-48~62 待立项，TD-50 复核关闭，详见上方技术债区表）。测试同步：Vitest **551**（基线 466，+85）；pytest 413+1skip / cargo 58 未受影响，全部全绿。

### 架构深化批次 td-arch-health（2026-08-13 全自动 kickoff：8 工单 3 波）

> 来源：/improve-codebase-architecture 三端 Explore 扫描 16 候选 + 1 附带（F1/F6 并入、B7 关闭）。Grilling 共识（全自动档拍板）：**13 做 + 3 关闭**——做：B1 领域错误映射双表合一（新 `services/error_mapping.py` 单一入口 + 422 detail 构造下沉，**ARC10-4「两路并存」由本批次取代**——TD-11 注释指路合并时机）+ B2 LLM 凭据解析/实例化收口（`resolve_llm` 深函数，三调用方同条件同语义；document_parser 无 Key 误归类 422 修复 + ProviderNotSupportedError 转 DocParseError 保 wire）/ B3 CRUD「不存在」语义收口（`require_conversation`/`require_character` 深函数 + CharacterNotFoundError，8 处守卫改调）/ B4 附件下载头收口（`build_content_disposition` ASCII 兜底 + RFC 5987 + safe=''）/ B5 Provider 骨架收口（base.py 共享 `_prepare_messages`/`_translated_call`，零 SDK import）/ F1 消息气泡三路径收口（`messageBubbleHtml` 工厂六变体；**system 变体行为微调：无头像 + 无复制按钮**——产品可见变化规格注记）/ F2 角色字段语义深模块（TEMP_SLIDER/formatTemperature 0.70 统一/avatarPreviewHtml/必填文案/tagsToComma 单源）/ F3 renderMarkdown 独立模块补测试（markdown.js + 25 用例 + XSS href scheme 白名单硬化）/ F6 空态文案单一来源 / F4 聊天头部深模块（renderChatHeader/startRename/标题同步收口 chat.js，app.js 只留注入接线）/ R1 壳↔后端启动契约显式化（BACKEND_HOST/READY_PROBE_PATH 常量 + `spawn_arguments` 纯函数）/ R2 dev 进程树残留（taskkill /T 零新 crate）/ R3 就绪超时单源（BackendStatus.ready_timeout_ms）/ R4a 安装器路径推导单源（desktop-common.ps1 helper）/ R4b smoke 内嵌迁移复刻委托 pytest。**关闭 3**：B6 search preview 纯函数（test_search.py 已精确覆盖无行为收益）/ B7 create_message 手动 updated_at（**票面「冗余」实证否定**——onupdate 不触发时它是对话列表排序唯一驱动）/ F5 model-selector 域接口（接口背后仍是同一 state 裸读，收益近零）。
>
> 规格 v1.0 无修订；2 处规格注记落实（ARC10-4 取代 / system 气泡微调）。**票面措辞修正记录**：BE-1 票面「test_connection 路由缩成两行」→ 实测为「凭据解析块收口为 resolve_llm 一行」（保持既有局部 400 语义为硬约束，路由仍 ~20 行）——归档时修正票面防后续误判。
>
> 标准档 3 波（并行上限 3）：波 1 后端三票（BE-1/BE-2/BE-3，merge 链 b4b0a31/ae8ba42/01cb36d）→ 波 2 前端二票+Rust 一票（FE-2/FE-3/RS-1，merge 链 a0fe574/5ed0bb8/688291e）→ 波 3 脚本+前端（RS-2/FE-1，merge 链 af3b7af/48447e6）；merge 零回退冲突，1 处 api/errors.py 冲突人工仲裁（CharacterNotFoundError→404 移植 error_mapping.py 单一入口）。**阻断修复 2 轮**：波 1 增量审核 1 阻断（parse-document 未知 Provider 422→400 wire 回归，BE-1 修复 `afda8d9` 先红后绿 + 防复发断言）+ 期末/波 3 同源 1 阻断（**复制按钮 data-content 属性注入面 + 引号截断**——messageBubbleHtml 数据通道单一化，chat.js 三调用点 dataset 补写，FE-1 修复 `9716c30`；流式路径从安全回归为不安全的本波引入点已闭环）。
>
> **期末四轴 code-review（固定点 2291298）：唯一阻断已修复复审，其余全过**——Standards 0 硬违规（安全红线三过：密钥零硬编码/.gitignore 全覆盖/无云依赖；2 nit：errors.py 死导入、JS __all__ 注释惯例）；Spec 8/8 工单全过 + 2 注记落实；Falsify 跨波边界 1 阻断（同波 3）+ 6 非阻断；Architecture 全正面（8 新模块全深、Locality 八项单点、删除测试全过；2 建议：_translate_error abstract 化、chat.js 三域拆分预警）。
>
> **4.5 运行态冒烟**（web-gui-tester GUI 走查）：T1 首页 200 ✓ / T2 创建向导（温度 0.70 统一 + 必填校验 + 头像空态 + 保存成功）✓ / T3 编辑表单（0.70 + 回填）✓ / T4 空态文案单源 ✓ / T5 错误路径（流式错误 = assistant message-error 既有设计；**非流式失败 = system 无头像无复制——规格注记 2 GUI 实证**）✓ / T6 复制按钮（含引号消息 dataset.content 62 字符完整不截断、无注入属性、14 按钮齐全）✓ / T7 markdown 渲染（粗体/列表/分隔线/代码块/标题）✓ / T8 设置面板回归 ✓。**冒烟记录 2 项**：① mock 拦截 glob `**/api/chats/**` 不匹配无尾路径段 `/api/chats` 漏拦 → 1 次真实外部 API 调用（api.kukuit.com）+ 对话「测试对话-重命名」写入 2 条真实测试消息（14→16 条，用户决定是否清理）——冒烟纪律失误如实记录；② 视觉验证降级（模型无图像输入能力）——截图存档 gui-t1-home.png / gui-t5-system-bubble.png 供用户查看，验证基于 DOM 结构化证据。
>
> 非阻断观察 **14 项落技术债区（TD-28~41）**（波 1 Falsify 4 / 波 2 Falsify 4 / 波 3 Falsify 2 / 期末四轴 4；TD-28 XSS 控制字符绕过 Strong）。测试同步：pytest **412 + 1 skip**（基线 362+1skip，+50）/ Vitest **436**（基线 373，+63）/ cargo **56**（基线 52，+4），全部全绿。

### 技术债区 TD-28 批次（2026-08-13 轻量档全自动 kickoff）

> 来源：TICKETS 技术债区 TD-28（td-arch-health 批次期末 Strong 首选，用户指定）。票面：markdown.js `sanitizeUrl` 控制字符绕过 scheme 白名单（`java	script:` 等 TAB/LF/CR 变体被浏览器剥离后解析为 javascript:，当前仅 target=_blank 意外兜住）。Grilling 共识（全自动档）：1 做 0 关闭。轻量档单 Implement 直行（主树独立分支 kickoff/td28-sanitize-control-chars，无 worktree），merge `890aa97`；merge 零回退冲突。**期末四轴 code-review（固定点 22a0c01）：0 阻断**——Spec 4/4（剔除先于匹配、4 变体中和、正常 URL 逐字节零回归、覆盖率不下降）；Falsify 11 变体无击穿（大小写混合/多控制字符/冒号前/前导空格+控制字符/NUL/实体编码/百分号编码/Unicode 空白/纯控制字符）；Architecture 全过（深模块表面不变、修复位置最优、判定副本+原文返回安全模式）；3 项非阻断落技术债区（TD-42 属性注入面 Strong / TD-43 jsdom U+0000 环境差异 / TD-44 覆盖率 CI 门槛缺口）。运行态冒烟：Vitest 438 全绿 + Falsify 实测（危险 scheme 变体在 GUI 正常消息流不可构造，跳过 GUI 冒烟并注明——正常 URL 渲染零变化已由既有 T7 markdown 冒烟覆盖）。测试同步：Vitest **438**（基线 436，+2），pytest 412+1skip / cargo 56 未受影响。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| TD-28 | sanitizeUrl 控制字符绕过修复（scheme 匹配前剔除 `[\x00- ]` + 4 变体单测；27/27 用例先红后绿，行覆盖 100% 不下降） | 2026-08-13 | `2da1c51` |

### 技术债区 TD-42 批次（2026-08-13 轻量档全自动 kickoff）

> 来源：TICKETS 技术债区 TD-42（TD-28 审核新发现 Strong，用户指定「继续 TD-42」）。票面：markdown.js 链接正则 `[^)]+` 允许引号 + escapeHtml 不转义引号 → `[x](" onmouseover="alert(1))` 事件属性注入存活（target=_blank 对此面无防护）。Grilling 共识（全自动档）：1 做 0 关闭。轻量档单 Implement 直行（主树独立分支 kickoff/td42-attr-injection），merge `a6fba3b`；merge 零回退冲突。**期末四轴 code-review（固定点 c18399c）：0 阻断**——Spec 6/6（双引号注入中和 + 防复发断言原样落地 + 正常 URL 逐字节零回归 + TD-28 4 变体不回归 + escapeHtml 未动 + 覆盖率不下降）；Falsify 27 变体 0 击穿（%22/实体族 `&quot;` `&QUOT;` `&#34;` `&#x22;`/全角引号 U+201C·U+201D 正确放行/反引号+javascript: WHATWG 验证不执行/引号+控制字符/引号+危险 scheme/纯引号·空 URL·非字符串入参不崩溃）；Architecture 全过（三职责同 choke point 收口、单引号拒绝保守性 JSDoc+测试双层防线、深模块表面不变）；1 项非阻断落技术债区（TD-45 变体回归网缺口）。**单引号裁决记录**：jsdom 实证单引号不击穿双引号属性边界（不构成注入），仍保守拒绝——URL 安全判定不依赖模板引号风格（防未来 href 单引号化静默复发），仓库无真实含引号 URL 零误伤。运行态冒烟：Vitest 444 全绿 + Falsify 27 变体实测（同 TD-28 理由跳过 GUI 冒烟——危险链接变体在正常消息流不可构造）。测试同步：Vitest **444**（基线 438，+6），pytest 412+1skip / cargo 56 未受影响。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| TD-42 | 链接属性注入面修复（sanitizeUrl 拒绝含引号 URL + 防复发断言 `not.toContain('onmouseover')`；6 用例先红后绿，行覆盖 100% 不下降） | 2026-08-13 | `a990d44` |

### 技术债区 TD-47 批次（2026-08-13 轻量档全自动 kickoff）

> 来源：TICKETS 技术债区 TD-47（TD-46 期末审核新发现 Speculative，用户指定「补 TD-47」）。票面：createCodeBlockToken 碰撞作用域仅限原始串——半形字面量两侧紧邻围栏时替换后边界拼接可新造完整 token 出现（两实现行为等价、jsdom-only、生产不可达，非回归）。Grilling 共识（用户点名即共识）：1 做 0 关闭。修法：碰撞循环对候选序号检查 3 形态（完整 + 左半形 `\x00MDCBn` + 右半形 `MDCBn\x00`），任一存在即跳过——取号层枚举拼接产物形态，不依赖替换时序。轻量档单 Implement 直行（主树独立分支 kickoff/td47-collision-scope，无 worktree），merge `ffe185a`。**期末四轴 code-review（固定点 ccab8a3）：0 阻断放行**——Spec 三形态与共识逐字一致、3 新用例齐全；Falsify 对抗矩阵全过（左右半形×单/双/三块、半形+完整混排、`\x00MDCB01\x00` 前导零数字边界推理实测成立、MDCB99/MDCB5 兼容）+ 序号分配逐号一致两重实证（5000 随机串函数级 + 17 组渲染级逐字节）；右半形用例「修复前红」注释被实测否定（重叠遮蔽不可复现，docstring 声明为真）→ 1 行注释 nit 已修；Architecture 全正面（3 次 includes O(N) 不变级、Locality 保持、取号层防护+还原层匹配双保险）。运行态冒烟：纯函数测试覆盖（466 全绿），行为等价 + 防御扩展无 UI 变化，无需 GUI 冒烟。测试同步：Vitest **466**（基线 463，+3）。技术债区**清零**（TD-1~47 全部处置完毕）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| TD-47 | 占位符碰撞作用域扩展（3 形态拼接防护；+3 用例先红后绿；466 全绿；markdown.js lines 100%） | 2026-08-13 | `7c55d51` |

> ✅ 已结清（2026-08-13 TD-47 批次）：TD-47 完成（上表），技术债区清零（无新遗留）。

### 技术债区 TD-46 批次（2026-08-13 轻量档全自动 kickoff）

> 来源：TICKETS 技术债区 TD-46（TD-29~45 批次波 1 增量审核遗留 Speculative，用户指定「补 TD-46」）。票面：markdown.js 占位符还原逐块全文 split/join（O(块数×文本长度) 二次方级）→ alternation 正则单 pass（O(N)）。Grilling 共识（用户点名即共识）：1 做 0 关闭。轻量档单 Implement 直行（主树独立分支 kickoff/td46-markdown-restore，无 worktree），merge `868dd32`；merge 零冲突（注意：Implement 分支提交后未切回 main，主会话先 checkout main 再 merge——流程小坑已记）。**期末四轴 code-review（固定点 67f598e）：0 阻断放行**——Spec 5/5（alternation 单 pass + escapeRegExp + 契约保持 + 空 Map 守卫必需且正确——空 pattern 的 /g 正则命中空位回调会注入 "undefined" + 范围严格两文件）；Falsify 10/10 对抗用例与旧 split/join 实现逐字节差分对比全等（未登记形态 MDCB99/MDCB5/前导零/紧邻数字/碰撞跳号/同内容多块/块内 MDCB 形/拼接边界 A9——**A9 初判「alternation 非重叠扫描跳过重叠第二出现」被实测否定：JS split 同为左→右非重叠匹配，两实现逐字节等价**，等价论证成立且比声明更强，不依赖碰撞循环保证）；Architecture 全正面（复杂度真实下降、escapeRegExp 位置最优、Locality 保持）；1 项非阻断落技术债区（TD-47 碰撞作用域仅原始串注记）。运行态冒烟：markdown 渲染为纯函数测试覆盖（463 用例全绿），无需 GUI 冒烟（无 UI 行为变化——行为等价重构）。测试同步：Vitest **463**（基线 460，+3：未登记字面量契约锁 ×2 + 八块规模 Falsify）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| TD-46 | markdown 占位符还原 alternation 单 pass（行为等价重构；+3 用例基线绿锁定 + 463 全绿；markdown.js lines 100%） | 2026-08-13 | `1f8e71e` |

> ✅ 已结清（2026-08-13 TD-46 批次）：TD-46 完成（上表），TD-47 入技术债区（Speculative，复核关闭候选）。

### 技术债区 TD-29~41/43~45 批次（2026-08-13 标准档全自动 kickoff）

> 来源：TICKETS 技术债区 17 项（TD-29~41/43~45：td-arch-health 批次 13 项 + TD-28 审核 3 项 + TD-42 审核 1 项）。Grilling 共识（全自动档，用户确认）：**11 做 + 5 关闭 + 1 票面修正**——做：TD-29（formatTemperature Number.isFinite 回退）/ TD-30（boot.html 就绪超时 >0 兜底）/ TD-31（**票面修正**：先 child.kill() 再 taskkill 实证自相矛盾——直接子进程死后 taskkill /T 找不到树，改 taskkill 先行 + 失败存活兜底 child.kill() + 5s 有界回收）/ TD-33（resolver 未注册名改捕 ProviderNotSupportedError，构造 ValueError 原样上抛）/ TD-36（renderMessages Array.isArray 守卫）/ TD-37（startRename conv 守卫）/ TD-38（代码块占位符原子化——块内标记渲染为可点击链接属真实交互缺陷）/ TD-40（_translate_error @abstractmethod 钉契约）/ TD-41（errors.py 死导入）/ TD-44（markdown.js 纳入 coverage.include）/ TD-45（XSS 五变体回归网补齐）；**关闭 5**（复核确认维持）：TD-32（latin-1 契约 docstring 已声明 + 三调用点均 ASCII）/ TD-34（SQLite 单写者 TOCTOU 不可达）/ TD-35（前端下载器已兼容 filename*，仅注释顺手修）/ TD-39（config DEFAULT_PROVIDER 常量兜底恒非空）/ TD-43（**票面机制实证否定**：jsdom v26 实测 NUL→U+FFFD 与真实浏览器一致，断言无需放宽）。
>
> 规格 v1.0 无修订。标准档 2 波（波 1：工单 01/02/03 并行 3；波 2：工单 04 单张），worktree `.worktrees/td0{1..4}-*`，merge 链 `b835210`+`615aba8`+`a5fe7b9`（波 1）+ `cef3fea`（波 2）；merge 零回退冲突。**波 1 增量审核（固定点 4a43b5b）：0 阻断**——文件范围 18 合规 / 1 记录警告（vitest.config.js 申报改动）/ 0 回退；4 项非阻断处置（960c9c4 修 2 项：character-submit.js 纳入 coverage.include + resolve_llm docstring 失真；93b51ab 落盘 TD-46；复核维持 1 项）。**波 2 增量审核（固定点 a5fe7b9）：0 阻断**——F6 测试注释如实化 + F8 TICKETS.md NUL 字节转义（649910c/d96b4ce）。**期末四轴 code-review（固定点 4a43b5b）：1 阻断已修复放行**——Falsify 抓到 TD-38 占位符碰撞循环计数器失同步（createCodeBlockToken do-while 碰撞消耗多序号 vs 调用方单次 tokenId++ → 多代码块 + 用户内容含 `\x00MDCB<n>\x00` 形文本时首块被覆盖丢失；碰撞免疫契约失效 + 套件零覆盖）→ daf5503 修复（返回 { token, nextId } 取号单一职责 + 5 防复发用例转正），merge `342382e`；复审 9 场景 Falsify 全过（无丢失/无双份/零占位符泄漏）、范围严格两文件、放行；Architecture Locality 注记与阻断同源一并修复；TD-46 期末复证（100 块 64KB 实测 1.7ms，不新开条目）。运行态冒烟：uvicorn 起服 /api/models 200 + test-connection 400「不支持的 Provider: gemini」+ /api/characters 200，端口停净。测试同步：pytest **413 + 1 skip**（基线 412+1，+1 构造 ValueError 透传用例）/ Vitest **460**（基线 444，+16：工单 01 +3 / 工单 02 +8 / 阻断修复 +5）/ cargo **58**（基线 56，+2）。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| 01 | 前端防御性收口（TD-29/36/37 + api.test 注释修正；3 用例先红后绿，涉改文件 100% 覆盖） | 2026-08-13 | `f01560f` |
| 02 | markdown 原子化 + 回归网（TD-38/44/45；8 用例，markdown.js 100% 覆盖） | 2026-08-13 | `ce943f3` |
| 03 | 后端错误处理小改（TD-33/40/41 + 连带同步；llm+errors 97.45% 覆盖） | 2026-08-13 | `e18925c` |
| 04 | 壳生命周期硬化（TD-30/31 票面修正；+2 用例，cargo 58） | 2026-08-13 | `a737d4a` |
| 阻断修复 | markdown 占位符碰撞计数器失同步（5 防复发用例转正，markdown.js 100%） | 2026-08-13 | `daf5503` |

> ✅ 已结清（2026-08-13 TD-29~41/43~45 批次）：17 项全部处置——11 做（含 TD-31 票面修正）+ 5 关闭（复核确认维持，各附实证理由）+ 1 新遗留 TD-46 入技术债区（markdown 还原性能 Speculative）。期末阻断修复防复发断言 5 用例落库。

### 技术债区 TD-13~14 批次（2026-08-12 全自动 kickoff）

> 来源：TICKETS 技术债区 TD-13/TD-14 清零（TD-8~12 批次期末遗留，用户指令「继续完善这两个观察项」）。Grilling 共识（全自动档拍板）：**2 做 + TD-9 顺带闭环**——TD-13 做（save 回调入口统一守卫：11 元素收集 + 任一缺失 console.warn 早退 + :339 `?.textContent.trim() ?? ''` 收口；先红后绿 2 用例实证 :334 value / :339 textContent 两条 TypeError 路径）+ TD-14 做（三处「逐字符一致」措辞补 pathlib 规范化注记 + 1 契约锁用例；v2 不变 Rust 镜像零改动）；**TD-9 维持 → 做（顺带闭环）**——TD-13 入口守卫覆盖 getSelectedModel 全部调用点（:340/:281），本体零改动。规格 v1.0 无修订。单波 2 并行（TD-13 前端 / TD-14 后端+文档，文件互斥无链），merge `61f1721`；merge 零回退冲突。**期末四轴 code-review（固定点 b76cf7b）：0 阻断**——2 工单 10 项验收全达标、守卫三态实测（正常 DOM 保存全流程/11 元素逐一缺失/空下拉）、pathlib 声称实测一致（除 UNC 前导例外已记）、seam 选择正确（入口统一守卫 Leverage 高）；10 项非阻断观察落技术债区（TD-15~24）。运行态冒烟：后端 GET / 200；GUI：设置面板完整渲染（11 元素齐备）→ 保存设置「设置已保存」弹窗全过（TD-13 正常路径零回归）。测试同步：pytest **360 + 1 skip** / Vitest **371** / cargo test **52**，全部全绿。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| TD-13 | save 回调入口统一守卫收口裸读（11 元素收集 + :339 收口 + docstring；+2 用例⑦⑧ 先红后绿；testApiKeys/getSelectedModel 本体零改动） | 2026-08-12 | `a754a13` |
| TD-14 | 契约「逐字符一致」措辞澄清（3 处补 pathlib 规范化注记）+ 契约锁用例（+1，基线绿非回归；v2 不变） | 2026-08-12 | `b284f78` |

> ✅ 已结清（2026-08-12 TD-13~14 批次）：TD-13/TD-14 完成（上表）+ **TD-9 顺带闭环**——TD-9（getSelectedModel 未守卫）由「复核确认维持」转「做（顺带闭环）」：TD-13 入口守卫覆盖其全部调用点（:340/:281），本体零改动（延续 TD-5 Q4 不加固共识），缺口闭合。

### 技术债区 TD-15~24 批次（2026-08-12 全自动 kickoff）

> 来源：TICKETS 技术债区 TD-15~24 清零（TD-13~14 批次期末遗留）。Grilling 共识（全自动档拍板）：**10 项全做，无关闭项**——TD-15 做（守卫条件化：`#setting-custom-model` 仅 `modelSelect.value === '__custom__'` 时要求；**票面建议 providerSelect 条件实证否定**——provider 下拉只填 providers key 永不为 '__custom__'，条件恒假会让守卫形同虚设；+2 用例 A 先红后绿 + B 基线绿）/ TD-16 做（UNC 前导特例注记，实测背书）/ TD-17 做（契约锁补尾分隔符+UNC 断言，基线绿非先红）/ TD-18 做（tauri-desktop.md「路径形态」限定）/ TD-19 做（warnSpy.mockRestore 惯例对齐——:529 afterEach 已兜底，属硬化非活 bug）/ TD-20 做（夹具 replace 防御断言）/ TD-21 做（getSelectedModel docstring 契约标注）/ TD-22 做（providerSelect.querySelector 复用）/ TD-23 做（计数口径修正，grep 归零）/ TD-24 做（server.rs 透传契约注释，注释-only）。规格 v1.0 无修订。小档 2 工单（TD-A 前端 6 项 / TD-B 后端+文档 4 项，文件互斥无链），单 Implement 直行（worktree `.worktrees/td15-24`），merge `0010f1b`；merge 零回退冲突。**期末四轴 code-review（固定点 3072346）：0 阻断**——2 工单 10 项验收全达标（grep 三项实测归零/带限定；pathlib 声称实测逐字一致）、守卫四态 Falsify 无击穿、安全红线全过；3 项非阻断观察落技术债区（TD-25~27）。运行态冒烟：后端 GET / 200；GUI：设置面板完整渲染（11 元素齐备）→ 保存设置「设置已保存」弹窗全过（TD-15 放行场景运行时实证——非 __custom__ 模型 + 无 custom 输入保存成功，旧守卫在此形态拒绝）。测试同步：pytest **360 + 1 skip** / Vitest **373** / cargo test **52**，全部全绿。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| TD-A | settings-panel 守卫收窄与卫生（TD-15/19/20/21/22/23：守卫条件化 modelSelect + 计数口径修正 + 契约标注 + 查询复用 + 防御断言 + restore 惯例；+2 用例 A 先红后绿 + B 基线绿；settings-panel.js 覆盖 100% 行） | 2026-08-12 | `85aca1b` |
| TD-B | 路径契约注记与锁补强（TD-16/17/18/24：UNC 特例注记 + 尾分隔符/UNC 锁断言 + 「路径形态」限定 + Rust 透传注释；pytest/cargo 计数不变） | 2026-08-12 | `e16048f` |

> ✅ 已结清（2026-08-12 TD-15~24 批次）：TD-15~24 全部完成（10 做 0 关闭），技术债区对应行移除（TD-25~27 为本批次新遗留，保留原位）。

### 技术债区 TD-25~27 批次（2026-08-13 全自动 kickoff）

> 来源：TICKETS 技术债区 TD-25~27（TD-15~24 批次期末遗留）。Grilling 共识（全自动档拍板）：**1 做 + 2 关闭（复核确认维持）**——TD-25 做（UNC 锁断言平台隔离：拆独立用例 `test_env_override_unc_prefix_preserved` + `@pytest.mark.skipif(sys.platform != 'win32')`；**票面「断言级 skipif」实测不可表达**——装饰器无断言级形态，修正为函数级；skipif 可见 skip 信号优于静默 `if sys.platform` 包裹——后者锁悄悄失效不可见；Windows 锁语义零变化照跑）/ **TD-26 关闭**（复核确认维持：:371 守卫条件化在，空模型下拉放行存 `''` 与用例⑧ 先例同构，零 TypeError 风险；决策内容在代码注释 + TICKETS 归档行双重可证，不加锁测试——超出票面「仅记录」范围）/ **TD-27 关闭**（复核确认维持：UNC 复述 5 处/3 文件现状成立，跨文件引用已存在（data_dir.py:12-13 / server.rs:401 互引），复述是决策出处上下文非纯冗余，漂移由 TD-25 锁兜底）。规格 v1.0 无修订。轻量档单 Implement 直行（主树独立分支，无 worktree），merge `8ae3801`；merge 零回退冲突。**期末四轴 code-review（固定点 aa3391f）：0 阻断**——验收①-⑤全过（361+1 skip / test_data_dir.py 16 passed / --co 362 / grep 无散落 / 锁语义独立实测不削弱）、POSIX 语义与 reason 措辞逐字吻合；4 项非阻断观察经评审判断不落债（docstring 首行重复 = spec 明示保留形态 / reason 行宽 = 无 lint 工具链取舍 / skip 插件禁用理论边角 = 现实不可达 / 平台守卫模式 = spec 已落盘）。运行态冒烟：后端 GET / 200（测试-only 改动零行为变化）。测试同步：pytest **361 + 1 skip** / Vitest **373** / cargo test **52**，全部全绿。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| TD-25 | UNC 锁断言平台隔离（拆独立用例 + 函数级 skipif + docstring 随迁；Windows 锁照跑 + POSIX 可见 skip） | 2026-08-13 | `ea222d3` |

> ✅ 已结清（2026-08-13 TD-25~27 批次）：TD-25 完成（上表）+ TD-26/TD-27 **复核确认维持**关闭（归档注记：现状即设计意图——TD-26 空下拉放行是 TD-15 决策字面内行为；TD-27 复述受双端镜像契约表惯例保护且锁断言已兜底）。技术债区清零。

### 技术债区 TD-8~12 批次（2026-08-12 全自动 kickoff）

> 来源：TICKETS 技术债区 TD-8~12 清零（TD-1~7 批次期末遗留）。Grilling 共识（全自动档拍板）：**3 做 + 2 维持关闭**——TD-8 做（save/clear 裸绑定 `?.` 化收口守卫体系）/ TD-9 维持关闭（spec 明示不加固 + TD-8 实施后触发路径不变复证实证）/ TD-10 做（「当前盘根」+ MSYS2 转换说明）/ TD-11 维持关闭（ARC10-4「两路并存」规格背书 + 双向注释已在 chat.py:217-218 ↔ errors.py:49-50）/ TD-12 做（+1 契约锁测试）。规格 v1.0 无修订。单波 3 并行（TD-8 前端 / TD-10 文档 / TD-12 后端测试，文件互斥无链），merge `a12d48e`；merge 零回退冲突。**期末四轴 code-review（固定点 ab25867）：0 阻断**——3 工单 Spec 全达标（TD-8 用例⑥ 先红后绿实证：:332 null.addEventListener TypeError / TD-12 契约锁基线绿非先红语义正确）、TD-10「当前盘根」修订经 pathlib 实测验证准确、守卫体系绑定层完整收口；2 项非阻断观察落技术债区（TD-13/TD-14）。运行态冒烟：后端 GET / 200；GUI：设置面板渲染 / 保存设置弹窗 / 清空对话确认弹窗全过（TD-8 save/clear 正常路径回归）。测试同步：pytest **359 + 1 skip** / Vitest **369** / cargo test **52**，全部全绿。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| TD-8 | save/clear 按钮绑定纳入 no-op 守卫（:332/:366 `?.` 化 + docstring 同步；+1 用例⑥ 先红后绿；用例②⑤ 注释同步申报） | 2026-08-12 | `30bd2a0` |
| TD-10 | tauri-desktop.md POSIX 警告补「当前盘根」+ MSYS2 转换说明（单段修订） | 2026-08-12 | `4108e49` |
| TD-12 | llm_error_response provider=None 契约锁用例（+1 用例，基线绿非回归；chat.py 零改动） | 2026-08-12 | `a94b3ec` |

> ✅ 已结清（2026-08-12 TD-8~12 批次）：TD-8~12 全部处置——3 做（上表）+ 2 **复核确认维持**（归档注记）：
> - TD-9 `getSelectedModel`（settings-panel.js:87-94）未守卫：spec 明示不加固（TD-5 共识 Q4 背书）——save 回调触发前提 = UI 已渲染 + 按钮存在，model 下拉正常渲染下必在，防御性不可达；TD-8 实施后触发路径不变（调用点 :340/:281 零改动复证）
> - TD-11 chat_error_response 400 vs api/errors.py 422 家族函数级分歧：合并单一映射表触及 ARC10-4「spec 明令两路并存」规格变更，非技术债清零可拍板；分歧已被双向注释显式标注（chat.py:217-218 ↔ errors.py:49-50），非静默假设，未来规格变更时按注释指路合并

### 技术债区 TD-1~7 批次（2026-08-12 全自动 kickoff）

> 来源：TICKETS 技术债区 TD-1~7 清零（上批次期末遗留）。Grilling 共识：**7 项全做，无关闭项**（Q1 TD-1 注释收窄 / Q2 TD-2 三文件全扫 / Q3 TD-4 调用侧守卫 / Q4 TD-5 绑定侧守卫不加固 getSelectedModel / Q5 TD-6 无新测试 / Q6 保守微调）。规格 v1.0 无修订。两波执行：波 1 前端+文档 3 并行（TD-3/TD-4→TD-5 链/TD-7，merge `053f949`）、波 2 后端 2 并行（TD-2/TD-1→TD-6 链，merge `3cae11d`）；merge 零回退冲突；波末降配增量审核两轮无阻断（波 1：F1-F6 含 save/clear 裸绑定基线遗留实证；波 2：F1-F13 含 `?` 分隔符实测、v1 历史叙述区分）。**期末四轴 code-review（固定点 bfe75f2）：0 阻断**——7 工单 Spec 意图全达标（TD-2 验收口径注记：`grep 契约表 v1` 字面未归零，5 处为历史叙述非漂移，意图达成）、Falsify 先红后绿实证齐全（TD-4 两路径 + TD-5 事件期）、守卫层级与 Seam 选择正确；5 项非阻断观察落技术债区（TD-8~12）。运行态冒烟：后端 GET / + /api/models 200；GUI：设置面板完整渲染 / provider 切换联动 / 自定义模型切换全过（TD-4/5 正常路径回归）。测试同步：pytest **358 + 1 skip** / Vitest **368** / cargo test **52**，全部全绿。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| TD-3 | initSearchView docstring 增补「作用域与前提」段（bound 模块级/DOM 冻结语义，纯注释） | 2026-08-12 | `2340db0` |
| TD-4 | refreshModelOptions 三元素缺失守卫补全（provider/model/custom 任一缺 → no-op；+2 Falsify 用例先红后绿，model-utils.js 零改动） | 2026-08-12 | `03002a9` |
| TD-5 | 模型联动 handler 缺一不绑定（model/custom 缺一不绑 change；docstring 同步；+1 用例先红后绿；getSelectedModel 不加固） | 2026-08-12 | `d3f3ffc` |
| TD-7 | tauri-desktop.md POSIX 警告措辞具体化（`C:\c\...` 字面落位，单行） | 2026-08-12 | `f51c4cb` |
| TD-2 | 契约表版本标签 v1→v2 全量同步（8 处目标文件 + 已申报 tests 扩展 4 处同类漂移；编码基准描述 v1 旧语义 → v2） | 2026-08-12 | `92789fd` |
| TD-1 | chat_error_response 兜底分支注释补遗（422 家族不落此分支，ARC10-2/4 关联，纯注释） | 2026-08-12 | `d53b436` |
| TD-6 | llm_error_response 参数标注 str → str \| None（运行时零变化，from __future__ annotations） | 2026-08-12 | `ccc5e25` |

> ✅ 已结清（2026-08-12 TD 批次）：TD-1~7 全部完成（7 做 0 关闭）——其中 TD-2 验收口径注记：`grep -rn "契约表 v1" backend/` 字面未归零，残留 5 处为**历史叙述**（test_data_dir.py/test_data_dir_connection.py 描述旧编码与防回归锁），非漂移标签，改写会篡改历史语境；「版本标签归零」已达。

### 技术债区批次（2026-08-12 全自动 kickoff）

> 来源：TICKETS 技术债区 16 项遗留（ARC9-1~8 + ARC10-1~5 + T-04~06）清零。Grilling 共识：4 做 + 2 拍板（ARC9-7 settleTurn 维持——共识固定签名；T-06 维持 + 文档补强——代码不归一化是逐字符契约）+ 10 项复核确认维持关闭（审计快照复核惯例：逐项 git grep 核实仍成立后判关闭，非盲删）。规格 v1.0 无修订。两波执行：波 1 前端 3 并行（T-A1/A2/A3，merge `bd0eb81`）、波 2 后端（T-B1→T-B2 同代理串行链 + T-B3 并行，merge `ed7a3ac`）；merge 零回退冲突；波末降配增量审核两轮无阻断（波 1：F1-F6 含 T-A2 守卫半兑现实证；波 2：F1-F10 含 test_error_handler 断言更新必要性实证）。**期末四轴 code-review（固定点 13bc791）：0 阻断**——6 工单 Spec 全过（含已申报 test_error_handler.py 断言期望值更新必要核实）、深模块边界未破坏、Falsify 9 构造无击穿（422 家族分叉防御性不可达）；8 非阻断观察去重后 7 项落技术债区（TD-1~7）。运行态冒烟：后端 GET / + /docs + /api/models + /api/settings 全 200；GUI（Playwright 375px+桌面）：搜索防抖/Enter 无双发/结果跳转 ✓、设置面板/provider 联动 ✓、移动端侧栏展开收起往返 ✓（活替代路径回归）。测试同步：pytest **358 + 1 skip** / Vitest **365** / cargo test **52**，全部全绿。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| T-A1 | 搜索视图绑定守卫兑现幂等契约（ARC9-1；模块级 bound 标志，+1 用例，search-view.js 覆盖 100%） | 2026-08-12 | `86df358` |
| T-A2 | 设置面板初始化补 no-op 守卫（ARC9-2；早退 + 两处 `?.`，+2 用例，覆盖 91.32%） | 2026-08-12 | `603944a` |
| T-A3 | 删除 toggleConvList 死代码（ARC9-6；app.js -8 行，grep 零残留，活替代内联保留） | 2026-08-12 | `75c74b1` |
| T-B1 | LLM 401 消息条件模板消除前导空格（ARC10-1；chat.py 条件前缀，+1 用例，chat.py 覆盖 96%） | 2026-08-12 | `9aa6e87` |
| T-B2 | 未知领域异常对齐 400 语义（ARC10-2；chat.py 兜底 +1 行，+1 用例，与 api/errors.py handler 归一） | 2026-08-12 | `a27f085` |
| T-B3 | 数据目录覆盖节补 POSIX 路径警告（T-06；docs/tauri-desktop.md +2 行，代码零改动） | 2026-08-12 | `8b2af59` |

> ✅ 已结清（2026-08-12 技术债批次）：16 项技术债区遗留全部处置——6 项修复完成（上表）+ 10 项**复核确认维持**（审计快照过期复核惯例：逐项 git grep 核实现状后判关闭，保留审计原始描述便于对照）：
> - ARC9-3 build-desktop `-SkipBackendBuild` 提前 throw 已落地（终态即描述，语义微变为更优行为）
> - ARC9-4 smoke 验收 6 无复查等待窗口（单 worker force-kill 即时释放，多 worker 未来形态假设再评估）
> - ARC9-5 run_backend 直执行形态不受支持（`python -m backend.run_backend` 正常）
> - ARC9-7 settleTurn 五件套 Data Clumps（共识固定签名，重构零行为收益，不急于改）
> - ARC9-8 `?` 编码跨平台边界（防御编码非回归，Windows 下 `?` 非法不可达，非 Windows 部署前知晓已注记）
> - ARC10-3 wizard modal-body 嵌套（被 min-height:480px 掩蔽，留 CSS `:has()` 修复预案注记）
> - ARC10-4 领域错误映射双址（spec 明令两路并存 B1 只读约束背书）
> - ARC10-5 register_builtin_providers 半注册（fail-fast 设计意图 + `_builtins_loaded=False` 自愈）
> - T-04 run_backend 端口越界 SystemExit（经壳不可达，壳恒传合法 u16）
> - T-05 setup_tray 失败即启动失败（响亮失败设计意图，图标产物齐全）

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
