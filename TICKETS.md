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

> 当前 **10 项待办**（5 批：WL 世界书 / MS 消息操作 / BR 分支 / CG 图像沉淀 / MD Mod 挂载）。
> 规格依据（字段规格、纯函数签名、契约锁用例）统一见 [docs/chat-simulator-upgrade-spec.md](docs/chat-simulator-upgrade-spec.md)。
> 来源：AI风月对标调研（证据链与三份规格笔记见仓库外 `D:\tmp\fetchflow-aigs\`——采集脚手架不入库，避免 doc_sync files 双向覆盖校验误判）；定位约束=纯本地、不盈利、不做社交体系/积分体系。
> 技术债候选池见 [TECH_DEBT.md](TECH_DEBT.md)。

### 批次 WL — 世界书引擎（承接 docs/world-simulation-exploration.md D3/D4）

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|

### 批次 MS — 消息操作（继续 + swipes 多候选）

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|
| MS-1 | swipes 数据模型与服务（message_swipes 新表 + messages.active_swipe_index 自愈迁移） | ⬜ 待办 | spec §MS-1；序号唯一约束 + 切换越界异常 + 级联 + 导出往返 |
| MS-2 | swipes 前端（候选计数 + 左右切换 + 失败回滚；重生成改为追加候选） | ⬜ 待办 | spec §MS-2；Vitest 用例；单选不渲染控制条 |
| MS-3 | 「继续」生成（append 续写，不追加 user 消息） | ⬜ 待办 | spec §MS-3；条数不变 + 失败原内容零改动 |

### 批次 BR — 存档升级为分支点

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|
| BR-1 | 分支元数据 + 快照导出（conversations 增 parent/branch_from_message_id；版本化快照含世界书与 swipes） | ⬜ 待办 | spec §BR-1；截断锚正确性 + 版本拒绝 + 导出导入往返 |
| BR-2 | 从快照/分支派生会话（clone_conversation / branch_from_message + 路由） | ⬜ 待办 | spec §BR-2；新会话逐条一致 + 源零改动 + 世界书独立 + 父子级联语义 |

### 批次 CG — CG 沉淀与剧情回顾

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|
| CG-1 | text2img Provider 抽象（与 LLM Provider 同构 + 单一来源登记） | ⬜ 待办 | spec §CG-1；注册表派生 + 缺 Key 错误映射 + 超时/轮询上限 |
| CG-2 | CG 资产库 + 画廊（cg_images 新表 + 加权抽取 + 解锁） | ⬜ 待办 | spec §CG-2；入库去重 + 解锁幂等 + 加权分布可复现 + 会话删除图保留 |
| CG-3 | 对话内出图 + 剧情回顾时间线 | ⬜ 待办 | spec §CG-3；三态渲染 + 失败不破坏对话 + 时间线顺序 |

### 批次 MD — Mod 挂载层

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|
| MD-1 | Mod 数据模型与注入叠加（mods + mod_bindings 新表；apply_prompt_mods 三区域叠加） | ⬜ 待办 | spec §MD-1；绑定唯一 + 禁用零影响 + 排序稳定 + 空列表原样返回 |
| MD-2 | Mod 管理 UI（列表/开关/排序/区域选择/导入导出；CSS 类复用现有后载序注入 seam） | ⬜ 待办 | spec §MD-2；Vitest 用例 + Playwright 冒烟 |

> **实施顺序建议**：WL → MS → BR → CG → MD（依赖与风险见 spec 末节表格）。
> **每批统一验收口径**：先红后绿 + 全量基线不回退（pytest 823+1skip / Vitest 1189 / cargo 70）+ 覆盖率不放宽 + 冒烟 + 文档同步。

---

## 技术债区

> 已迁移至独立文件 [TECH_DEBT.md](TECH_DEBT.md)（AGENTS.md §3 规范，2026-08-24 迁移，
> 条目原文完整保留：C3/C4/C7/C8 + F-1~F-22 共 26 项，迁移时全部处置完毕、技术债区清零状态维持）。

---

## 已完成归档

> 完整批次（最近 6 批）见下方；更早批次已折叠为「历史归档索引」表（2026-08-27 首次压缩执行，原文 54 批次由 git 历史承担）。

### 世界书批次 WL-5（2026-09-10 — 记忆宫殿 AI 归纳层，WL 批收官）

> 来源：AI风月对标调研五批工单（WL 世界书第五张/收官）；设计语义对齐对标站「AI 自动写条目」，引擎零改动（调用方形态，spec §WL-5）。叙述详见 DEV_LOG〈WL-5 记忆宫殿（2026-09-10）〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| WL-5 | 记忆宫殿（AI 归纳 → source=auto 条目；阈值触发；失败隔离） | 2026-09-10 | 91cb653 |

**验证链：** pytest 901+1skip→916+1skip（+15：test_memory_palace——阈值矩阵/JSON 剥围栏严格解析/非法与缺字段与 LLM 异常降级不抛/keys 空跳过/同 keys+content 去重/position-depth-source 固定/schema 三字段/chat 完整回合触发/开关关不产生/归纳失败不破坏回合/触发层意外外层隔离/title 超长截断防 500/每 N 轮增量节奏）| Vitest 1212→1213（+1：source 过滤 + 记忆标记）| 双端全绿零回归 | 期末 code-review 三轴：Standards 0 硬违例 / Spec 3 发现（每 N 轮节奏增量修复 / 开关全局偏差落债 / source 过滤已补）/ Falsify 2 MEDIUM + 2 LOW 当场修复（stream done 帧后触发 / title 截断 / prompt 注入隔离指令 / 窗口字符预算）| doc_sync 零漂移
**非阻断落债：** F-97（记忆开关会话级细化候选）；「自动总结」互斥项按 spec 后置不实现（DEV_LOG 记录）

---

### 世界书批次 WL-4（2026-09-10 — 世界书编辑器前端，WL 批第四张）

> 来源：AI风月对标调研五批工单（WL 世界书第四张）；UI 规格/契约锁依据见 docs/chat-simulator-upgrade-spec.md §WL-4。叙述详见 DEV_LOG〈WL-4 世界书编辑器前端（2026-09-10）〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| WL-4 | 世界书编辑器前端（CRUD 面板 + 泛词告警 + 字段校验） | 2026-09-10 | 7073757 |

**验证链：** 后端 pytest 896+1skip→901+1skip（+5：test_lorebook_routes 路由契约锁——列表/创建/部分更新/删除/守卫 404/校验 422）| 前端 Vitest 1189→1211（+22：lorebook-editor 契约锁——chips 录入去重删除与增删交互/表单校验（含空数值防静默 0）/泛词告警/payload 字段映射与后端 schema 一致/列表渲染搜索过滤/开关态渲染/保存成功失败与校验拦截/列表错误路径/属性上下文注入防护；覆盖率 94.18% 过 90% 门）| 全量双端绿零回归 | Playwright 端到端：角色卡「世界书」按钮开面板 → 新增（chip 录入/内容/保存）→ 列表显示 → 重开编辑字段全还原 → 发消息「酒馆在哪里？」后端 DEBUG 日志「世界书注入：{'system': 1}（1 条）」注入生效 | 期末 code-review 三轴：Standards 1 硬违例（路由 type hints）+ Spec 0 硬发现 + Falsify 1 HIGH（stored XSS 属性注入，escapeAttr 修复+契约锁）+ 2 LOW 当场修复 | doc_sync 零漂移
**非阻断落债：** F-96（escapeHtml 属性转义仓库级同族），入 TECH_DEBT 候选区；内容 20000 上限为设计决策（UI 层可配，后端不限长保导入保真）

---

### 技术债消费批次 F-96（2026-09-10，轻量档 1 工单）

> 来源：用户「继续消费技术债」；候选区 WL-4 期末 Falsify 轴 stored XSS 实证（escapeHtml 不转义引号 → 属性上下文注入）。Grilling 实证拍板**做**——git grep 复核 15 处 `="${escapeHtml(...)}"` 属性插值（format/character-form/settings-panel/model-selector/tab-bar/character-wizard/model-utils），值多为用户可控内容。方案：升级共享 `escapeHtml` 同时转义 `"`（一处收敛全族），lorebook-editor 局部 escapeAttr 退役；markdown sanitizeUrl 补实体引号形态拒绝保住 TD-42 契约。处置详情见 TECH_DEBT 2026-09-10 节。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| 01 | escapeHtml 升级转义引号（15 处属性插值一处收敛 + markdown 实体引号拒绝 + 契约锁） | F-96 | 2026-09-10 | 46069c8 |

