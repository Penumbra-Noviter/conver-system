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


### 复核关闭（Speculative 类，防重复提议）

| 编号 | 遗留项（压缩摘要） | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| F-97 | 记忆宫殿会话级开关细化（全局开关与角色级条目注入架构自洽，会话级需结构性变更） | WL-5 期末 code-review Spec 轴 | Worth exploring | ❌ 复核关闭 |
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
| F-128 | `append_swipe_and_bump` 冗余重取——`add_swipe(commit=False)` 后 msg 未 expire，`_require_message` 命中 identity map 不再发 SQL；剩余「再取一次」是 append 需 msg.conversation_id 而 add_swipe 返回 next_index 的合理结构（非冗余开销） | arch-f123-126 期末四轴 Architecture | Speculative | ❌ 复核关闭 |
| F-133 | editMessage/deleteMessage 角色判定取自 tab.messages 乐观缓存——与 regenerate/continue/branch 同源的既有乐观 UI 模式，服务端 404 兜底，二次确认文案错述非破坏性（用户可取消） | 消息编辑重发期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-136 | `_resolve_edit_target`/`_resolve_continue_target`/`_resolve_regenerate_target` 三解析函数独立领域语义（edit=user / continue=末条 assistant / regenerate=assistant+缺省末条），仅 3 实例抽象「目标解析器」收益 < 成本（Speculative Generality 反面） | 消息编辑重发期末四轴 Architecture | Speculative | ❌ 复核关闭 |
| F-140 | character-wizard.js 备用开场白删除 indexOf(row) 后 splice(idx,1)——row 经 `btn.closest('.alt-greeting-row')` 定位且事件委托在 altList 上，row 必在 DOM 内，indexOf 不可能 -1（单线程无并发），不可达缺陷 | PD 批次波 2 增量审核 Falsify | Speculative | ❌ 复核关闭 |
| F-142 | CharacterBase.prompt_mode 用 str 未用 Literal——build_messages 仅 `== "expert"` 走 expert 分支、其余任意值运行时安全回退 simple，改 Literal 需破坏 CharacterBase 单一来源或冒 CharacterResponse 序列化风险，纵深防御收益 < 成本 | PD 批次期末四轴 Standards | Speculative | ❌ 复核关闭 |
| F-143 | chat._character_data 与 message.build_message_list 的 CharacterData 构造逐字镜像——有意识设计（`_character_data` docstring 已声明「同口径单一语义镜像」），仅 2 实例提取 helper 收益 < 成本 | PD 批次期末四轴 Architecture | Speculative | ❌ 复核关闭 |
| F-144 | character-wizard.js `state.splice` 直接变异 vs character-form.js 以 DOM 为真源——wizard 的 state 是跨步骤向导真源（增删须同步 state 供后续步骤读）、form 的 DOM 是单表单提交时读的真源，语境不同，强行统一收益 < 成本 | PD 批次期末四轴 Architecture | Speculative | ❌ 复核关闭 |

## 技术债处置记录

> 按处置日期分节，滚动保留最近 2 节；更早的节由 git 历史归档（`git log -p -- TECH_DEBT.md`）。

