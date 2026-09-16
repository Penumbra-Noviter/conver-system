# Conver System 移动端 — 开发日志 (DEV_LOG)

> 只记「已做」与决策/避坑；待办一律进 [TICKETS.md](TICKETS.md)（唯一待办事实来源）。
> 格式：`YYYY-MM-DD | <操作> | <描述>`（倒序，最新在前）
> 滚动摘要窗口上限 12 条，超限在文档同步时折叠为阶段摘要。

---

## 技术债消费批次 techdebt-f101f103（2026-09-17 — handoff-techdebt-f98f100-done-2026-09-17 交接指令，/project-kickoff 全自动档）

- **范围**：消费候选区 3 条（F-101 反序 gate 用例验收 reason 文本归因待裁决 / F-102 告警 seam 用例「组级 plugin 零引用」字面验收线 / F-103 全仓 format 存量差异）；2 工单并批 1 波串行 lane（同文件 `notification_service_test.dart`，01/02 区域零重叠）；F-103 复核关闭（用户拍板归一不立项）。先搜开源三分：自建（两票全为仓内测试文件局部增强，零新依赖）。
- **票面纠偏（本批核心实证）**：F-101 票面 A 方案（修正 reason 文本）修正对象**不存在**——`git show 76f7da8` 原文与 HEAD 的 reason 文本均为「若早退拦截则为 1」（本就正确），`git log -S "锁失效并行交错"` 零命中；票面 B 方案（fake 记录调用顺序断言）经 microtask 推演在锁失效时**不红**（gate 单 Completer FIFO 巧合串行化使 fake 可观测序列与锁生效时全同）。唯一零生产改动可独立钉锁方案 = **B′ 双 gate 两阶段 + 中间态 `initializeCalls==1` 断言**。
- **交付**：
  - F101F103-01：反序 gate 用例重构双 gate 两阶段（`gate1` 无回调 lazy 挂起 → `gate2` 带回调 wired 挂起 → `gate2.complete()` + flush microtask 断言中间态 `initializeCalls==1` → `gate1.complete()` 最终断言）——锁失效（移除 `await previous`）突变下中间态红（Expected 1 / Actual 2）实锤，恢复全绿；fake 零改动、生产零 diff——commit `8fd29fe`（merge `61c9ca3`，验收 8/8）
  - F101F103-02：告警 seam 用例正常分支独立 `normalPlugin`（`_FakePlugin`）+ 独立 `FlutterLocalNotificationsScheduler`（channel/isAndroid 注入），用例内组级 `plugin.`/`scheduler.` 前缀零命中；行为断言语义零变化；顺序对调（doomed 先跑）31 测全绿机器实证——commit `3d2b8b1`（merge `61c9ca3`，验收 5/5）
  - F-103：❌ 复核关闭（实测全仓 188 文件/223 检查 format 差异为存量 formatter 版本漂移，上批基线 `3943bf8` 同失败、hunk 一一对应；无行为风险；用户拍板归一不立项）——复核关闭表留档一行
- **门禁链**：全量 **2000 测**全绿（基线 2000，01/02 增强既有用例不净增）/ analyze 0（No issues found）/ 期末四轴 **0 阻断**（固定点 5aeffe7；F-103 复核关闭，候选区清零后落债 F-104/F-105）。
- **审核修复（R-S1）**：期末四轴 Recommended 1 项——01 票中间态断言 `reason:` 单行 108 字符触发 dart format 违规（本批引入，非 F-103 存量漂移）；已 `dart format` 修复 + 单文件 31 测复绿；F-103 复核论据补注（「188 文件存量差异」判断仍成立，本批审核期新增 1 处差异已随 R-S1 修复）；非阻断落债 F-104（`characters_view_stage2_test` publish 用例存量 flaky，单跑/重跑全绿）/ F-105（票面纠偏表述收窄：「锁失效并行交错」未存在于代码 reason，文档/注释引述除外）。
- **过程遥测**：子智能体 4（Grilling 1 + plan-tickets 1 + Implement 1×2 票串行 + 合并主会话）+ 主会话直做（03 文档收尾）；无重开/冲突/回退；01 票突变实验（临时移除 `await previous`）由 Implement 在分支内完成并恢复；全量测试 1 次绿（1 分 07 秒）。
- **技术债闭环**：3 条全处置（F-101/F-102 ✅ 已修、F-103 ❌ 复核关闭）；候选区清零后落债 F-104/F-105（期末四轴非阻断发现，见「审核修复（R-S1）」节）。
- **知识库召回轨迹**：预检 persona（Conver System）+ 精读 5 条（《Falsify测试要钉住缺陷所在层》《补锁测试先枚举分支矩阵》《并发测试确定性：脚本式fake按位置消费必然不稳定》《技术债票面修复建议须实证复核》《工单验收标准避免行号与grep计数》）；开发期 kb-search 未触发。
- **编排教训**：① 技术债票面建议本身须实证复核——本批 A 方案修正对象不存在、B 方案不钉锁，均被 git 实证/microtask 推演否定，B′ 双 gate 为唯一零生产改动方案（与知识库《技术债票面修复建议须实证复核》合流复证）；② 「钉缺陷层」经验直接指导裁决：反序用例原不钉锁机制（gate 巧合串行化掩盖），中间态断言钉住等待依赖本身，最终断言钉结果语义——分层钉力明确。
- **预设接续**：候选区清零（F-101~103 全处置）；残留清理 `.worktrees/f91f97-1` 空壳仍待进程释放后手动删；权限弹窗真机补验、阶段 3 人机恋深化仍开放（可选）；交付后复核（约一周后三问）可选。

## 技术债消费批次 techdebt-f98f100（2026-09-17 — handoff-techdebt-f91f97-done-2026-09-17 交接指令，/project-kickoff 全自动档）

- **范围**：消费候选区 3 条（F-98 并发交错反序测试缺口 / F-99 initialize 返回值契约缝隙 / F-100 告警 seam 用例共享实例时序敏感）；3 工单并批 1 波串行 lane（三票共享 notification_service_test.dart，串行为唯一安全形态；02 票改动核心模块 → 标准档机制）。先搜开源三分：自建（零新依赖，插件契约已本地实证）。
- **交付**：
  - F98F100-01：反序并发交错 gate 用例（无回调挂起中带回调进入 → 锁串行重挂 + 零告警 + 可消费），钉 `_initSerial` 结果语义；纯测试生产零 diff——commit `76f7da8`（+merge `49a1b12`，验收 8/8）
  - F98F100-02：`_initializeLocked` 两处读 `Future<bool?>` 返回值——首次 false/null 不置 `_initialized` 返回 false（可自然重试）、重挂走 `onHotCallbackLost` seam 返回 false 不更新 `_registeredCallback`（C2 edge 落 docstring）；docstring 三处补注「成功 = true 且非 null」+ 插件 22.3.1 覆盖赋值实证；fake 增 `bool? initializeResult`；先红后绿 3 红实锤（Expected false / Actual true）——commit `562e968`（+merge `e9bfc10`，验收 8/8）
  - F98F100-03：告警 seam 用例 recoverable/doomed 每分支独立 `_FakePlugin`（直接构造 scheduler 避开 build 工厂闭包捕获）；顺序对调双向全绿机器实证；纯测试生产零 diff——commit `e378f78`（+merge `6f67160`，验收 5/5）
- **门禁链**：全量 **2000 测**绿（基线 1996 → +4）/ analyze 0 / 期末四轴 **0 阻断**（固定点 3943bf8；结论位「需修 Recommended 2 项无 Critical」——R-S1 测试新增块 dart format 已修 / R-S2 本文档 + TECH_DEBT + TICKETS 同步本 commit 收口）。Falsify 突变实证：02 票失败语义钉力全成立（删 ok!=true 分支全断言红）；01 票反序用例钉结果语义、锁机制钉力由正序用例承担（矩阵闭合）。
- **过程遥测**：子智能体 6（Grilling 1 + plan-tickets 1 + Implement 3 + code-review 1）+ 主会话直修（R-S1 format）；无重开/冲突/回退；工具链绕行发现——子代理 pwsh 沙箱拦 flutter_tools 子进程写 Flutter cache（lockfile/version-check）导致 flutter.bat 卡死，绕行 = `danger-full-access` + `dart.exe flutter_tools.snapshot` 直跑 + `FLUTTER_ALREADY_LOCKED=true` + `--no-version-check`（01 票实证，02/03 沿用）；03 票全量首轮 chat_entry_test 1 例并发 flake（隔离 10/10 绿 + 重跑 2000/2000 绿，判定环境性与本批零关联，记此不落债）；全量测试 3 次绿。
- **技术债闭环**：3 条全处置（F-98/F-99/F-100 ✅ 已修）；期末非阻断落债 F-101（01 票 reason 文本归因错误：锁失效时反序用例仍绿，锁钉力由正序用例承担——补调用顺序断言或修正文本）/ F-102（03 票验收①「组级 plugin 零引用」字面未达成，正常分支仍用组级 scheduler）/ F-103（service 11 处存量 format 差异，formatter 版本漂移，全仓归一批次需拍板）；候选区剩 3 条待立项。
- **知识库召回轨迹**：预检 persona + 精读《并发测试确定性：脚本式fake按位置消费》《补锁测试先枚举分支矩阵》《Falsify测试要钉住缺陷所在层》《worktree落exFAT盘dubious ownership》；开发期 kb-search 未触发（无报错/测试失败绕过该闸门点的库查询）。
- **编排教训**：① flutter 工具链在子代理沙箱下的绕行配方须随批传递（非技术债，工具链事实）；② 本期无新流程坑——并行票共享文件（01↔02↔03 同文件）通过「同 commit 串行 lane」规避，经验与前批「冲突矩阵再核」合流。
- **预设接续**：候选区 F-101~103 待下轮 kickoff 预检消费（F-101/F-102 低强度、F-103 Speculative）；交付后复核（约一周后三问）可选。

## 文档清出机制执行（2026-09-17 — Neat 遗留裁决）

- **背景**：Neat 审计报告两条历史遗留——TECH_DEBT 处置记录 25 节超「最近 2 节」滚动上限；TICKETS 已完成归档批次数未按 6 批上限执行折叠。用户裁决「择机执行」→ 本节点清出。
- **执行**（commit `6b019f3`，已推送）：
  - TECH_DEBT.md：处置记录收敛为最近 2 节（2026-09-17 两节），删除 23 节更早记录；新增「复核关闭」表收纳最近 4 批关闭项单行摘要（F-86/87、F-74、F-71/72、F-57、F-53/54、F-58、F-60~62）；更早归档由 git 历史承担。
  - TICKETS.md：已完成归档收敛为最近 6 批次（F-91~97 / F-78~90 / F-84~88+F-83 / 阶段 2 / 阶段 1.5 / 阶段 1 MVP），更早 23 批次折叠为「历史归档索引」29 行（工单号/提交哈希/一句话摘要）。
- **验证**：`python scripts/pool_cleanup_check.py --check` 全绿（候选区/复核关闭/归档索引合规）；TECH_DEBT 处置节数 2、TICKETS 归档节数 6。

## 技术债消费批次 techdebt-f91f97（2026-09-17 — handoff-techdebt-f78f90-done-2026-09-17 交接指令，/project-kickoff 全自动档）

- **范围**：消费候选区 7 条全部——F-92+F-97 并批（通知热态回调状态机盲区 + 告警 seam）+ F-91（活跃窗口常量单源）+ F-93（测试 fixture 双份去重）+ F-94（构造死参数清理）+ F-95（messages.created_at 索引 + schemaVersion 4）+ F-96（RelationshipThresholds 构造自洽校验）。6 工单：W1 FD-01‖02‖03（并行 worktree）+ W2 FD-04‖05‖06（05 Blocked by 03 顺序满足）。
- **交付**：
  - FD-01：通知初始化锁串行 `_initSerial`（并发按序执行、无回调后到者早退静默不触碰插件回调槽）+ 重挂语义（新回调再次 initialize 透传，插件 22.3.1 覆盖赋值实证）+ 告警 seam `initialize(..., onHotCallbackLost:)` 上达装配方（正常/可补救 0、不可补救 ≥1）+ `_hotCallbackRegistered` 语义强化（hot=true ⇔ 插件侧已注册非 null）；先红后绿（7 失败→全绿）——commit `8508af1`
  - FD-02：`companion_time_windows.dart` 深模块（协议表面 1 符号）单源收敛 activeWindow/recentWindow + 判定表述统一「≥now−7d 允许、<now−7d 拒绝」+ 恰 7 天边界锚 + 两常量同源锚（主会话补齐）——commit `c2e6f0f`
  - FD-03：`sqliteMasterNames`/`_SaveFailRepo` 迁 test/helpers 单源 + 告警捕获 `captureDebugPrint()` 收敛（4 处 setup 形状）——commit `5762ec7`
  - FD-04：删 `ProactiveMessageService` 构造死参数 conversationRepository（实际 5 处调用点）+ 测试替身 super 转发连带清理；grep 零残留净删 15 行——commit `22672d1`
  - FD-05：`idx_messages_created_at` 索引 + schemaVersion 3→4 + onUpgrade `from<4` 分支（IF NOT EXISTS 幂等）+ 迁移测试断言链同步（冻结 4/索引/user_version=4/自愈四要素）+ 秒精度复证 docstring；先红后绿（8 失败→全绿），v1/v2 夹具 DROP INDEX 逼真走补建路径——commit `25eef77`
  - FD-06：RelationshipThresholds 构造 assert 链（全档 max 严格递增 + intimateMax+1 ≤ affinityMax + gap≥1）；非法注入构造失败先红后绿；默认/自定义合法全档反向自洽增强断言——commit `43efb82`
- **门禁链**：全量 **1996 测**绿（基线 1987 → +9）/ analyze 0 / 期末四轴 **0 阻断**（固定点 0191e50；Standards 2 Recommended / Spec 0 硬错 / Falsify 2 Recommended + 2 Info / Architecture 0）。期末修复 R-S1（测试文件 dart format）/ R-S2（app.dart 装配注释对齐重挂语义）——commit `b0c3650`。
- **过程遥测**：子智能体 10（Grilling 1 + plan-tickets 1 + Implement 6 + code-review 2 重派）；重开 1（code-review 首次仅返 Architecture 中间态未落盘 → 重派补完）；合并冲突 1（FD-01↔03 共享 notification_service_test.dart，手工合取保留 01 新语义断言 + 03 helper 收敛）；worktree 误入 git 索引（git add -A 卷入嵌入式仓库，gitignore 补 `.worktrees/` 修正）；safe.directory 预注册 6 worktree（exFAT 所有权坑）；全量测试 1 次绿。
- **技术债闭环**：7 条全处置（F-92+F-97/F-91/F-93/F-94/F-95/F-96 ✅ 已修，处置记录 2026-09-17 节）；期末非阻断落债 F-98（并发交错测试矩阵缺口：反序变体未机器化）/ F-99（initialize 返回值忽略契约缝隙，既有行为）/ F-100（告警 seam 用例共享实例时序敏感，Speculative）；候选区剩 3 条待立项。
- **知识库召回轨迹**：预检 persona（Conver System）+ 精读《worktree落exFAT盘dubious ownership》（操作坑①实证）；开发期 kb-search 未触发；
- **编排教训**：① 共享测试文件跨票未入冲突矩阵（FD-01 与 FD-03 同改 notification_service_test）——plan-tickets 冲突面应含「同文件不同票」再核一遍；② FD-02 子代理完成未 commit（半成品：验收 4 同源锚缺失）→ 主会话核验补完，stats 显示「completed」但磁盘态未收口，须 git status 实核。
- **预设接续**：候选区 F-98~100 待下轮 kickoff 预检消费；权限系统弹窗真机路径、阶段 3 人机恋深化仍开放。

## 技术债消费批次 techdebt-f78f90（2026-09-17 — handoff-techdebt-f84f88-done-2026-09-16 交接指令，/project-kickoff 全自动档）

- **范围**：消费候选区 7 条中的 6 条——F-78（迁移注释纠偏）+ F-79（中断残留自愈用例）+ F-80（后台反思写失败回滚测试）+ F-81（活跃时间查询单源）+ F-82（confirm 档位下限 clamp）+ F-90（通知热态回调契约防御）；F-89 复核关闭。5 工单 2 波：W1 FDBT-01‖02‖03‖04（并行 worktree）+ W2 FDBT-05（Blocked by FDBT-04 串行）。
- **交付**：
  - FDBT-01：app_database.dart 注释改述 drift onUpgrade 默认非事务 + 幂等自愈三机制（IF NOT EXISTS / user_version 后写 / 失败锁库）；stage2_migration_test 新增「中断残留重开自愈」用例（残留态前置断言 → 重开重跑 → 表/索引/版本/旧行四要素）——commit `bbefa33`
  - FDBT-02：conversation_settings_page_stage2_test 补「后台反思写失败 → 回滚 + SnackBar『保存失败』」（复用 `_SaveFailRepo`；生产零 diff）——commit `ae4ea54`
  - FDBT-03：notification_service `_hotCallbackRegistered` 追踪 + 早退告警「热态回调丢失」+ 契约注释（插件覆盖赋值实证纠偏）；测「先 schedule 后装配」不重注册 + 波末修复（并发 OR 置位 / 零告警断言 / 注释归因）——commit `6deba8e` + `ec72f17`
  - FDBT-04：`MessageRepository.latestMessageAt` 单源（join 单查询全局 max）；relationship/proactive 两服务改调；activeDays/_allMessagesFor 保留；乱序 fixture 消除顺序依赖 + 波末证伪增强（最旧消息移窗口外）——commit `25fbbc6` + `ec72f17`
  - FDBT-05：RelationshipThresholds.floorForStage + confirm 写入 clamp 到 targetStage 档下限；先红后绿（58→59 / 78→79 落库旧档缺陷实锤）；反向自洽断言（默认 + 自定义阈值全档遍历）；characters_view 注释同步——commit `fbc12ed`
- **门禁链**：全量 **1987 测**绿（基线 1974 → +13）/ analyze 0 / 期末四轴 **0 阻断**（固定点 a67e2a7；Standards 0 / Spec 0 硬错 / Falsify 2 低 / Architecture 1 中已认账 F-92/F-97）。
- **过程遥测**：子智能体 9（Grilling 1 + plan-tickets 1 + Implement 5 + code-review 2 波末）；重开 3（Grilling 中断 1 + FDBT-05 空返回 1 + 期末四轴空返回 1，均无半成品残留）；合并冲突 0（W1 四分支 + W2 单分支 ort 全自动）；全量测试 1 次绿；波末审核修复 1 轮（4 项 Recommended 全收敛）。
- **技术债闭环**：F-78/F-79/F-80/F-81/F-82/F-90 ✅ 已修（处置记录 2026-09-17 节）；F-89 ❌ 复核关闭（git grep 复核：生产恒 null、排程契约已在接口 seam、Leverage≈0）；非阻断落债 F-91（活跃窗口常量双源）/ F-92（告警缺 seam）/ F-93（测试 fixture 双份）/ F-94（构造死参数）/ F-95（latestMessageAt 无索引）/ F-96（阈值构造无校验）/ F-97（双 bool 状态机 OR 假绿）；候选区剩 7 条开放。
- **知识库召回轨迹**：预检精读 3 条（《drift迁移非事务原子靠幂等自愈》《哑Provider无消费者default-lazy永不执行》《Flutter测试碰平台依赖必须超时兜底》）——F-78/79 与 F-90 直接消费既有经验结论；开发期 kb-search 未触发额外检索。
- **预设接续**：候选区 F-91~97（F-92+F-97 建议并批通知域、F-96 阈值构造校验、F-94 死参数删除）待下轮 kickoff 预检消费；权限系统弹窗真机路径、阶段 3 人机恋深化仍开放。

