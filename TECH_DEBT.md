# TECH_DEBT: conver system mobile

> **技术债候选池**（未立项子集）与**处置记录**。本文件与 [TO-TICKETS.md](TO-TICKETS.md)（任务池）分离——候选不等于任务，不自动进入任何 session 的 preflight 认领；消费 = 显式「立项」（从候选区取出 → 转入 `TO-TICKETS.md` 活跃工单，或标记 ❌ 不立项附理由）。
> 读取契约与强度消费规则见 [AGENTS.md](AGENTS.md) §3 任务清单生命周期（项目级，与桌面库同构）。

---

## 规范说明

### 条目格式

候选区每行对应一条技术债，含 6 个字段：

| 字段 | 含义 |
|------|------|
| **编号** | `F-N` 递增唯一（与桌面库编号体系独立，本库从 F-1 起） |
| **遗留项** | 什么问题、在哪个文件、当前影响 |
| **来源** | 产生此条目的审核/讨论/评审 |
| **强度** | `Strong` / `Worth exploring` / `Speculative`（见下方消费规则） |
| **状态** | `📝 待立项` / `🔄 进行中` / `✅ 已修` / `❌ 复核关闭` |
| **归属方向** | 业务方向（如 `聊天链路` / `模拟器桥` / `数据层`），session 只认领匹配方向的条目 |

### 强度消费规则

| 强度 | 消费规则 |
|------|----------|
| **Strong** | 必入工单清单（下一轮 kickoff 的 plan-tickets 必须包含） |
| **Worth exploring** | 入候选由 Grilling 拍板（做/关闭），无默认方向 |
| **Speculative** | 可关闭，关闭须「`git grep` 复核现状仍成立」一句话理由 |

### 清出机制（防膨胀）

1. 候选区只留开放条目（📝 待立项 / 🔄 进行中）；条目处置后整行移出候选区，处置详情写入「技术债处置记录」。
2. ❌ 关闭条目压缩：具复核价值的关闭项保留单行摘要于「复核关闭」表（滚动保留最近 4 批关闭批次，按关闭日期计同日合并一批），更早批次整批删除。
3. 处置记录按日期分节，滚动保留最近 2 节；更早节整体删除（归档由 git 历史承担）。
4. **候选区 0 项时正文只留标题 + 空表格，不写任何「当前 0 项待立项 / 历史消费罗列」叙述**——处置事实由「技术债处置记录」与 git 历史承担（2026-09-07 用户拍板，防清空后残留历史罗列）。
5. 清出动作绑定会话末 commit 前节点执行，不新增仪式。
6. **机械约束**由 `scripts/pool_cleanup_check.py --check --tickets-file TO-TICKETS.md --candidate-section "## 候选区"` 强制（挂 pre-commit，失败拒提交）——本库候选区节名非标准（`候选区`）且无「维护说明」footer 锚点，脚本按节名参数与「无 footer 节则不检查」自适应：候选区无 ✅/❌ 滞留、活跃工单无 ✅/❌、重复标题、非空与必要节、表格列数异常报格式问题；安装 `sh scripts/install-pre-commit.sh`（每 clone 一次，本库安装脚本按上述参数定制）。

---

## 候选区

