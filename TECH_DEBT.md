# TECH_DEBT: conver system

> **技术债候选池**（未立项子集）与**处置记录**。本文件与 `TO-TICKETS.md`（任务池，本项目任务文件名为 `TO-TICKETS.md` 而非 `TO-TICKETS.md`）分离——候选不等于任务，不自动进入任何 session 的 preflight 认领；消费 = 显式「立项」（从候选区取出 → 转入 `TO-TICKETS.md` 活跃工单，或标记 ❌ 不立项附理由）。
> 读取契约与强度消费规则见 project-kickoff 步骤 0 预检（`AGENTS.md` §3 任务清单生命周期）。
>
> 本文件由 `TO-TICKETS.md` 技术债区独立化迁移而来（2026-08-24，对齐 AGENTS.md §3 规范），原文完整保留审计追溯。

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
5. **机械约束**由 `scripts/pool_cleanup_check.py --check --tickets-file TO-TICKETS.md` 强制（任务池本库名为 `TO-TICKETS.md`）：候选区无 ✅/❌ 滞留、复核关闭表全 ❌、活跃工单无 ✅/❌、重复标题、脚注「当前最大 F-N」与全库最大编号一致、非空与必要节、表格列数异常报格式问题；本库沿用既有 `scripts/install-hooks.bat`（doc_sync 检查），清出检查建议并入同一 pre-commit（2026-08-31 起，脚本已就位）

### 多 session 防污染

1. **任务所有权分离**：`TO-TICKETS.md` 是唯一任务池（preflight 只读它）；本文件是候选池（只写不认领）
2. **条目归属标注**：每条目必填「来源」与「归属方向」，session 只认领自己方向匹配的条目
3. **消费显式化**：从候选区转工单必须带一句话理由（强度 + 方向匹配），禁止静默批量认领
4. **写冲突隔离**：候选人落盘写本文件（评审 session 独占），任务状态变更写 `TO-TICKETS.md`（认领 session 独占），不同 session 写不同文件，不互踩

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
| F-149 | prompt.py:232 `_assemble` 9 位置参数 + 8 线性 if 注入点——`_build_tagged_injection` seam 归位后参数打包重估留待上游 seam 稳定，Grilling 拍板本批暂不拆单 | arch-deepening Grilling 增量审 | Worth exploring | ❌ 复核关闭 |
| F-150 | prompt.py:146 `build_messages` 与 `build_messages_with_source` 九参数签名逐字重复——与 F-149 同批判据（seam 归位后重估） | arch-deepening Grilling 增量审 | Worth exploring | ❌ 复核关闭 |
| F-151 | character_card.py:273 与 character-submit.js:187 preset_dialogue 归一化双端镜像——双端已各自锚定 + 注释互指，跨运行时单一权威不可表达 | arch-deepening Grilling 增量审 | Speculative | ❌ 复核关闭 |
| F-155 | chat.py:918-923 世界书注入 logger.debug 可观测性扩展（seam 归位后 build_prompt_debug 路径也输出同文案 debug 日志）——开发级日志非在线 prompt 契约，spec「输出逐字节不变」不覆盖，无 spec 追认载体 | arch-deepening 期末四轴 Spec | Speculative | ❌ 复核关闭 |

## 技术债处置记录

> 按处置日期分节，滚动保留最近 2 节；更早的节由 git 历史归档（`git log -p -- TECH_DEBT.md`）。

### 2026-09-22（技术债消费批次 F-156~F-157，2 做 0 关，主会话直做）

> 来源：用户「折回消费」userselect 全选 F-156/F-157。逐项 git grep 复核现状后 2 做 0 关。code-review 四轴通过（0 阻断）。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-157 | CharacterUpdate 其余 list/dict 字段（tags/alternate_greetings/creator_notes/extensions）显式 null → NULL 写库 → 响应序列化 500 同类缺口 | 打包 2026-09-21 修复 Falsify 快审 | Speculative | ✅ 已修（2026-09-22：CharacterBase 统一 mode=before 验证器 `_coerce_none_to_json_default` None→默认形态，create/update/response 三态契约锁定 test_character_schema.py +3 用例；commit 98a04af） |
| F-156 | `Assert-Or-Build-BackendExe` 只认缺失不认过期——后端 exe 早于源码被静默复用 | 打包新程序 2026-09-21 | Worth exploring | ✅ 已修（2026-09-22：Get-ConverBackendRebuildInputs/Test-ConverBackendExeIsCurrent 过期检测，四象限 缺失补/过期重建/-Skip 缺失报错/过期告警放行；逻辑四场景脚本化验证 + 冒烟 happy path；commit 5ba98df） |

**验证链：** pytest 1356+1skip→1359+1skip（+3 契约锁零回归）+ doc_sync 零漂移 + pool_cleanup_check 全合规 | code-review 四轴 0 阻断（2 🟡 当场收口：create-null 契约锁定 + 重复构建块收敛）| 候选区 2→0 清零。

### 2026-09-15（架构深化批次 arch-deepening + 技术债消费 F-152~F-155 两批次）

