# Conver System — 可执行任务清单 (TICKETS)

> 规则：本文件是**仓库内唯一的待办事实来源**。活跃表只保留「未完成」工单；每完成一项 → 移入「已完成归档」并记完成日期（+提交哈希）→ 同步 [DEV_LOG.md](DEV_LOG.md) → 与本提交一起 commit。
>
> 维护节奏（绑定现有流程节点，不新增习惯）：
> 1. 开始实现某工单前：📝 已录入 → 🔄 进行中（认领）
> 2. 每会话结束、commit 之前：完成 → ✅/❌ → 移入归档；新评审候选（含未拍板的 `Worth exploring` / `Speculative`）立即录入技术债区（= 活跃表的未立项子集，带 编号/来源/强度/状态）
> 3. 待办**不得写在 memory / DEV_LOG / 个人笔记里**——不落 TICKETS 就不算数
>
> 状态：⬜ 待办 | 🔄 进行中 | ✅ 完成

---

## 活跃工单

> 当前无未完成工单。技术债区批次已全部归档（见下）。期末审核遗留见下方技术债区。

---

## 技术债区

> 期末/波次审核的非阻断发现落盘于此（带来源 + 推荐强度 + 状态），供未来会话与下一轮 kickoff 可见（读取契约：kickoff 步骤 0 预检；强度消费：Strong 必入 / Worth exploring 拍板 / Speculative 可复核关闭）。修复时机自由，不影响当前交付。落盘前与既有条目去重（文件:行号为主键），重复仅追加复证标注。

| 编号 | 遗留项 | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| TD-46 | frontend/js/markdown.js:163-165 占位符还原逐块全文 split/join，多块大文本二次方级操作（聊天消息量级无感知）——未来大文本渲染性能候选 | 波 1 增量审核 Falsify | Speculative | 📝 |

> 技术债区当前 **1 项**（TD-46：波 1 增量审核遗留；TD-29~41/43~45 批次处置完毕见下）。

---

## 已完成归档

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