| 编号 | 遗留项 | 来源 | 强度 | 状态 | 归属方向 |
|------|--------|------|------|------|----------|
| F-146 | `chat_controller._loadSwipeCounts`（chat_controller.dart:1085-1099）仍是逐消息 `listSwipes` N+1——`listSwipesBatch` 原语（F-142）已有 branch/export 两消费方，「第三处出现即复用」惯例未兑现；控制面 docstring（:188-193）保留原语存在前的让步注释 | 架构报告 2026-09-21 C1 | Strong | 📝 待立项 | 聊天链路 |
| F-147 | 采样温度解析链双实现：`chat_service.dart:1913-1926` 与 `memory_palace_service.dart:358-372` 逐字重复「角色为主/全局兜底 + NaN 回退 + clamp」（F-76 NaN 防线被复制），各带整套防御测试 | 架构报告 2026-09-21 C2 | Strong | 📝 待立项 | 聊天链路 |
| F-148 | 回合末三服务（reflection:194-200 / proactive:460-469 / memory_palace:329-351）各自重建「最近对话窗口」：全量 getMessages → sublist(20) → 署名行，窗口常量 20 三处、署名格式三套微差，每回合 ×3 全量读 | 架构报告 2026-09-21 C3 | Strong | 📝 待立项 | 数据层 |
| F-149 | ChatService 组装上溯上下文双份维护：`_assembleMessages`（:1606-1683）与 `promptDebug`（:1771-1839）各自重建 CharacterData 投影/历史/世界书/叙述风格；promptDebug 不含 memory/stage2 注入——生产开启记忆后「逐条一致」契约不成立（测试仅在 memoryService 缺省时通过） | 架构报告 2026-09-21 C4 | Strong | 📝 待立项 | 聊天链路 |
| F-150 | `RelationshipService.activeDays`（relationship_service.dart:307-316 + _allMessagesFor:369-380 全量拉取）生产零调用方（回合增量早改 isRecentlyActive，F-81 收口）；deletion test 通过；删除需 ADR-0006「活跃口径」是否 UI 展示的先决确认 | 架构报告 2026-09-21 C5 | Worth exploring | 📝 待立项 | 聊天链路 |
| F-151 | 主动消息「过期核对」双实现：`proactive_message_service.dart:427-441` _reconcileOverdue 与 `proactive_deep_link.dart:210-233` restoreProactiveSchedules 各自实现 scheduled→expired（`!scheduledAt.isAfter(now)` 同义两处）；F-125 同类「全表拉取+内存过滤」已移除，此为遗留 | 架构报告 2026-09-21 C6 | Worth exploring | 📝 待立项 | 聊天链路 |
| F-152 | `ChatService` 构造持有 `AppDatabase`（chat_service.dart:389-423，`var _ = database` wildcard）仅为缺省构造 LorebookRepository 兜底，装配层（app.dart:187-189）已注入 repo 但参数可选——数据层类型泄漏进服务协议面；修复 = lorebookRepository required + 删 database 参数（测试构造面 churn 有界） | 架构报告 2026-09-21 C7 | Worth exploring | 📝 待立项 | 装配层 |
| F-153 | `app.dart` endOfTurnHooks（:409-487）五闭包逐个复制「characterId 空守卫 + context.read 取用」样板；开关读取不对称（反思/宫殿装配层读、主动消息服务内读） | 架构报告 2026-09-21 C8 | Speculative | 📝 待立项 | 装配层 |
| F-154 | `RelationshipService`（relationship_service.dart:164）`required ConversationRepository conversationRepository` 构造参数在 C5 删除 `_allMessagesFor`/`_conversations` 后**零消费死参**：8 处构造点（app.dart:372 + 7 测试）被迫传一个不改变行为的仓储；删除 = 8 构造点机械改（与 C7 构造净化同款模式）；C5 当时因出票面范围保留 | 波 1 增量审核（架构批次） | Speculative | 📝 待立项 | 装配层 |

## 技术债处置记录

### 2026-09-21 — 技术债消费批次（F-143~145 三条全部处置，候选区清零）

> 来源：用户「按技术债消费决策点折回 F-143~145」拍板；project-kickoff 全自动档标准档单波 3 并行（高風險面② → 最低标准档）。门禁：全量 **2836 测**绿（零新增测试）/ `flutter analyze` 0 / 波末增量审核 0 阻断 / 期末四轴 **通过（0 findings）**。处置详情与逐条实证见 DEV_LOG〈技术债消费批次 F-143~145 — 三条全部处置〉。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-143 | ✅ 已修 | `listSwipesBatch` docstring 声明输入规模 bound（SQLITE_MAX_VARIABLE_NUMBER ≥3.32 默认 32766 + 超限「too many SQL variables」硬失败 + 调用方职责「须 ≤ 上限、超规模自行分块」）；方法体与两消费方零改动、零新增测试（Grilling 定案：chunking 属 YAGNI，触发规模超真实对话量级三数量级）；顺带修正候选区原行消费方行号漂移（conversation_export_service.dart:114 → :260，实际在 `_listSwipeContentsBatch` 内）；T-01 commit `d1c755f`（merge def3a4b） |
| F-144 | ✅ 已修 | `ChatService` 抽提私有 `_requireMessageOwnership`（messageById → null → MessageNotFoundError，跨对话同 id 视为不存在）；deleteMessage 接返回值用 target.role（user 截断/非 user 单删不变量保留）、switchSwipe 只 await 不接值（越界原样上抛保留）；`_resolveContinueTarget` 零改动；**桌面前提实证修正**：桌面 message.py:259 早有 `_require_message`（6 调用点），抽提 = 对齐桌面既有结构非偏离（helper docstring 注明 id-only vs conversation 过滤差异）；零新增测试（双路径用例兜底 + 突变抽查实证灵敏度）；T-02 commit `9094f12`（merge 32071f0） |
| F-145 | ✅ 已修 | `ChatTestEnv.seedCharacter` 两次 `_now()` 收敛为单次局部变量两字段同引用（createdAt/updatedAt 必填命名参数保留）；docstring 从「逐值等价」改述为「值恒被 createCharacter 覆写／占位、无观测语义」；零新增测试（覆写契约由 character_repository_test:133-137 锚定）；T-03 commit `f5d9104`（merge a885886） |

