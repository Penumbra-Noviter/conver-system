# TECH_DEBT: conver system

> **技术债候选池**（未立项子集）与**处置记录**。本文件与 `TICKETS.md`（任务池，本项目任务文件名为 `TICKETS.md` 而非 `TO-TICKETS.md`）分离——候选不等于任务，不自动进入任何 session 的 preflight 认领；消费 = 显式「立项」（从候选区取出 → 转入 `TICKETS.md` 活跃工单，或标记 ❌ 不立项附理由）。
> 读取契约与强度消费规则见 project-kickoff 步骤 0 预检（`AGENTS.md` §3 任务清单生命周期）。
>
> 本文件由 `TICKETS.md` 技术债区独立化迁移而来（2026-08-24，对齐 AGENTS.md §3 规范），原文完整保留审计追溯。

---

## 规范说明

### 条目格式

候选区每行对应一条技术债，含 6 个字段：

| 字段 | 含义 |
|------|------|
| **编号** | `F-N` 递增唯一 |
| **遗留项** | 什么问题、在哪个文件、当前影响 |
| **来源** | 产生此条目的审核/讨论/评审（如「波 1 增量审核」「期末四轴 Architecture」） |
| **强度** | `Strong` / `Worth exploring` / `Speculative`（见下方消费规则） |
| **状态** | `📝 待立项` / `🔄 进行中` / `✅ 已修` / `❌ 复核关闭` |
| **归属方向** | 此条目的业务方向（如 `前端渲染` / `流式链路` / `架构`），session 只认领匹配方向的条目 |

> 注：本项目历史条目使用旧强度词汇（「中」≈ `Worth exploring`、「低」/「低（信息性）」≈ `Speculative`）；历史条目保留原词，新条目按上方三档录入。

### 强度消费规则

| 强度 | 消费规则 |
|------|----------|
| **Strong** | 必入工单清单（下一轮 kickoff 的 plan-tickets 必须包含） |
| **Worth exploring** | 入候选由 Grilling 拍板（做/关闭），无默认方向 |
| **Speculative** | 可关闭，关闭须「`git grep` 复核现状仍成立」一句话理由 |

### 清出机制（防膨胀）

1. 候选区只留开放条目（📝 待立项 / 🔄 进行中）；条目处置后整行移出候选区，处置详情写入「技术债处置记录」
2. ❌ 关闭条目压缩：具复核价值的关闭项（防 review 重复提出的 Speculative 类）保留单行摘要于「复核关闭」表，其余直接删除
3. 处置记录按日期分节，滚动保留最近 **2 节**（同日多批次合并计为一节）；更早归档由 git 历史承担（`git log -p -- TECH_DEBT.md`）
4. 清出动作绑定既有维护节点：每会话结束、commit 之前同步执行，不新增仪式
5. **机械约束**由 `scripts/pool_cleanup_check.py --check --tickets-file TICKETS.md` 强制（任务池本库名为 `TICKETS.md`）：候选区无 ✅/❌ 滞留、复核关闭表全 ❌、活跃工单无 ✅/❌、重复标题、脚注「当前最大 F-N」与全库最大编号一致、非空与必要节、表格列数异常报格式问题；本库沿用既有 `scripts/install-hooks.bat`（doc_sync 检查），清出检查建议并入同一 pre-commit（2026-08-31 起，脚本已就位）

### 多 session 防污染

1. **任务所有权分离**：`TICKETS.md` 是唯一任务池（preflight 只读它）；本文件是候选池（只写不认领）
2. **条目归属标注**：每条目必填「来源」与「归属方向」，session 只认领自己方向匹配的条目
3. **消费显式化**：从候选区转工单必须带一句话理由（强度 + 方向匹配），禁止静默批量认领
4. **写冲突隔离**：候选人落盘写本文件（评审 session 独占），任务状态变更写 `TICKETS.md`（认领 session 独占），不同 session 写不同文件，不互踩

---

## 技术债候选区