**验证链：** Vitest 1211→1212（+1：escapeHtml 引号转义 + DOM 实体解码往返 + 无注入属性）| markdown TD-42 既有用例全绿（实体引号拒绝保住「引号 URL → 纯文本」契约）| 全量双端绿零回归 | doc_sync 零漂移
**非阻断落债：** 无（候选区清零）

---

### 技术债消费批次 F-94 + F-95（2026-09-10，轻量档 2 工单）

> 来源：用户「继续消费技术债」；候选区 WL-3 期末 code-review Standards 轴两项。Grilling 实证拍板**全做**——F-94 `chat._msg_role` 与 `prompt._role_str` 枚举归一重复（chat.py:535 / prompt.py:103 `hasattr(.value)`）；F-95 `build_message_list` 生产调用方仅 chat.py 两处，加可选 history 参数即消除扫描窗 + 内部双查。方案：text_utils 增 `role_str` 收敛（prompt/chat 改指）+ build_message_list 增 `history: Sequence | None`（None → 内部查询）。处置详情见 TECH_DEBT 2026-09-10 节。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| 01 | text_utils.role_str 共享收敛（prompt/chat 改指 + 删私有归一函数） | F-94 | 2026-09-10 | 364436d |
| 02 | build_message_list 增可选 history 参数（assemble 传入已取历史消除双查） | F-95 | 2026-09-10 | 364436d |