### 2026-09-21 — 技术债消费批次（F-140/F-141/F-142 全部处置，候选区留 F-143~145）

> 来源：用户「F-140/141/142 待立项消费」拍板；project-kickoff 全自动档单波 3 并行（高風險面② → 标准档）。门禁：全量 **2836 测**绿（基线 2829 → +7）/ `flutter analyze` 0 / 波及文件覆盖率全 ≥90% / 波末增量审核 0 阻断 / 期末四轴 **通过（0 Critical）**。处置详情与逐条实证见 DEV_LOG〈技术债消费批次 F-140/F-141/F-142 — 三条全部处置〉。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-140 | ✅ 已修 | `ChatService.switchSwipe` 服务层落地（chat_service.dart 新方法 + 归属校验与 deleteMessage 同构 + 越界原样上抛），ChatRound 改调服务层（守卫/notice/reload 保留），spec §4.8 契约表实现补位免修订；chat_round_test 13 行接口顺应存根（Dart implements 编译必需，批准归记录警告）；T-01 commit `6b5ba9a`（merge d85ff5a） |
| F-141 | ✅ 已修 | 根因实证 = 测试夹具不可控时钟（seedCharacter 的 `DateTime.now()` 被 createCharacter 的 `_now()` 覆写 + drift 秒级存储 + 两 seed 跨秒边界 → 排序错 → first.id=2），非控制器竞态；ChatTestEnv 注入可控时钟（`create({now})` 默认参数，抄 chat_controller_test 先例）；先红（a6132fd 复现 first.id==2）后绿（d107291）+ 契约锁双口径 + 全量 4 遍首跑零复现；T-02 commits `a6132fd`+`d107291`（merge 97e556b） |
| F-142 | ✅ 已修 | `MessageRepository.listSwipesBatch` batch 原语（drift `isIn` 单查询 + 空输入短路 + index 升序），branch_service.buildBranchSnapshot 与 conversation_export_service JSON 导出两消费方改调，输出逐字节等价（既有断言零改动全绿）；`_loadSwipeCounts` 明确不动；T-03 commit `d617564`（merge 007776c） |

### 2026-09-19 — 技术债消费批次（F-123~139 十七条全部处置，候选区清零）

