# Conver System — 可执行任务清单 (TICKETS)

> 规则：本文件是**仓库内唯一的待办事实来源**。活跃表只保留「未完成」工单；每完成一项 → 移入「已完成归档」并记完成日期（+提交哈希）→ 同步 [DEV_LOG.md](DEV_LOG.md) → 与本提交一起 commit。
>
> 维护节奏（绑定现有流程节点，不新增习惯）：
> 1. 开始实现某工单前：📝 已录入 → 🔄 进行中（认领）
> 2. 每会话结束、commit 之前：完成 → ✅/❌ → 移入归档；新评审候选（含未拍板的 `Worth exploring` / `Speculative`）立即录入 [TECH_DEBT.md](TECH_DEBT.md) 候选池（不自动进入 preflight 认领，带 编号/来源/强度/状态）
> 3. 待办**不得写在 memory / DEV_LOG / 个人笔记里**——不落 TICKETS 就不算数
>
> **归档清出机制（2026-08-27 试点实施，详见 [docs/ticket-archive-cleanup-research.md](docs/ticket-archive-cleanup-research.md)）**：
> 1. 已完成归档完整保留**最近 6 个批次**；更早批次折叠为「历史归档索引」单行（工单号/提交哈希/验收摘要在此保留一条，细节由 git 历史承担：`git log -p -- TICKETS.md`）
> 2. 索引行超 **60 行**时，最旧的行整行删除
> 3. **叙述职责归位**：新批次归档只承载工单事实表（编号/标题/F 项/日期/提交）；来源/Grilling 共识/验证链/过程遥测/落债等叙述**只写 DEV_LOG.md**（已有 12 条滚动折叠机制），归档批次末尾一句引用「详见 DEV_LOG〈节标题〉」
> 4. 活跃表禁止 ✅ 滞留：会话结束 commit 前检查活跃表无完成态为显式一步
>
> 状态：⬜ 待办 | 🔄 进行中 | ✅ 完成

---

## 活跃工单