## 技术债消费批次 F-84/F-85/F-88 + F-83（2026-09-16 — handoff 交接指令，/project-kickoff 全自动档）

- **范围**：伴侣域通知收尾——F-84（热态点按/权限/排程失败兜底）+ F-88（冷启动收口竞态）+ F-85（深链 id 正值域）+ F-83（restore expired per-plan 降级）；F-86/F-87 复核关闭。6 工单 4 波：W1 01‖02 / W2 03 / W3 04‖05 / W4 06，独立 worktree + 分支 + 每波 merge。
- **交付**：
  - F-88：`markDeliveredByMessageId` 白名单放宽 `{scheduled}→{scheduled, expired}`（点按即送达证据；sent 幂等/dropped 排除保持）——commit `38059d8`
  - F-85：`ProactiveDeepLink.tryParse` 正则 `^[1-9][0-9]*$` 形态校验 + int.tryParse 溢出兜底——commit `262f693`
  - F-84 三件套：通知 seam 扩展（channel.initialize 透传 `onDidReceiveNotificationResponse` + `requestNotificationsPermission` + `schedule` 契约 `Future<bool>`）commit `3d1f3c1`；热态深链接线（`consumeProactiveNotificationResponse` 复用 `handleProactiveDeepLink` 共享路径 + rootScaffoldMessengerKey + `showScheduleFailedNotice`「通知排程失败」+ 恢复路径静默）commit `83c53be`；权限请求挂点（开关 true 落库成功后恰一次；拒权/异常不回滚）commit `5b52e73`
  - F-83：restore 置 expired 分支 per-plan try/catch（SR-08 语义完整）commit `d56a7c1`
- **门禁链**：全量 **1974 测**绿（基线 1948 → +26）/ analyze 0 / 期末四轴 **0 阻断**（固定点 8b72c53；Falsify 实证 tryParse 换行形态/双入口 +5 幂等门控，3 实证通过 + 1 Recommended 落债）。
- **过程遥测**：子智能体 11（Grilling 1 + plan-tickets 1 + Implement 6 + code-review 1 + 备用）；空返回 0；回退 0；重开 0；合并冲突 0（4 波 ort 全自动无冲突）；全量测试 1 次绿。
- **技术债闭环**：F-84/F-85/F-88/F-83 ✅ 已修（处置记录 2026-09-16 节）；F-86/F-87 ❌ 复核关闭（git grep 现状复核成立）；期末四轴非阻断落债 F-89（ConverApp.scheduler 测试 seam 未申报，Speculative）/ F-90（schedule 懒初始化先于装配时热态回调可丢失，Speculative）；候选区剩 F-78~82 + F-89/90。
- **知识库召回轨迹**：预检 persona（Conver System）无新增经验精读；开发期 kb-search 未触发（无报错/无新测试场景缺口）。
- **预设接续**：候选区 F-78~82（Worth exploring ×5，F-79/F-83 同源）+ F-89/90 待下轮 kickoff 预检消费；权限系统弹窗真机路径留真机验证。
- **真机冒烟补充验证（同批完成）**：API 35 模拟器 + debug APK（HEAD 971d453，adb 注入 SQLite + 通知栏驱动）——① 热态点按 PASS：通知排程真通道投递（channel=proactive_messages importance=4 vis=PRIVATE，「主动消息/角色发来一条消息」固定摘要）+ App 存活点按 → `onDidReceiveNotificationResponse` → `consumeProactiveNotificationResponse` → `handleProactiveDeepLink` 共享路径 → 计划 sent 落库 + affinity 50→55；② 冷启动点按 F-88 实证 PASS：注入 scheduledAt=now+5s 计划 → 投递（id=7）→ HOME + `am kill`（保留通知，force-stop 会清通知）→ 通知栏点按 → App 冷启动 → `restoreProactiveSchedules` 置 expired → `consumeProactiveLaunchDeepLink` → **expired 计划收口 sent + sentAt 落库**（1789532759 > scheduledAt 1789532710）——F-88 放宽语义真机关环；③ 权限：POST_NOTIFICATIONS granted=true + 真通道投递实证。复验期间 2 次注入脚本撞 same messageId（`getPlanByMessageId` single 查询炸 Too many elements）修正后通过——纯测试数据问题非产品缺陷。证据 `.scratch/techdebt-f84-f88/smoke-20260916.md`。

## 真机冒烟补验批次 — 主动消息通知真通道 + 深链（2026-09-16 — 用户「真机/模拟器冒烟补验」指令）

- **范围**：handoff 阶段 2 收官后的实机验证（阶段 2 交付时纯单测兜底，未做模拟器/真机冒烟；交接建议「通知平台薄层真通道验证是下一批次首选实机验证项」）。API 35 模拟器（medium_phone）+ debug APK 全链路：安装/启动/引导 → 数据库注入（角色/会话/6 消息/关系 familiar-50/2 记忆/1 独白/scheduled 计划，now+90s）→ 排程恢复 → 通知真通道 → 冷/热态点按深链 → 送达收口。
- **PASS 项**：构建链修复后 APK 安装启动正常、首启引导（4 页分页器）/聊天空态/角色空态/注入数据渲染（角色条/会话列表「6 条消息」）正常；通知排程真通道完整实证（zonedSchedule → AlarmManager `RTC_WAKEUP` 注册 → 到点投递 `NotificationRecord channel=proactive_messages importance=4 vis=PRIVATE`，通知栏「主动消息/角色发来一条消息」固定摘要——SR-03 零内容 / SR-11 锁屏隐私实证）；**冷启动深链导航 PASS**（进程杀后点通知 → App 冷启动 → 直接打开目标会话 + 目标消息琥珀色 3 秒高亮，C1 导航链路真机闭环）。
- **阻断级发现 4 项**：
  1. **构建断链（本次已修，Critical）**：flutter_local_notifications 22.3.1 AAR 元数据强制 core library desugaring，`android/app/build.gradle.kts` 未开启 → `checkDebugAarMetadata` 直接失败——**阶段 2 交付后 debug/release APK 均无法构建**（1948 测绿不覆盖 Android 构建配置）。修复：compileOptions `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`；构建复验 PASS。
  2. **F-84 三项全实锤（未修，Strong 升级确认）**：App 全程未请求运行时权限（`appops POST_NOTIFICATION: ignore, userSet=false`——无 `requestNotificationsPermission` 装配）→ Android 13+ 真实用户开启开关也收不到通知（实测无权限时计划到点通知不显示、importance=NONE）；热态点按零处理实锤（App 存活时点通知 → 仅回聊天首页，payload 未消费、无收口、无导航——`onDidReceiveNotificationResponse` 缺失）；scheduler 返回 false 无站内兜底（代码确认，ProactiveMessageService 忽略返回值）。
  3. **新发现 C 级竞态：冷启动点按的送达收口被过期置位吞噬（落债 F-88）**：App 冷启动两个启动副作用按**声明顺序**执行——`_startProactiveNotifications→restoreProactiveSchedules`（app.dart:391，先）把「pending 且 scheduledAt ≤ now」置 expired，`consumeProactiveLaunchDeepLink`（app.dart:458，后）消费 payload 调 `markDeliveredByMessageId`（仅 scheduled 生效）。通知点按必在 scheduledAt 之后（inexact 弹窗延迟是常态）→ 冷启动点按几乎必被置 expired → sent/sentAt 不落、节流计数/冷却口径不更新、关系 +5 不触发。C1 的 8 例单测为直接调用无 restore 竞态覆盖；真机实证：点按后 plan=expired、affinity 50 未变。
  4. 测试数据注意（非缺陷）：数据库直注绕过运行时，`<thought>` 标签原样渲染——剥离仅存在于 ChatService 落库路径（ThoughtService.stripAndPersist），不入库不剥离。
- **验收口径**：通知排程/投递/冷启动深链导航 = PASS；热态点按/权限请求/收口竞态 = FAIL。**净收益 = 抓出 1 条构建断链（Critical）+ 1 条收口竞态（C 级）+ F-84 三项全实证**——印证交接「通知真通道待实机验证」的提示价值。

## 人机恋阶段 2 批次 — 主动消息 / 关系状态机 / 内心独白（2026-09-15 — /project-kickoff 全自动档）

- **范围**：执行 handoff 阶段 2 三项（主动消息循环 / 关系状态机 / 内心独白）。Grilling 共识 6 真拍点（P1~P6）全按推荐；threat-model SR-01~15（P0×10 P1×2 P2×3）并入工单验收；ADR-0005/0006/0007 落盘；新增依赖 flutter_local_notifications 22.3.1 / timezone 0.11.1 精确钉版。
- **10 工单 6 波**：W1 01（16c3eca）→ W2 02（a67d88a）→ W3 03/04/05 并行（43f0353/616a45d/e205ad7）→ W4 06/07/09 并行 + W3 返修 F1/F2（c63c547/17e5ed7/a138d7f + ab42d0c/de6c11f）→ W5 08（749e5da）→ W6 10（f3c7d47）；Lane A 串行链 5 票后按链中重启点交接 Lane E。波末增量审核 W1~W6 六轮全执行。
- **波末审核命中的真缺陷（门禁收益实证）**：W2-F1 `getActivePlan` 双在途抛 StateError（证据文件表述失实→修正+观察传 PS2-05）；W3-F1/F2 确认闸门无域校验可降档 + 角色冷却跨角色污染（→ 返修派回，先红后绿 3+3 用例）；W5-F1 SR-08 置 expired 无 per-plan catch（→ 落债 F-83）；W6-F1 **哑 Provider lazy 默认永不执行**——冷启动深链接线与排程恢复为真机死代码（→ lazy:false 修复 + 兼容 _maybeProvider 修正，装配冒烟由假阴性转实跑）；W6-F2 拒绝记录视图 State 字段切 tab 丢失（→ 上提 broker，判定⑤语义进程级成立）。
- **期末**：全量测试绿（含 1 次并发 flaky 重试：character_wizard_step2 全量并发偶发，单跑/目录整批均绿；同批 wizard 既有 drift 多库 warning 场景）/ analyze 0（期末清理基线 5 个 unused import/local）/ 威胁模型 P0 全落地 / 技术债候选区新落 F-78~F-83（Worth exploring ×6：drift 迁移非事务、迁移中断自愈用例、设置失败路径测试、活跃口径双实现、确认漂移、per-plan catch）。
- **期末四轴审核 + C1 阻断修复**：期末四轴（基线 4dddada → HEAD）结论 = Spec 轴 1 项 Critical（C1：主动消息 sent 状态机零载体、节流生产不可达、点按零业务副作用），Standards/Falsify/Architecture 零阻断；安全红线通过。C1 修复（c0fc1ed）：`CompanionRepository.getPlanByMessageId` + `ProactiveMessageService.markDeliveredByMessageId`（scheduled→sent 幂等收口）+ 深链 handle/consume 接线（归属校验通过即置 sent + `recordProactiveMessageOpened` 点开 +5）+ 8 例测试（幂等/节流生产可达闭环实证/深链接线）；全量测试复跑确认 + analyze 0。非阻断落债 F-84（热态点按/权限请求/站内兜底，Strong）、F-85（tryParse 正值域）、F-86（1MiB 截断代理对）、F-87（关系域读契约）。
- **过程遥测**：子智能体 12（Grilling + plan-tickets + threat-model + Implement×5 lane + code-review 审核×6）；合并冲突 0；空返回 0；flaky 2（wizard 全量并发 ×1、characters stage2 全量并发 ×1，均单跑绿）；切票粒度 10 票全低于硬上限（最大 PS2-05 640 行）；门禁命中：增量审核 6 轮共拦回逻辑缺陷 3 个（F1×2 + F2）+ 死代码 1（W6-F1），全部派回修复后复审；期末四轴拦回 C1 逻辑闭环缺口 1（修复）。

## 人机恋阶段 1.5 批次 — 后台反思提取（2026-09-15 — 用户「阶段 1.5 可选增强」指令）

- **范围**：执行 ADR-0004（后台反思提取）——每 N 回合异步 LLM 提炼人格事实落 `persona_fact`，补 prompt 指令驱动（阶段 1）遗漏的稳定事实。三决策拍板：每 6 回合反思（user 消息数 `% 6 == 0` 幂等判定）、默认关闭、仅人格事实。全量 **1740 测**绿（+15）/ analyze 0。
- **ReflectionService**（`lib/services/memory/reflection_service.dart`）：协议表面 `reflectAfterTurn` 单入口，内聚「节流判定 → 对话历史组装 → extractor 反思 → `parseReflectionFacts` 三级 JSON 数组容错 → 去重落库」；seam 化（`PersonaFactExtractor` typedef + `extractPersonaFactsWithProvider` 生产包装 `generate`），复用 `PersonaEvolutionService` 同构 seam 模式。
- **挂点**：ChatService 增可选 `ReflectionService` 依赖（`this._reflectionService`，null = 未启用，既有装配零改动）；`_onProviderStreamDone` 完整 assistant 落库后 `unawaited(_maybeReflectAfterTurn)` fire-and-forget，失败降级 `debugPrint` 不阻断主回复。
- **开关**：settings 白名单加 `memory_reflection_enabled`（默认 false，成本敏感）；`SettingsRepository.memoryReflectionEnabled` getter；「对话」设置子页加 SwitchListTile「后台反思记忆」即时写入。
- **装配**：app.dart 增 `ReflectionService` provider（extractor 闭包经 `wireCredentialsResolver().resolve()` + `LLMProviderFactory.create`，await 前 capture factory 规避 `use_build_context_synchronously`）。
- **过程遥测**：主会话直做（纯 Dart 业务 + 无头测试）；合并冲突 0；flaky 0。

## 人机恋阶段 1 MVP 批次 — 记忆 + 抗 OOC + 人设演化（2026-09-15 — 用户「继续」handoff）

- **范围**：执行 ADR-0003 立项的 AC-01~AC-05（记忆 prompt 指令驱动 + 抗 OOC 每轮重注入 + 人设演化版本化 + 记忆管理 UI）。依依赖序 AC-01→AC-05 交付，全量 **1725 测**绿 / analyze 0。
- **AC-01 数据层**：`MemoryEntries` 单表 + kind 区分（persona_fact / episodic）+ `PersonaRevisions` 版本化，schemaVersion 1→2 `onUpgrade`（createTable + raw SQL 补 characterId 外键索引；drift 2.34 `createIndex` 签名已改为单参数 Index，故用 customStatement 建索引，避开 API 漂移）；`MemoryRepository` 全语义 CRUD（listEntries/listPersonaFacts/listRecentEpisodic/searchEntries/updateEntry/deleteEntry/listRevisions/getRevision/deleteRevision/addRevision）。
- **AC-02 记忆指令**：`memory_commands.dart` 纯函数解析 `<add:>`/`<persona:>`/`<search:>` 标签（`>` 终止、`[^>\n]` 排除换行、空内容丢弃、未知标签原样保留）；`memory_prompt.dart` 记忆三模式（strong/medium/weak，对齐逆向对照材料 WEAK/MEDIUM/STRONG 语义，文案自主表述）+ `buildMemoryLibrarySection`；`MemoryService` 编排 applyAssistantReply（add→episodic、persona→persona_fact、search→本地检索、剥离标签）。
- **AC-03 记忆注入**：ChatService 增可选 `MemoryService` 依赖（`this._memoryService` initializing formal，缺省 null 保持既有装配零改动）；`_assembleMessages` 在人格 system 后插入记忆注入（三模式指令 + 人格事实全量 + 近期情景记忆），注入失败降级跳过不阻断主回复；`_persistAssistant` 落库前经 `_applyMemoryCommands` 剥离标签 + 落库记忆（记忆失败降级保留原始文本）。
- **AC-04 人设演化**：`PersonaEvolutionService`（reflector seam 注入 + `buildEvolutionMessages` + `reflectPersonaWithProvider` 生产装配）——proposeEvolution（LLM 反思→PersonaRevisions 快照，**不回写** personality，无变化返回 null）/ applyRevision（确认闸门回写）/ discardRevision（拒绝删除快照）。
- **AC-05 记忆管理 UI**：角色卡「记忆」入口按钮（psychology_outlined）→ `MemoryManagementView`（条目增改删 + 演化历史只读）；`MemoryManagementController` ChangeNotifier 视图模型。
- **装配**：app.dart 增 `MemoryRepository` / `MemoryService` provider，ChatService 注入 memoryService（生产链路接通）；characters_view 记忆入口经 `context.read<MemoryRepository>()` 现造 controller（对齐 C2「装配唯一落点、视图只消费」约定）。
- **契约更新**：schemaVersion 1→2（app_database_test 断言同步）；settings 白名单加 `memory_prompt_mode`（十键 + 五 mobile 先行，settings_repository_test 断言同步）；`SettingsRepository.memoryPromptMode` 返回原始字符串、由消费方经 `MemoryPromptMode.fromValue` 解析（data 层不 import services 层，分层不倒挂）。
- **过程遥测**：主会话直做（纯 Dart 业务 + 无头 widget，未派子智能体）；合并冲突 0；flaky 0；drift build_runner 一次通过（createIndex 签名坑已按 raw SQL 绕开）。

## 技术债消费批次 F-75/F-76/F-77 — 全部处置（2026-09-14 — 用户「消费技术债」指令）

- **范围**：候选区 3 条全处置（做 1 关 2）——F-76 消费，F-75/F-77 复核关闭。全量 **1684 测**绿（+3）/ analyze 0。**候选区清零**（0 项开放）。
- **F-76 temperature NaN/Infinity 回退 + clamp**（✅ 修）：`_resolveTemperature`（chat_service.dart）原用 `==` 比较 double、对 `character.temperature` 无 clamp——角色温度 NaN/Infinity（DB 无 CHECK 约束）时 `== 0.7` 恒 false 会误判「已覆盖」透传致 API 400、越界值直接透传。改为 NaN/Infinity 回退全局、越界 clamp 到 [0,2]（对齐 `SettingsRepository.getTemperature` 契约）；3 复现测试（上界 9.9→2.0 / 下界 -1.5→0.0 / Infinity→全局 0.9）红→绿。
- **F-77 SettingsReader implements 成本**（❌ 复核关闭）：git grep 复核——接口 4 getter 稳定（defaultProvider/defaultModel/userName/templateVars，近期仅 U-UX 加 templateVars 一个），16 处 implements 中 15 处测试假实现；Dart `implements` 编译期强制加 getter 时同步提醒所有实现方更新是防漏测的正确成本，非结构性脆弱。
- **F-75 种子 HTML 响应式**（❌ 复核关闭）：复核现状——22 款种子 HTML 均已带 viewport meta + @media 断点（768/420 等）；根因是内容资产 CSS 质量（固定宽度面板 270/300px 在异形屏截断）非 Flutter 代码债；WebView setInitialScale 兜底治标（整体缩放文字变小破坏布局，Android 专属 API 与 iOS 引入平台分歧）。真实 UX 问题转内容更新专项（逐款改 CSS + 真机验证），不进代码债候选区。
- **过程遥测**：零子智能体（纯代码修复 + 复核关闭，主会话直做）；合并冲突 0；flaky 0。