| 编号 | 遗留项 | 来源 | 强度 | 状态 | 归属方向 |
|------|--------|------|------|------|----------|
| F-127 | `append_swipe_and_bump` 两段提交非原子——`add_swipe` 内部 commit 后，外层再 bump updated_at + 二次 commit，崩溃窗口内「候选已落库但 updated_at 未 bump」（排序置顶不变量短暂失效；非本批回归，重构前同样两段，但「持久化仪式」未真正原子化） | arch-f123-126 期末四轴 Falsify/Architecture | Worth exploring | 📝 待立项 | 架构去重 |
| F-128 | `append_swipe_and_bump` 冗余重取——`add_swipe` 已 `_require_message` 取到消息，外层又 `_require_message` 重取一次（identity map 同对象，冗余 SELECT） | arch-f123-126 期末四轴 Architecture | Speculative | 📝 待立项 | 架构去重 |
| F-129 | `_ensure_conversation_branch_columns` 三列循环在 Engine 形态下各开独立连接 + 各 commit（原 1 连接 1 commit → 3 连接 3 commit），封装边界的轻微代价 | arch-f123-126 期末四轴 Architecture | Speculative | 📝 待立项 | 架构去重 |

### 复核关闭（Speculative 类，防重复提议）

| 编号 | 遗留项（压缩摘要） | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| F-97 | 记忆宫殿会话级开关细化（全局开关与角色级条目注入架构自洽，会话级需结构性变更） | WL-5 期末 code-review Spec 轴 | Worth exploring | ❌ 复核关闭 |
| F-25 | `error_mapping.py:117` provider 前导空格——docstring 已声明「由调用方负责」，设计意图非缺陷 | 波 1 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-27 | `test_error_mapping_export.py` 文件末尾无换行符 | 波 1 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-28 | simulator_store/manifest/import 三个文件末尾缺失换行符 | 波 2 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-32 | `simulator_import.py` `__all__` 含 read_manifest/write_manifest re-export | 波 2 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-34 | `game_generator.py:286` 函数对象身份比较（`if check is _check_security`） | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-35 | `scan_generated_html` 被导出到 `__all__` 扩展公共 API 表面 | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-36 | 校验失败时 scan 结果被丢弃，每次重试重新扫描 | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-40 | game_generator `_build_suggestion` 六分支级联 | 2026-08-25 全量审查 | Speculative | ❌ 复核关闭 |
| F-46 | 空串 token-only 流的前端占位残留（空气泡） | 期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-48 | Scroll handler Feature Envy，建议提取 ScrollSpy 类 | 2026-08-26 期末四轴（Architecture A6） | Speculative | ❌ 复核关闭 |
| F-49 | `error-bar.js:67` `String(message)` 对可抛 `toString()` 的 message 会抛 TypeError | W1 增量审核 | Speculative | ❌ 复核关闭 |
| F-75 | String(null/undefined) 坍缩字面量参与 id 比较 | 期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-76 | #b45309 对 --page 4.26:1 余量 0.11 | 期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-79 | locateAndHighlight 顶层 children 遍历注记 | 期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-87 | 文档区分「去重契约模块」与「深模块」标签 | 架构报告 2026-08-27 | Speculative | ❌ 复核关闭 |
| F-107 | mod-manager 导出未走 spec 字面 downloadBlob——utils.downloadBlob 是服务端导出 fetch helper，Mod 导出纯客户端无服务端导出面，本地 Blob 下载为正确形态，spec 措辞不精确 | MD-2 期末四轴 Spec | Speculative | ❌ 复核关闭 |
| F-108 | 导入往返逐条 version 回落服务端默认 1.0（id/created_at 重建）——spec 仅强制信封 version=1、未强制逐条 version 保留，非缺陷 | MD-2 期末四轴 Spec | Speculative | ❌ 复核关闭 |
| F-101 | ModResponse 非可选 vs 可空列——create_mod/update_mod 全路径经 Schema 默认值落库不产 NULL，理论性 500 不可达 | 技术债批次复核关闭 | Speculative | ❌ 复核关闭 |
| F-104 | 客户端 Blob 下载第三份重复——两处轻度重复，提取共享 helper 收益 < 成本 | 技术债批次复核关闭 | Speculative | ❌ 复核关闭 |
| F-105 | 角色存在性守卫两处——轻（Character.id 查询）与重（载会话计数）是不同 seam，非缺陷 | 技术债批次复核关闭 | Speculative | ❌ 复核关闭 |
| F-112 | ModsOrderUpdate lax 强转（字符串数字/布尔不 422）——前端唯一调用方 mod-manager reorder 恒传 number 数组，无真实脏数据路径 | 技术债批次期末四轴 Spec | Speculative | ❌ 复核关闭 |
| F-113 | `_prepare_messages` content.strip() 无类型守卫（非 str 抛 AttributeError）——组装层 content 恒为 DB Text 列字符串，防御缺口不可达 | 技术债批次期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-114 | 前端 reorder 乐观假设（提交后本地即按新序渲染，并发陈旧 400 由重拉自愈）——fail-closed 可接受，自愈语义已有契约 | 技术债批次期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-109 | mod-codec.js 声明名实不符——docstring 硬约束段（:16-18）已逐字豁免 importModsFromEnvelope（async、经 api.js fetch 注入点、不触 DOM），声明与实现一致，票面前提不成立 | 技术债批次期末四轴 Architecture | Worth exploring | ❌ 复核关闭 |
| F-111 | 会话列表分支来源标记空值渲染——list-views.js:323 空值守卫使空引号场景不可达（branch_title 与锚预览均空时 resolveBranchSource 返回 null 整段不渲染），后端标题/预览兜底链封死输入源 | 技术债批次期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-115 | list_cg 路由透传 gallery.list_cg 既有 group_name/unlocked_only 过滤参数（非无中生有），画廊分组过滤是可预见需求（网格已展示 group_name），删除反而未来返工 | mod-cg-wiring 期末四轴 Spec/Standards | Speculative | ❌ 复核关闭 |
| F-116 | 锁定 CG url 在 list 响应体是 spec 设计使然（list 全量含未解锁、响应含 url），前端渲染层已正确不加载锁定原图，锁定是软 UX 门非机密边界（本地单用户信任模型可接受） | mod-cg-wiring 期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-118 | applyCharacterCss 的 false 无法区分「无 css Mod 空态」vs「取数失败」，修复需改返回契约牵动 17 用例，实际开销（流式本地 2 次请求）可忽略——成本收益不成比例 | mod-cg-wiring 期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-121 | 候选池过滤是回合末一次性触发语义（未解锁+weight>0），与 gallery.list_cg 列表展示过滤不同；下沉只增被 chat.py 独调的窄函数 Leverage 低，spec 已划 chat.py 为触发编排落点 | mod-cg-wiring 期末四轴 Architecture | Worth exploring | ❌ 复核关闭 |
| F-122 | chat.py 本就是编排 seam，两处回合末副作用触发器各有独立领域语义，仅 2 实例抽象「触发器」收益 < 成本（Speculative Generality 反面），暂可接受 | mod-cg-wiring 期末四轴 Architecture | Worth exploring | ❌ 复核关闭 |