> 当前 **0 项待办**。
> 规格依据（字段规格、纯函数签名、契约锁用例）统一见 [docs/chat-simulator-upgrade-spec.md](docs/chat-simulator-upgrade-spec.md)。
> 来源：AI风月对标调研（证据链与三份规格笔记见仓库外 `D:\tmp\fetchflow-aigs\`——采集脚手架不入库，避免 doc_sync files 双向覆盖校验误判）；定位约束=纯本地、不盈利、不做社交体系/积分体系。
> 技术债候选池见 [TECH_DEBT.md](TECH_DEBT.md)。

### 批次 WL — 世界书引擎（承接 docs/world-simulation-exploration.md D3/D4）

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|

### 批次 MS — 消息操作（继续 + swipes 多候选）

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|

### 批次 BR — 存档升级为分支点

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|

### 批次 CG — CG 沉淀与剧情回顾

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|

### 批次 MD — Mod 挂载层

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|

> **实施顺序建议**：WL → MS → BR → CG → MD（依赖与风险见 spec 末节表格）。
> **每批统一验收口径**：先红后绿 + 全量基线不回退（pytest 823+1skip / Vitest 1189 / cargo 70）+ 覆盖率不放宽 + 冒烟 + 文档同步。

---

## 技术债区

> 已迁移至独立文件 [TECH_DEBT.md](TECH_DEBT.md)（AGENTS.md §3 规范，2026-08-24 迁移，
> 条目原文完整保留：C3/C4/C7/C8 + F-1~F-22 共 26 项，迁移时全部处置完毕、技术债区清零状态维持）。

---

## 已完成归档

> 完整批次（最近 6 批）见下方；更早批次已折叠为「历史归档索引」表（2026-08-27 首次压缩执行，原文 54 批次由 git 历史承担）。

### 消息编辑重发 + 删除单条消息批次（2026-09-14 — 3 工单小档，对标 AI 风月消息级操作）

> 来源：用户对标 AI 风月「把角色对话打磨更精细」，选定「消息编辑重发 + 删除单条消息」。叙述详见 DEV_LOG〈消息编辑重发 + 删除单条消息批次（2026-09-14）〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| T1 | 后端 service 层：update_message/delete_message/edit_and_resend（编辑重发编排 + 角色感知删除） | — | 2026-09-14 | a365b81 |
| T2 | 后端端点：PUT 编辑重发 + DELETE 删除单条（EditMessageRequest + 路由） | — | 2026-09-14 | 3bcd80f |
| T3 | 前端 UI：编辑/删除按钮 + 二次确认 + 重载（messages.edit/delete + messageBubbleHtml 按钮） | — | 2026-09-14 | 8269f1e |

**验证链：** pytest 1200+1skip→1223+1skip（+23）→ 期末审核修复 1225+1skip（+2 级联契约锁）；Vitest 1351→1378（+27）→ 修复 1379（+1 互斥锁）；cargo 70 零改动 | 期末四轴 0 Critical/0 HIGH（2 MEDIUM 主会话直修：bulk-delete 级联零测试锁定 + 前端 nonStreamingInFlight 互斥缺口）| doc_sync 零漂移
**非阻断落债：** F-130~F-138（9 项，来源期末四轴 + 工单 03 concern）

---

### 技术债消费批次 F-127~F-129（2026-09-14 — 2 做 1 关，轻量档 3 项主会话直做）

> 来源：用户指令「消费 F-127~129」（架构批次期末四轴观察级落债）。逐项 git grep 复核后拍板 2 做 1 关。叙述详见 DEV_LOG〈技术债消费批次 F-127~F-129（2026-09-14）〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| F-127 | add_swipe 加 commit 参数 + append 单 commit 原子落库（消除两段提交窗口） | F-127 | 2026-09-14 | 5ed88f5 |
| F-129 | _ensure_conversation_branch_columns 单连接循环补三列 | F-129 | 2026-09-14 | 5ed88f5 |

**验证链：** pytest 1199+1skip→1200+1skip（+1 防复发断言 test_append_swipe_and_bump_single_commit_atomic）+ Vitest 1351 + cargo 70 零回退全绿 | 复核关闭 F-128（commit=False 后 msg 未 expire 命中 identity map，剩余再取是合理结构）| 技术债候选区 3→0 清零
**非阻断落债：** 无（候选区清零）

---

### 架构深化候选消费批次 F-123~F-126（2026-09-14 — 4 做，标准档 4 工单串行）

> 来源：用户指令「全做」架构深化扫描 4 候选（F-123~F-126，source=架构报告 2026-09-14）。纯重构行为零变化。叙述详见 DEV_LOG〈架构深化候选消费批次 F-123~F-126（2026-09-14）〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| T1 | Mod 区过滤读取单一 seam（list_enabled_mods_for_area 下沉 mods.py） | F-123 | 2026-09-14 | a016d7c |
| T2 | 追加候选「持久化仪式」收口（append_swipe_and_bump 单一入口） | F-124 | 2026-09-14 | 49d342c |
| T3 | generate+LLM 错误映射接线收口（_generate_with_error_mapping 私有 seam，stream_reply 排除） | F-126 | 2026-09-14 | 114aae6 |
| T4 | 自愈迁移原语抽取（_ensure_column 通用原语 + 三 wrapper 退化声明） | F-125 | 2026-09-14 | 19868f2 |

**验证链：** pytest 1174+1skip→1199+1skip（+25 契约锁）+ Vitest 1351 + cargo 70 零回退全绿 | 冒烟 uvicorn 8899 docs/models/available 全 200 | 期末四轴「通过」0 Critical（Architecture 轴确认四工单均真深化，无伪深化）+ 观察级落债 F-127~F-129 | doc_sync 零漂移
**非阻断落债：** F-127~F-129（append 两段提交非原子 / 冗余重取 / 三连接）

---

### 技术债消费批次 F-115~F-122（2026-09-14 — 3 做 5 关，轻量档 8 项主会话直做）

> 来源：用户指令「消费」+ userselect F-115~F-122（mod-cg-wiring 期末四轴落债 8 项）。逐项 git grep 复核现状后拍板 3 做 5 关。叙述详见 DEV_LOG〈技术债消费批次 F-115~F-122（2026-09-14）〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| F-117 | mod-css.js 空串 payload 过滤（跳过空串防游离换行，防复发断言） | F-117 | 2026-09-14 | 0fb43ba |
| F-119 | database.py `isinstance(bind, Engine)` 替代 hasattr duck-type | F-119 | 2026-09-14 | 0fb43ba |
| F-120 | cg-review.js NaN 守卫（actionEl 脱离 tile 静默 no-op 防御） | F-120 | 2026-09-14 | 0fb43ba |

**验证链：** pytest 1173+1skip→1174+1skip + Vitest 1351 零回退 + cargo 70 零改动全绿 | 复核关闭 F-115/116/118/121/122（理由见 TECH_DEBT.md 复核关闭表）| 技术债候选区 8→0 清零 | 一并删除 `.scratch/mod-cg-wiring/`（归档已完成，一次性产物无用）
**非阻断落债：** 无（候选区清零）

---

### mod-cg-wiring 批次（2026-09-14 — Mod memory/css 消费 + CG 解锁/画廊/加权自动出图，标准档 7 工单）

> 来源：用户指令「检查项目进度，看还有哪些原有设计未落地」→ 选第一梯队半成品（Mod memory/css 消费方 + CG 解锁端点/加权自动出图接线）；project-kickoff 全自动档。Grilling 四 ADR 拍板（memory 区=归纳指令叠加 / css 区=会话内样式注入 / 画廊=cg-review 扩 tab+录入表单 / 自动出图=回合末概率触发+全局 settings 键）。叙述详见 DEV_LOG〈mod-cg-wiring 批次（2026-09-14）〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| T1 | cg_images weight 列迁移 + add_cg 扩参（weight/unlocked/is_special，幂等去重不改既有语义） | 2026-09-14 | 52c3b03 |
| T2 | CG 路由三件套：POST/GET /api/characters/{id}/cg + POST /api/cg/{id}/unlock（零 ORM 走 gallery service） | 2026-09-14 | 351871d |
| T3 | memory 区 Mod 消费：summarize_turn 扩 extra_instructions + chat 回读注入（纯文本 \n 连接，无 Mod 字节级不变） | 2026-09-14 | 96386e7 |
| T4 | css 区 Mod 前端注入 seam（mod-css.js 深模块 + chat.js onTabsChanged 接线） | 2026-09-14 | e079d80 |
| T5 | 画廊页签 + 录入表单 + 锁定态交互（cg-review.js 页签自建 + api.js 三方法） | 2026-09-14 | 112e722 |
| T6 | 回合末概率触发 + settings 键 cg_auto_trigger_probability + _maybe_auto_cg | 2026-09-14 | c5ef42d |
| T7 | 版本号 0.6.1 → 1.1.0（package.json/package-lock/tauri.conf/Cargo.toml/Cargo.lock） | 2026-09-14 | da28e69 |

**验证链：** pytest 1117+1skip→1173+1skip（+56）+ Vitest 1311→1351（+40）+ cargo 70 零改动，全绿 | 运行态冒烟：uvicorn 8899 docs/available 200 + CG 真实链路（录入→列表→解锁）全通 | 期末四轴 0 HIGH 阻断 + 2 MEDIUM 当场修（7e953d5：_maybe_auto_cg 恢复 unlock_cg seam + 删 provider/model 死参数，防复发断言 test_unlock_uses_unlock_cg_seam）+ 安全红线 0 违例 | doc_sync 零漂移
**非阻断落债：** F-115~F-122（8 项，详见 TECH_DEBT.md 候选区）；另 merge 遗漏修复——T2 分支初漏合并（de50b80 补齐，冒烟发现 unlock 端点 405 定位）

---

### 技术债消费批次 F-109~F-111（2026-09-13 — 1 做 2 关，轻量档 1 工单）

> 来源：用户指令「消费技术债候选区 3 项（F-109~111）」；Grilling 实证拍板 F-110 做、F-109/F-111 复核关闭（关闭理由见 TECH_DEBT.md 复核关闭表）。叙述详见 DEV_LOG〈技术债候选区消费批次 F-109~F-111（2026-09-13）〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| F-110 | chat.js 末条 assistant 动作生命周期样板提取（runLastAssistantAction，行为保持重构） | F-110 | 2026-09-13 | 57bef68 |

**验证链：** 全量 Vitest 1311 断言零修改全绿 + pytest 1117+1skip 零回归（cargo 零改动）| grep 收敛证据 nonStreamingInFlight.has 4→2 | 运行态冒烟：uvicorn 8017 加载应用→打开会话→消息气泡渲染无 console 错误 | 期末四轴详见 DEV_LOG | doc_sync 零漂移（pre-commit 刷新 1 标记）
**非阻断落债：** 技术债候选区 3→0 项清零（净消 3，防膨胀合规）

---

### Mod 挂载批次 MD-2（2026-09-12 — Mod 管理 UI + 注入链集成，MD 批收官）

> 来源：AI风月对标调研五批工单（MD Mod 挂载第二张/收官）；后端路由 + prompt 注入链集成 + 前端 Mod 管理面板（库 CRUD/挂载/开关/排序/区域选择/导入导出），规格/契约锁依据见 docs/chat-simulator-upgrade-spec.md §MD-2。叙述详见 DEV_LOG〈MD-2 Mod 管理 UI + 注入链集成（2026-09-12）〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| MD-2 | Mod 管理 UI + 注入链集成（路由 + assemble_chat_context 注入 + Mod 管理面板 + 卡片入口） | 2026-09-12 | 0c3edfb |

**验证链：** 后端 pytest 1078+1skip→1096+1skip（+18：test_mods_routes 12 用例——库 CRUD/挂载/开关/排序/解绑/404·400·422 守卫 + F1 修复锁 sort_order 越界 422；test_chat_mod_injection 6 用例——三区域叠加/禁用与非 prompt 区零影响/无 Mod 零回归/sort_order 升序/不新增尾随 system）| 前端 Vitest 1239→1287（+48：mod-manager 43 + api.test 端点映射 + format/list-views 入口接线）| services/mods.py 增 set_binding_sort_order（排序落库 v1.1 拍板）+ routes/mods.py 9 端点 + chat.py `_mod_prompt_injection`（IN 回读组 ModPayload → apply_prompt_mods）| mod-manager.js（库区块 + 挂载区块 + computeSortSwap 纯函数，覆盖率 96%+）| 运行态冒烟：uvicorn 建角色→建 Mod→挂载→排序→开关全链路 200 | 期末四轴 0 HIGH 阻断（1 MEDIUM 非原子排序自愈 + 若干 LOW 落债）+ 安全红线 0 违例 + 文件范围核验合规 | doc_sync 零漂移
**非阻断落债：** F-101~F-106（候选区 6 项）+ F-107~F-108（复核关闭 2 项，详见 TECH_DEBT.md）；另波末环境修复——CG-1 遗留依赖声明缺口（requirements.txt 补 pillow/httpx + venv pip install）

---

### 历史归档索引（2026-09-14 二次压缩：2026-08-27 ~ 2026-09-11 批次）

> 折叠规则见头部「归档清出机制」。原文细节由 git 历史承担（`git log -p -- TICKETS.md`）；叙述详情见 DEV_LOG 同名节。

| 日期 | 批次 | 提交 | 摘要 |
|------|------|------|------|
| 2026-09-12 | Mod 挂载批次 MD-1（Mod 数据模型与注入叠加） | e047462 | mods + mod_bindings 新表 + apply_prompt_mods 三区域叠加纯函数 |
| 2026-09-11 | 图片出图门控 MD-3（出图能力门控 + 图片 Provider 设置） | daf0fd7 | image_generation_available 判定单源 + settings image_provider/base_url + 前端按钮门控 |
| 2026-09-11 | CG 批次 CG-3（对话内出图 + 剧情回顾） | 3e04824 | 出图三态渲染 + 剧情回顾时间线，image_tasks 表 + /cg 静态挂载 |
| 2026-09-11 | CG 批次 CG-2（CG 资产库 + 画廊） | 4b2d16d | cg_images 表 + add/list/unlock/pick_cg_by_weight，生命周期 FK 落实 |
| 2026-09-11 | CG 批次 CG-1（text2img Provider 抽象） | 0f8a8d9 | image 包镜像 llm 六件套，Http/LocalImageGen + 错误映射 |
| 2026-09-11 | 分支批次 BR-2（从快照/分支派生会话） | 90ea7b4 | clone/branch_from_message + 三路由 + 删源置空 |
| 2026-09-11 | 分支批次 BR-1（分支元数据与快照导出） | 43693d2 | conversations 加三列 + 版本化快照含世界书与 swipes |
| 2026-09-11 | 消息操作批次 MS-3（继续生成 append 续写） | db149e9 | continue_chat 尾随 user 触发形态拍板，不追加 user |
| 2026-09-10 | 消息操作批次 MS-2（swipes 前端） | ef6be24 | 候选控制条 + switchSwipe 乐观更新 + generation token |
| 2026-09-10 | 消息操作批次 MS-1（swipes 数据模型与服务） | a95c2b2 | message_swipes 表 + add/switch/delete，重生成改追加候选 |
| 2026-09-10 | 世界书批次 WL-5（记忆宫殿 AI 归纳层） | 91cb653 | AI 归纳→auto 条目 + 阈值触发 + 失败隔离 |
| 2026-09-10 | 世界书批次 WL-4（编辑器前端） | 7073757 | CRUD 面板 + 泛词告警 + 字段校验 |
| 2026-09-10 | 技术债消费批次 F-96 | 46069c8 | escapeHtml 转义引号（15 处属性插值收敛） |
| 2026-09-10 | 技术债消费批次 F-94+F-95 | 364436d | text_utils.role_str 收敛 + build_message_list history 参数 |
| 2026-09-10 | 世界书批次 WL-3（注入链集成） | ec5f1e3 | build_messages world 参数 + 三注入位 |
| 2026-09-10 | 技术债消费批次 F-93 | 4ad64e7 | text_utils.as_str_list 共享收敛 |
| 2026-09-10 | 世界书批次 WL-2（激活引擎纯函数） | 59c3726 | activate_lorebook_entries/build_world_injection/collect_scan_text |
| 2026-09-10 | 世界书批次 WL-1（数据模型 + 仓库层） | 51e3786 | lorebook_entries 表 + character_book 解析入库 |
| 2026-08-28 | 用户修复批次（模拟器 API CORS 反代 + 重新识别 UI 收口） | c26144a | 同源反代端点 + reprobe 工具栏全量 + 无简介占位 |
| 2026-08-27 | 技术债消费批次 F-92 | 207af86 | canReprobeGame 驱动重新识别按钮渲染 |
| 2026-08-27 | 用户 bug 修复 F-91（斗罗大陆同步失效） | bab57a1 | config 多候选 id（探针全量收集） |
| 2026-08-27 | 技术债消费批次 F-90 | 58a7f6b | syncGameCredentials 收编 getDoc-only |
| 2026-08-27 | 技术债消费批次 F-82~F-89（3 做 5 关） | de150c4 | DISPLAY_KEYS 单源 + docstring 补时序 + 断连失效守卫 |
| 2026-08-27 | 架构深化批次 S1~S3 | cf60935 | append_current_input 显式路径 + _LLM_ERROR_MAP 有序列表 + 观察者生命周期迁移 |
| 2026-08-27 | 技术债消费批次 F-80~F-81 | 5936068 | sameId 归一比较 helper |
| 2026-08-27 | 技术债消费批次 F-74~F-79（2 做 3 关） | f865440 | 幂等 id 比较归一 + warnReason 文案映射表 |
| 2026-08-26 | 技术债消费批次 F-64~F-73（8 做 2 关） | 59b17c9 | error-bar 幂等寻址 + stream-session 结算边界 + chat.js 防御 + 对比度 |

### 历史归档索引（2026-08-27 首次压缩：2026-07-30 ~ 2026-08-26 批次）

> 折叠规则见头部「归档清出机制」。原文细节由 git 历史承担（`git log -p -- TICKETS.md`）；叙述详情见 DEV_LOG 同名节。

| 日期 | 批次 | 提交范围 | 摘要 |
|------|------|---------|------|
| 2026-08-26 | 技术债消费批次 F-49~F-63（10 工单 5 波） | ef67814→b0ce8b8 | Claude anthropic 1.x 去 temperature + P-/S- 前端防御十项收口，13 做 2 关 |
| 2026-08-26 | UX 体验改进批次（8 工单 5 波） | e127b52→04635ce | regenerate 重生成全链路 + 搜索跳转高亮 + 对话内模型切换 + 快赢三项 |
| 2026-08-26 | 会话交付：模拟器导入「AI/本地」识别补强 + 重新识别入口 | 07d9ab4 | probe_config 三重盲区补强 + reprobe 端点 + 卡片重新识别按钮 |
| 2026-08-26 | 会话交付：code-review 修复批次（3 工单） | 18490b6→8bb771b | 滚动高亮坐标系 + package-lock 0.1.0→0.2.0 + CSS 死代码清理 |
| 2026-08-26 | 技术债区 24 项批次（8 做 15 关 1 跳） | e750e07→8080563 | F-23~F-46 消费：docstring/常量/`__all__` 收口 + 15 项复核关闭（F-45 跳过） |
| 2026-08-25 | 会话交付：AI 游戏生成功能三处登记 | 3c06fa0 | CONSENSUS §14 + PROJECT_REFERENCE 交付侧面补登记 |
| 2026-08-19 | 会话交付：模拟器接入契约 + 外置数据目录与用户导入（T-01/T-02，5 工单 3 波） | c710eb5→78ad707 | 覆盖层核对脚本 + 数据目录外置 + 导入端点/UI + per-game CSS 注入 |
| 2026-08-19 | 会话交付：模拟器 PC 阅读优化（2 工单） | 857d14b→1edf945 | 共享覆盖层 6 分区 + injectPcOverlay 注入 + 22 游戏全量浏览器实测 |
| 2026-08-15 | 会话交付：关闭行为偏好 D11（无工单） | settings.rs 深模块 | CloseAction tray/quit 决策 + 首次运行选择弹窗 + 12+19 用例 |
| 2026-08-15 | 会话交付：模拟器获取列表修复 + 开场白预插（无工单） | — | openai_base_url 统一 /v1 + `first_mes` 预插 + 循环导入函数级延迟 |
| 2026-08-15 | 技术债区 F-1/F-2/F-4 批次（轻量档 1 工单） | 68251a6 | F-1 setter 名改述 + F-2/F-4 复核关闭，技术债区清零 |
| 2026-08-15 | C3/C4/C8 技术债批次（标准档 2 波 3 工单） | 43474eb→10a0093 | 注入钩子 options-object + simulator-contracts 契约深模块 + list-views 下沉 |
| 2026-08-15 | C6 后端 LLM 派生链收敛（小档 3 工单 + F4 修复） | f4a76f4→73d32e6 | provider_registry 单源 + factory/setting 对标 + 缺 id 对称校验 |
| 2026-08-15 | C5 角色字段知识收敛（标准档 2 工单串行链） | 4556492→fdf0179 | character_fields 16 字段单源 + CharacterBase 继承 + 26 契约锁 |
| 2026-08-15 | C2 saveKeys 匹配语义收口（轻量档 1 工单） | b60520d | save-key-meta 三导出（IsPattern/IsValidPattern/Matches）深模块 |
| 2026-08-15 | C1 写回环状态机收口（串行链 4 工单） | 18300a1→922f03d | key-injector 熔断/冷却单一状态机，simulator-view 收口触发时机 |
| 2026-08-14 | 技术债区 TD-75/76 批次（小档 2 工单） | 18b96ce→26b6af6 | 观察者 attributes 监听 + 熔断改 written 真写入判据 |
| 2026-08-14 | SIM-API-1 批次（用户需求） | 2fdfd5e | 22 款模拟器 API/模型统一由主应用同步（endpointMode manifest） |
| 2026-08-14 | 技术债区 TD-72/73/74 批次（轻量档 1 工单 3 提交） | 942ffb9→5435ea5 | 超时守卫延展响应体 + 导入回滚 per-key + 图标锁票面修正 |
| 2026-08-14 | 技术债区 TD-48~71 余项批次（标准档 4 工单 2 波） | dbcc15c→bad8006 | fetch-seam + 导航守卫 + 导入快照回滚 + 图标一致性锁，13 做 4 关 |
| 2026-08-14 | 技术债区 TD-57/66/67/68 批次（3 工单小档） | 75d9d5c→7d803d0 | model 门控 + save-key-meta 建模块 + 信任边界文档化 |
| 2026-08-14 | U8+U9 模拟器二期批次（4 工单 2 波） | 9aa6cfd→79598c2 | 凭证端点 + manifest v2 + Key 一键注入 + 存档管理面板 |
| 2026-08-14 | U7 模拟器模块批次（5 工单标准档 3 波） | 0e19f50→72af4f4 | 模拟器入口/22 游戏数据/列表页/运行视图/冒烟脚本 |
| 2026-08-13 | 架构深化批次 td-arch-health（8 工单 3 波） | b4b0a31→48447e6 | 13 做 3 关：错误映射/凭据解析/CRUD 语义/气泡六变体/深模块化 |
| 2026-08-13 | 技术债区 TD-28 批次（轻量档） | 2da1c51 | sanitizeUrl 控制字符绕过修复（scheme 前剔除 [\x00- ]） |
| 2026-08-13 | 技术债区 TD-42 批次（轻量档） | a990d44 | 链接引号属性注入面修复 + 单引号保守拒绝裁决 |
| 2026-08-13 | 技术债区 TD-47 批次（轻量档） | 7c55d51 | 占位符碰撞作用域 3 形态拼接防护 |
| 2026-08-13 | 技术债区 TD-46 批次（轻量档） | 1f8e71e | 占位符还原 alternation 单 pass（O(N)，逐字节差分等价） |
| 2026-08-13 | 技术债区 TD-29~41/43~45 批次（标准档） | f01560f→daf5503 | 11 做 5 关 1 票面修正 + 占位符碰撞计数器失同步阻断修复 |
| 2026-08-12 | 技术债区 TD-13~14 批次 | a754a13→b284f78 | save 回调入口统一守卫 + 「逐字符一致」措辞澄清 + TD-9 顺带闭环 |
| 2026-08-12 | 技术债区 TD-15~24 批次（小档 2 工单） | 85aca1b→e16048f | 守卫条件化（模型下拉）10 项全做 |
| 2026-08-13 | 技术债区 TD-25~27 批次（轻量档） | ea222d3 | UNC 锁断言平台隔离 + TD-26/27 复核确认维持关闭 |
| 2026-08-12 | 技术债区 TD-8~12 批次（单波 3 并行） | 30bd2a0→a94b3ec | save/clear 裸绑定 `?.` 化收口 + TD-9/11 复核维持 |
| 2026-08-12 | 技术债区 TD-1~7 批次（两波） | 2340db0→ccc5e25 | 守卫体系 7 项全做（注释/守卫/绑定侧 no-op） |
| 2026-08-12 | 技术债区批次（16 项遗留清零） | 86df358→8b2af59 | ARC9-1~8/ARC10-1~5/T-04~06：6 做 + 10 项复核确认维持关闭 |
| 2026-08-12 | ARC-10 架构深化批次：剩余 8 候选 | 8b690bf→26ea54a | modal 工厂/C3-DEFER/角色域深模块/异常 handler/schema 快照/聚焦序列 |
| 2026-08-12 | ARC-9 架构深化批次：6 Strong 候选 | cef6ed9→abdeb0f | search-view/settleTurn/B1 非流式回合/数据目录四套/冒烟清理 + T-04 编码阻断修复 |
| 2026-08-11 | P6.4 Tauri 桌面版（8 工单 3 波） | 4226b27→1e93a97 | Tauri v2 壳 + PyInstaller onedir + 托盘/自启 + NSIS 安装器，2 阻断修复 |
| 2026-08-11 | OPT-1 UI 克制化与图标协议收口 | 8ce17bd（+OPT-1-FIX） | SVG 图标 seam + emoji 清除 + 主题 token 单源 + 错误气泡 CSS 回归修复 |
| 2026-08-10 | 架构深化 8 候选（两波并行） | aba8335→432d89b | StreamSession 深模块/级联/标题策略/展示契约/app.js 拆分/导出 seam |
| 2026-08-10 | P6.5 多 tab 会话管理（5 工单） | 4cc4c2e→811645e | tab 工作区 + 后台流式按捕获 id 写回 + sessionStorage 恢复 |
| 2026-08-09 | GUI 全功能验证修复（4 bug） | eaf3456 | 停止内容落库兜底/导出 RFC 5987/badge 误显/移动端布局 |
| 2026-08-09 | GUI 观察项修复 ①-④ | dd1d07d | greeting 重载/错误气泡样式/MD 导出模板变量/按钮 SVG |
| 2026-08-09 | 导入路径错误引导 | beec1a5 | 失败提示带格式说明 + 前端引导创建向导 |
| 2026-08-05 | 架构摩擦分析 11 候选（第三轮收官） | a69c53e→29da016 | 设置面板/模型选择/Provider 重构/异常解耦/SSE 解析器，全部落地 |
| 2026-08-03 | 架构深化候选 ②③④⑤（第二轮收官） | 8098114 | 导出收拢 + modal 工厂 + SearchResult schema + Vitest 基建 |
| 2026-08-04 | UI 重设计 | f83ec2f | Linear 设计语言 CSS 全面重写，0 行 JS 修改 |
| 2026-08-03 | 架构深化候选 ①②⑥ | 25bf5a4 | chat/setting 深模块 + Provider 注册显式化 |
| 2026-08-03 | 架构深化候选 ③⑤ | 98e0c29 | prompt 纯函数化 + app.js 拆分（1380→1080 行） |
| 2026-08-03 | 架构深化候选 ④ | 5ee1ba8 | response_model 驱动序列化，退役手写 dict |
| 2026-07-30 | Phase 0-5 + P6.1-6.3（初始 commit） | b5fe037 | 基础设施 + 全阶段骨架 + 导出/搜索/模板变量 |
| 2026-07-30~08-03 | Code Review — CR 项（两轮清零） | 7d892ed→6bdb1ca | 初轮严重 bug + 硬性违规 + 深模块化整改 |
| 2026-08-03 | 文档/测试专项审查 CR（D1~D7） | 8259266 | api-design/architecture/llm-integration 防漂移 + 测试规范 |
| 2026-08-03 | P2.5.1-5.8 角色卡导入导出 | bb4e7ba→5902ee2 | 转换层 + import/export API/UI + 引导 + 53 用例 |
| 2026-08-03 | P3.5 对话过程交互增强 | 4053e38 | 停止生成按钮 + 标题自动生成/截断 |
| 2026-08-03 | P4.3 API Key 保存时测试连接 | c0b6505 | test-connection 端点 + 前端确认框 |

---

> 创建者: to-tickets 阶段 (2026-07-30) · 本文件维护规则见 [docs/documentation-standards.md](docs/documentation-standards.md) · 归档压缩试点见 [docs/ticket-archive-cleanup-research.md](docs/ticket-archive-cleanup-research.md)