**验证链：** pytest 891+1skip→896+1skip（+5：test_text_utils role_str 矩阵 4 + build_message_list 显式 history 不再查库锁）| 既有 prompt/chat/regenerate 用例全绿（role_str 收敛零行为变化）| 波末文件范围核验合规（text_utils/prompt/chat/message+tests）| doc_sync 零漂移
**非阻断落债：** 无（候选区清零）

---

### 世界书批次 WL-3（2026-09-10 — 注入链集成，WL 批第三张）

> 来源：AI风月对标调研五批工单（WL 世界书第三张）；组装语义/契约锁依据见 docs/chat-simulator-upgrade-spec.md §WL-3。叙述详见 DEV_LOG〈WL-3 世界书注入链集成（2026-09-10）〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| WL-3 | 注入链集成（build_messages 增 world 可选参数，三注入位；prepare_chat 组装） | 2026-09-10 | ec5f1e3 |

**验证链：** pytest 879+1skip→891+1skip（+12：test_prompt_world_injection 7 + test_chat_world_injection 5——world=None 逐字节零回归/三注入位序列/世界知识合并单条/重生成尾随剥离/空世界书无空 system/空 content 条目过滤/普通与重生成两路径一致/无条目零开销/滑窗与 depth 解耦）| 既有 build_messages/chat/regenerate 用例全绿（零变化硬约束）| 期末 code-review 三轴：Standards 0 违例 / Spec 0 发现 / Falsify 1 LOW 当场修复（空内容空壳 system）| doc_sync 零漂移
**非阻断落债：** F-94（_msg_role/_role_str 重复）/ F-95（双查历史），入 TECH_DEBT 候选区

---

### 技术债消费批次 F-93（2026-09-10，轻量档 1 工单）

> 来源：用户「消费技术债后继续推进 WL-3」；候选区唯一剩余项 F-93（WL-1 期末 code-review Standards 轴）。Grilling 实证拍板**做**——git grep 复核 `lorebook._as_str_list` 与 `character_card._as_list` 逐行重复仍成立（character_card 2 处 + lorebook 1 处消费）。方案：新建 `services/text_utils.py` 共享单点 `as_str_list` 收敛，两消费者改指、删除重复私有函数；行为由既有测试全量锁定 + 新契约锁 7 条。处置详情见 TECH_DEBT 2026-09-10 节。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| 01 | text_utils.as_str_list 共享单点收敛（character_card/lorebook 改指 + 删重复私有函数） | F-93 | 2026-09-10 | 4ad64e7 |