## 技术债处置记录

> 按处置日期分节，滚动保留最近 2 节；更早的节由 git 历史归档（`git log -p -- TECH_DEBT.md`）。

### 2026-09-14（技术债消费批次 ×2：批1 F-115~F-122 3 做 5 关轻量档；批2 F-123~F-126 架构深化全做标准档 4 工单串行）

> 来源：用户指令「消费」+ userselect F-115~F-122。逐项 git grep 复核现状后拍板 3 做 5 关（全 Speculative/Worth exploring，成本收益显式权衡）。处置后候选区清零。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-117 | `mod-css.js::collectCssPayloads` 空串 payload 产生游离 `\n`（与后端 `_memory_mod_instructions` 语义不一致） | mod-cg-wiring 期末四轴 Falsify | Speculative | ✅ 已修（2026-09-14：`.map(payload)` 后加 `.filter((p) => p.trim() !== '')` 跳过空串；防复发断言——多 Mod 拼接测试加空串 payload 锁定 textContent 无游离换行） |
| F-119 | `database.py::_ensure_cg_images_weight` 用 `hasattr(bind, "connect")` 脆弱 duck-type 区分 Engine/Connection | mod-cg-wiring 期末四轴 Falsify | Speculative | ✅ 已修（2026-09-14：改 `isinstance(bind, Engine)` + `from sqlalchemy import Engine`；test_gallery 45 用例锁定两路径行为不变） |
| F-120 | `cg-review.js::handleCgGalleryClick` `Number(tile?.dataset.cgId)` 在 actionEl 脱离 `.cg-tile` 时得 `NaN` 静默 no-op | mod-cg-wiring 期末四轴 Falsify | Speculative | ✅ 已修（2026-09-14：加 `Number.isNaN(cgId)||Number.isNaN(characterId)` 守卫 early return） |
| F-115 | `images.py::list_cg` 路由暴露 `group_name`/`unlocked_only` 查询参数（spec 未定义、前端未消费） | mod-cg-wiring 期末四轴 Spec/Standards | Speculative | ❌ 复核关闭（透传 gallery.list_cg 既有过滤参数非无中生有；画廊分组过滤可预见需求，删除反而未来返工） |
| F-116 | 锁定 CG 的 `url` 仍含于 list 响应体 | mod-cg-wiring 期末四轴 Falsify | Speculative | ❌ 复核关闭（spec 设计使然——list 全量含未解锁；锁定=软 UX 门非机密边界，前端渲染层已正确不加载锁定原图） |
| F-118 | `reconcileCharacterCss` 把合法空态也置 null 击穿去重守卫（流式重复拉取低效） | mod-cg-wiring 期末四轴 Falsify | Speculative | ❌ 复核关闭（`applyCharacterCss` false 无法区分「无 css Mod 空态」vs「取数失败」，修复需改返回契约牵动 17 用例，实际开销可忽略——成本收益不成比例） |
| F-121 | 候选池过滤内联 chat.py（加权候选池概念拆两模块） | mod-cg-wiring 期末四轴 Architecture | Worth exploring | ❌ 复核关闭（回合末一次性触发语义 ≠ gallery.list_cg 展示过滤；下沉只增被 chat.py 独调的窄函数 Leverage 低，spec 已划 chat.py 为触发编排落点） |
| F-122 | chat.py 持续膨胀，两处回合末副作用触发器并列（Repeated Switches 雏形） | mod-cg-wiring 期末四轴 Architecture | Worth exploring | ❌ 复核关闭（chat.py 本就是编排 seam，两触发器各有独立领域语义，仅 2 实例抽象「触发器」收益 < 成本） |
| F-123 | Mod 区过滤读取 Repeated Switch | 架构报告 2026-09-14 | Strong | ✅ 已修（2026-09-14：工单 T1 `list_enabled_mods_for_area` 下沉 mods.py 单一 seam，chat.py 两调用点改指，`Mod.id.in_` 0 / 覆盖率 97.79%，commit a016d7c） |
| F-124 | 候选追加「持久化仪式」重复 + 不变量泄漏 | 架构报告 2026-09-14 | Strong | ✅ 已修（2026-09-14：工单 T2 `append_swipe_and_bump` 收口 message.py 单一入口，`updated_at=datetime` 0 / 覆盖率 96.11%，commit 49d342c） |
| F-125 | 自愈迁移原语 Repeated Switch | 架构报告 2026-09-14 | Worth exploring | ✅ 已修（2026-09-14：工单 T4 `_ensure_column` 通用原语 + 三 wrapper 退化为声明，`ALTER TABLE` 1 / `PRAGMA table_info` 1，commit 19868f2） |
| F-126 | generate+LLM 错误映射接线重复 | 架构报告 2026-09-14 | Speculative | ✅ 已修（2026-09-14：工单 T3 私有 `_generate_with_error_mapping` 三调用点复用，stream_reply 刻意排除，`except LLMError` 2，commit 114aae6） |