> 来源：handoff-conver-mobile-arch-deepening-s1s6-20260918 交接指令（用户「消费候选区技术债」拍板，Grilling 共识 16 做 1 关）。主会话直行 5 波（全自动档，无子代理派发）。门禁：全量 **2274 测**绿（基线 2264 → +10）/ `flutter analyze` 0 / 波及文件覆盖率全 ≥90%。处置详情与逐条实证见 DEV_LOG〈技术债消费批次 F-123~139 — 十七条全部处置〉。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-123 | ✅ 已修 | 深链接线业务下沉 proactive 域：新建 `lib/services/companion/proactive_deep_link.dart`（协议表面 = 导航 seam ×2 + 消费函数 ×3 + 恢复/初始化 ×2，深模块），app.dart 摘除约 210 行业务接线圈（剩 ScaffoldMessenger 桥接基础设施 + Provider 闭包）；装配闭包经 import 改调 |
| F-124 | ✅ 已修 | `chatErrorMessage` 单源（chat_service 顶层，Domain/LLM/未知三叉判型收敛），chat_service 三叉 catch + 事件流路径 + chat_round `_descriptiveError` 共 7 处改调 |
| F-125 | ✅ 已修 | `getActivePlan` 加 `limit(1)`（双在途不再抛 StateError，契约锁测试）+ docstring 修正；服务侧 `_hasInFlightPlan` 改调 getActivePlan（去全表拉取绕路） |
| F-126 | ✅ 已修 | `float32_codec.dart` 迁 `lib/utils/`（git mv + 4 处 import 更新，含测试镜像迁移）消除 data→services 反向边 |
| F-127 | ✅ 已修 | 视图侧 3s 高亮 timer 删除（字段/处理/dispose 三处），清除生命周期单一归属 `ChatController._applyHighlight`（既有 widget 测试锁 3s 保持） |
| F-128 | ✅ 已修 | 截断重试判据改 noticeId 配对：`_interruptedNoticeId` 在 ChatInterrupted 置位后记录，`hasRetryableInterrupted` 与 `_resolveInterruptedTarget` 身份门弃文案比较（F-65② 并发语义保留） |
| F-129 | ✅ 已修 | 日历日口径单源：`CompanionTimeWindows.localDayOf/isSameLocalDay`（F-91 宿主扩面），proactive 同日判定 + relationship distinct 日计数双消费点改调，删 proactive `_isSameDay` |
| F-130 | ✅ 已修 | 索引对账机械测试 `test/data/database/index_parity_test.dart`（source 正则提取 onUpgrade CREATE INDEX ⊆ tables.dart @TableIndex；IF NOT EXISTS 设必需前缀防注释假名；断行字面量容忍引号） |
| F-131 | ❌ 复核关闭 | prompt.dart role 唯一构造点（chat_service `HistoryMessage(role: m.role)`）m.role 为 Role 枚举，toString 兜底路径真实不可达；docstring 已契约化（镜像桌面 SimpleNamespace 语义） |
| F-132 | ✅ 已修 | `persistThought` 服务侧截断（与 extractThought 同源 `_maxThoughtLength` 1 MiB，落库参数改 content）+ 超长用例（先红后绿：漏改落库参数被测试捕获修复） |
| F-133 | ✅ 已修 | 开关读抛错双测试：thought_service 层「persistThought 上抛（服务不吞）」+ chat_service_stage2 端到端「正文保留 + ChatDone 不受阻」（`_ThrowingSettingsRepository` 显式构造） |
| F-134 | ❌ 复核关闭 | planner 闭包运行路径已在 chat_service_stage2 hooks ③ 直测（planAfterTurn 调用 + shouldSend 成功路径）；装配层 plan hook 为 context.read 薄直调，`_resolveLlm` 成功路径被 reflector 装配测试间接覆盖——重测为同函数间接覆盖 |
| F-135 | ✅ 已修 | 反射条件补嵌单点编排：`reflectAndBackfillPending`（app.dart 顶层、函数 seam 注入可测）——added>0 才 backfillPending，消灭每回合无条件重复清扫；装配测试 +2 |
| F-136 | ✅ 已修 | chat_entry_test「默认选中首角色」断言前置 `pumpUntil(selectedCharacterId == first.id)`（加载完成显式等待；单帧 pump 下异步加载未完成即断言 = 残余窗口） |
| F-137 | ❌ 复核关闭 | 本批复现循环 5 遍全量零复现（run 1-5 全绿）；characters_view_stage2 已全量 pumpUntil 双终态等待（F-104/F-122 双重修复在位），无可见待加固点——按 fallback 语义收口，残余风险记录 |
| F-138 | ✅ 已修 | `_resolveGenerationCredentials`（app.dart 顶层抽共享），GameGenerator 闭包改调 + `_resolveLlm` 内部复用（S4/F-120 装配收敛第五处） |
| F-139 | ✅ 已修 | `_autoInsertGreeting` 判空读下推 `MessageRepository.lastMessage` 单值定位读（S6 语义化读面） |

### 2026-09-18 — 架构深化批次（S1~S6 六条 Strong 全 ✅ 已修）

> 来源：improve-codebase-architecture 报告（D:\tmp\architecture-review-20260918-203548.html）六条 Strong，用户拍板全立项；project-kickoff 全自动档 3 波（波 1 = AD-01/03/04，波 2 = AD-02/05，波 3 = AD-06）。门禁：全量 **2264 测**绿（基线 2225 → +39）/ analyze 0 / 波及文件覆盖率全 ≥90%（多数 100%）/ 波末两轮增量审核 0 阻断 / 期末主会话四轴复核通过（**子代理聚合故障降级**：四路内部审核完成但通知未送达聚合层、聚合层不可续接，主会话以波末两轮增量审核 + 锚文本抽查 + 全量绿合成期末结论，如实标注）。非阻断发现落债 F-132~139（波末审核 + 复核 flaky 观察 + spec 范围外随批落债）。候选区保留 F-123~131（未选中候选）与 F-132~139（本批新落）。详见 DEV_LOG〈架构深化批次 S1~S6 — 六条 Strong 全交付〉。

| 编号 | 处置 | 详情 |
|------|------|------|
| AD-01（S5） | ✅ 已修 | extractThought 全链路唯一剥离点；stripAndPersist → persistThought（收已剥离结果）；ADR-0007 第 32 行排布句改写 + 修订记录节；`6341a22` |
| AD-02（S1） | ✅ 已修 | EndOfTurnHook 有序集合（backfill→reflect→plan→relate）+ 服务内吞错契约（reflect/relate 迁移内部降级）+ 构造收敛（删 5 参数）；_persistThought 排除；`17add6a` |
| AD-03（S2） | ✅ 已修 | lib/utils/llm_json_candidates.dart 单源 + 三调用方改调（类型化解码保留）；marker 字面量单源；`2507f62` |
| AD-04（S4） | ✅ 已修 | planner 闭包改调 _resolveLlm（F-120「第三处出现即复用」承诺兑现）；行为零变化；`a21bd9d` |
| AD-05（S3） | ✅ 已修 | 基类默认 streamGenerate（模板方法）+ protected streamRequest 扩展点；双 provider 删覆写；夹具 12 类迁移 + _RawErrorProvider 保 A2 契约；`de07cb9` |
| AD-06（S6） | ✅ 已修 | MessageRepository 5 定位读（lastAssistantMessage/lastUserMessageBefore/messagesBefore/messageById/lastMessage）+ chat_service 三判据下推 + chat_round last 下推；重生成 I/O 实证 getMessages=0 + ≤3 定位读；`1f60ffd` |