### 2026-09-14（技术债消费批次 ×4：批1 F-115~F-122 3 做 5 关轻量档；批2 F-123~F-126 架构深化全做标准档 4 工单串行；批3 F-130~F-138 7 做 2 关轻量档主会话直做；批4 F-139~F-144 1 做 4 关轻量档主会话直做）

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
| F-127 | `append_swipe_and_bump` 两段提交非原子 | arch-f123-126 期末四轴 Falsify/Architecture | Worth exploring | ✅ 已修（2026-09-14：add_swipe 加 `commit=False` 参数 + append 单 commit 原子落库，防复发断言 test_append_swipe_and_bump_single_commit_atomic） |
| F-128 | `append_swipe_and_bump` 冗余重取 | arch-f123-126 期末四轴 Architecture | Speculative | ❌ 复核关闭（commit=False 后 msg 未 expire，_require_message 命中 identity map 不发 SQL；剩余再取一次是 append 需 conversation_id 而 add_swipe 返回 index 的合理结构） |
| F-129 | `_ensure_conversation_branch_columns` 三连接/三 commit | arch-f123-126 期末四轴 Architecture | Speculative | ✅ 已修（2026-09-14：Engine 形态单连接循环补三列，Connection 形态直接循环） |
| F-130 | `require_message` 零行为透传别名 + 目标解析知识散布（路由 require_message → _resolve_edit_target 再查 → update_message 三查同消息冗余） | 消息编辑重发期末四轴 Standards/Architecture/Spec | Worth exploring | ✅ 已修（2026-09-14：edit_and_resend 去 conversation_id 参数、_resolve_edit_target 简化只传 message_id 派生 conversation_id、删 require_message 公开别名 + 路由直调，目标解析知识收口单一入口） |
| F-131 | 级联删除 Seam 依赖全局 PRAGMA + `synchronize_session=False` bulk delete 后 identity map 残留被删对象 | 消息编辑重发期末四轴 Architecture/Falsify | Worth exploring | ✅ 已修（2026-09-14：delete_message/edit_and_resend 两处 bulk delete 改 `synchronize_session="fetch"` 消除身份映射残留 + 防复发断言 test_delete_user_syncs_identity_map；PRAGMA 依赖文档化为 SQLite 连接级固有，非模块可局部化） |
| F-132 | 消息操作按钮 css 悬停显示不统一（copy hover 显示，regen/cont/branch/edit/delete 常驻） | 工单 03 期末 concern + 期末四轴观察 | Worth exploring | ✅ 已修（2026-09-14：style.css 操作按钮组加 opacity 0→hover 0.6→自身 1 统一 hover 显示 + 图标按钮样式对齐 copy） |
| F-133 | editMessage/deleteMessage 角色判定取自 tab.messages 乐观缓存，漂移时二次确认文案错述破坏范围 | 消息编辑重发期末四轴 Falsify | Speculative | ❌ 复核关闭（乐观 UI 既有模式——与 regenerate/continue/branch 同源读 tab 缓存；服务端 404 兜底，二次确认文案错述非破坏性（用户可取消）） |
| F-134 | autoflush 分歧——conftest db_session 默认 autoflush=True vs 生产 SessionLocal autoflush=False | 消息编辑重发期末四轴 Falsify | Speculative | ✅ 已修（2026-09-14：conftest sessionmaker 加 autoflush=False 对齐生产，测试复现生产 flush 时序） |
| F-135 | promptMessageEdit 与 promptImageDescription 同型重复 | 消息编辑重发期末四轴 Architecture + 工单 03 concern | Speculative | ✅ 已修（2026-09-14：提取 chat.js 私有 promptTextarea helper 收敛两同型函数，DOM id/行为逐字保持） |
| F-136 | `_resolve_edit_target` 与 `_resolve_continue_target`/regenerate 解析构成平行家族萌芽 | 消息编辑重发期末四轴 Architecture | Speculative | ❌ 复核关闭（三解析函数独立领域语义——edit=user / continue=末条 assistant / regenerate=assistant+缺省末条，仅 3 实例抽象「目标解析器」收益 < 成本） |
| F-137 | `EditMessageRequest.content` 仅 min_length=1，全空白字符串穿过校验送生成 | 消息编辑重发期末四轴 Falsify（观察） | Speculative | ✅ 已修（2026-09-14：加 field_validator strip 后拒绝全空白 + 防复发断言 test_edit_blank_content_422） |
| F-138 | error_mapping.py 400 分支 isinstance 元组行膨胀（~180 字符） | 消息编辑重发期末四轴 Standards | Speculative | ✅ 已修（2026-09-14：提取模块常量 `_HTTP_400_DOMAIN_ERRORS` 多行元组，400 分支改指常量） |
| F-141 | build_prompt_debug character=None 时 character.prompt_mode AttributeError | PD 批次期末四轴 Falsify | Worth exploring | ❌ 复核关闭（误报：_character_data 用 getattr 默认值返回空 CharacterData + character_name/prompt_mode 均有 if-else 守卫 + _lorebook_world_injection/_mod_prompt_injection None 时返回空注入，None 路径已完整覆盖） |
| F-139 | CharacterUpdate.prompt_mode/expert_prompt Optional[str]=None 但 ORM 列 nullable=False，显式 null 触发 IntegrityError(500) | PD 批次波 1 增量审核 Falsify | Speculative | ✅ 已修（2026-09-14：CharacterUpdate 加 field_validator 拒绝 name/prompt_mode/expert_prompt 显式 null，防复发断言 test_update_rejects_null_for_not_null_columns 三字段 422；附带修复 name 同构缺口） |
| F-140 | character-wizard.js 备用开场白删除 indexOf(row) 后 splice(idx,1)，idx 可能 -1 误删末项 | PD 批次波 2 增量审核 Falsify | Speculative | ❌ 复核关闭（row 经 btn.closest 定位且事件委托在 altList 上，row 必在 DOM 内，indexOf 不可能 -1，单线程无并发，不可达） |
| F-142 | CharacterBase.prompt_mode 用 str 未用 Literal 枚举 | PD 批次期末四轴 Standards | Speculative | ❌ 复核关闭（build_messages 仅 ==expert 走 expert 分支、其余任意值安全回退 simple，改 Literal 需破坏 CharacterBase 单一来源或冒响应序列化风险，纵深防御收益 < 成本） |
| F-143 | chat._character_data 与 message.build_message_list CharacterData 构造逐字镜像 | PD 批次期末四轴 Architecture | Speculative | ❌ 复核关闭（有意识镜像——_character_data docstring 已声明同口径单一语义镜像，仅 2 实例提取 helper 收益 < 成本） |
| F-144 | character-wizard.js state.splice vs character-form.js DOM 真源两套模式 | PD 批次期末四轴 Architecture | Speculative | ❌ 复核关闭（wizard state 是跨步骤向导真源、form DOM 是单表单真源，语境不同，强行统一收益 < 成本） |

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

---

## 处置记录说明

- 候选区只保留开放条目（📝 待立项 / 🔄 进行中），处置后条目移入「技术债处置记录」按日期分节。
- ❌ 复核关闭的 Speculative 类条目在候选区「复核关闭」表中保留单行压缩摘要防重复提议（Worth exploring 类关闭理由完整保留于处置记录）。
- 处置记录滚动保留最近 2 节；更早的归档由 git 历史承担（`git log -p -- TECH_DEBT.md`）。
- 新条目从最大编号 +1 递增（当前最大 F-144），避免编号冲突。