### 2026-09-13（技术债消费批次 ×2：批1 F-99/F-100/F-102/F-103/F-106 做 + F-101/F-104/F-105 关 + F-100 能力3 关，标准档 7 工单 3 波；批2 F-110 做 + F-109/F-111 关，轻量档 1 工单）

> 批 1 处置详情：5 项消费（F-99→工单01、F-100 能力1/2→工单06/07、F-102→工单03/04、F-103→工单02、F-106→工单05，见 DEV_LOG〈技术债候选区消费批次〉）；3 项复核关闭——F-101 全路径不产 NULL 理论性 500 不可达、F-104 提取共享 helper 收益 < 成本、F-105 轻重两种守卫是不同 seam 非缺陷；另 F-100 能力 3「模拟器存档开新对话」部分关闭（存档=游戏 localStorage 状态 ≠ BranchSnapshot 对话快照，不同构，语义不清）。期末四轴 0 HIGH 阻断 + 1 MEDIUM 当场修（ddfe978：branch_title 契约断裂——分支调用补传源会话标题，能力 2「父缺失回落 branch_title」恢复生效）+ 非阻断落债 F-109~F-111 / 复核关闭 F-112~F-114。
>
> 批 2 处置详情：Grilling 实证拍板 1 做 2 关——F-110 三函数样板逐行比对成立（守卫前奏/finally 复原逐字相同、差异仅按钮 selector 与错误文案），提取 chat.js 私有 helper `runLastAssistantAction({buttonSelector, errorLabel, isActive, prepare, action})`（对齐 setChatHooks options-object 先例，handleSend 明确排除），行为保持重构由全量 Vitest 1311 锚定 + grep 收敛 4→2 机械证据，见 DEV_LOG〈技术债候选区消费批次 F-109~F-111〉；F-109/F-111 复核关闭理由见复核关闭表。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-99 | LLM 适配器多 system 折叠（last system wins 丢弃 persona/scenario/世界书 system 块） | MS-3 期末四轴 | Strong | ✅ 已修（2026-09-13：工单01 `_prepare_messages` 全量合并——按序 \n\n 连接 + 空/空白过滤 + 无 system None，test_llm_shared「取末条」契约修订为「合并」，base.py 覆盖率 100%） |
| F-100 | spec §BR-2 前端段未消费（消息级分支 + 列表来源标记 + 存档开新对话） | BR-2 期末四轴 | Worth exploring | ✅ 已修（2026-09-13：能力 1 工单06 末条气泡分支按钮创建即打开 + 能力 2 工单07 ConversationResponse 扩分支字段 + 锚预览 + 卡片标记；能力 3 复核关闭——存档≠对话快照语义不清） |
| F-101 | ModResponse 非可选 str/datetime 映射可空 DB 列（理论性 500） | MD-2 波 1 增量审核 Falsify | Speculative | ❌ 复核关闭（2026-09-13：create_mod/update_mod 全路径经 Schema 默认值落库不产 NULL，理论性不可达） |
| F-102 | 排序交换非原子（两次 setSortOrder 中间态重复 sort_order） | MD-2 期末四轴 Falsify | Worth exploring | ✅ 已修（2026-09-13：工单03 `reorder_character_mods` 单事务原子端点（空列表 400/归属不符 404）+ 工单04 前端单次 reorder + computeSortSwap 改产完整新序数组，setSortOrder 前端退役） |
| F-103 | mod-manager.js 混责（UI + 8 codec 纯函数同室） | MD-2 期末四轴 Architecture | Worth exploring | ✅ 已修（2026-09-13：工单02 提取 mod-codec.js 深模块（js 根，零 DOM），8 函数字节等价 9/9 零行为变化证明） |
| F-104 | 客户端 Blob 下载逻辑第三份拷贝 | MD-2 期末四轴 Standards | Speculative | ❌ 复核关闭（2026-09-13：两处轻度重复，提取共享 helper 收益 < 成本） |
| F-105 | 角色存在性守卫两处两种实现（轻 vs 重） | MD-2 期末四轴 Standards/Architecture | Speculative | ❌ 复核关闭（2026-09-13：轻量 Character.id 查询与重载会话计数是不同 seam，非缺陷） |
| F-106 | 导入信封数组类型漏校验（mods:[[]] 建空名 Mod） | MD-2 期末四轴 Falsify | Speculative | ✅ 已修（2026-09-13：工单05 importModsFromEnvelope 补 Array.isArray 拒绝 + 「数组拒绝/合法导入」两臂契约锁，红灯证明测试灵敏） |
| F-110 | 发送类动作进行中态样板第 4 次复制（chat.js branchLastReply 复制 handleSend/regenerateLastReply/continueLastReply 的 ~20 行 nonStreamingInFlight + 按钮禁用 + thinking 样板） | 技术债批次期末四轴 Architecture | Worth exploring | ✅ 已修（2026-09-13：批 2 工单 F-110 提取 chat.js 私有 `runLastAssistantAction` options-object helper（prepare 可中止 + finally 统一复原含 isConnected 兜底），三函数收缩为 prepare+action 闭包、handleSend 排除；grep 4→2，Vitest 1311 断言零修改全绿） |