**验证链：** pytest 873+1skip→879+1skip（+6：test_text_utils 脏数据容错矩阵）| character_card（56）+ lorebook_store（24）既有用例零变化 | 覆盖率不放宽（纯重构收敛）| 波末文件范围核验合规（text_utils/character_card/lorebook/__init__+tests）| doc_sync 零漂移
**非阻断落债：** 无（候选区清零）

---

### 世界书批次 WL-2（2026-09-10 — 激活引擎纯函数，WL 批第二张）

> 来源：AI风月对标调研五批工单（WL 世界书第二张）；引擎语义/契约锁依据见 docs/chat-simulator-upgrade-spec.md §WL-2。叙述详见 DEV_LOG〈WL-2 世界书激活引擎纯函数（2026-09-10）〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| WL-2 | 激活引擎纯函数（activate_lorebook_entries / build_world_injection / collect_scan_text） | 2026-09-10 | 59c3726 |

**验证链：** pytest 847+1skip→873+1skip（+26：test_lorebook_engine 契约锁 24 + 审核修复锁 2——空输入零异常/constant 直进/or-and 矩阵/大小写不敏感锁定/depth 边界裁剪/system 不计轮/概率 0-100 闸/RNG 同种子复现/跨输入顺序可复现/互斥组加权抽一/order-id 稳定排序/空白 key 剔除与裁剪/泛词不报错/零 DB 导入 subprocess 检查）| services __all__ 登记同步 | 期末 code-review 三轴：Standards 0 违例 / Spec 0 发现 / Falsify 1 MEDIUM + 1 LOW 当场修复 | doc_sync 零漂移
**非阻断落债：** 无（F-93 仍为 WL-1 遗留候选，未消费）

---

### 世界书批次 WL-1（2026-09-10 — 世界书数据模型 + 仓库层，WL 批首个）

> 来源：AI风月对标调研五批工单（WL 世界书首张）；字段规格/契约锁依据见 docs/chat-simulator-upgrade-spec.md §WL-1。叙述详见 DEV_LOG〈WL-1 世界书数据模型 + 仓库层（2026-09-10）〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| WL-1 | 世界书数据模型 + 仓库层（lorebook_entries 新表 + character_book 解析入库） | 2026-09-10 | 51e3786 |

**验证链：** pytest 823+1skip→847+1skip（+24：test_lorebook_store 契约锁 22 + Falsify 修复锁 2——keys 数组/越界拒/级联/替换幂等/ST 解析/布尔字符串/显式 null 防毒化/保真零回归）| schema.sql 快照同步（新表 DDL + CHECK ×4 + 索引）+ test_migrate_data 表集合更新 | services/schemas __all__ 登记同步 | 既有 character_book 往返保真零回归（test_character_card 全绿）| 期末 code-review 三轴：Standards 0 违例 / Spec 0 发现 / Falsify 2 HIGH 当场修复 | doc_sync 零漂移
**非阻断落债：** F-93（架构去重，入 TECH_DEBT 候选区）

---

### 用户修复批次 — 模拟器 API CORS 反代 + 重新识别按钮 UI 收口（2026-08-28）

> 来源：用户报告「模拟器 API 连接不上、聊天畅通」+「本地导入斗罗大陆在列表显违和（无简介、卡片带 per-card 重新识别按钮）」，建议把重新识别收口为工具栏全量操作。
> 根因（CORS 实证）：模拟器游戏在 iframe 内用浏览器 fetch 直连第三方 OpenAI 兼容 API（SIM-API-1 方案 2 固有架构），目标 yunshuzhilian.asia 无 `Access-Control-Allow-Origin`（OPTIONS 预检实测 403）→ 浏览器 CORS 拦截 →「连不上」；聊天走主应用后端服务端请求不受此限。
> 修复：后端新增 `/api/simulators/proxy/{path}` 同源反代（httpx 服务端转发 + 后端注入 key + 流式透传，纯函数 `_build_proxy_target`/`_proxy_headers` 可单测）；前端 key-injector 新增 `toProxyEndpoint`，注入 endpoint 改写成主应用同源反代地址再口径转换。UI：重新识别按钮由 per-card 收口为工具栏全量 `reprobeAllImported`（对 canReprobeGame 条目全量 POST）；无简介导入/AI 生成卡片渲染占位简介（`renderCardDesc`，消除空白违和）。详见 DEV_LOG〈模拟器 API CORS 反代 + 重新识别按钮 UI 收口（2026-08-28）〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| 01 | 模拟器 API 同源反代（CORS 修复：proxy 端点 + 注入代理化） | 用户报告 | 2026-08-28 | c26144a |
| 02 | 重新识别按钮收口工具栏全量 + 无简介占位（UI 收口） | 用户报告 | 2026-08-28 | c26144a |