### 2026-09-17 — 技术债消费批次（F-122 publish 等待族收口 ✅ 已修）

> 来源：F-121 批次全量首跑 1 失败观察落债（Weak）。单 commit `19e0192`（lib 1 文件 + test 1 文件）。根因：`CharactersView._maybeBroker` 用 `Provider.of<StageUpgradeBroker>(context)`（listen 默认 false）——publish 只改数据不建立 UI 依赖，UI 更新靠轮询兜底；且确认后置等待 `find.text('亲密')` 在确认完成前即被「升级建议：亲密」提前满足，拒绝/F1 固定时长 pump 在负载下不足。修复：broker 读取 `listen: true`（publish 触发一帧重建，publish 用例改单帧断言）+ 确认/拒绝/F1 等待条件改「`broker.lastProposal == null` 且 `find.text('确认')` 消失」双终态；新增 `_GateRelationshipService` Completer 门闩用例确定性复现「提议文本已存在但服务未完成」场景（先红后绿）。门禁：全量 **2225 测**绿（基线 2224 → +1）/ `flutter analyze` 0 / pre-commit 池检查通过；候选区清零、无新落债。详见 DEV_LOG〈技术债消费批次 F-122 publish 等待族收口〉。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-122 | ✅ 已修 | broker `listen: true` 订阅 + publish 单帧断言；确认/拒绝/F1 双终态等待（broker 清除 ∧ 确认按钮消失）；门闩 seam（`_GateRelationshipService`）确定性复现提前解除场景 |

### 2026-09-17 — 技术债消费批次（F-113~120 八条全部处置）

> 来源：handoff-techdebt-f109-evolution-done-2026-09-17 交接指令（用户「消费 F-113~120」指示，8 条 Weak 全处置）。单 commit `84fcdac`（9 文件 +410/-54，含 2 新文件 lib/utils/utf16_truncate.dart + test/utils/utf16_truncate_test.dart）。门禁：全量 **2224 测**绿（基线 2210 → +14 = helper 7 + A 4 + B 3）/ `flutter analyze` 0 / 波及文件覆盖率全 ≥90%（utf16_truncate 100% / persona_evolution_service 100% / memory_repository 100% / controller 100% / view 98.3%）/ pre-commit 池检查通过。详情与过程遥测见 DEV_LOG〈技术债消费批次 F-113~120 八条全部处置〉。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-113 | ✅ 已修（契约锁证伪） | 360dp 窄屏 widget 契约锁直接绿（待确认 tile 双按钮无 RenderFlex overflow，`takeException()` null）——票面疑虑证伪，未改生产 |
| F-114 | ✅ 已修 | `truncateUtf16` 防劈代理对（高代理 0xD800..0xDBFF 结尾多截 1 code unit）+ 单测 3 个代理对边界用例；接入 persona_evolution_service `_clampPersonalitySnapshot` 与 memory_repository `upsertEmbedding` 两处 |
| F-115 | ✅ 已修 | `maxSnapshotLength = 2000` 单源收于 `lib/utils/utf16_truncate.dart`；persona（原 `maxPersonalitySnapshotLength` 删除）+ embedding 两消费点接入，docstring 对账句改单源引用；测试侧 8 处常量改名同步（语义等价） |
| F-116 | ✅ 已修 | 契约锁补测：clamp 后恰等于当前人格（current = 2000 字符 + reflector 返回 2001）→ proposeEvolution 返回 null 且不落快照 |
| F-117 | ✅ 已修 | 契约锁补测：apply → 手动编辑 personality → Q7 重算回待确认 → reapply 同一 revision 幂等（appliedRevisionIds 恢复 + personality 回写） |
| F-118 | ✅ 已修 | controller 侧 `_ThrowingEvolutionService`（super parameters）异常吞并两用例 + view 侧 propose 异常 NoticeBanner 渲染断言（SR-16 摘要不含异常原文） |
| F-119 | ✅ 已修 | widget 契约锁：`_PromptDialog` 取消路径（pop → unmount → dispose）无 TextEditingController-disposed 异常且不新增条目（F-109 修复的复证） |
| F-120 | ✅ 已修 | `app.dart` 顶层 `_resolveLlm`（wireCredentialsResolver + factory.create 返回 record）抽共享，ReflectionService / PersonaEvolutionService 两处装配闭包同构段收敛单点；装配冒烟 112 测零回归 |