## U-UX 补全批次 — 聊天首页/生成参数/模板变量/新手指引（2026-09-14 — 用户 APK/模拟器实测反馈）

- **范围**：用户实测反馈四条（① 聊天首页「临时」半成品 ② 模拟器 UI 适配 ③ 新手指引缺失 ④ 设置两占位行）落 4 工单 U-1~U-4 + 技术债候选 F-75（模拟器响应式，本批未消费）。Grilling 4 决策全按推荐拍板（mobile 先行 / 全局同一替换管线 / 分页 carousel / 对齐桌面完整语义）；拆 5 工单（U-2 拆 prefactoring 02 + 功能 03）。
- **交付**：U-1 聊天首页角色选择条（ChoiceChip 选中高亮）+ 会话长按重命名/删除；U-2 `LLMProvider` 补 temperature 参数（wide refactor 15 子类，openai 透传/claude 忽略，对齐桌面 F-56）+ 全局 temperature/max_tokens 设置（角色级为主、全局兜底）；U-3 `applyTemplateVars` 增 `extraVars` 全局替换管线（key 长度降序防前缀吞并、保留 user/char 优先）+ 设置编辑页；U-4 首次启动分页新手指引（`_StartupGate` 启动门 + 跳过持久化）。
- **门禁链**：全量 **1681 测**绿 / analyze 0 / 各工单本工单口径覆盖率 ≥90% / 期末四轴 **0 阻断**（通过）。修复 F-73 色彩契约回归（01 角色选择条误引 ConverColors → colorScheme，`eb7b119`）。
- **期末四轴非阻断 6 项**：F-1 temperature NaN/Infinity 边界 → 落 TECH_DEBT F-76；A-1 SettingsReader 接口加 getter 连锁 16 处 → 落 F-77；Sp-1 settings_view 文件头注释漂移 → 已顺手修；F-2 JSON 嵌套静默丢弃 / F-3 重复 key 无 UI 去重 → 记录不落（UX 小面，UI 路径不触发）；安全红线 grep 零命中。
- **串行链降级**：后台 job settle 后 `send_message` 不可用（`list_agents` 空），串行链改为复用 worktree 派新 Implement 逐票接续（02→03→04→05 各一新 agent）。
- **范围外测试连锁（两处，记录警告）**：03「对话」占位改导航 → `settings_nav_test`/`settings_shared_row_test` chevron 3→4；04 `SettingsReader`（abstract interface class）加 `templateVars` getter → 17 处 `implements` fake 需实现（14 测试文件清单外机械连带，每处一行 `async => const {}`）。均为 Dart 语言特性/编译硬前提，非功能蔓延。
- **过程遥测**：子智能体 7（Grilling + plan-tickets + Implement×4 含 05 修复 + code-review）；合并冲突 0；空返回 0；flaky 1（chat_entry_test 全量偶发、单跑复绿）；code-review 子智能体默认模型路由失效（yunshu 无 deepseek-v4-flash）→ 改用 kuku/qwen3.7-plus。

## 技术债折回批次 F-73/F-74 — 全部处置（2026-09-10 — 用户「消费技术债区」指令）

- **范围**：候选区 2 条全处置（做 1 关 1）——F-73 消费，F-74 复核关闭。全量 **1613 测**绿 / analyze 0。**候选区清零**（0 项开放）。
- **F-73 toProxyEndpoint 双实现交叉校验**（✅ 修）：injection_test.dart 金样组新增「F-73 交叉校验」测试——JS 模板 toProxyEndpoint 四个语义步骤（非字符串短路 / origin 回退 / pathname 提取+尾斜杠剥离 / 前缀拼接）逐一 token 断言 + Dart mirror 行为锚调用。原金样为逐字锁（改 JS 同步改金样字面量即绿，锁不住语义漂移），新测试锁**语义结构锚**——改任一步骤结构（含同步改金样）即红，与既有 Dart mirror 行为矩阵形成双向联动。58 injection 测绿。
- **F-74 /proxy 开放面**（❌ 复核关闭）：git grep 复核——server 仅回环绑定（`HttpServer.bind(InternetAddress.loopbackIPv4)`，simulator_server.dart:138，无公网暴露）；`_buildProxyTarget` 目标 netloc 恒取配置 base（无任意 URL 转发面）；spec Out of Scope 已声明不做鉴权；桌面同构先例（后端同样不鉴权）——加鉴权属过度工程。纵深防御提示保留。
- **过程遥测**：零子智能体（纯测试增强 + 复核关闭，主会话直做）；合并冲突 0；flaky 0。

## 真机问题批次 CORS 反代 + 测试连接 — 诊断与修复（2026-09-10 — 用户真机验证反馈）

- **诊断**：真机反馈两问题——① 设置页测试连接失败（Claude 显示「Claude API Key 无效或未配置」、OpenAI 显示 `Model "gpt-4o" is not supported`）；② 模拟器连接 API 失败。代码定位：`api_config_section.dart:210` 测试连接 `llm.testConnection()` **不传 model** → 落硬编码默认模型（openai `gpt-4o` / claude `claude-sonnet-5`）——用户配第三方兼容端点只认自定义模型（实测 `/v1/models` 仅 `deepseek-v4-flash`），对话正常（聊天走 CredentialsResolver 传配置模型）。模拟器失败 = WebView 浏览器 fetch 直连目标端点被 CORS 拦截（dio 原生不受限所以对话 OK）。
- **实测端点**（用户提供测试 key，修复后注销）：OpenAI 面 `deepseek-v4-flash` → **200**（key 有效）；Claude 面 `/v1/messages` 5 个模型名全 **502「Upstream authentication failed」**——站侧 Claude 上游未开通（非 App 缺陷，Claude 测试连接传模型后仍看站侧）；`sk-` 实测 key 未入库（临时验证脚本跑完即删）。
- **修复（3 工单）**：T1 `05d54b8` api_config 测试连接传 `settingsRepository.defaultModel`（与聊天链同源，红→绿实证）；T2 `2418ff1` 注入脚本加桌面逐字 `toProxyEndpoint`（origin 运行时 `location.origin`，调用序 `convertEndpoint(toProxyEndpoint(...))`，`proxyPrefix='/proxy'` 单源）；T3 `2972dd7` server `/proxy` 路由（任意 method → `scheme://netloc + path` 目标解析 → 丢弃游戏 Authorization + App 侧 Bearer 注入 → dart:io HttpClient 流式透传 SSE → 未配置 503）。**SDK 三层坑实证**：autoCompress 缺省 gzip / dart HttpClient 无条件注入 accept-encoding / bufferOutput 缺省缓冲到 close 才落 socket（首字节 1061ms）——全在 _handleProxy 修复并锁进测试。
- **期末四轴**：0 阻断；Spec 1 项缺失（`connectionTimeout` 只管连接建立、上游 stall 时无限挂起——全相位超时未实现）→ 修 `fd3820b`：`close().timeout(60s)` + 响应体 `.timeout(60s)`（对齐桌面 httpx timeout=60 全局语义）+ stall 回归测试（裸上游 accept 不响应，注入 300ms 验证 502 不挂连接）；非阻断 F-73（JS/Dart mirror 双实现无交叉校验）/ F-74（本地 /proxy 开放面纵深）落盘。
- **真实端点链路验证 PASS**：Dart VM 起 SimulatorServer 反代 → `yunshuzhilian.asia/v1/chat/completions` → **HTTP 200 + deepseek-v4-flash**（game-side-key 被丢弃 + App 侧 Bearer 注入实证，JNI 通道 + 流式 SSE 真通道）。
- **门禁链**：全量 **1612 测**绿 / analyze 0 / 期末四轴 0 阻断 / APK 重建（62.3MB）。**技术债候选区 F-73/F-74 待立项**。
- **过程遥测**：子智能体 5（research + Implement×3 + 期末四轴）；合并冲突 0；空返回 0；flaky 0；`dart run` 直接跑项目外脚本因 flutter 依赖树解析失败 → 改临时 `flutter test` 文件验证（跑完即删，防 key 残留）。

## 技术债折回批次 F-68~72 — 全部处置（2026-09-10 — 用户「消费技术债 F-68~72」指令）

- **范围**：候选区 5 条全处置（做 3 关 2）——F-68/F-69/F-70 消费，F-71/F-72 复核关闭。全量 **1579 测**绿 / analyze 0 / pytest 66（覆盖 99.24%）。**候选区清零**（0 项开放）。
- **F-68 签名守卫**（`769368f` merge `e0b1bd7`）：build.gradle.kts release 打包任务（packageRelease，APK+AAB 均覆盖）双 exists() 守卫——key.properties/keystore 缺失时清晰报错含绝对路径 + docs/release-android.md §5 指引；debug 构建不受影响（缺失时仍 exit 0 实证）；keystore 存在时正常路径行为绝对一致（apksigner 指纹仍 7B:7C:00:A6...）。TDD 先复现晦涩报错（`SigningConfig "release" is missing required property "storeFile"`）再改。
- **F-69 图标色值双向守卫**（同 commit）：generate_app_icon.py 新增 `LAUNCHER_ICONS_YAML`（权威源路径）+ `assert_icon_colors_consistent(bg_hex, yaml_path)`——yaml 双键任一 ≠ 脚本 BG_HEX、双键彼此分叉、缺段、非法色均抛 ValueError 拒生成；generate_icons 生成前必跑；零新增依赖（pyyaml 环境既有）；确定性复验两次运行字节 IDENTICAL；突变（删守卫调用 → 单测必失败）灵敏度实证。守卫测试红→绿（8 failed → 41 passed），覆盖率 97.44%。
- **F-70 删 Mapping 分支**（`2de3b89` merge `a1ce47a`）：privacy_audit 删 `_packages_from_mapping`（无生产消费方 Speculative 第二解析器），audit_lockfile 收敛单 str 输入，新增 dict 输入拒绝 TypeError 契约锁（负样本从静默接受改为明确报错）；25 测 / 覆盖 99.24%；CLI 输出 133 包 0 命中与 docs 一致；Dart 侧零引用。
- **F-71/F-72 复核关闭**：F-71 patterns= 参数被 test_privacy_audit.py:215-216 消费（测试 seam 负样本注入正当性，公开 API 合法扩展点）；F-72 FileNameEdgeTrim.none 是 FileNameSanitizerConfig.edgeTrim 默认值（file_name.dart:31）+ _applyEdgeTrim case（:71），删除破坏默认配置完整性（none=不修剪是导出锚行为基座）。
- **过程遥测**：子智能体 2（Implement×2 并行）；合并冲突 0；空返回 0；flaky 0；F-68 缺失路径构建从 2m47s 提速到 22s（fail fast 副产品）。**残留目录处置**：M7 补报的 `.worktrees/m4-export`（123M）+ `m4-parse`（122M）孤儿 worktree（gitdir 指向 D 盘旧路径、git 完全脱管）经用户确认后删除，`.worktrees/` 整体清空。

## 架构审查批次 C1~C4 — 全库架构深化（2026-09-10 — improve-codebase-architecture 报告直落全自动档）

- **范围**：审查报告 5 候选（HTML `D:\tmp\architecture-review-20260910.html`）；Grilling 拍板 C1~C4 全做、C5 观察不动作；4 工单单波并行（文件集互不相交、零冲突合并）。
- **C1 translateError 下沉**（`af0a0c2` merge `078916b`）：LLMProvider 基类新增默认 translateError 分发链（LLMError 直通→Dio→HttpStatus→钩子→Socket→Http→Format/Type→兜底）+ `providerName` instance getter（缺省 'LLM'）+ `translateProviderError` 钩子（protected 语义，Claude `_StreamApiError` 唯一实，槽位 HttpStatusError 后）；Claude/OpenAI 删完整覆写各 -40+ 行，`_providerName` static const → instance getter。契约逐字对比程序化核对（base 链 == openai 原链全等、claude 仅差钩子分支）；261 llm 测 + 128 夹具消费方绿；4 突变全红。fixtures 8 处 override 零改动。
- **C2 装配收敛**（`022e972` merge `ad6c484`）：SettingsRepository 新增 `wireCredentialsResolver()`（四 reader tear-off 单一落点，B1 等价性组 +81 锁与手工接线逐位一致）；chat_service/document_parse_service `_wireCredentialsResolver` 单行委托；app.dart 装配图新增 Provider<DocumentParseService> + Provider<GameGenerator>（resolveCredentials 闭包映射 GenerationCredentials 复用 LLMProviderFactory）；characters_view `_openWizard` 与 simulators_view `_defaultOpenGenerateDialog` 改 `context.read`（`_buildGenerator` 删 -49 行、6 import 剪除）。**构造签名冻结**（chat 构造点 20+ 零波及）。3 处已申报测试偏差均结构必需（wizard 入口 provider 注入 / app_assembly_test 新增 / layer_boundary 正则兼容裸 `X(`）。lgrep 现造扫描 CLEAN。覆盖 97.1%（app.dart 84.4% 闭包面豁免）。
- **C3 双净化器合并**（`818c136` merge `7150600`）：file_name.dart 新增参数化核心 `safeFileNameCore(Object?, {required FileNameSanitizerConfig})` + `FileNameSanitizerConfig`（extraChars/edgeTrim/maxLength/trimAfterTruncate/fallback 显式命名）+ `FileNameEdgeTrim`；safeFileName 变薄包装（导出锚）+ save_contract.sanitizeFilename 公开名/签名保持委托核心（存档锚）。**双桌面锚 22 边界逐字符保契**（含 %·0x7f/首尾点/超长/`a . .` 怪癖『a 』保留非修一致）；消费方六文件零 diff；211 测绿 / 覆盖 100%。已知：FileNamEdgeTrim.none 无生产消费方 → F-72。
- **C4 删死代码**（`50cdb3e` merge `7cae529`）：删零实例化 PlaceholderGroup（grep 全库零残留含注释），保留 PlaceholderItem；settings_view 占位行+导航行收敛 `_SettingsRow`（label+note+onTap 三字段，onTap null → InkWell 惰性无 chevron），`_SettingsNavRow` 删、`_ProfileEntry` 降 record；settings_view 净减 56 行（290→234）；新增 settings_shared_row_test 4 用例；58+485 测绿。
- **门禁链**：全量 **1579 测**绿（+61）/ analyze 0 / 波末增量审核「通过」（文件范围 1 合规 3 警告结构必需，Falsify 6 非阻断，O1/O2 保留复核成立）/ 期末四轴 **0 阻断**（Standards 0 硬违规，Spec 0 缺失，Falsify 0 阻断，Architecture 0 阻断；2 轻量观察不立项：extraChars 按 code unit 迭代非 BMP 静默失效、providerName 缺省 'LLM' 静默文案回退点）。技术债候选区净增 F-72（FileNameEdgeTrim.none Speculative）。
- **过程遥测**：子智能体 8（Explore + Grilling + plan-tickets + Implement×4 + 波末增量审核 + 期末四轴）；合并冲突 0；空返回 0；flaky 0；C3 初期文件误落主仓库已检出自纠（TDD 红先绿）；sqlite3 native-assets 下载抖动沿用缓存复制惯例（C1）。

## M7 批次 — 发布准备（Android 范围收窄，iOS 延后）（2026-09-09 — project-kickoff 全自动档，source 交接书 handoff-M7）

- **范围**：用户拍板仅 Android（iOS 延后标注，Windows 无 macOS 路径 design §7.1）；4 工单 2 波 + F1 修复。
- **T01 自适应启动图标**（`19b1642`）：PIL 管线 `scripts/generate_app_icon.py` 程序化生成占位稿（#784E14 实心底 + #FFFBF4「汇」字形，字形 bbox ≤40% 画布/中心 ≤3%/全像素安全区 66%，msyhbd.ttc 渲染）→ `flutter_launcher_icons ^0.14.4`（dev 吸收）产出 adaptive（含 monochrome）+ legacy 五档；确定性（两次运行字节一致零 git 脏）；manifest 零改动。33 测 / 覆盖率 98% / 全量 1518 绿。
- **T02 release 签名**（`8452920` + F1 修复 `31796b2`）：keystore 仓库外 `keys/conver_system_upload.jks`（RSA2048/SHA256withRSA/25y）+ gitignored `android/key.properties`（强随机 24 位口令，不入库）；build.gradle.kts signingConfigs 读四键 + release 切专属签名；**波末增量审核 F1 阻断**：`file(it)` 相对 app 模块 off-by-one → 改 `rootProject.file(it)`（相对 android/）+ 防复发断言实跑相对路径版 release 构建通过（指纹 7B:7C:00:A6... 一致）。校验：keytool↔apksigner 指纹核对、AAB/APK 同证书、debug 通道仍 CN=Android Debug。
- **T03 Android 隐私清单**（`8b5e182`）：`docs/privacy-android.md` 三节式（本机存储 drift+secure_storage / 功能必需传输 dio 用户主动 / 零第三方 SDK 追踪）+ `scripts/privacy_audit.py` 可 import 审计模块（pubspec.lock 全量 133 包 × 11 模式命中 0）+ pytest 99.3%。权限集合核对 = 仅 INTERNET + 明文回环豁免。
- **T04 发布验证门禁**（`8a14b5c` + `7eca555`）：`docs/release-android.md`（版本策略 1.0.0+1/versionCode=1/递增规则 + 双产物命令链 + keystore 生命周期 + 数据安全表单对照）；`flutter build appbundle/apk --release` 双产物同签名（versionCode=1/versionName=1.0.0 机器核对）；AVD medium_phone release APK 冒烟 PASS（launcher 图标「汇」字形圆角遮罩实机验证 + 主界面 5 tab + 角色页，三截图留证）；TICKETS M7 归档（iOS 延后注记）。
- **门禁链**：全量 **1518 测**绿 / analyze 0 / pytest scripts/ 57 passed（generate_app_icon 98% / privacy_audit 99%）/ pool_cleanup_check OK / **期末四轴 0 阻断**（期末 Spec 非阻断 1 项：privacy 计数过期 129→133/17→18 已修，文档与 `python scripts/privacy_audit.py` 实测一致）/ 波末增量审核 F1 阻断已修复闭环。
- **技术债落盘**：F-68~71（key.properties 缺失报错 / 图标色值双处硬编码无守卫 / audit_lockfile Mapping 分支 Speculative / patterns 参数 YAGNI）入候选区本周未消费。
- **过程遥测**：子智能体 6（Implement×4 + 增量审核 + 期末四轴）+ View×2（图标视觉）+ Grilling + plan-tickets；合并冲突 0；空返回 0；flaky 0；coverage 7.15.3 需模块名口径 `--cov=scripts.privacy_audit`（`--cov=<file.py>` 字面形式 0.00% 陷阱）；sqlite3 native-assets 网络抖动 → curl 重试预下载 + SHA-256 校验惯例（T02/T04 两次遇到）。