**验证链：** pytest 809+1skip→823+1skip（+14：test_simulator_proxy 纯函数矩阵 + 路由 wire）| Vitest 1182→1189（+7：key-injector toProxyEndpoint + 注入 core + simulators 全量 reprobe/占位简介）| 全量绿 | 端到端（源码后端 + Playwright）：注入 endpoint 变为 `http://127.0.0.1:8000/api/simulators/proxy/v1/chat/completions`、点「保存并继续」无 CORS blocked 错误、curl proxy 端点转发到上游（401 INVALID_API_KEY 证明服务端转发 + key 注入）；斗罗大陆卡片去掉 per-card 按钮、占位简介「本地导入的模拟器」、工具栏出现「重新识别」全量按钮
**非阻断落债：** 无

---

> 完整批次（最近 6 批）见下方；更早批次已折叠为「历史归档索引」表（2026-08-27 首次压缩执行，原文 54 批次由 git 历史承担）。

### 技术债消费批次 F-92（2026-08-27，kickoff 全自动档轻量档 1 工单）

> 来源：用户「消费技术债区，进入 project-kickoff 全自动流程」选择候选区唯一剩余项 F-92。Grilling 实证拍板**做**——git grep 复核 simulators.js 按钮条件 `type==='local'` 与 reprobe 端点按 id 定位不区分 type，确认「ai 但 config 错的老条目无 UI reprobe 入口」为真实缺口；方案 D 锁定：新增纯函数 `canReprobeGame(game) = local 恒真 || ai∧source==='imported'` 驱动渲染条件，后端零改动。轻量档单工单独立分支 kickoff/f92-reprobe-ai-card。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| 01 | canReprobeGame 驱动「重新识别」按钮渲染（ai+imported 可一键 reprobe） | F-92 | 2026-08-27 | 207af86 / merge 43d0bbf / doc_sync 5557a91 |

**验证链：** pytest 809+1skip（后端零改动）| Vitest 1172→1182（+10：canReprobeGame 判定矩阵 8 + 渲染契约 ai+imported/generated + __all__ 断言更新；simulators.test.js 79→89）| 覆盖率不放宽（simulators.js Stmts 99.64 / Branch 93.93，任务前基线口径）| 突变抽查：删 ai+imported 分支 → 测试失败（非伪测试）| 期末四轴 **0 阻断放行**、安全红线 0 违例（非阻断 2 项文档发现已顺手修订）| 运行态冒烟通过（Playwright：ai+imported 斗罗大陆卡片出现「重新识别」按钮、种子 ai 卡片无按钮；点击 → reprobe 成功、manifest type/source/config 保留）| doc_sync 零漂移
**非阻断落债：** 无（候选区清零）

---

### 用户 bug 修复批次 F-91（2026-08-27 — 斗罗大陆同步失效，用户报告单工单）

> 来源：用户报告「本地导入的斗罗大陆同步全局 API 设置失效」。根因实证：斗罗大陆有两套 AI 配置控件（向导 wz-* load 渲染 + 设置模态 s-* 后开），探针每组只取文档序首个命中 → manifest 记 s-* 族，load 注入找不到控件。修复：config 三元组支持多候选 id（`string | string[]`），探针全量收集、注入/观察者按候选逐个尝试。详见 DEV_LOG〈用户 bug 修复 F-91〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| 01 | 模拟器 config 多候选 id（探针全量收集 + 注入/观察者按候选尝试） | F-91 | 2026-08-27 | bab57a1 |