### 2026-09-17 — 技术债消费批次（F-121 空态入口 ✅ 已修）

> 来源：handoff-techdebt-f109-evolution-done-2026-09-17 交接指令（F-121 Worth exploring 折回首选；用户拍板折回）。单票直行（F121-01 `688a406`）：`_MemoryList` 空态分支在 `EmptyState` 下方加 `_AddEntryButton`（FilledButton.tonalIcon，复用既有 `_showAddDialog` 选类型→输入→保存全链路）；边界态（entries 空、revisions 非空）ListView 顶部同步补入口；`EmptyState` 组件本体零改动（TP-4 全局定案「操作入口由调用方提供」保持，F-53/F-54 曾有 action 槽被 AR-6 删除的先例佐证）。先红后绿：2 新 widget 用例先红（2 失败「新增记忆」文本缺失）后绿；全量 **2210 测**绿 + analyze 0 + 覆盖率 controller 100%（58/58）/ view 97.75%（174/178，新增行全覆）。全量首跑 1 失败为既有 flaky（characters_view_stage2 publish 等待族，单文件复跑+全量重跑均绿，与本批零关联——grep 证测试文件无 memory_management 引用）→ 落债 F-122。详见 DEV_LOG〈技术债消费批次 F-121 空态入口〉。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-121 | ✅ 已修 | 记忆管理页空态与边界态「新增记忆」入口：`_AddEntryButton` 深模块单点（onPressed 走 `_showAddDialog`）；空态 Column（EmptyState + space3 + 按钮）、边界态 ListView 顶部 Align 左齐；非空态仍走既有 section header IconButton（tooltip「新增记忆」），三态入口语义统一；widget 测试 +2（空态全链路新增 / 边界态情景记忆新增） |

### 2026-09-17 — 技术债消费批次（F-109 已修 + F-110~112 复核关闭）

> 来源：handoff-stage3-vector-recall-a8-local-2026-09-17 交接指令（project-kickoff 全自动档）。F-109 立项消费（3 工单串行 lane：01 E1+SR-22 `2d580ca` / 02 装配腿 `a532e93` / 03 确认闸门 UI `4ef0977`，merge `9b642d8`）；F-110~112 逐条 git grep 复核关闭（证据见 `.scratch/f109-evolution/grilling-consensus.md` §4）。门禁：全量 **2208 测**绿（基线 2185 → +23）/ analyze 0 / 波末增量审核 0 阻断（W-1/W-2 落债 F-113/114）/ 期末四轴 **通过**（0 Critical，7 条 Weak 落债 F-115~121）。详见 DEV_LOG〈技术债消费批次 F-109 演化入口补全〉。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-109 | ✅ 已修 | 演化端到端入口补全三腿：E1 服务 `_reflector` 改 `CharacterScopedReflector` + propose 透传 characterId（PersonaReflector typedef 保留）/ F1 装配腿 `Provider<PersonaEvolutionService>`（默认 lazy，wireCredentialsResolver + buildClusteredReflector 闭包，与 ReflectionService 先例同构）/ 确认闸门 UI（记忆管理页 AppBar「提出人设演化」+ tile 双形态应用拒绝 + Q7 启发式 appliedRevisionIds + SnackBar 三态 + `characters_view` 注入入口）；SR-22 快照长度 clamp 2000（`maxPersonalitySnapshotLength`）；零新依赖、schemaVersion 保持 5；顺带修复既有 `_PromptDialog` dispose 时机 bug（widget 测试暴露） |
| F-110 | ❌ 复核关闭 | per-element isFinite 守卫已存在（cosine_similarity.dart:32-34）+ float32 截断 Infinity 双防线，票面「float32 真实数据不可达」复核成立 |
| F-111 | ❌ 复核关闭 | SR-20 装配链单一落点 validateEmbeddingBaseUrl 已拦截全部无 host 输入；normalizeBaseUrl 仅在校验后输入上运行（docstring 明示前置），「绕过装配直构」非支持路径；F-111 残余用户拍板不立票 |
| F-112 | ❌ 复核关闭 | 唯一索引 `idx_embedding_entries_character_id_content_hash`（unique:true）实锤存在 + 服务层串行 await 无竞争窗口 + 反思链精确去重，票面「服务层无竞争窗口」复核成立 |

### 2026-09-17 — 人机恋阶段 3 批次（净增候选 F-109~112，随后于 F-109 消费批次全部处置）