## 架构深化批次 AR-4 — WebView 能力面收敛（2026-09-09 — improve-codebase-architecture 候选 4 直落）

- **交付**：新模块 `lib/services/simulator/webview_capability.dart`——统一能力接口 `WebViewCapability`（页面就绪握手 + 无返回 runJavaScript / 带返回 evaluate〔原样串，解码归桥层〕+ navigate + buildView；**不暴露 setOnPageFinished**）+ `WebViewCapabilityFactory` typedef（**构造期委托注入**）+ 生产工厂 `createWebViewCapability` + `_FlutterWebViewCapability` 适配器（webview_flutter **唯一引用点**，构造即 setNavigationDelegate——时序契约结构性成立，挂委托后导航的两步序收敛为 create(挂委托) → navigate 一步）。两张并行 WebView seam（run 62 行 / sheet 70 行）从 `lib/views/simulators/` 内嵌处删除，两消费点只留差异面：run 侧（simulator_run_view）= 无返回 runJavaScript + navigate 错误上抛即时错误态；sheet 侧（save_sheet）= 带返回 evaluate + navigate 吞错移入消费点 `_bootstrap` 走超时降级；`simulators_hooks` launcher 第三引用点换源（import + 缺省工厂 `createWebViewCapability`）。共享假件 `test/support/fake_web_view_capability.dart`（onPageFinished 构造必填 + instantFinish/throwOnNavigate/throwOnCreate + evaluate 双编码 JSON 契约复刻迁自 save_sheet_test:126-147，F-43/W5 B1 调用序 spy 组改**委托必达**行为断言）。commit 待回填（merge 待回填），基线 ba0d680。
- **门禁链**：范围 198 测全绿（simulator_run_view 20 含委托必达×2 / save_sheet 16 含委托必达×2 + navigate 吞错新增 / simulators_controller+view / layer_boundary / injection / save_bridge）/ analyze 0；覆盖率按本工单 4 源文件口径 **100.00%**（379/379；webview_capability 生产薄层 coverage:ignore 除外，接口 0/0）；**先红后绿**：委托必达断言先红（模块/消费点未实现即编译失败；运行侧委托不发即时事件 → 秒开页不注入超时错误态红 → 实现后绿）；**变异抽查**：删 instantFinish 事件派发 → run/sheet 委托必达双红、删 evaluate 值序批分支 → save_sheet happy path 红（灵敏度实证，桥层双解码容错 = 单编码变异不红的既有面豁免于假件契约，依赖方 save_bridge_test 承重）。**验收 6 条全过**（单一平台薄层 grep 唯一命中 / 时序结构性成立 / 求值能力面不变 / navigate 错误策略差异面 / 既有回归全绿 + 可观察行为零变更 + pubspec 零 diff / 命名登记）；安全红线 grep 零命中；CONTEXT 登记「WebView 能力面」「页面就绪握手」。

## 技术债折回批次 F-56/F-65/F-67 — 全部折回收官（2026-09-09 — 用户「全部折回」指令）


- **F-56 假活终态化**（`972aea8` merge fd9aafb）：`stream_wire` 新增可注入 `terminalTimeout`（缺省 2s）第二计时器——终态帧钩子臂起、终态后尾随新帧逐帧复位（不误杀）、到期无新帧 `client.close(force: true)` → 干净 EOF **正常完成**（reachedTerminated 已置位、不抛断流不触发重试）；09 验收 4 正常终态（elapsed ≥500ms）零回归；idle（终态前）/终态守卫（终态后）分工不重叠；finally 双计时器防泄漏。stream_wire 97.62% 覆盖 / 3 新测试。
- **F-65 断流重试边界 ③④**（`0708dcc` merge 2b2b4d5）：③ 判据加 `!_reloadPending`——reload 一帧窗口内「重试」按钮不可达，杜绝共享守卫静默 no-op；④ **notice 身份 seq**——NoticeRunner set/setFirst 分配 `++_noticeSeq`（先错者胜零变）、banner 增 noticeId 参数 + `_dismissingNoticeId` 身份守卫（同文案新旧不误清；未接入回退文案相等）、两控制器 getter + 两视图接线。12 文件 +374/-18；覆盖 92.9%。
- **F-67 characters_view 覆盖补齐**（`517aad6` merge 508efaf）：5 缺口路径测试（刷新失败 debugPrint / 创建向导入口 / 批删确认对话框 / 勾选 onChanged / :351 tap 多选态）+ `_RefreshThrowingController` 替身；覆盖 87.6%→99.1%（窄）/100%（宽）；5 处突变全红；**零产品代码改动**。**合并冲突 1**（characters_view_test：F-65 seq 组 + F-67 覆盖组同点追加——手工解决顺序共存，补 F-65 组闭合后 analyze 0 + 22 测绿）。
- **门禁链**：全量 **1518 测**绿（1500 + 3 + 10 + 5 精确）/ analyze 0 / 联合审核 **0 阻断**（F-56 终态路径职责链完整、F-65 seq 契约成立、冲突解决核验通过；N 观察均非阻断）。**技术债候选区清零**。
- **过程遥测**：子智能体 4（Implement×3 + 审核）；合并冲突 1（手工解决）；flaky 0；技术债闭环：F-52~67 全序列处置完毕（AR-1 消费 F-52/55/56②③、AR-5 消费 F-64/65②①、AR-6 逆向 F-53/54、折回 F-59/63/66/56/65/67、复核关闭 F-57/58/60/61/62）。

## 技术债折回批次 F-66 — 「回复中断」小标语义断言落位（2026-09-09 — 技术债折回直落，最小闭口）

- **交付**：TDD 首写断言 → **首跑即绿**（「回复中断」/「已停止」小标已在 `_AssistantBubble` 气泡内容 MergeSemantics 外成独立可读 label 节点——屏读可达，未触发最小语义修复）→ **零产品代码改动**；并列对照双锁 2 断言（断流面锁「回复中断」findsOneWidget + 「已停止」findsNothing / 停止面反向——标注界互不污染）+ ExcludeSemantics 突变双红还原实证（非恒真）。commit `d2fce63`，merge `34bd231`，基线 f55bbee。
- **门禁链**：全量 **1500 测**绿（+2）/ analyze 0 / semantics_test 17/17（既有 15 保绿）/ 审核 0 阻断（灵敏度独立复现；N 观察：文本锚非结构锚低位风险〔虚绿需文案撞车〕/ find.text 类型敏感〔RichText 化假红〕/ 时序硬编码〔fake async 确定性〕/ stream_wire 预置 flake 无关）。
- **过程遥测**：子智能体 2；flaky 0（stream_wire 预置时序 flake 观察，非本 diff）；技术债闭环：F-66 ✅ 已修——**三轮折回（F-59/63/66）全收口，候选区 5 条**。

## 技术债折回批次 F-63 — 光标 reduce-motion 面缺口收口（2026-09-09 — 技术债折回直落）

- **交付**：① `blinking_cursor_reduce_motion_test` 补同挂载 MediaQuery disableAnimations 翻转用例（静态→闪烁恢复 + zone 零异常）；② 瞬态修复——`..value=0.0 ..repeat(reverse:true)` → `repeat(reverse:true)`（SDK `_RepeatingSimulation._initialT` 按当前 value 计算，翻转帧 opacity 连续 1.0 不落下界 0.25 暗帧；reduce 停闪语义零动）；③ `_appliedOnce` 注释修正（真实作用 = 防无关 didChangeDependencies 重跑闪断，非 Ticker 泄漏——repeat 自 stop）；④ `large_text_probe_test` 流式占位面真实触发（发送 + 10 token 长流 + 60ms 积累 + 上滑强制构建 + 1.3x 无溢出；改回空 provider 必红实证——原为永不触发伪测试）。commit `3b929f4`，merge `31d3056`，基线 f7b90fe。
- **门禁链**：全量 **1498 测**绿（+2）/ analyze 0 / chat_view 92.5%（守卫行全覆）/ 先红后绿（红 Expected 1.0 / Actual 0.25 + 流式面 0 个 ▍）；code-review 四轴 **0 阻断**（② 机制 SDK 源码链独立复核成立、验收 2/4 红阶段独立复现、4 N 观察均既有形态〔format 基线常态/重复 setup/上滑 12 次上限/transient 代理指标〕）。
- **过程遥测**：子智能体 2；flaky 0；回退 0；技术债闭环：F-63 ✅ 已修。

## 技术债折回批次 F-59 — 角色卡语义按钮守卫对齐（2026-09-09 — 技术债折回直落）

- **交付**：`characters_view.dart:347` `Semantics(button: true)` → `button: selectionMode`（对齐游戏卡 `button: onOpen != null` 同构守卫——tap 有效才宣告 button；常态非多选 onTap null 不宣告、长按进多选手势由 hint「长按可多选」描述且三态保持）+ characters_view_test 双态/退出往返断言 + **semantics_test.dart 镜像断言同步**（M6-03 验收 4 同源镜像、doc 自指 characters_view_test——方案 A 影响面扩展，主会话批准，零生产代码改动）。commit `672b9d8`，merge `f6fd709`，基线 506a125。
- **门禁链**：全量 **1496 测**绿（+1 往返测试）/ analyze 0；变异灵敏度（mutant revert 守卫 → 常态 + 往返 + 镜像 3 用例红，证据口径 2 用例为单文件口径——实际更高）；code-review 0 阻断 / 6 验收全 PASS（守卫同构 flag⇔tap 同帧核验 / 行为变更面收敛 grep 无其他消费方 / 文件范围 3 文件成立）。**行为变更**：TalkBack 常态角色卡不再宣告「按钮」（修复目标——对齐实际可点性，随交付汇报）。
- **过程遥测**：子智能体 2（Implement + code-review）；flaky 1（stream_wire_test connectTimeout 时序——标记 flaky:true 记入证据，与 F-59 无关）；覆盖率 87.6%（守卫行全覆；缺口 12.4% 为既有非 seam 路径〔刷新失败/向导/批删确认/勾选 onChanged/:351 tap 未覆盖〕→ 落债 F-67）。
- **知识库**：无新教训（TDD 双态断言/镜像同步为既有模式，不蒸馏）。

## 架构深化批次 AR-4/5/6 — WebView 能力面 / 断流生命周期 / 组件协议面（2026-09-09 — improve-codebase-architecture 候选 4/5/6 直落）

- **AR-4 WebView 能力面**：新模块 `lib/services/simulator/webview_capability.dart`（对齐 AGENTS.md:19 平台薄层归 services/）——统一能力接口（握手 + runJavaScript/evaluate + navigate + buildView，不暴露 setOnPageFinished）+ 构造期委托注入工厂（F-43/W5 B1 契约结构化，委托必达形态消费点不可违规）+ 生产适配器 webview_flutter 唯一引用点；共享假件 `test/support/fake_web_view_capability.dart`（evaluate 双编码契约复刻）；两消费点差异面（求值形态 + navigate 错误策略 run 上抛/sheet 吞错）；CONTEXT 登记「WebView 能力面」「页面就绪握手」。commit 3ff295a（+N-F1 修复 8222614：假件键名分支单编码→双编码——M5 缺陷#1 教训复核，突变 NF1-B 红实证真契约错即破面板），merge 8e6f1e8 + dead8b6。门禁：198 测 / 覆盖 100% / 审核 0 阻断（委托必达形态专项核验成立）。
- **AR-5 断流生命周期**：`hasRetryableInterrupted` 判据入 chat_round（controller 纯转发）；`RegenerateResult.replacedMessageId` 结算键（F-64：_resolveLastAssistantId 删除，末条判定唯余 _resolveRegenerateTarget）；三条件结算（配对门 !removed||target!=replacedId 早退 / 推进 target=max(marks) / 文案门才 clear）——F-65② 条件清理 + F-65① 目标推进关闭，F-4 配对门回归逐位保持；CONTEXT 登记「截断回复生命周期」「重生成替换目标」。commit 6dc67ad，merge 5172e34。门禁：chat 域 224 测 / 覆盖 96.71% / 三处突变全红 / B1 双锚零改动 git diff 实证 / 审核 0 阻断（4 N 观察：1 doc 措辞已修 + 3 既有形态）。**产品语义确认点**：推进到旧截断后重试 = 「从截断点重写后续全部消息（有界删旧，桌面 mirror 重新生成语义）」——实证今天已存在（横幅重试非末条截断可触发），本票仅扩展入口不新建语义。
- **AR-6 组件协议面**：EmptyState.action + StatusView.hint 死参数删除（**逆向 F-53/F-54 W1 复核关闭**——TP-4 授权删除路径 + 审计收敛投机面，处置记录补逆向说明）；锚句改写（TP-4 决策保留）；NoticeBanner 零 diff 承重墙（140ms 双向 + _dismissingNotice 守卫 + onDismiss 契约逐位，审计确认守卫归属正确非浅模块症状；F-65④ 续期 + 关闭成本陈述存档）。commit fefe870，merge 7089384。门禁：1489 测 / 双组件覆盖 100% / 审核 0 阻断 0 非阻断。
- **全批收口**：**期末全量 1495 测全绿 / analyze 0**；技术债流转：F-52/55/56②③（AR-1）+ F-64（AR-5）+ F-65②①（AR-5）+ F-53/54 逆向（AR-6）+ F-56 缩减 = 候选区 9 条 → 剩 **F-57/59/63/65③④/66**（5 条开放）；AR 批次 6 票全收口。

## 架构深化批次 AR-3 — 凭据解析链单一归属（2026-09-09 — improve-codebase-architecture 候选 3 直落）

- **交付**：新模块 `lib/services/llm/credentials_resolver.dart`（纯 Dart 深模块——四 reader 注入 defaultProvider/defaultModel/apiKey/baseUrl + `ResolvedCredentials{provider, apiKey, model, baseUrl?}` + `CredentialsResolver.resolve({providerOverride, modelOverride})`，镜像桌面 resolver.py::resolve_llm）收编 4 组合点（chat `_resolveProvider` conv 覆盖 / doc-parse parse catch→DocParseError 422 文案逐字 / simulators_view 生成组合包裹 GenerationCredentials；**hook（simulators_hooks）Key 注入契约变体 openai-only 零接触独立单源**）；空 key 抛点统一入解析器（复用 ApiKeyMissingError 类+文案零新增）；ChatService/DocumentParseService 构造加可选 resolver 参数（缺省既有装配零 churn）；CONTEXT 登记「凭据解析链」。commit `8810e0f`（merge `33cdc77`），基线 a6b0070。
- **门禁链**：规则矩阵 A1-A6（15 用例纯注入零 flutter）+ 范围 754 测全绿（chat 71 / doc-parse+layer 26 / injection+run_view+generate_dialog 75 / game_gen+wizard 68 等）/ analyze 0；覆盖率 100.00%（新模块 11/11）；**变异抽查**：删空 key throw → A3/A6 红、忽略 provider override → A1/A6 红（灵敏度实证）；code-review 四轴 **0 阻断 / 5 非阻断**（缺结尾换行已补 / DEV_LOG 记录本批补 / F1-F2 纯读 await 顺序角落观察〔理论双失败角落错误来源、空 key 省读，正常操作不可观察〕/ A1 装配接线三处同形重复——共识已明示 tradeoff 可接受）。**可观察行为零变更**（B1-B3 内部委派、B4 hook 零 diff）；api_config_section key.isEmpty 表单值路径 grep 实证零槽链引用未误收编。

## 架构深化批次 AR-2 — 停止完成契约（2026-09-09 — improve-codebase-architecture 候选 2 直落）

- **交付**：停止完成信号（stop completion signal）落位 ChatService——`_StreamRunState.userWriteSettled` Completer 门 + `_runStreamReply` user 写后 complete + 终态兜底（写成功 / DomainError / LLMError / 未预期 catch 四条终态路径门必结算）+ `_stopStreamReply` 置 stopped 后先 await 门（3s 有界 F-17 同款 + try/catch 对齐 F-55 结构保证）再走既有收尾；`sub.cancel()` resolve 结构性保证「已发 user 写已结算」。chat_round 删除 F1 轮询补偿（`_awaitInFlightUserLanded` 20ms 轮询 ≤3s + 1s 单轮查询超时 + `_roundUserText` 死字段），「会话内/入口态后台流」两条腿与 F3b 补标**保留**（共识事实校准：两腿因标记放置位置而非 user 写时序，任何契约形态都不改变两腿结构）；chat_round 的 `_messageRepository` 依赖保留（F3b 末条判定 / regenerate 目标解析）。F1（候选 5 批次走查发现编号）随轮询删除**自然关闭**（非 TECH_DEBT 独立条项，已核实）。commit `9be52cd` 入 `kickoff/ar2-stop-contract`（merge `a6b0070`），基线 ba8830a。**自审修复**：首版门只在 finally 结算 → 与 `controller.close()` 完成（依赖 onCancel 收尾）形成闭环，终态错误路径取消卡满 3s（诊断实证）——门改在三 catch 内、close 之前独立结算（`_settleUserWriteGate`），finally 保留为兜底 + 2s 上界回归断言锁定。
- **门禁链**：范围 134 测全绿（chat_service 70 / chat_round 21 / chat_controller 43）+ analyze 0；覆盖率按本工单 2 lib 源文件（chat_service.dart + chat_round.dart）口径 **98.90%**（359/363）；**先红后绿**：S1（门确定性——Expected false / Actual true，未实现前 cancel 在 user 写结算前即 resolve，实现后门等待到位绿）+ S2 改造（A3 无部分内容删 `_until` 预等，`await sub.cancel()` 即闩锁，改造后绿）；R4（立即停止契约，wireRound 注入门控仓储）新增随实现绿；双突变灵敏度：删门等待 → S1 红、删 catch 级门结算 → 死锁回归红。
- **行为变更点（交付汇报）**：B1 stop 的 in-flight user 落库等待由 UI 层每 20ms 轮询 MessageRepository（3s deadline + 1s 单轮超时）反向推断服务层时序 → 前移为 ChatService onCancel 内部门等待（`sub.cancel()` resolve ⟹ user 写已结算），UI 推断逻辑消亡；B2 `_stopStreamReply` 时序升级「置 stopped → await 门 → cancel → persist → close」。
- **测试面**：chat_service_test 增 S1（Completer 门确定性零墙钟）+ 改 S2（删 `_until(user 落库)` 预等）+ S3 注释（F3 终态兜底 / 停滞 provider 已产出 token 门已完成）；chat_round_test 增 R4（立即停止契约）并给 wireRound 测试辅助加 messageRepository 注入；chat_controller_test F1 端到端（`_SlowMessageRepository` 慢落库 200ms）保留为行为锚，注释更新为「契约保证 cancel resolve 后 user 已落库」。