### 2026-09-10（技术债消费批次：F-93 + F-94 + F-95 + F-96（做）+ F-97（关）+ F-98（做），轻量档 6 项）

> 处置详情：3 项消费（各对应 TICKETS 归档工单）。Grilling 实证拍板**全做**——F-93 git grep 复核 `lorebook._as_str_list` 与 `character_card._as_list` 逐行重复仍成立（character_card 2 处 + lorebook 1 处消费）；F-94 `chat._msg_role` 与 `prompt._role_str` 的 `hasattr(.value)` 枚举归一重复（chat.py:535 / prompt.py:103）；F-95 `build_message_list` 生产调用方仅 chat.py 两处（assemble_chat_context），加可选 history 参数即可消除扫描窗 + 内部双查。方案：新建 `services/text_utils.py` 共享单点（as_str_list + role_str）收敛 F-93/F-94；F-95 build_message_list 增 `history: Sequence | None`（None → 内部查询，既有调用不变）。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-93 | lorebook._as_str_list 与 character_card._as_list 逐行重复 | WL-1 期末 code-review Standards 轴 | Worth exploring | ✅ 已修（2026-09-10：轻量档工单 `text_utils.as_str_list` 共享单点收敛——character_card / lorebook 改指 + 删私有函数，pytest 873→879 全绿零回归、doc_sync 零漂移） |
| F-94 | chat._msg_role 与 prompt._role_str 枚举归一重复 | WL-3 期末 code-review Standards 轴 | Worth exploring | ✅ 已修（2026-09-10：轻量档工单 `text_utils.role_str` 收敛——prompt/chat 改指 + 删私有函数，pytest 891→896 全绿零回归） |
| F-95 | assemble_chat_context 扫描窗 + build_message_list 双查历史 | WL-3 期末 code-review Standards 轴 | Speculative | ✅ 已修（2026-09-10：轻量档工单 `build_message_list` 增可选 history 参数，assemble 传入已取历史消除双查；显式传 history 不再查库由契约锁锁定） |
| F-96 | escapeHtml 不转义引号——属性上下文插值（value="..."/data-*="..."）含 " 时可属性注入（WL-4 lorebook-editor 曾局部 escapeAttr，其余组件同类） | WL-4 期末 code-review Falsify 轴（stored XSS 实证） | Worth exploring | ✅ 已修（2026-09-10：轻量档工单升级共享 `escapeHtml` 同时转义 " → &quot;（15 处属性插值一处收敛），lorebook-editor escapeAttr 退役；markdown sanitizeUrl 补实体引号形态拒绝（&quot;/&#34;/&#x22/，保 TD-42「引号 URL → 纯文本」契约）；契约锁 escapeHtml 引号转义 + DOM 往返 + 无注入属性，Vitest 1211→1212） |
| F-97 | 记忆宫殿开关为全局 settings 而非会话级 | WL-5 期末 code-review Spec 轴 | Worth exploring | ❌ 复核关闭（2026-09-10：注入链 `_lorebook_world_injection` → `list_entries(character_id)` 取角色全部启用条目（含 source=auto），无会话维度过滤——auto 条目对角色所有会话注入；「会话级开关」要生效须结构性变更（注入链按会话过滤或 auto 条目改挂会话），与「记忆归角色跨会话共享」产品语义冲突且改动面大；现状全局开关与角色级注入架构自洽，spec 存储位置二选一（settings 已实现）已满足） |
| F-98 | delete_messages_from 生产退役 | MS-1 期末 code-review Standards 轴 | Speculative | ✅ 已修（2026-09-10：轻量档工单删除——无生产调用方、语义被 MS-1 add_swipe/regenerate 新流程取代，保留即误导（截断语义与 swipes 冲突）；删函数 + __all__ + 模块 docstring + test_regenerate §2 三用例，pytest 925→922 全绿零回归） |

---

## 处置记录说明

- 候选区只保留开放条目（📝 待立项 / 🔄 进行中），处置后条目移入「技术债处置记录」按日期分节。
- ❌ 复核关闭的 Speculative 类条目在候选区「复核关闭」表中保留单行压缩摘要防重复提议（Worth exploring 类关闭理由完整保留于处置记录）。
- 处置记录滚动保留最近 2 节；更早的归档由 git 历史承担（`git log -p -- TECH_DEBT.md`）。
- 新条目从最大编号 +1 递增（当前最大 F-129），避免编号冲突。