**验证链：** pytest 809+1skip（探针矩阵零回归，斗罗大陆场景断言多候选数组）| Vitest 1172（key-injector 97 用例，+5 多候选）| 真实 probe 返回双族候选 | Playwright 端到端：首启向导自动填入全局 key/端点/模型 | AppData 老条目 config 数据修正 | doc_sync 零漂移
**非阻断观察：** 前端「重新识别」按钮仅 local 卡片渲染，ai 但 config 错的老条目无法从 UI 一键 reprobe（本次靠一次性数据修正）——Worth exploring 候选，不入本期

---

### 技术债消费批次 F-90（2026-08-27，kickoff 全自动档轻量档 1 工单）

> 来源：用户「继续新一轮消费」选择候选区唯一剩余项 F-90。Grilling 实证拍板**做**——`syncGameCredentials` 生产唯一调用方 runSync 传 getDoc（doc 回落分支生产死代码），doc 仅测试消费（5 处直调用例）；收编 getDoc-only 消除 F-89 引入的双通道冗余。轻量档单工单独立分支 kickoff/f90-getdoc-only。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| 01 | syncGameCredentials 收编 getDoc-only（删 doc 死参数，5 处测试迁移，惰性时序保持） | F-90 | 2026-08-27 | 58a7f6b / merge 1465c33 |

**验证链：** pytest 809+1skip ✅（零后端改动）| Vitest 1165 ✅（不回退）| key-injector 100% 覆盖（Branch 92.55%）| 波末文件范围核验合规（key-injector.js + test）| 期末轻量自审 0 阻断（Standards 安全红线零命中 / Falsify 突变 `targetDoc 恒 null` → 24 测试失败证明灵敏）| 运行态冒烟通过（uvicorn + 5 端点全 200）| doc_sync 零漂移
**非阻断落债：** 无（候选区清零）

---

### 技术债消费批次 F-82~F-89（2026-08-27，kickoff 全自动档小档 3 工单后台 lane）

> 来源：用户「继续消费 TECH_DEBT 候选区 8 项」。Grilling 逐项实证拍板 **3 做 + 5 关**——5 关均附 git grep 复核理由：F-82 settleTurn refresh 收口边界不可行（onError 停止路径与流中断分支绕过 settleTurn，注入刷新回调即扩参数面=同 F-65 被关闭项）；F-84 双并发守卫为有意分工（流式 isStreaming+停止态 UX vs 非流式 Set+禁用态，互斥闭环无缝、关 tab 自愈防锁死，chat.js:111 注释属实）；F-85 compareCoverage 归一化唯一消费方入参恒规整、防御分支生产不可达且被测试契约锁定；F-86 avatarImgHtml 三层转义已单点化且契约锁定、无注入面；F-87 深模块标签通胀修复=大面积美容性重标无功能价值。3 做项经小档后台 lane 连续交付（同分支 kickoff/g1-g3 每工单独立 commit，规避并发上限）。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| G1 | tabs.js 展示字段单一声明表派生 DISPLAY_KEYS（消除双清单「改动须同步」约束） | F-83 | 2026-08-27 | de150c4 / merge 15ad372 |
| G2 | stream-session 模块 docstring 补停止路径时序/职责表（tabs.abortStream→api.abort→isAbortError 分流→phase error+stopped→复位钩子，五跳） | F-88 | 2026-08-27 | 3926db9 / merge 15ad372 |
| G3 | flushObserverSync 断连失效守卫 + syncGameCredentials getDoc 惰性取用（陈旧在途写不污染熔断计数） | F-89 | 2026-08-27 | 5a3cab5 / merge 15ad372 |

**关闭：** F-82 / F-84 / F-85 / F-86 / F-87（复核成立，无代码改动，理由见 TECH_DEBT 处置记录）
**验证链：** pytest 809+1skip ✅（零后端改动）| Vitest 1164→1165 ✅（+1：G3 断连失效守卫测试）| 波末文件范围核验合规（tabs/stream-session/key-injector+test）| 期末四轴 **0 阻断放行**（G3 偏离处方被独立判定必要且最小：工单处方「只改 getDoc 闭包」因 runSync 同步急切求值成死代码，惰性取用是正确补位）、安全红线 0 违例 | 运行态冒烟通过（uvicorn + 5 端点全 200）| doc_sync 零漂移
**非阻断落债：** F-90（期末四轴 Architecture/Standards：syncGameCredentials doc/getDoc 双通道轻度冗余——外部直调用契约 + 观察者惰性取用刻意保留，未来可收编为 getDoc-only；AGENTS.md 测试基线散文句手工维护不归 doc_sync 管）