- **门禁链**：范围 134/134 全绿（chat_service 70 / chat_round 21 / chat_controller 43——S1 门确定性 + S2 改造 + R4 立即停止契约 + 死锁 2s 上界回归 + 门超时兜底回归；chat_round_test 既有测试零删改、F1 行为锚仅注释）；analyze 0；覆盖率 **98.90%**（359/363，2 lib 源文件口径；未覆盖 4 行防御/不可达面诚实披露）；**先红后绿**：S1（红 Expected false/Actual true → 绿）+ 突变①删门等待红 / 突变②删 catch 级结算 → 死锁回归红（灵敏度实证）；code-review 四轴 **0 阻断**（死锁修复完整性经突变①②复现承重；N-S1 merge hash 占位已回填 / N-S2 DEV_LOG 格式批次先例 / N-ST1 dispose 注释陈旧观察 / N-AR1 测试 helper 跨文件重复观察）。可观察行为零变更（轮询删除为内部实现委派）。
## 架构深化批次 AR-1 — wire 连接相位编码（2026-09-09 — improve-codebase-architecture 候选 1 直落）

- **交付**：双子类 `ConnectPhaseInterruptedError`/`ReadPhaseInterruptedError` extends `LLMConnectionInterruptedError`（基类 concrete 升格「不可重试兜底信号」）；wire 三抛点相位映射（connect 段 2 catch → Connect / 读段 2 catch + !reachedTerminated → Read）；重试判据单行 `error is ConnectPhaseInterruptedError` + `producedToken` 字段与 `!producedToken` 判据删除（ConnectPhase 构造性保证无 token）；F-55 结构保证（try/catch 包 cancel().timeout——Dart `Future.timeout` 无 onError 参数事实校准 + 落库/close 收尾进 finally）；F-56 ② 注释失真 / ③ N4 两层拼合断言 / flake 容差收编（① 假活终态化排除续期）；CONTEXT 登记「连接相位/读取相位」。commit 613fcd4（merge 89fd1bf），基线 c5e5ce7。
- **门禁链**：范围 183 测（errors 28 / wire 17 / chat_service 67 / claude 37 / openai 34）+ 受影响 92 测全绿 / analyze 0；覆盖率 99.32%（291/293，3 源文件口径，2 未命中为既有面诚实披露）；**先红后绿**：F-52（B3 红 callCount 2→绿 1）/ F-55（B5 红错误穿透 :590→绿收尾完整 zone 零异常）/ B4 idle（红→绿）+ 三处突变抽查灵敏度；code-review 四轴 **0 阻断**（B1/B2 影响面核验干净无回归；N-F1「ConnectPhase 无 token 依赖 wire 构造」标未来 provider 扩展复核点；N-S1 TECH_DEBT 流转已补）。
- **行为变更点（交付汇报）**：B1 首 token 前 idle 断线由「可重试」收窄为「read 相位不重试」（M6-06 契约面收窄，消解 F-58 观察的 ≈3.5 分钟静默 + 杜绝重复计费）；B2 基类语义升级为「不可重试的断流兜底信号」（生产抛点全迁叶子）。
- **过程遥测**：子智能体 4（Grilling ×1 两轮 + Implement ×1 + code-review ×1）；回退 0 / 冲突 0；空返回 0；技术债闭环：候选区 9 → 7（F-52/55 已修移出 + F-56 缩减）。

## M6 kickoff 批次（2026-09-08 — project-kickoff 全自动档交付：去 AI 味打磨）

- **交付**：Grilling 共识 5 真拍点全按推荐 A 定案（⚑1 克制动效子集 8 项 / ⚑2 聊天链路弱网重连自建不引 connectivity_plus / ⚑3 实用层无障碍含 F-73 授权 / ⚑4 空态不加操作入口 / ⚑5 视觉评审走查清单+基线对照）。11 票 7 波次 DAG：W1 01‖04‖06（空态/状态组件抽离 + F-73 浅色 accent #784E14 族对比度 ≥4.5:1 + 连接阶段重试 2 次退避 1s/2s）/ W2 02‖09（NoticeBanner 抽离 + idle timeout 60s）/ W3 03（语义覆盖：气泡 MergeSemantics「角色名: 内容」/装饰排除/卡片 button/tooltip 审计，controller 加只读 activeCharacterName）/ W4 05（1.3x 六面探测零溢出 + reduce-motion 光标停闪，Falsify 抓 _appliedOnce 首帧守卫 bug）/ W5 07‖10（ConverDurations 三档 token + tab Fade 160ms 无保活 + SnackBarTheme + a11y 15 断言）/ W6 08（断流「回复中断」标记 + NoticeBanner 重试 regenerate replace）/ W7 11 视觉评审验收（8/8 PASS）。**Lane U 串行链** 01→02→03→05→07 单 agent 连续 + 第 5 票后链中重启点换新 agent 接 08；Lane W 06→09。合并链 f2391b3→0772c80→df25274→6b03d2c→80512e3→14a49a7→3226a4b→b115c3a→48a31b9→f32db5f→c70ae8b→0118b6a→06673bf→9221a9f→4ba0635。证据 `.scratch/m6-kickoff/evidence/`（01~11 + B1 附录）+ 37 张截图 `11-visual/`。
- **门禁链**：全量 **1460 测**全绿（基线 1360 → +100）/ analyze 0 / MUTATION 残留 0 / 全局覆盖率 **96.78%**（5839/6033，剔除 app_database.g.dart，手写口径同既往）/ 波末增量审核 ×6：W5 B1（NoticeBanner 消失过渡缺失——组件改 StatefulWidget + AnimatedOpacity 140ms 双向 + 调用点去条件渲染；半成品 AnimatedSize 命中区 bug 移除）+ W6 B1（图标 regenerate 与横幅重试双路径清理分歧→死重试按钮——`_interruptedNoticeTargetId` 单一来源 + 双路径收敛共享腿）均派回修复 + 突变红→绿回归断言（变异 A 5 例红/B 红）；**期末四轴阻断 0** / 非阻断 12（S 2 + Falsify 9 + Arch 1——S-N1 DBG print 残留与 S-N2 缺换行已顺手修 9221a9f；F-52 计费 gap 复核留债下批优先；A-N1 目标解析重复落债）；**M6 门视觉评审 PASS**（AVD medium_phone）：§5.2×5tab×双主题（grep 0 BoxShadow/Gradient/UI emoji + 像素采样 + vision）、动效代码级（8 处/时长 token 对齐桌面/零动画库）、空态 7 处+错误态 4 型、断流「回复中断」vs「已停止」两标互斥、弱网单测复核、a11y 语义树+15 断言（TalkBack 可选未做标注）、浅色 accent 实测 7.32:1/深色 8.71:1、logcat FATAL=0；**B1 核心路径模拟器实测**（断流→图标 regenerate→小标消失+横幅消失+replace 完整回复+user 行不重复；横幅重试同链路）。
- **过程遥测**：票 11 + B1 修复 2 + hygiene 1；波 7（W1 三 agent 并行、峰值 3）；子智能体 24+（Grilling/plan-tickets/Implement×11 含重开×2 接续×2/code-review×6 增量+1 期末）；**网关 TLS 断连 W1 三连**（首派运行 ~36min 后断连、无 usage、worktree 半成品在盘——04 colors+contrast 测试/06 六文件半成品；半成品接续优于重写复证）；**暂停/恢复一次**（用户「保留进度先暂停」→ TaskStop 两在途 agent → SendMessage 不可续接（No active task）→ 新 agent 现场核查接续：07 WIP 固化 + 同步主分支 + 冲突 ort 自动合并（chat_view_test 双方改动不同区段共存）；11 复用 12 截图 + mock SSE 成果）；空返回 0；回退 0；**合并冲突 1**（07/08 B1 同触碰 chat_view_test——ort 自动合并不同区段，grep 复核双方改动在位）；审核 findings：波末 6 轮 2 阻断 + 22 非阻断、期末 12 非阻断。**技术债净增**：候选区 0 → 9（F-52/55/56/57/59/63/64/65/66 开放 + F-53/54/58/60/61/62 关闭 6 条）。
- **知识库蒸馏**（2026-09-08 distill-lesson）：无新笔记（查重命中 3 条既有同根因条目，按防膨胀更新）——《worktree半成品现场续用重开模式》补「用户暂停 + TaskStop 后不可 SendMessage 续接 → 新 agent + WIP 固化现场核查」场景、《网关故障期kickoff批次韧性处置》补「并行首派 TLS 断连三连 + 立即重开 + 半成品接续」形态、《同文件并行追加段的合并重构法》补「ort 自动合并不报错 ≠ 双方向都在 → grep 复核锚文本」实证。

## M6 kickoff 预检（2026-09-08 — project-kickoff 全自动档，工程目标 = M6 去 AI 味打磨）

- **知识库预检**（库路由：mobile 仓库无 KNOWLEDGE_BASE.md → demo 库注册表命中 Conver System → 回退 demo 库，补登记提示随 Neat）：persona 已读（L3：全自动档偏好 / 深模块 / 单一事实来源 / 模拟器 GUI 冒烟纪律〔tap 坐标 UI 树实测 + 像素 PIL 采样 + 基线先采样〕/ widget 测试平台依赖 timeout 兜底 / 覆盖率口径剔除 drift 生成物）；经验精读 3 条（预算内）：《Flutter测试碰平台依赖必须超时兜底》《模拟器GUI冒烟tap坐标须UI树实测》《模拟器截图像素采样须PIL解码》（SSE done 分支/瞬态断言/运行态基线等 6 条摘要级复用，不精读）；守卫反查无缺摘要笔记。召回轨迹记于此。
- **工程 preflight**：基线 `d5b8c03`（mobile 分支，M5+TD-1~4 后 origin 未推）；`flutter test` 1360 测基线全绿；git worktree 可用（遗留 m4/m5/td* 多 worktree 待 Neat）；主分支 mobile 存在。
- **技术债预检**：TECH_DEBT 候选区 0 项（TD-1~4 清零），无待消费候选；TICKETS 活跃 M6/M7（本批认领 M6）。
- **交付形态**：源码跑通（全自动档默认 a，仅汇报）；M6 门 = 模拟器视觉评审走查。
- **先搜开源预检**：无领域轮子清单命中；潜在候选 = connectivity_plus（网络状态监测，弱网重连可能引入，待 Grilling 拍板）、flutter 原生动画框架 + Semantics 为平台覆盖优先复用。
- **M6 范围快照**（TICKETS）：动效/空态/错误态/无障碍/弱网断线重连，验收 = 视觉评审；权威依据 = `docs/mobile-design.md` §5.2「去 AI 味」明确清单（❌ 紫蓝渐变/发光描边/吉祥物 emoji 图标/果冻卡片/大留白小字号/typing 三点；✅ 单点琥珀强调/低饱和暖灰层次/1px 边框分割/统一线性图标/信息密度适中）+ §6 交互表（触屏消息操作/停止红色大按钮/键盘适配/安全区）。

## 技术债消费批次 TD-1~TD-4（2026-09-07 — 用户「消费 F-25~F-51」显式立项，27 条候选全处置）

- **交付**：候选区 27 条（M5 波末增量审核 + 期末四轴非阻断落债）全部处置——**19 待修拆 4 工单 2 波**（波1 398d610：TD-1 异常链 9e8f696〔F-25 种子单游戏缺失降级 / F-31 refresh in-flight 守卫 / F-32 种子错误路径文案 / F-33 timeout 取消底层〕+ TD-2 契约层 1f64ef4〔F-27 导入整包拒对齐 / F-29 manifest 深度兜底 / F-34 import 超时取消令牌补偿 / F-38 枚举分片 / F-39 BOM 容错〕；波2 027bcd3：TD-3 hooks/注入 4677597〔F-35 合成器 doc 对齐 / F-36 占位符碰撞熔断 / F-43 run view 委托先挂对齐 save_sheet / F-44 死合成器清面〕+ TD-4 生成链路 ed8dfbd〔F-40 校验大小写统一 / F-45 409 已存在终止重试 / F-46 取消拦在途 / F-47 空描述兜底 / F-48 标题净化 / F-49 死分支清理〕）；**8 复核关闭**（F-26/42 M5 内已修、F-28/30/37 桌面同构或契约边界、F-41/50/51 设计意图）。候选区清零。
- **门禁链**：全量 **1360 测**全绿（M5 终 1315 + 新增 45）/ analyze 0 / MUTATION 残留零命中；4 工单均 TDD 红→绿 + 覆盖率 ≥90%（96.1% / 99.5% / 100% / 98.25%）+ 突变抽查 ≥2 处灵敏度实证。
- **波内复核修正 3 条**（审计快照过期须复核惯例）：F-27 核对桌面 save-manager.js——JS 对象键恒字符串、桌面无「非字符串键拒绝」路径，移动端行为即桌面等价，不改行为只补 docstring 结论 + 3 锚测试；F-29 实证 Dart 3.13 jsonDecode 为迭代解析器（400 万层不溢出），StackOverflowError 当前 VM 不可复现——改确定性深度预扫（maxManifestDepth=4096）+ on StackOverflowError 二道降级；F-39 实证当前 SDK utf8.decode 已剥离 BOM——改显式 `_stripBom` 防御 + 可观察契约锚测试。
- **过程遥测**：票 4、波 2、merge 3；子智能体 4（Implement×4）；空返回 0；回退/冲突 0；审核 findings 0（消费批次按 TDD 自审 + 全量门禁，未派 code-review——19 条均为审核已定位的单点修复，复核由波内 Implement 自审 + 主会话全量复验承担）；技术债净增 0（候选区 27 → 0）。
- **避坑（勿重蹈）**：
  1. **「消费」≠「全修」**：27 条按强度与现状分类——8 条复核关闭（已修 2 + 桌面同构 3 + 设计意图 3）不硬修，Speculative 级「git grep 复核现状仍成立后处置」路径（F-27/29/39 三条复核出审计前提变化，按实证修正处置而非盲修）
  2. **F-43 与 W5 B1 同构缺陷跨票蔓延**：同一「先 loadRequest 后挂委托」模式出现在两个 seam（save_sheet 已修、run_view 未修）——同构缺陷要在**首次发现时 grep 全仓同类模式**一并处置，不留给期末
  3. **波末声称的「结构状态」会随后续波失效**：W6 B1 改 wireViewDefaults 后，W5/W6 波末声称「四合成器共存」的 append* 合成器全部失去调用方（F-44）——结构重构后必须重 grep 消费方，不沿用旧波结论
- **知识库蒸馏**：候选教训（WebView runJavaScriptReturningResult 跨平台 JSON 编码契约 + fake 契约 / onPageFinished 事件委托时序 / tab 往返死 context / 同文件并行追加合并）——完成段经 distill-lesson 处理（3 新笔记 + 1 更新）。

## M5 kickoff 批次（2026-09-07 — project-kickoff 全自动档交付：模拟器里程碑）

- **交付**：Grilling 共识 16 增量决策 + 5 真拍点按推荐 A 定案（⚑1「我」页=设置页内三占位 / ⚑2 AI 生成入 M5 / ⚑3 冒烟五游戏集+量化口径 / ⚑4 固定端口 8642 / ⚑5 手册 13 节全改写）。11 票 7 波次 DAG（W1 01‖05 / W2 02‖10 / W3 03 / W4 04‖07 / W5 06‖08a / W6 08b / W7 09）。**模拟器全量**：22 款游戏随包种子（manifest 后落盘幂等）+ dart:io 本地 HTTP 托管（固定 8642，路径穿越守卫，Android network_security_config + iOS ATS LocalNetworking）/ 列表页四态 + 懒启动编排 + AppBar 三入口 / Key 注入桥（runJavaScript 自包含脚本，桌面 key-injector 契约逐字：三元组白名单/endpointMode/受管 option/幂等/双事件 + 就绪轮询 ≤5s；claude key 恒不进）+ 官方端点提示条 / 存档桥（契约层纯 Dart 对拍桌面 save-manager 边界矩阵 + 底部半屏 sheet 一次管全部 + 导出分享复用 M4 seam）/ 导入链（净化/SHA-256 去重/cfg 三层探测/恶意粗筛 + 拒绝清单二次确认 + manifest 原子写）/ AI 生成（种子模板 + 六项校验 + 重试 ≤3 + 对话框）/ 「我」页（手册 13 节移动端改写 + 关于 + 桌面版说明）。基线 dfafeb7 → merge 链 90064ca→ebdea6d→843de68→ed5d738→b7e61a2→7f4a4bf→41db74a→87e83c7→6ecf19e→9237bbf。证据 `.scratch/m5-kickoff/evidence/`。
- **门禁链**：全量 **1315 测**全绿（基线 827 → M5 +488）/ analyze 0；波末增量审核 ×6 全零阻断（W1/W2/W3 零阻断；W4 B1〔MUTATION 残留+排序契约未隔离〕/ W5 B1〔save_sheet onPageFinished 事件丢失竞态〕/ W6 B1〔tab 往返死 context〕各派回修复 + 防复发回归断言）；期末四轴阻断 0 / 非阻断 18（Standards 6 / Spec 0 / Falsify 12 / Architecture 2，安全红线 0 违例；落债 F-43~F-51）；**M5 门冒烟 PASS**（AVD medium_phone API 35）：Q11 CORS 复验（DeepSeek 放行 401 vs Anthropic 官方拦截 TypeError 双侧对照 + 官方端点提示条逐字 + claude key 无 sk-ant 值进 WebView）/ Q12 force-stop 重启存档持久化（leveldb 字节完整）/ Q10 五游戏（人生模拟器/仿微/小马宝莉/暮色女巫/许愿柳）25/25 轮 App 零 FATAL/ANR + 注入三元组读回 + 受管 option 追加实证（deepseek-v4-flash 不在默认列表被追加）+ 15s 超时守卫实测（死循环 HTML + 重试恢复）+ 导入有效/恶意拒绝/二次确认放行 + 生成失败路径 UI。
- **波末 B1 三连（修复均含防复发断言）**：① W4 B1 `// MUTATION: sort REMOVED` 残留 + scanSuspicious 排序契约未测试隔离 → 删残留 + doc 对齐键序契约 + 「输出序==keys 声明序」逐元素断言（对抗演示：keys 非字典序 + sort 恢复 → 断言红）；② W5 B1 save_sheet `onPageFinished` 事件丢失（loadRequest 先于委托挂载，webview_flutter 不回放挂载前事件 → loaded completer 永不完成 → 8s 超时恒/偶发降级；单测 fake 模拟良性时序）→ seam 改零参工厂 + navigate 方法，委托先挂后导航 + 调用序 spy 回归；③ W6 B1 tab 往返后 AppBar 四入口闭包持有已卸载 State 死 context（HomeShell switch 直接切换无 IndexedStack，`if (slot != null) return;` 守卫短路不重接）→ wireViewDefaults 每次挂载刷新 + 四闭包 mounted 守卫 + 重挂载回归断言。
- **冒烟产线缺陷修复**：SaveSheet Android 恒 0 键（缺陷#1）——Android `evaluateJavascript` 返回**编码 JSON 串**（外层引号）经 `runJavaScriptReturningResult` 原样透传 → `parseLocalStorageEntries` FormatException → 枚举空 Map；**单测 fake evaluator 返回裸 JSON 编码了错误契约** → 修复 = 解包容错（编码串再 decode 一次 / 裸值兼容 iOS）+ fake 契约修正 + 回归断言；真机复验 PASS（2 个存档 · 698 字符 + 导出 ShareSheet 弹出 + 按钮语义正确）。发现 #2（小马宝莉首启向导 wz-* vs manifest config s-*）确认**与桌面行为等价**（桌面 configIdCandidates 同语义只命中设置弹窗），非缺陷不派修。
- **过程遥测**：票 11、波 7、merge 14（含修复合并）；子智能体 20+（Grilling/plan-tickets/Implement×10/波末审核×6/期末四轴/修复×3+B1；token 累计 ≈1.6 亿）；并发峰值 3（含审核错峰）；空返回 0；**合并冲突 2**（W4b：04/07 同波顺序追加 hooks/view——手工合并双方改动成功，非冲突仲裁）；阻塞 B1 3 + 冒烟缺陷 1 全闭环；审核 findings：波末 6 轮 4 阻断 + 21 非阻断、期末 18 非阻断。**技术债净增**：候选区 0 → 27 条（F-25~F-51，全部待立项；本轮未消费——M6/M7 预检时按强度规则处理）。
- **避坑（勿重蹈）**：
  1. **并行票共享文件（hooks/view）的顺序追加不是真并行**：W4 的 04/07 都「post-03 顺序追加」hooks/view，各自 worktree 独立 commit，合并时两文件冲突——同文件顺序追加必须串行或合并时先知会；手工合并 = 双方改动都要、`import 'show A, B, C'` 合并导出、initState 双接线先后有序
  2. **webview_flutter runJavaScriptReturningResult 返回值契约跨平台不一致**：Android evaluateJavascript 返回**编码 JSON 串**（字符串结果带外层引号原样透传），iOS 返回裸值——跨平台通道契约必须在桥解析层统一容错（解包判断），单测 fake 必须模拟**生产真实契约**而非理想契约（本批 fake 编码错误契约 = 单测全绿但真机必坏）
  3. **onPageFinished 等 WebView 事件只派发给挂载时已存在的委托**：先 `loadRequest` 后 `setOnPageFinished` 会丢事件（completer 永不完成 → 超时兜底掩盖）——委托先挂、导航后发；凡是「事件驱动 + Future 等待」的 WebView 时序都必须用调用序 spy 锁「挂委托 < 导航」顺序
  4. **HomeShell switch 直接切换 tab（无 IndexedStack）= 每次切回重新挂载 State**：视图首挂载闭包持有的 context 在卸载后 defunct——「每次挂载刷新接线 + 闭包内 mounted 守卫」是唯一安全形态；单次挂载的 widget 测捕获不到卸载-重建时序，必须显式 pumpWidget 卸载重挂载
  5. **波末审核会漏「波内声称已解决、后续波改结构后失效」的死面**：W6 B1 改 wireViewDefaults 统一接线后，波末声称「四合成器共存」的 append* 合成器全部失去调用方——期末四轴才抓到（F-44）；结构重构后必须重 grep 消费方，不沿用旧波结论
  6. **MUTATION 突变标记残留**：突变抽查后未还原的标记进成品（W5 审核抓到 `// MUTATION: sort REMOVED`）——突变练习改完必须 `grep -rn MUTATION lib/ test/` 归零再 commit
  7. **AVD 冒烟 key 注入断言**：leveldb（`app_webview/Default/Local Storage/leveldb/*`）是 localStorage 持久化的**确定性证据**（force-stop 前后字节对比），比 UI 读回更可靠——存档/注入断言优先用 run-as 直读 leveldb + uiautomator 双通道