> 本批为功能批次（远端 embedding 向量检索 kickoff），未消费既有候选。波末/期末审核非阻断发现落盘 4 条候选（F-109 plan-tickets 实证 / F-110 波 1 审核 / F-111、F-112 波 2 审核）；Falsify-1（`https://` 纯协议段放行）波内修复不入债。F-110~112 均为 Weak（float32 真实数据不可达 / 装配链已拦截 / 服务层无竞争窗口），F-109 为 Worth exploring（演化端到端入口缺位）。详见 DEV_LOG〈人机恋阶段 3 批次〉。四候选已由上方「F-109 已修 + F-110~112 复核关闭」节收口。

### 2026-09-17 — 技术债消费批次（F-106~F-108 全部处置）

> 来源：handoff-techdebt-f104f105-done-2026-09-17 交接指令（project-kickoff 全自动档）。2 工单并批 1 波 + 批次收尾（F106F108-01 `a537f71` / F106F108-02 `a399b9f`，merge `9200f49`）。门禁：全量 **2001 测**绿（基线 2000 → +1 排序锚用例）/ analyze 0 / 期末四轴 **通过**（0 Critical）。**F-106 根因实证**：`listCharacters` 仅 `ORDER BY updated_at DESC` 无二级排序键 + drift 秒级存储 + `DateTime.now()` 连续创建同值 → 同值行返回序不确定 → `_resolveSelectedCharacterId()` 取 `_characters.first.id` 偶发非 seed 首个（chat_entry_test「默认选中首角色」Expected 1/Actual 2）；修复 = `id ASC` 二级排序键（生产 1 文件），同刻注入单测钉序。**F-107 单源收敛**：`test/helpers/pump_until.dart`（窗口统一 300×10ms）替代 6 测试文件各自定义 + why 归因改现象式。**F-108 收敛**：纠偏口径文档落点收敛 DEV_LOG 指针 + 补注 `git log -S` 搜索串。候选区清零，无新落债。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-106 | ✅ 已修 | F106F108-01：`character_repository.dart` `listCharacters` 排序改 `ORDER BY updated_at DESC, id ASC`（同 updated_at 按创建序稳定，docstring 契约句）；`character_repository_test.dart` 新增同刻注入锚用例（固定 `fakeNow` 两次 seed → 首元素 id = 较小者）；本批复现循环 10 遍全绿（fallback，锚定上批 10+5 次实证 Expected 1/Actual 2 + 静态根因闭合） |
| F-107 | ✅ 已修 | F106F108-02：`test/helpers/pump_until.dart` 单一权威定义（300×10ms，docstring 注明用途与失败模式）；6 测试文件删本地定义 + import；`characters_view_stage2_test` 5 处「（broker publish 生效延迟）」归因 why 改现象式；生产零 diff |
| F-108 | ✅ 已修 | 批次收尾：TECH_DEBT/TICKETS 的 F-101/F-105 引述收敛为「详见 DEV_LOG」指针（删 4-commit 清单复制）；DEV_LOG 权威源补注 `git log -S "锁失效并行交错"`（子串口径，勿与完整带若变体混用） |

### 2026-09-17 — 技术债消费批次（F-104~F-105 全部处置）

> 来源：handoff-techdebt-f101f103-done-2026-09-17 交接指令（project-kickoff 全自动档）。2 工单并批 1 波串行 lane（F104F105-01 `a5e79b7` merge `ffb05c7` / F104F105-02 `77fb9a1` merge `ffb05c7`）。门禁：全量 **2000 测**绿 / analyze 0 / 期末四轴 **通过**（0 Critical）。**票面归因实证推翻**：F-104 复现循环（shell 逐遍 10 次全量，`--repeat` 不被 flutter_tools 3.47.2 支持）捕获 2 次失败，均为 `chat_entry_test`「默认选中首角色」竞态（Expected 1/Actual 2），票面目标 `characters_view_stage2_test` 15 遍零失败——用户拍板：01 票按 fallback 语义收口（健壮性修复 + 残余风险明确定位），chat_entry 竞态另立 F-106（Strong）下批消费。F-105 四处「从未存在于仓库」失实表述统一为「从未存在于代码 reason（文档/注释引述除外）」口径。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-104 | ✅ 已修（fallback 语义） | F104F105-01：`pumpStage2` loading 轮询 100 次静默放行 → `pumpUntil`（300 次）+ 显式断言「角色列表加载未在轮询窗口内完成」；5 处 publish 用例（升级建议：亲密 / 多选态确认 / 确认 / 拒绝 / F1）断言前单帧裸 pump → 条件等待；无 test 块增删、生产零 diff。票面目标未实证复现（15 遍零失败），残余 flaky = chat_entry_test 竞态（立 F-106），交付说明如实标注 |
| F-105 | ✅ 已修 | F104F105-02：4 处旧版失实表述修正（DEV_LOG 票面纠偏句 / TECH_DEBT 处置记录引注 / TICKETS 归档行 / `notification_service_test.dart` 注释块），统一「从未存在于代码 reason（文档/注释引述除外）」口径 + `git log -S` 实证引据（commit 清单详见 DEV_LOG〈技术债消费批次 techdebt-f101f103〉）；纯文本/注释，生产零 diff、行为零变化 |