---

### 架构深化批次 S1~S3（2026-08-27，kickoff 全自动档标准档 3 工单单波并行）

> 来源：用户「improve-codebase-architecture 后评审交付 project-kickoff 全自动优化」——架构报告（D:\tmp\architecture-review-20260827-180658.html）Strong 三候选直落。Grilling 共识：零重开、行为零变化硬约束（S2/S3 纯收口，S1 仅重生成代码形态变化、行为由既有 PHI 用例锁定）。spec：本批 spec/evidence 经 Neat 清场移除（决策结论折入本行与 DEV_LOG 批次摘要）。三工单文件互不相交无阻塞 → 单波 3 并行；doc_sync 钩子 worktree 拦截用 --no-verify 提交、合并后主会话统一刷新；工单 02 两次网关并发上限失败后串行重试成功。

| Ticket | 标题 | 锚定 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| 01 | build_messages/build_message_list 新增 append_current_input 显式路径，重生成分支退化为单行调用（PHI 剥离迁入纯函数） | S1 | 2026-08-27 | cf60935 / merge af5fc4c |
| 02 | _LLM_ERROR_MAP 改为显式有序列表 + docstring「顺序即优先级/基类兜底」契约 | S2 | 2026-08-27 | ec44fdb / merge 958f527 |
| 03 | 模拟器配置同步状态机边界收口：观察者生命周期（disconnectObserver/configObserver/observerTimer/mutationTouchesConfig）迁入 key-injector，simulator-view 仅留触发点 | S3 | 2026-08-27 | 0476927 / merge f947a65 |

**验证链：** pytest 792→809+1skip ✅（+17）| Vitest 1145→1164 ✅（+19，S3 观察者生命周期 + key-injector 89%）| 覆盖率（本工单口径）：S1 92.08% / S2 97% / S3 两源文件 100% | 波末文件范围核验合规 | 期末四轴 1 阻断修复（CODE_WIKI doc_sync 刷新未提交态 → 补 commit 2ac2211）+ 非阻断落债 F-89 | 运行态冒烟通过（uvicorn + /api/models /docs /api/characters /api/conversations / 首页全 200）| doc_sync 零漂移
**非阻断落债：** F-89（期末四轴 Falsify：断连与在途同步窄竞态，离树写入不可见，无用户可见影响，Speculative）

---

### 技术债消费批次 F-80~F-81（2026-08-27，kickoff 全自动档轻量档 1 工单）

> 来源：用户「继续新一轮消费 kick」选择新债 F-80/F-81。Grilling 共识 1 做 + 1 关（F-81 复核关闭——会话 id 全库严格 `===` 惯例（chat.js:655/797、conversation-activation.js:134、app.js:218、list-views.js:317、tabs.js 全套）、两侧同源 JSON number 无跨边界风险、严格比对是正确守卫会响亮暴露契约破裂而非被 String() 静默掩盖）。工单为纯可读性重构零行为变化；期末四轴 0 阻断放行；技术债候选区清零。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| 01 | stream-session 提取 sameId 归一比较 helper（4 处 String() 字面比较收敛） | F-80 | 2026-08-27 | 5936068 / merge 0a15e94 |

**关闭：** F-81（复核成立，无代码改动，理由见 TECH_DEBT 处置记录）
**验证链：** pytest 792+1skip ✅（零后端改动）| Vitest 1145 ✅（零新增零改动——纯重构）| 波末文件范围核验合规（仅 stream-session.js）| 期末四轴 0 阻断、安全红线 0 违例 | 运行态冒烟通过（uvicorn + 页面/JS/API 全 200，服务端 JS 含 sameId 标记）| doc_sync 零漂移
**非阻断落债：** 无（候选区清零）

---