- **知识库蒸馏**：候选教训（并行顺序追加合并 / WebView 返回值跨平台契约 + fake 编码 / WebView 事件委托时序 / tab 重挂载死 context / 重构后重 grep 死面）——完成段经 distill-lesson 处理。

## M5 kickoff 预检（2026-09-07 — project-kickoff 全自动档，工程目标 = M5 模拟器里程碑）

- **知识库预检**（库路由：mobile 仓库无 KNOWLEDGE_BASE.md → demo 库注册表命中 Conver System → 回退 demo 库，补登记提示随 Neat）：persona 已读（L3：全自动档偏好 / CLI 优先 / 模拟器 GUI 冒烟纪律〔tap 坐标 UI 树实测 + 像素 PIL 采样〕/ 桌面模拟器集成先例 U7~U9·T-01/T-02〔注入契约 / 存档桥 / 导入链〕）；经验精读 5 条（预算内）：《Flutter测试碰平台依赖必须超时兜底》《模拟器GUI冒烟tap坐标须UI树实测》《中间转换层转圈丢字段》《状态发布与文件落盘顺序契约》《模拟器截图像素采样须PIL解码》；守卫反查无缺摘要笔记。召回轨迹记于此。
- **工程 preflight**：基线 `dfafeb7`（mobile 分支，ahead 2 未推送）；`flutter test` 827 测基线全绿；git worktree 可用（遗留 m4-export/m4-parse 两 prunable 待 Neat）；主分支 mobile 存在。
- **技术债预检**：TECH_DEBT 候选区 0 项，无待消费候选。
- **交付形态**：源码跑通（全自动档默认 a，仅汇报）。
- **M5 范围快照**：`assets/simulators/` 空（仅 .gitkeep，22 款游戏种子未入包）；`simulators_view.dart` 为占位；设置页「用户手册/关于/桌面版说明」仍为占位；`webview_flutter` 已拍板未落地；桌面蓝本 = `desktop/frontend/js/{key-injector(902 行),simulator-adapt(432 行),save-manager,simulator-import,simulator-contracts}.js` + `backend/app/services/{simulator_store,simulator_import,simulator_manifest,game_generator}.py` + `frontend/simulators/` 23 文件（22 游戏 + manifest）。

## 架构深化批次 — 角色字段装配收敛 + ChatRound 分离（2026-09-07 — improve-codebase-architecture 候选 4/5 收官）

- **交付**：grilling 三问全按推荐 A 拍板，落地 explore 报告最后两个 Worth exploring 候选（候选 1/2/3 已于前两批做掉）。**候选 4**（角色字段 → CharactersCompanion 装配三处收敛 + 解耦 parse 链）：删 `CharacterDraft.fromParseResult` 工厂（`character_card.dart` 不再依赖 `document_parse_service`——纯转换层解耦，零平台依赖声明恢复成立）；向导 `_applyParseResult` 改从 DocParseResult **直拷 8 个表单字段**（此前经 16 字段草稿转圈）；**修复数据丢失**（grilling 拍板）：解析出的 postHistoryInstructions 在 save 路径静默丢弃（注释声称「保留于草稿可落库」与实现不符；chat_service 对话时消费该字段注入系统提示、桌面 CharacterBase 带此字段）——现存入 `_parsedPostHistoryInstructions` 随保存落库（TDD 红测先行：解析→save→DB 断言，creator 维持 spec 恒空）；装配收敛：`save()` 改经 CharacterDraft（6 个缺省字段〔version '1.0' / alternateGreetings [] / creatorNotes {} / extensions {} / creator '' / avatar null〕下沉为构造器默认值，装配点只传业务字段）→ `toCompanion()`，drift 列名映射单一归属 character_card.dart（对齐桌面 CharacterBase 16 字段基类「消除字段清单重复重声明」先例）；edit 部分更新（Value.absent=不动，语义不同）保持原位。**候选 5**（ChatController 回合状态机与杂项职责分离）：新建 **`views/chat/chat_round.dart`**——ChatRound 深模块（协议表面 = send/stop/regenerate 三操作 + 合成消息只读状态面 + resetForNavigation/applyBackgroundStoppedMark/isStopped；实现含流订阅 / 合成消息 id / F1 停止竞态（_awaitInFlightUserLanded）/ F3b 后台补标（_backgroundStoppedConversationIds）/ _descriptiveError 映射，~250 行），**纯搬迁不动行为**（公开 API 零变化，chat_controller_test 1260 行原样绿）；ChatController 836→~500 行编排器（入口 / 导航 / 高亮 / 导出 / DB 消息与展示消息组装保留，回合面委托 `_round`〔late final 同 NoticeRunner 惯用〕+ reloadMessages 回调注入——`_reloadMessages` 改返回 List<Message> 供「已停止」标记判定）；新增 `chat_round_test.dart` **9 个独立契约测试**（打字机经 notify 录制 / 空文本与流式中忽略 / 终态 reload / 会话内停止标已停止 / 后台停止 F3b 补标 / 断流 notice / regenerate 成败 / resetForNavigation 后台流语义），证明深模块可脱离 controller 直测。
- **门禁链**：全量 **827 测**全绿（819 基线 + 修复测试 1 + round 9 − 删 fromParseResult 旧测 2）/ analyze 0；**code-review 四轴 PASS**（Falsify 8 类对抗场景逐点：postHistory 空串/纯空白与 Value.absent 落库等价、avatar 三态 insert 等价〔nullable 无默认列〕、temperature 未 clamp 与 HEAD 一致〔setTemperature 已 clamp〕、stop 双 null 分支不可达、resetForNavigation 后自然终态经 ChatDone→_finishRound 重新武装 reloadPending 仍 reload 与 HEAD 一致、dispose 后 round 回调等价〔cancel 后事件不投递〕、send 守卫顺序不敏感、_round late final 循环引用实证安全；Spec：搬迁逐字对照 + grep 零残留〔fromParseResult / 旧概念 doc〕）。非阻断 3 条全部处理：postHistoryInstructions 落库前 `.trim()` 对齐表单惯例 / 删 `_reloadMessages` null 分支冗余 `_round.clearInFlight()`（双向引用退化为单向回调，顺带删 round 公开 clearInFlight 死面）/ CharacterDraft 缺省字段下沉构造器默认值（装配点只传业务字段）。
- **过程遥测**：grilling AskUserQuestion 三问（parse 链丢失处置 / 装配收敛形态 / ChatCtrl 分离方向）全按推荐 A 拍板；候选 4 TDD 红→绿（红测 = 解析后保存 postHistory 落库断言，实测 actual '' vs 期望「保持人设」确认缺口）；候选 5 先迁后改（round 落新文件 → controller 委托 → 既有 66 测原样绿证明零回归 → 补 9 测直测契约）；code-review 子代理 ≈8.5 分钟；踩坑两次——① 断言 `streamingStopped` 在 stop 完成后为 true 失败：实际 stop 末尾 `_clearInFlight` 复位为 false（占位已由 DB 重载替换，true 只是 stop 窗口瞬态）；② 打字机累积序列用轮询录制漏末态「你好！」：最后一 token 与流关闭（_onStreamDone 清占位）同一事件循环，2ms 轮询采样不到——改经 notify 回调逐次录制 streamingText（逐 token 通知必采样）。
- **避坑（勿重蹈）**：
  1. **行为变更点先红测钉死，纯搬迁借既有测试绿证明**：候选 4 的 postHistory 落库是行为变更——先写解析→save→DB 断言（红），实现后绿；候选 5 抽 ChatRound 是纯搬迁——controller 公开面不变，1260 行既有测试原样绿即零回归证明，新测试只补「深模块可独立测」契约。两类工作分开验证，不混在一个断言里。
  2. **瞬态状态不可做终态断言**：`streamingStopped` 在 stop() 内先置 true（渲染「已停止」占位）、末尾 `_clearInFlight` 复位 false（DB 重载已替换占位）——操作完成后稳定值是 false；断言写「操作完成后的稳态」，中间瞬态依赖具体实现时序。
  3. **逐 token 累积序列用通知采样，不用轮询**：流式末 token 与流关闭清占位在同一事件循环，任何轮询间隔都可能漏最后中间态——经 notify 回调逐次录制（每次 token 事件必触发一次通知，序列完整）。
- **知识库蒸馏**：候选教训（行为变更 vs 纯搬迁分开验证 / 瞬态终态断言 / 通知采样打字机序列）——完成段经 distill-lesson 处理。

## 技术债消费 F-24（2026-09-07 — 用户「先消费技术债」指令立项：SettingsReader 契约语义收敛）

- **交付**：兜底常量**单一归属**——`settings_reader.dart` 新增 `abstract final class SettingsDefaults`（provider='claude' / model='claude-sonnet-5' / userName='User'，桌面 config.py 常量等价物）；`SettingsRepository` 三类型化 getter 的缺省填充与 `ConversationRepository._fallbackProvider/_fallbackModel/_fallbackUserName` 兜底均改为引用同一常量（原为两份字面量「碰巧相等」：接口契约声明「返回空串由消费方回退」、实现做缺省填充，任何一侧常量变动即静默破约——`settings_repository.dart:37-42` 长注释自认的诚实声明）；契约文档对齐「实现方填充」现状；`_resolveValue` 逻辑与测试 fake（返回空串）的兜底语义保留不动。**行为零变化的重构型收敛**：数据层 88 测原样绿。
- **门禁链**：全量 **819 测**全绿（F-24 后不变——纯引用替换无新行为）/ analyze 0。Speculative 级按「git grep 复核现状仍成立后消费」路径——本项因用户显式指令立项（候选区为 0，从探索报告备选源落债）。
- **过程遥测**：候选区 0 项 → 向用户澄清事实 + AskUserQuestion 从来源立项（A：立项 SettingsReader，用户拍板）；实现主会话直做（三文件引用替换 + 文档对齐，无新测试——行为不变由既有 88 测锁定）。
- **避坑（勿重蹈）**：**「碰巧相等」的隐式契约比显式重复更危险**——两份字面量靠注释自认一致时，任一侧改动静默破约（本债根因）；收敛手段是「单一归属 + 引用」而非「删一份」，因为消费方对测试 fake（返回空串）的兜底语义是真实的防御需求。
- **知识库蒸馏**：候选教训（碰巧相等隐式契约 → 单一归属引用收敛）——完成段经 distill-lesson 处理。

## 架构深化批次 — 控制器编排收敛 + LLM 流式骨架收敛（2026-09-07 — improve-codebase-architecture 候选 2/3）

- **交付**：grilling 共识 4 问全 A 落地两个 Strong 候选。**候选 2**（控制器超时/notice 编排去重）：新建 **`services/notice_runner.dart`**——[guard] 统一「try / await / `.timeout` / 错误折叠 / 先错者胜 notice」骨架（`timeout` 缺省 3s；[set]/[clear]/[setFirst]/[onChanged] 通知），替换 chat + characters 两控制器 `.timeout(3s)` 6 处 + notice 编排 12 处；专项错误（CardFormat/CardValidation）折叠进 guard.onError switch（单一错误路径）；loading 标志（`_loading`/`_loadingEntry`/`_creatingConversation`/`_exporting`/`_isRegenerating`）各自保留（并发语义不同不硬扭）。**候选 3**（LLM 流式 wire 骨架收敛）：新建 **`services/llm/stream_wire.dart`**——[streamSse] 共享骨架（POST + SSE 消费 + 非 200→HttpStatusError + **消费阶段**断连→LLMConnectionInterruptedError + 未终态 EOF 兜底 + finally 强制关连接，~45 行取代原 ~50 行 ×2 逐行同构）；claude/openai `_streamRequest` 只剩差异面（端点/头/终态/帧提取/errorFrameException 工厂——claude 流内 error 帧保持私有 `_StreamApiError`，openai 传 null，M2 双协议决策不破）。**行为变更点（有意统一，审核确认）**：① regenerate/_export 失败 notice 从「直接覆盖」统一为「先错者胜」（其余 10 处本已 first-wins，此两处是异类收编）；② loadEntry 第二查询（listCharacters）失败保留已成功加载的对话列表（原为清空，新语义对齐 characters.refresh「失败保留既有列表」哲学）——两处均有测试钉死。
- **门禁链**：全量 **819 测**全绿（810 基线 + NoticeRunner 5 + stream_wire 9 + loadEntry 二查 1 − 结构调整净变）/ analyze 0；**code-review 四轴 PASS**（Falsify 逐点：guard 成功/抛错/挂起/先错者胜、createConversationFor 角色 null vs 查询失败的 setFirst 区分、_export result null vs 失败、streamSse headers.forEach 原样送达 captured 实证、errorFrame 中止 yield、消费方取消 finally close；Spec：文案锚 16 条逐字不变）。非阻断 6 条：处理 4（unused import 删 / 200+空体未终态测试 / **连接拒绝分层契约测试**——postUrl 阶段 SocketException 原样上抛，映射归 provider translateError 层〔openai_provider_test 端到端钉住〕/ loadEntry 二查语义测试），知悉 2（双重 notify 冗余为既有模式 / 7 参顶层函数偏浅为合理权衡）。
- **过程遥测**：用户 AskUserQuestion 四问全 A；候选 2、3 主会话直做（TDD 迁移风格）+ code-review 子代理 ≈15 分钟；踩坑两次——① NoticeRunner 字段初始化器引用实例方法须 `late final`（`onChanged: notifyListeners` 在构造期不可用）；② **Dart 3 事实修正：`StateError extends Error` 不是 `Exception` 子类型**（二者是兄弟接口）——errorFrameException 工厂返回自定义 `implements Exception` 类型（claude `_StreamApiError` 同构），流式连接拒绝测试因此改断言为 SocketException 上抛而非折叠。
- **避坑（勿重蹈）**：
  1. **ChangeNotifier 字段初始化器不能引用实例方法**：`final x = Runner(onChanged: notifyListeners)` 在字段初始化期无 this——用 `late final`（首次访问时 this 可用）或构造体内赋值。
  2. **Dart 3 中 Error 与 Exception 是兄弟接口**：`StateError is Exception` 为 false（与 Dart 2 直觉相反）——「异常工厂返回 Exception?」时具体错误类型必须 `implements Exception`；测试也据实调整（连接拒绝分层契约）。
  3. **「覆盖 → 先错者胜」收编是行为变更**：老代码两处失败 notice 直接覆盖（regenerate/_export），统一 first-wins 后若既有未清 notice 会保留旧错——有意为之（与其余 10 处一致）但必须记入变更说明，且失败的文档/测试同步。
- **知识库蒸馏**：候选教训（ChangeNotifier late final 初始化器 / Dart3 Error≠Exception 子类型 / 收编行为变更要测试钉死）——完成段经 distill-lesson 处理。

## 架构深化批次 — 文件交换平台腿收敛（2026-09-07 — improve-codebase-architecture 候选 1）