> 批 1 来源：用户指令继架构全库扫描（F-145~F-151 落盘）后走 project-kickoff 全自动档消费。Grilling 增量审拍板 4 做 3 关。4 做 = 2 工单标准档串行链（工单 01 注入链 seam 归位 = F-145+F-146；工单 02 组装入口收口 = F-147+F-148），纯重构在线 prompt 输出逐字节不变。
>
> 批 2 来源：用户指令「消费候选区技术债」（F-152~F-155）。逐项 git grep 复核现状后拍板 3 做 1 关，轻量档主会话直做（补契约锁 + 文档注记，零行为变更）。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-145 | chat.py 注入链编排两处逐字复制（assemble_chat_context 与 build_prompt_debug） | 架构报告 | Strong | ✅ 已修（2026-09-15：工单 01 `chat._build_tagged_injection` 单一编排 seam 收编三步，两调用点改指；commit ab587ed） |
| F-146 | lorebook_engine.build_world_injection 孤儿 + position 映射三处复制 | 架构报告 | Strong | ✅ 已修（2026-09-15：工单 01 回并 `build_world_injection` 返回 `dict[str, list[InjectedSegment]]` + 新增 `source_by_id` 可选形参，删 chat._build_tagged_world_injection / _WORLD_POSITION_KEYS；commit ab587ed） |
| F-147 | ORM Character→CharacterData 投影两处逐字重复 | 架构报告 | Strong | ✅ 已修（2026-09-15：工单 02 `CharacterData.from_orm` 唯一投影入口（None→空角色），删 chat._character_data + message 内联构造；commit a807363） |
| F-148 | build_message_list 隐式读 ORM 快照 vs narrative_style 显式透传不对称 | 架构报告 | Worth exploring | ✅ 已修（2026-09-15：工单 02 `build_message_list` 增 `preset_dialogue: str = ""` 显式形参，快照读取责任上移 chat 层统一；commit a807363） |
| F-149 | prompt.py `_assemble` 9 位置参数 + 8 线性 if 注入点 | 架构报告 | Worth exploring | ❌ 复核关闭（`_build_tagged_injection` seam 归位后参数打包重估留待上游 seam 稳定，Grilling 拍板本批不拆单） |
| F-150 | prompt.py `build_messages` 双签名逐字重复 | 架构报告 | Worth exploring | ❌ 复核关闭（与 F-149 同批判据——seam 归位后重估） |
| F-151 | preset_dialogue 归一化前后端双份镜像 | 架构报告 | Speculative | ❌ 复核关闭（双端已各自锚定 + 注释互指，跨运行时单一权威不可表达） |
| F-152 | build_world_injection 空激活集与 source_by_id 未知值无直接单测断言 | arch-deepening 期末四轴 Falsify | Speculative | ✅ 已修（2026-09-15：test_lorebook_engine.py 补 test_build_world_injection_empty_activated（三空键）+ test_build_world_injection_source_by_id_unknown_value（回落 SOURCE_WORLD）两契约锁） |
| F-153 | build_message_list preset_dialogue 无 None 直传防护契约锁 | arch-deepening 期末四轴 Falsify | Speculative | ✅ 已修（2026-09-15：test_preset_dialogue_injection.py 补 test_none_preset_zero_injection——None falsy 短路零注入，与空串/纯空白同语义） |
| F-154 | CharacterData.from_orm 签名 object/None 与 spec 字面不一致 | arch-deepening 期末四轴 Spec | Worth exploring | ✅ 已修（2026-09-15：from_orm docstring 注记「object 而非 Character 有意保持 prompt.py 零 ORM 依赖，勿改回」，防未来误改破坏纯函数层契约） |
| F-155 | 世界书注入 logger.debug 可观测性扩展待 spec 追认 | arch-deepening 期末四轴 Spec | Speculative | ❌ 复核关闭（开发级 debug 日志非在线 prompt 契约，spec「输出逐字节不变」不覆盖，无追认载体；本批证据文件与 DEV_LOG 已记录） |

**验证链（批 1）：** pytest 1349+1skip→1352+1skip（+3 用例）+ cargo 70 零改动 | 期末四轴「通过」0 阻断（Standards 0 / Spec 2 警告 / Falsify 3 弱覆盖缺口 / Architecture 0，两 seam 均真深化无伪深化）| 运行态冒烟 segments 全序正确 | 全量 1352 passed 独立复现 | commit ab587ed + a807363 + merge 43bb61f。
**验证链（批 2）：** pytest 1352+1skip→1355+1skip（+3 契约锁：空激活集/未知 source 值/None 直传）+ 受影响模块 44 passed | doc_sync + pool_cleanup_check 全合规 | 候选区清零。

## 处置记录说明

- 候选区只保留开放条目（📝 待立项 / 🔄 进行中），处置后条目移入「技术债处置记录」按日期分节。
- ❌ 复核关闭的 Speculative 类条目在候选区「复核关闭」表中保留单行压缩摘要防重复提议（Worth exploring 类关闭理由完整保留于处置记录）。
- 处置记录滚动保留最近 2 节；更早的归档由 git 历史承担（`git log -p -- TECH_DEBT.md`）。
- 新条目从最大编号 +1 递增（当前最大 F-157），避免编号冲突。