### 2026-09-17 — 技术债消费批次（F-101~F-103 全部处置）

> 来源：handoff-techdebt-f98f100-done-2026-09-17 交接指令（project-kickoff 全自动档）。2 工单并批 1 波串行 lane（F101F103-01 `8fd29fe` merge `61c9ca3` / F101F103-02 `3d2b8b1` merge `61c9ca3`）。门禁：全量 **2000 测**绿 / analyze 0 / 期末四轴 **0 阻断**（F-103 复核关闭；无新落债）。票面纠偏：F-101 票面「修正 reason 文本」修正对象不存在（「若锁失效并行交错则为 1」从未存在于**代码 reason**（文档/注释引述除外），`git log -S` 实证引据与 `git show 76f7da8` 原文详见 DEV_LOG〈技术债消费批次 techdebt-f101f103〉）；B′ 双 gate 中间态断言为唯一零生产改动独立钉锁方案，突变实验实锤（移除 `await previous` → 中间态期望 1 实际 2 红）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-101 | ✅ 已修 | F101F103-01：反序 gate 用例重构双 gate 两阶段 + 中间态 `initializeCalls==1` 断言独立钉 `_initSerial` 锁等待（锁失效突变下红）；fake 零改动、生产零 diff；先红后绿（临时移除 `await previous` → 期望 1 实际 2 红，恢复全绿） |
| F-102 | ✅ 已修 | F101F103-02：告警 seam 用例正常分支独立 `_FakePlugin` + 独立 scheduler，用例内组级 plugin/scheduler 零引用（字面验收线达成）；行为断言语义零变化；顺序对调双向全绿机器实证；生产零 diff |
| F-103 | ❌ 复核关闭 | 全仓 188 文件/223 检查 format 差异为存量 formatter 版本漂移（上批基线 `3943bf8` 同检查失败、hunk 一一对应），无行为风险；全仓归一大 diff 噪音，用户已拍板不立项 |

## 复核关闭（最近 4 批，滚动保留）

> 具复核价值的 Speculative 类关闭项单行摘要，防 review 重复提出；更早批次由 git 历史承担（`git log -p -- TECH_DEBT.md`）。

| 编号 | 关闭批次 | 单行摘要 |
|------|----------|----------|
| F-131/F-134/F-137 | 2026-09-19 | prompt role 唯一构造点只传 Role（F-131）／planner hook 已直测 + _resolveLlm 间接覆盖为本批同函数覆盖（F-134）／chars_view publish 等待族 5 遍全量零复现 + 双终态在位（F-137） |
| F-110/F-111/F-112 | 2026-09-17 | per-element isFinite 守卫 + float32 截断双防线成立（F-110）／SR-20 装配链单一落点已拦截无 host（F-111，残余用户拍板不立票）／唯一索引 `idx_embedding_entries_character_id_content_hash` 实锤 + 服务层无竞争窗口（F-112） |
| F-103 | 2026-09-17 | 全仓 188 文件/223 检查 format 差异为存量 formatter 版本漂移（基线 `3943bf8` 同失败、hunk 一一对应），无行为风险；全仓归一大 diff 噪音已拍板不立项 |
| F-86/F-87 | 2026-09-16 | extractThought 1MiB 截断切破代理对（thought_service.dart:32 现状成立）／关系域读契约双依赖点（chat_service.dart:278/315 注入现状成立），本批聚焦通知域关闭留档 |
| F-74 | 2026-09-10 | 模拟器 server 仅回环绑定 + proxy 目标恒取配置 base + spec 声明不鉴权——加鉴权属过度工程，纵深防御提示留 DEV_LOG |
| F-71/F-72 | 2026-09-10 | patterns= 为 privacy_audit 测试 seam 合法扩展点（非死代码）／FileNameEdgeTrim.none 是默认配置完整性基座（设计意图保留） |
| F-57 | 2026-09-09 | sub.cancel 停滞挂起经三重覆盖收窄，「停止收尾不可跳过」结构性成立，剩余 3s 为 F-17 既定有界契约 |
| F-53/F-54 | 2026-09-09 | `EmptyState.action`／`StatusView.hint` 参数槽 TP-4 共识保留（W1 复核关闭）→ 后被 AR-6 按授权删除（见处置记录） |
| F-58 | 2026-09-09 | 首 token 前 idle 3×60s+退避纯时长 UX 观察，各环行为与契约一致无错判；随 AR-1 行为变更 B1 消亡 |