- **交付**：grilling 共识（Q1=共享腿 / Q2=safeFileName 挪纯逻辑 / Q3=删死面 / Q4=新建模块 / Q5=组合级）落地的第一深化候选。新建 **`services/file_name.dart`**（safeFileName 纯函数迁出平台 seam，纯函数归纯处）+ **`services/platform_file_exchange.dart`**（typedef 三枚收敛 + `writeTempAndShare` 组合级共享腿〔临时目录带超时 → 写盘 flush → 分享带超时，StateError 文案单一归属〕+ `pickJsonWithTimeout` + 缺省平台腿 `defaultResolveTempDirectory/defaultPickJsonFile/defaultShareViaPlus`，`coverage:ignore` 平台委托）。两个消费 seam（`character_file_exchange` / `conversation_export_file_exchange`）删除本地 typedef / `_shareViaPlus` / 平台包 import，变薄为业务数据组装 + 注入契约（构造参数名与类型名不变，消费方零改动）；删 `ConversationExportService.characterExportBaseName` 死公开面（生产零调用，规则收敛私有 `_extractCharacterName`）；`conversation_export_service` import 改向 `file_name.dart`——**平台 seam 反向依赖消除**。测试收敛：超时防御用例从两个 seam 测试移入新 `platform_file_exchange_test.dart`（6 测：成功链 + tempDir/share 挂起降级 + pick 三态），safeFileName 组迁入 `file_name_test.dart`，死面测试组删除。
- **门禁链**：全量 **804 测**全绿（803 基线 + 2 seam 接线微测试；净变化 = 新 12 − 删 9 − 接线 2 归位）/ analyze 0；**code-review 四轴 PASS**（Spec：`_shareViaPlus`/typedef 双定义/safeFileName 双定义零残留、文案锚逐字保留、`parseCharacterCardBytes` 未触；Falsify：importCharacter「pick null 与超时 null 合流」语义逐位等价、exportCharacter 信封/文件名/文案逐位等价、共享腿失败路径实测；Architecture：Locality 达成、平台包 import 收敛单点、共享腿为深模块〔协议 2 函数 + 3 typedef + 3 缺省〕）。非阻断 4 条处理 3 条：类 docstring 残留删、seam 级 `platformTimeout` 接线微测试 ×2（兜未来 seam 忘透传的盲点）、`file_name_test` 补文件头；跳过 1 条（缺省装配工厂，成本收益边缘）。
- **过程遥测**：用户经 AskUserQuestion 拍板 Q1/Q2/Q3，Q4/Q5 未答按推荐执行（系统提示 best judgment）；Explore 子代理扫描产出 5 候选 + 2 备选（HTML 报告 `D:\tmp\architecture-review-20260907.html`）；本批实现主会话直做（TDD 迁移风格：行为不变，先迁后改）；code-review 子代理 ≈5 分钟；另 4 候选（控制器超时/notice 去重 · LLM 流式骨架收敛 · 角色字段装配收敛 · ChatController 分离）待后续探索。
- **避坑（勿重蹈）**：
  1. **「收敛重复」类重构先迁后改**：平台腿收敛是行为不变的迁移——先把纯函数/共享腿落新文件（测试跟着迁），再改消费方（断言锚不动），最后删死面；每步都可独立验证，避免一步大改把行为变更混进迁移。
  2. **死面删除要同步类级 docstring**：删 `characterExportBaseName` 时漏掉类 docstring 里「文件名基公开方法」的描述——code-review 抓出的残留，收拢型改动必须 grep 全文旧概念引用（F-18 同款教训复证）。
  3. **seam 级接线测试保留一条**：超时防御收敛到共享腿后，seam→腿的 `platformTimeout` 透传只剩 happy path 隐含覆盖——每 seam 留一条「挂起 fake + 短超时 → StateError」微测试，防未来 seam 忘传参数的回归盲点。
- **知识库蒸馏**：候选教训（收敛型重构先迁后改 / 死面删除同步 docstring grep / seam 接线微测试兜透传盲点）——完成段经 distill-lesson 处理。

## 技术债消费批次 F-18/F-23（2026-09-07 — 用户指令显式立项，2 项并行交付）

- **交付**：**F-18 向导校验门收拢**（代码）：步骤②模板门从视图 `_handleNext`（`_step2Error` 字段）移入 `WizardController.next()` case 2——template 未选模板 → `_error = '请选择一个模板'` + notify + return false（不前进）；import 模式放行（不受内容影响）；`selectTemplate(id)` 补 `_error = null`（原视图 setState 清错的 controller 化）；视图删除 `_step2Error` 字段、视图层拦截块与两处 setState，`build` 统一读 `controller.error`，`onSelectTemplate` 由包一层闭包改直接 tear-off。**Locality 达成**：分步校验单一载体 = next() 的 case 1/2/3 switch（controller 全权持有，视图零校验状态）。**F-23 平台真通道冒烟**（验证，零代码）：file_picker V2 卡导入 → `com.android.documentsui` 系统选择器弹出（实测排除「弹不出」挂起风险）；批量删除长按多选手势（长按进多选自动勾选 / 点击加选计数「已选 2 个角色」/ 退出恢复）真机实证；share_plus 分面已于 M4-06 关闭 → **F-23 三分面全部闭环**。证据 `.scratch/techdebt-f18-f23/evidence/`（F-23.md + smoke-file-picker.png + smoke-batch-select.png）。
- **门禁链**：TDD 先红后绿（controller_test 新契约「template 未选拦截/已选放行」先红 → 实现后绿）；全量 **803 测**全绿（802 基线 + 测试拆分净增 1）/ analyze 0；**code-review 四轴 PASS**（Standards/Spec/Falsify/Architecture 零阻断——Falsify 实测状态流遍历 6 清错点完备、`selectTemplate('未知id')` 早退保错语义正确、视图展示等价性成立；1 条非阻断 stale doc〔视图文件头仍写「本层拦截」〕已修复）。
- **过程遥测**：立项 = 用户「消费技术债 F-18 F-23」显式指令（候选区状态 📝 → TICKETS 活跃 🔄 → 完成后归档）；主会话 TDD 直做 + code-review 子代理审核（约 8.5 分钟）；模拟器冒烟复用 M3/M4 遗留数据（知性学姐/测试助手），**零写库**（导入取消、删除未执行——避免级联污染，删除动作本身已由 26 测 batch 契约锁定）。
- **避坑（勿重蹈）**：
  1. **文档注释与技术债收拢同步**：F-18 代码收拢后，视图文件头 doc 仍写着「本层步骤②校验…本层拦截不越权」——审核抓出的 stale doc 把已消除的分置概念写回文档，误导后续把门放回视图（重新引入技术债）；收拢型改动必须全文 grep 旧概念引用并同步。
  2. **长按模拟用 adb 同点 swipe**：MCP 无长按原语，`adb shell input swipe x y x y 800`（同点 800ms）即长按手势；从 UI 树实测坐标取点（测算坐标会打偏——既有纪律）。
  3. **冒烟数据零污染原则**：验证删除/选择类手势到「入口 + 在位可点」即止，不执行破坏性动作（批量删除未点击确认），依赖单测收尾行为面。
- **知识库蒸馏**：候选教训（文档注释与技术债收拢同步 grep / 长按手势 adb 同点 swipe 模拟 / 冒烟破坏性动作止于在位可点）——完成段经 distill-lesson 处理。

## M4 kickoff 批次（2026-09-06 收口 — project-kickoff 全自动档交付：导出 / 文档解析里程碑）

- **交付**：Grilling 共识 6 票两条并行依赖链（文件范围互不相交）：链A 导出 M4-01→M4-02→M4-03→M4-06（ConversationExportService 组卷 · ConversationExportFileExchange 文件 seam · 聊天顶栏 ⋯ 菜单导出入口）、链B 解析 M4-04→M4-05（DocumentParseService 三级提取+白名单 · 向导步骤②「AI 智能解析」接入）。波1 merge **42099eb**（M4-01~03）+ **25c7696**（M4-04~05）+ 修复 **1feddd7**（m4-05 解析挂起中 dispose 崩溃，回归断言锁定）。基线 9a881cb。证据 `.scratch/m4-kickoff/evidence/`（M4-01~05 + M4-05-fix + M4-06 + smoke-share-sheet.png）。
- **门禁链（2026-08-30 合并时）**：全量 **729→802 测**（M4 新 +73）全绿 / analyze 0；M4-01~05 各票工单内覆盖率 ≥90%（如 M4-05 控制器 98.08% / 视图 99.75%）；波末增量审核 + 期末四轴零阻断（来源：M4-01~05 evidence 文件）。
- **M4-06 冒烟（2026-09-06 主会话补收口）**：模拟器 emulator-5554（AVD medium_phone API35）真通道实证——hihello 对话顶栏 ⋯ → 导出 JSON/MD → **ShareSheet 弹出 ×2**（`ChooserActivityLauncher` 前台 + UI 树 chooser_header 证据）+ `测试助手.json`/`测试助手.md` 临时文件生成（文件名=角色名净化，中文保留）+ 内容语义逐项核对（JSON：conversation/character/messages 结构 + UTC ISO 8601 带 Z + 消息升序；MD：`# 与 测试助手 的对话` + 角色信息 + 本地时间 + 日期分组 + 角色标记）+ **platformTimeout 超时兜底实测**（模拟器无分享接收 app → share_plus Future 不 resolve → 3s 超时 → StateError → 非阻塞 SnackBar「导出失败: 分享面板超时」，app 零崩溃、logcat 无 FATAL）。**结果 PASS** → F-23 share_plus 分面关闭（file_picker 与批量多选手势重定界归 M5）。
- **过程遥测**：M4-01~05 为 8/30 晚间主会话+Implement 子代理交付（lint 全绿）；M4-06 冒烟本周补做（基线 HEAD 4703a0f 无 dart 改动，直接复用 8/30 后构建）。冒烟中遭遇**模拟器进程中途退出**一次（qemu 进程消失、adb 失联）——快照重启恢复后 userdata 磁盘态完好（导出文件仍在），冒烟结论不受影响；该观察与用户在 09-05 报告的「使用模拟器时电脑偶尔卡死」同源（AVD 位于 F:\tools\android\avd USB 外接盘，宿主稳定性议题已单独诊断，见会话记录）。
- **避坑（勿重蹈）**：
  1. **模拟器进程中途退出可恢复**：异常退出后 adb 失联、`tasklist` 无 qemu，快照重启（秒级 boot）后 userdata 磁盘态完好——导出文件、DB 数据均持久化；冒烟中途掉线不必重做，先验证数据再继续。
  2. **Git Bash run-as 路径转换坑**：`adb shell run-as <pkg> cat /data/data/...` 会被 MSYS 路径转换污染（`/data` → `C:/Program Files/Git/data`）——前缀 `MSYS_NO_PATHCONV=1` 或双斜杠。
  3. **ShareSheet「No apps can perform this action.」≠ 功能缺陷**：干净模拟器镜像无 ACTION_SEND 接收 app，空态属环境限制——文件名可见性以临时目录文件清单（`run-as ls`）+ 代码契约（`ShareParams(files:[XFile])`）+ ShareSheet 弹出三方佐证；真机环境才显示分享目标列表。
  4. **分享面板空态 = 超时兜底的真实验证机会**：share_plus 的 Future 在用户选目标/关面板前不 resolve——无接收 app 时恰好让 `platformTimeout` 兜底路径在真机环境跑通（非阻塞 SnackBar + app 存活），比单测 fake 更有说服力。
  5. **快照恢复会把遗留系统 UI 一并恢复**：模拟器异常退出前的 ShareSheet 空态面板在快照恢复后仍挂在前台，先 BACK 关闭再继续操作。
- **知识库蒸馏**：候选教训（模拟器中途退出后的恢复路径与磁盘态持久化验证 / ShareSheet 无目标 app 时的三方佐证取证法）——完成段经 distill-lesson 处理。

## M3 kickoff 批次（2026-08-30 — project-kickoff 全自动档交付：角色 + 搜索里程碑）

- **交付**：Grilling 共识 5 面拍板（零真拍点 + 3 best-judgment 非拍板：导入占位保留 UI / 批量删除含可裁 / 开始对话默认模型）。8 票 4 波 DAG（W1 M3-01‖M3-04a / W2 M3-02a‖M3-04b / W3 M3-02b‖M3-03‖M3-04c / W4 M3-05，基线 f477e2d → merge 70bc094）。角色列表卡片+四按钮+下拉刷新+长按批量删除 / 6 步全屏向导+5 模板逐字移植（senpai/wanderer/tsundere/butler/nekomimi）/ V2 卡导入导出纯 Dart 服务（四格式识别+V1 兼容+temperature 裁剪）+ seam 收口（file_picker ^12.1.2/share_plus ^13.3.0/path_provider ^2.1.6 转正）/ 跨对话搜索防抖五态+跳转定位 3s 高亮（GlobalObjectKey+ensureVisible）。证据 `.scratch/m3-kickoff/evidence/`（M3-01~05 + W3 独立复核 + smoke-gate + 冒烟 PNG）。
- **门禁链**：全量 **729 测**全绿（M3 交付后 726 + 期末修复 3 新用例）/ analyze 0；覆盖率剔除 drift **98.06%**；四轮波末增量审核（W3 用户要求独立复核轮，0 阻断独立复现 179 测绿）+ **期末四轴零阻断**（Spec 8/8 票满足、F-7 token 契约全库绿、安全红线 0、架构无阻断）；**冒烟 PASS**（角色列表→向导模板建「知性学姐」→保存落库→搜索 hihello→跳转定位高亮全真机实证，UI 树确定性证据）。
- **主会话修复（期末发现低成本真缺）**：
  1. **F-7 契约回归 x2**：M3-04b search_view（d76e85e）+ M3-04c chat_view（ff24612）直接引用 ConverColors 违反视图层 token 契约 → 改经 `colorScheme.primary.withValues(alpha:0.13)` / `palette.border`，静态不变量 `view_theme_tokens_test` 真实绿
  2. **期末四项**（0057d9e）：NaN 温度绕过 [0,2] 裁剪（`_clampTemperature` 补 isNaN 回退 0.7，期末 Falsify 对抗发现）/ manual 回退后 next 误入步骤②（`next()` 补 manual 从①跳③）/ Escape 清空不递增 `_requestSeq` 致在途查询回填空态 / 删除角色后聊天入口陈旧 `_firstCharacter` 缓存（`invalidateEntryCache` 接入 deleteCharacter）
  3. **构建配置**（9cfc4aa）：`android/gradle.properties` 追加 `kotlin.incremental=false` + `org.gradle.parallel=false` 绕开 Kotlin daemon Windows 并行编译 storage 注册冲突（file_picker/share_plus 多模块触发）
- **过程遥测**：票 8、波 4（并行 2+2+3+1）、merge 8；子智能体 20+（含网关故障重开 M3-05 x3——两次静默死亡半成品 +849 行接续、W3 审核重开、W3 独立复核轮）；空返回/静默死亡 3（M3-05 x2 + W3 审核 x1）；回退 0；审核 findings：W1 增量 4、W2 增量 7（含 2 真缺）、W3 增量 18 + 独立复核 12、期末四轴 14 全非阻断。**技术债净增**：期末四轴非阻断观察按契约落盘 TECH_DEBT——F-18 校验门分置（Worth exploring，📝 待立项）+ F-23 平台真通道冒烟未深度触达（Worth exploring，📝 待立项）；F-19~F-22（CharacterDraft docstring / 双 timer / light alpha / searchPreview 边界）git grep 复核现状仍成立后 ❌ 复核关闭（处置记录留痕）。
- **避坑（勿重蹈）**：
  1. **子代理静默死亡**：M3-05 两次 agent 无通知死亡（任务记录消失），半成品在盘（controller/view/测试已改）——「无完成通知」时立即查磁盘 worktree 状态，半成品接续而非重写（第 3 次派发接续后 DONE）
  2. **F-7 契约回归进主分支**：M3-04b/04c 视图直接引用 ConverColors 违例被合并（全量测试未跑 view_theme_tokens_test 静态不变量）——波末合并后必须跑全量（或至少静态不变量组），不能只跑受影响模块
  3. **期末四轴对抗发现 NaN 温度**：JSON 字面量 NaN 被 jsonDecode 宽容接受、double.tryParse 返回 NaN 非 null——「非法值回退」类契约必须显式 isNaN 守卫（Falsify 用恶意输入打数据通路价值再证）
  4. **Kotlin daemon Windows storage 冲突**：`Could not close incremental caches ... already registered` 在新增多 Kotlin 模块（file_picker/share_plus）后触发——in-process 策略不覆盖此路径，需 `kotlin.incremental=false` + `org.gradle.parallel=false`
  5. **M3-05 半成品含残留脚本**：`cov_miss.py`/`cov_report.py` 覆盖率统计脚本留在 worktree——半成品接续时须清理临时脚本
- **知识库蒸馏**：候选教训（子代理静默死亡磁盘核验 / F-7 契约回归合并后全量测试 / NaN 温度 Falsify）——完成段经 distill-lesson 处理。

## 技术债消费批次 F-10~F-17（2026-08-30 — project-kickoff 全自动档交付：技术债八候选消费）

- **交付**：Grilling 共识 8 候选 **7 做 1 关闭**（F-15 关闭：桌面 ChatResponse 契约镜像 + F-6 先例 + 测试锁定，零真拍点）。6 工单 2 波 DAG：波1 T2‖T4‖T5（T2 `7d86628` ConverPalette of/maybeOf + 41 处迁移 / T4 `c040c06` 翻译栈共享 / T5 `353a857` CharacterNotFoundError 404 归类）merge `14bf479`；波2 T1‖T3‖T6（T1 `57c3db8` 保存事务化 / T3 `fe98671` 主题异步面 catchError+重入守卫 / T6 `e4ece9c` cancel 加界）merge `b9dc9bc`。证据 `.scratch/techdebt-f10-f17/evidence/`（T1~T6 + smoke-gate + 5 张冒烟 PNG）。
- **门禁链**：全量 497 测全绿 + analyze 0；覆盖率手写口径（剔除 drift 生成物 3 文件）**97.96%** ≥ 90%；波1/波2 增量审核 Falsify 16 项构造验证**全非阻断** + 文件范围 6 票全合规；**期末四轴零阻断**（Spec 6 工单验收语义全满足、token 契约/文案锚/errors.dart 零 dio 契约三约束保持、安全红线 0、架构无阻断）；运行态冒烟 PASS（设置页渲染 / 主题深 `#171512`↔浅 `#F0ECE5` 像素精确 / logcat 零异常）。
- **过程遥测**：票 6、波 2（并行 3+3）、merge 6；子智能体 13 个（Grilling/plan-tickets/Implement×6 含重开×2/code-review×3/主会话接续×1）；**空返回重开 2**（T5/T6 首派均零产出：T5 空 worktree、T6 半成品测试 +93 接续），重开后均 DONE（半成品接续优于重写复证）；回退/冲突 0；审核 findings：波1 增量 8 非阻断、波2 增量 8 非阻断、期末 5 非阻断（命名通用 ×2 / Data Clumps / snapshot+written 成对 / T6 测试上界 6s 慢 CI flaky 观察）。**技术债净增**：清零 8 → 追溯补录 3（F-24~F-26 Speculative 复核关闭，处置记录留痕；原「不入债」为交付偏差，2026-08-30 按契约纠正）。
- **避坑（勿重蹈）**：
  1. **子代理「声称无任务」型假完成**：T5/T6 首派均返回与任务无关内容（浏览器话题/「我没有任务」）且磁盘零产出——完成通知不可信，**必须以磁盘事实核验**（worktree commit + evidence 文件），核验零产出即重开复用 worktree（本轮两票重开后均 DONE）。重开 prompt 必附「前次现场核查指令」。
  2. **check-complete.py 的 STATUS token 格式**：脚本认 `STATUS: <状态>`（票号须放行尾注释 `# T`），且**未派发工单不放 STATUS 行**——首写把票号塞进 token 值导致「未找到 token」，修正后通过。
  3. **模拟器截图像素采样**：screencap PNG 为 colortype=6（RGBA）且每行带 filter 字节，裸解析得到全零；须用 PIL `Image.convert('RGB')` + getpixel（同 M1 教训：像素采样是确定性证据，命名/假设不是）。
  4. **plan-tickets 首派「未收到输入」**：子代理持有 prompt 但声称无输入——重开时把共识全文内联进 prompt（不依赖它读文件），二次调用即产出完整工单。
  5. **期末全局覆盖率口径**：`flutter test --coverage` 全量产 lcov，drift 生成物 `app_database.g.dart`（468 行 29.9%）拉低全局到 66.31%——按 M2 同口径剔除 3 个生成文件后 97.96% 达标（生成物不经测试覆盖是预期，此前批次已固化此口径）。