### 技术债消费批次 F-74~F-79（2026-08-27，kickoff 全自动档小档 2 工单后台 lane）

> 来源：用户「消费候选 F-74~F-79 进入全自动流程」。Grilling 共识 2 做 + 3 关（F-75 String(null) 坍缩不可达——replaceId/messageId 均前置守卫 + 后端 int id 不可能等于字面量；F-76 对比度余量——当前唯一渲染语境 `.modal`=--bg #b45309 4.61:1 达标、加深会改可见色；F-79 locateAndHighlight 顶层 children 遍历 F-69 已实现、当前气泡为直接子节点行为等价）。工单 A 含一处预期内行为修正（跨边界 string/number 幂等早退激活），工单 B 纯重构零行为变化；期末四轴 0 阻断放行。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| 01 | stream-session 幂等 id 比较 String() 归一（settleByPosition 幂等早退 + mergeFreshList stale 定位） | F-74 + F-78 | 2026-08-27 | f865440 / merge 8f464b0 |
| 02 | openModelSwitch warnReason 提示文案提取单一映射表（纯重构，文案逐字） | F-77 | 2026-08-27 | d7663c6 / merge 8f464b0 |

**关闭：** F-75 / F-76 / F-79（复核成立，无代码改动，理由见 TECH_DEBT 处置记录）
**验证链：** pytest 792+1skip ✅（零后端改动）| Vitest 1135→1145 ✅（+10：stream-session +6、chat +4）| 波末文件范围核验合规 | 期末四轴 0 阻断、安全红线 0 违例 | 运行态冒烟通过（uvicorn + 页面/JS/CSS/API 全 200，服务端 JS 含新标记）| doc_sync 零漂移
**非阻断落债：** F-80（stream-session `String()` 字面比较重复 4×，可提 `sameId(a,b)` 私有 helper）/ F-81（chat.js 3 处 state 同源严格 `===`，无跨边界风险，范围外既有写法）

---

### 技术债消费批次 F-64~F-73（2026-08-27，kickoff 全自动档标准档 4 工单 2 波）

> 来源：用户对 F-64~F-73 候选区继续立项。Grilling 共识 8 做 + 2 关（F-64 实证复核关闭——期末审核基于过时行号误报「regenerate 流式在途无守卫」，chat.js:760 入口实际已查 `tab.isStreaming`；F-65 架构重构候选与 F-37/F-38/F-42 同族关闭）。波 1 审核两中危 Falsify 缺陷主会话直修（F-66 类型归一 + F-73 dark override）；波 2 审核放行；期末四轴 0 阻断放行。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| 01 T1 | error-bar 会话幂等寻址防注入（F-67，遍历比对免疫选择器注入） | 2026-08-27 | 59b17c9 / merge b95fbc7 |
| 02 T2 | stream-session 结算合并边界（F-66 顶替场景 + F-68 空回复不丢弃） | 2026-08-27 | ea7661e / merge 1a622f4 |
| 03 T3 | chat.js 防御小修（F-69 定位转义 / F-70 保存语义分离 / F-71 fail-closed / F-72 快照迭代） | 2026-08-27 | e13739b / merge 0f3b8ba |
| 04 T4 | .gg-config-warning-nav 对比度加深（F-73，#b45309 对 light ≥4.5:1） | 2026-08-27 | 10af303 / merge 125a85e |

**主会话直修**：W1 审核两缺陷——F-66 String() 类型归一（replaceId 与缓存 id 跨类型失配时顶替失效）+ F-73 dark 语境回退 var(--warning)（防 #b45309 在 dark 底 3.45:1），各 +1 回归测试
**验证链：** pytest 792+1skip ✅（零后端改动）| Vitest 1117→1135 ✅（+18，含新建 style-css.test.js 5 例）| 波内增量审核 2 轮均放行 | 期末四轴 0 阻断、安全红线 0 违例 | 运行态冒烟通过（uvicorn + 页面/JS 模块/CSS/API 全 200）| doc_sync 零漂移
**非阻断落债：** F-74~F-79（6 项：幂等比较未归一/String(null) 坍缩/对比度余量 0.11/Repeated Switches/id 归一三文件分叉/顶层 children 遍历注记）

---

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