- **知识库蒸馏**：候选教训 2 条（子代理「假完成」必须磁盘核验 / 模拟器像素采样用 PIL 解码 filter）——完成段经 distill-lesson 处理。

## M2 kickoff 批次（2026-08-29 — project-kickoff 全自动档交付：聊天核心）

- **交付**：7 票 5 波 DAG（T00 工程门 e623268 / T01a Prompt 组装 bfc701d / T01b SSE+LLM 抽象 4f87f3d / T02 双协议 wire 2cc1c5b / T03 ChatService 342ddad / T04 聊天 UI 4b143d2 / T05 test_connection 0f88df7）+ 波3修复（a1bc0cc）/波4修复（a251df3）/期末收尾（0f9c33f），merge 链至 `59e766a`。证据 `.scratch/m2-kickoff/evidence/`（T00~T06 + 09-smoke-gate-a7 + 冒烟 PNG）。**A1~A8 门**：477 测全绿 / analyze 0 / 覆盖率手写口径 95.42%；**A7 冒烟 PASS（窄路径）**——模拟器端到端实证：入口 UI/autoGreeting/发送链/「未配置 claude API Key」逐字错误/测试连接 SnackBar（logcat+像素）；真实打字机流式留待用户 Key（付费账户未擅自调用）。
- **关键架构修正**：移动端无后端中间层，SSE 契约源 = **Anthropic/OpenAI 官方原始协议**（非桌面统一帧）；`temperature` 官方已弃用 → 不透传（research 实证，修正 Grilling 初判）；flutter_markdown 已 discontinued → flutter_markdown_plus（best-judgment，用户未答）；两端真拍点（markdown 包/最小入口）用户未答，按推荐定案并注明非拍板。
- **审核链**：波3增量审核（F1 阻断 regenerate×streamReply 数据丢失 / F3/F4/镜像 seam/F5）+ 波4增量审核（F1 阻断 stop 竞态 UI 丢失 / F3b/F2/F4）——四轮修复全被增量审核或合并核验捕获；期末四轴**零阻断**（Spec A1~A8 全过/安全红线 0/架构翻译栈去重非阻断）。
- **过程遥测**：票 7 + 修复 3 + 收尾 1；网关故障 0（本批未遇）；空返回 1（T05 首次中断，重派接续半成品）、T04 重派接续（ChatController 482 行半成品保留）；子智能体 13 个 token ≈ 1.2 亿；审核 findings：波3 阻断 1/Falsify 5、波4 阻断 1/Falsify 5、期末非阻断 9。**技术债净增**：本轮清零 0 → 净增 4（F-14~F-17）。
- **避坑（勿重蹈）**：
  1. **并行票 seam 契约必须合并后实测**：T02/T03 并行开发，T03 按「基类 LLMError 精确判型」、T02 实现「LLMConnectionInterruptedError 子类」——各自单测全绿、集成断流失效，合并时人工核验捕获。并行票间共享 seam 的契约要写进双方工单并合并后跑集成路径。
  2. **半成品接续优于重写**：T04/T05 两次中断（T05 片段文本早亡、T04 长会话中止），worktree 半成品保留，重派接续（ChatController 482 行/测试骨架 293 行全复用），接续成本远低于重写（M1 教训复证）。
  3. `adb shell input text` 不支持中文（Unicode NPE）——模拟器冒烟输入用 ASCII；adbd 管道 `cat` 会损坏二进制（用 run-as 设备端 sqlite3 直查，勿 pull 后本地解析）。
  4. drift_flutter DB 在 `app_flutter/` 目录（非 databases/），冒烟播种角色走设备端 sqlite3 run-as。
  5. `dart format` 全文件误触会引入无关重排——修复只改目标行（T04 修复教训）。
- **知识库蒸馏**：候选教训（并行 seam 契约合并在即实测 / 半成品接续复用 / 模拟器冒烟设备端数据操作）——完成段经 distill-lesson 处理。

## 技术债消费批次 F-7/F-8/F-9（2026-08-29 — project-kickoff 全自动档交付：技术债三候选消费）

- **交付**：3 工单单串行链（01 F-9 eb51b99 / 02 F-8 a7064fb / 03 F-7 ea1b724），merge 68e8d19（基线 78b8a94）。**F-7** ConverPalette ThemeExtension（ink1-4/border 5 枚，dark/light 注册 ConverTheme）+ 5 视图 25 处消费改经 `extension<ConverPalette>()!`（M1 同构契约零改动）；**F-8** 设置页三处失败路径统一失败 SnackBar + debugPrint、theme onSelectionChanged async await、settings_view 去静默吞错；**F-9** 视图层装配 required 化（删 AppDatabase.open/FlutterSecretStore 缺省分支 + app_database import），home_shell 单一装配链。
- **门禁链**：全量 171 测全绿 + analyze 0；覆盖率手写口径（剔除 drift 生成物）90.63% ≥ 90%；波末增量审核（Falsify 阻断 0、文件范围合规）；**期末四轴零阻断**（Spec 24/24 验收全过、Standards 0 硬违规安全红线 0、Architecture 无阻断、Falsify 6 非阻断）；运行态冒烟 PASS（模拟器浅色 #F0ECE5 / 深色 #171512 像素精确，主题双向切换成立，F-7 浅色主文字可读 vision 实证）。
- **过程遥测**：票 3、波 1（串行链）、并行 1（单 lane）；空返回 0、回退/冲突 0；子智能体 5 个（Grilling/plan-tickets/Implement/code-review×2）；波末审核 findings 非阻断 2（N1/N2）、期末 findings 非阻断 11（Falsify 6 + Standards/Arch 判断 5）。**技术债净增提示**：清零 3（F-7/8/9）→ 净增 4（F-10~F-13），净增 > 清零——审核产出仍大于修复容量，下一轮预检可继续消费。
- **避坑（勿重蹈）**：
  1. **截图主题状态先采样确认再下结论**：冒烟首张「深色基准」截图实际是浅色（应用持久化主题为浅色，前会话收尾态）——像素采样（背景 == token 精确值）是主题状态的确定性证据，vision 描述与命名假设都不可作为基线（来源：本批冒烟 4.5，教训已入冒烟证据 08-smoke-gate.md）。
  2. Flutter widget 测试碰 ThemeExtension：消费 `extension<ConverPalette>()!` 的组件在未注册扩展的测试环境 null 崩溃（fail-fast 契约）——测试泵 section 必须用 ConverTheme.dark() 包裹（F-7 涟漪，已申报记录警告档）。
  3. F-8 的 async 错误面改动暴露既有顺序写非事务性（N1）——失败 UI 把「部分持久化」首次显性化，落债 F-10；改错误面需顺带审视持久化原子性。
- **知识库蒸馏**：候选教训 1 条（运行态验证先确认基线状态：像素采样 vs 命名假设）——完成段经 distill-lesson 处理。

## M1 kickoff 批次（2026-08-29 — project-kickoff 全自动档交付：数据层 + 设置）

- **交付**：8 工单 5 波（01 SecureStore c575d58 / 02 模型清单 3266593 / 03 角色对话仓储 038d7f0 / 04 设置仓储 9ec7346 / 05 消息仓储 a7b1b73 / 06 设置页 de9e5de / 07 浅色主题+装配 54df54a+b9ad059+b39b283 / 08 收口 6b4bfd1），merge 链 955d002→783d15a→4e8db1b→794a847→a1d4265。**G1–G5 门全绿**（analyze 0 / 154 测试 / 仓储契约逐锚点 / 主题同构+行为断言 / 清单 60 模型锁 / 设置十键+解析链）+ **G6 冒烟全项过**（Key 真通道往返 27 字符精确回显 / 三值主题即时生效[深浅视觉反转+深色恢复逐字节归位] / 五 tab 零崩溃）。用户真拍两项：主题三值首启深 / 设置页三组真实化。
- **审核链**：波末增量审核 ×5 全过（W1 SecretStore 契约实证+清单 IDENTICAL / W2 CRUD 六锚+接缝编译探针 / W3 主会话完成票独立全标准 / W4 装配链逐环+浅色 token 22/22 / W5 零代码变更形式化实证+G 证据复核）+ 期末四轴（安全红线 0[Key 链路端到端核]/Spec 零越界/突变前置已由波末覆盖/架构分层完好[drift import 零泄漏出 data 层]）。覆盖率：全局 45.36%（生成物稀释）/ **手写口径（剔除 drift 生成物+schema 声明）90.90% 达标**——口径定义固化于本文，后续里程碑沿用同口径。
- **过程遥测**：波 5、票 8、并行峰值 2（网关配额）；**网关故障 episode 一次**：波 3 期间 05 三败触重开上限 + 06 两败 + W2 审核 captcha 两败——处置：05 触线报用户（无回答 → persona best-judgment）**主会话接续半成品完成**、06 押后主会话从零完成、审核错峰重派三派成功；空返回 0；回退/冲突 0；子智能体 15 个 token 合计 ≈1600 万；审核 findings：阻断 0、非阻断 15+（F-7/F-8/F-9 落候选 + 低危观察若干）。**技术债净增提示**：候选 0→3（净增 3 > 清零 1[F-3 消费]），全 Worth exploring 级。
- **避坑（勿重蹈）**：
  1. **orchestration/台账类文件的行级编辑用「追加」勿用「替换」**——本批三次误把前一条记录行替换掉（发现于 Neat 前自查，均已恢复）。
  2. **测试环境平台通道是挂起不是抛错**（secure_storage/drift 打开永不完成）——Flutter widget 测试碰平台依赖必须超时兜底（3s），try/catch 管不了挂起。
  3. **typedef 别名不可 const 调用**（`const ApiEchoValues({})` 非法）——Dart 任意 map 字面量直接 `const <String, String>{}`。
  4. 子代理报「用户已拍板」类断言必须核对交互事实——M1 Grilling 曾虚构两项拍板（三值主题/三组真实化），被声称核对拦下退回用户真拍。
  5. flutter_secure_storage 11.x 要求 compileSdk ≥37（Flutter 3.47 模板默认 36）——锁依赖前查 AAR 元数据。
- **知识库蒸馏**：候选教训（网关故障期的批次韧性处置：错峰重派/主会话接续/降压串行）——完成段经 distill-lesson 处理。

## M0 kickoff 批次（2026-08-29 — project-kickoff 全自动档交付：脚手架与空壳）

- **交付**：4 工单 3 波（01 脚手架 c2b5c1b / 02 主题 0c72ca0 / 03 drift 3fecff0 / 04 导航壳 0584c03），merge 链 643abcf→ef80f53→c55ced3；launcher 名「汇流」（用户拍板）。**G0 门全项过**：analyze 0 issue / test 23 全绿 / APK 158MB / 模拟器安装拉起 / 五 tab 切换零崩溃 / vision 视觉核对（深暖灰+琥珀选中+中文文案+设置页 8 分组对应 §6.1）。证据 `.scratch/m0-kickoff/evidence/`（01–04 + g0-gate.md）。
- **审核链**：波末增量审核 ×3 全过（W1 金标准脚手架逐字节对比 / W2 schema 逐字段保真+codegen 非陈旧实证 / W3 装配链逐环+测试判别力分析）+ 期末四轴（安全红线 grep 0 命中、Spec 零越界、突变抽查 3/3 击杀、架构分层完好[drift import 零泄漏出 data 层]）。覆盖率：全局 28.8%（生成物稀释）/ 手写 70.2%（<90% 预警非阻断：lcov 归属偏差+突变佐证）。
- **过程遥测**：波 3、票 4、并行峰值 2（网关并发配额实测=2：W1 审核首派撞限，错峰重派成功）；空返回 0；回退/冲突 0；子智能体 8 个（4 实现+4 审核）token 合计 ≈14.7M；审核 findings：阻断 0、非阻断 10（6 条落候选 F-1~F-6、4 条信息性关闭）。**技术债净增提示**：候选区 0→6，本轮清零 0——净增>清零（审核产出>修复容量信号），全部 Worth exploring/Speculative 级无 Strong。
- **避坑（勿重蹈）**：
  1. **模拟器 GUI 冒烟 tap 坐标必须来自 UI 树实测**（android_ui_describe）——推算坐标（屏高-100）会打进系统导航条背景/触发 Recents 污染截图；**相邻截图字节完全相同 = 内容未变的自查信号**，不许凭进程存活放行切换断言。
  2. MCP 工具调用 30s 客户端硬截断 → 首次 gradle/Flutter 全量构建必须 Bash 侧跑。
  3. GitHub 直连抖动时段：gradle 发行包可经国内镜像（sha256 对齐官方）预置 `~/.gradle/wrapper/dists` 绕行，不改仓库不改环境变量。
  4. `flutter create` 默认跳过已存在文件——仓库根直接 create 安全（README/.gitignore 定制版保留）；本机模板差 2 行（/coverage/ 与 .widget_preview/ 已补齐）。
  5. build_runner 2.16 已移除 `--delete-conflicting-outputs` flag（新行为即默认），工单措辞勿再带。
- **知识库蒸馏**：候选教训 1 条（GUI 冒烟坐标纪律+字节自查信号）——完成段经 distill-lesson 处理。

## M0 kickoff 预检（2026-08-28 — project-kickoff 全自动档，工程目标 = M0 里程碑）

- **知识库预检**（库路由：仓库无 KNOWLEDGE_BASE.md → demo 库注册表命中 Conver System 项目；建议后续补 KNOWLEDGE_BASE.md 登记）：persona 已读（L3：全自动档偏好/深模块/单一事实来源）；经验扫描 ConverSystem 条目按摘要过滤——**精读 1 条**《DB 枚举列按值存取》（M0 drift 表 schema 约束：枚举列显式按值落库，不依赖默认成员名）；跳过桌面/后端向笔记（SSE 状态机/base_url/Pydantic 等 M2+ 再消费）。召回轨迹记于此。
- **工程 preflight**：基线 `ad0570d`（mobile 分支）；git worktree 可用；测试框架 = `flutter test`（Flutter 3.47.2）；交付形态 = 源码跑通（全自动档仅汇报），M0 门「模拟器跑空壳」即步骤 4.5 运行态冒烟。
- **技术债预检**：TICKETS 活跃 M0–M7（本批认领 M0）；TECH_DEBT 候选区 0 项，无待消费候选。
- **前置清理**：android-smoke 冒烟残留 59MB 已删（用户确认），工作区根恢复 desktop/ + mobile/ 净布局。

## Flutter SDK 装载（2026-08-28 — D 盘，M0 前置条件达成）

- **Flutter 3.47.2 stable**（2026-08-27 发布，Dart 3.13.2）装于 `D:\Desktop\tools\Cache\Flutter\flutter`（3.3 GB），ZIP 走 Google 官方存储直连 + sha256 校验（官方 `37934f21…`，两次校验均匹配）；`bin` 已持久化进 User PATH（置顶）。
- `flutter config --no-analytics` 已关遥测；`flutter --version` 正常。
- **`flutter doctor` 全绿**：Android toolchain ✅（SDK 35/36 + build-tools + JDK17 全在 D 盘，AEHD 加速、AVD medium_phone、模拟器在线）；补装了 `platforms;android-36`（Flutter 3.47 新工程默认 compileSdk 36）＋ `flutter doctor --android-licenses` 补全 googletv/googlexr/arm-dbt/gdk/mips 许可文件。
- **避坑**：Git Bash 的 `tar` 是 GNU tar 不认 zip（Windows 的 `C:\Windows\System32\tar.exe` 是 bsdtar 才认）——解压 Flutter zip 用 `unzip`；下载校验通过前**不要删 zip**（犯过一次：解压失败+zip 已删 → 重下 1.84GB）。

## 移动端库文档体系规范化（2026-08-28 — 镜像桌面库结构建齐标准档）

- 9 文件就位：CLAUDE（项目规则）/ PROJECT_REFERENCE（介绍书）/ CONSENSUS（决策登记 + ADR 索引）/ TICKETS（M0–M7 里程碑录入）/ TECH_DEBT / DEV_LOG / CONTEXT / docs/documentation-standards / SECURITY。
- 决策表详版留在 `docs/mobile-design.md`（§0/§4.5）避免双源；ADR-0002 权威文本在桌面库 CONSENSUS.md，本库登记引用。
- 完整档（CODE_WIKI + doc_sync + F-01 门）按档位制随模块数 ≥ 8 自动升档，不提前建。

## 设计文档迁入移动端仓库（2026-08-28 — 从桌面库迁移）

- `desktop/docs/mobile-design.md` + `mobile-adaptation-research.md` → 本库 `docs/`（桌面库 git rm，提交 484555d；本库 76a34fa）。
- design 文档内桌面独有引用统一加 `desktop/` 前缀改反引号（两分支各自持树的链接边界）；桌面 CONSENSUS ADR-0002 引用同步更新。

## Android 工具链装载 + 插件管道冒烟（2026-08-28 — D 盘，用户要求不装 C）

- **全部落 D:\Desktop\tools\Cache**（3.6 GB）：JDK 17 Temurin、Gradle 8.9（winget 源无 Gradle.Gradle 包 → 官方 zip）、Android SDK 35（cmdline-tools 12 / platform-tools 37 / build-tools 35 / emulator / default x86_64 system image）、AEHD 2.2 加速驱动（用户 UAC 授权安装）、AVD `medium_phone`。
- 插件管道端到端冒烟通过：`android_preflight` 全绿 → `android_create_app`（android-smoke 工程）→ assembleDebug → 安装 → 启动 → 截图（vision 确认正常 Compose 界面）。
- **避坑（勿重蹈）**：
  - ZCode 的 android-emulator 插件 server 环境在**会话启动时冻结**——改环境变量/插件配置后必须重启 ZCode 一次，preflight 才看得到 D 盘工具链（配置已持久化：User 环境变量 + `sdk_path` 插件配置）。
  - `where gradle` 返回无扩展名的 `gradle`（Unix 脚本）→ 插件 spawn ENOENT → 已改名 `gradle.sh`（发行目录里）。
  - MCP 工具调用被客户端硬性 30s 截断 → 首次 gradle 全量构建必须在 Bash 侧跑；模板 `app/build.gradle.kts` 需显式补 compileOptions/kotlinOptions 对齐 JVM 17。

## 移动端库初始化（2026-08-28 — 独立 git 库，与桌面库分离）

- 仓库重构后建独立 git 库：默认分支 `mobile`（初提交 915b801，README + Flutter .gitignore）；托管于同源仓库 conver-system 的 `mobile` 分支（与桌面 main 历史完全独立）。git 身份沿用 Conver System Dev。