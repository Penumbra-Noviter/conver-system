# Conver System 移动端 — 开发日志 (DEV_LOG)

> 只记「已做」与决策/避坑；待办一律进 [TICKETS.md](TICKETS.md)（唯一待办事实来源）。
> 格式：`YYYY-MM-DD | <操作> | <描述>`（倒序，最新在前）
> 滚动摘要窗口上限 12 条，超限在文档同步时折叠为阶段摘要。

---

## 架构深化批次 AR-4 — WebView 能力面收敛（2026-09-09 — improve-codebase-architecture 候选 4 直落）

- **交付**：新模块 `lib/services/simulator/webview_capability.dart`——统一能力接口 `WebViewCapability`（页面就绪握手 + 无返回 runJavaScript / 带返回 evaluate〔原样串，解码归桥层〕+ navigate + buildView；**不暴露 setOnPageFinished**）+ `WebViewCapabilityFactory` typedef（**构造期委托注入**）+ 生产工厂 `createWebViewCapability` + `_FlutterWebViewCapability` 适配器（webview_flutter **唯一引用点**，构造即 setNavigationDelegate——时序契约结构性成立，挂委托后导航的两步序收敛为 create(挂委托) → navigate 一步）。两张并行 WebView seam（run 62 行 / sheet 70 行）从 `lib/views/simulators/` 内嵌处删除，两消费点只留差异面：run 侧（simulator_run_view）= 无返回 runJavaScript + navigate 错误上抛即时错误态；sheet 侧（save_sheet）= 带返回 evaluate + navigate 吞错移入消费点 `_bootstrap` 走超时降级；`simulators_hooks` launcher 第三引用点换源（import + 缺省工厂 `createWebViewCapability`）。共享假件 `test/support/fake_web_view_capability.dart`（onPageFinished 构造必填 + instantFinish/throwOnNavigate/throwOnCreate + evaluate 双编码 JSON 契约复刻迁自 save_sheet_test:126-147，F-43/W5 B1 调用序 spy 组改**委托必达**行为断言）。commit 待回填（merge 待回填），基线 ba0d680。
- **门禁链**：范围 198 测全绿（simulator_run_view 20 含委托必达×2 / save_sheet 16 含委托必达×2 + navigate 吞错新增 / simulators_controller+view / layer_boundary / injection / save_bridge）/ analyze 0；覆盖率按本工单 4 源文件口径 **100.00%**（379/379；webview_capability 生产薄层 coverage:ignore 除外，接口 0/0）；**先红后绿**：委托必达断言先红（模块/消费点未实现即编译失败；运行侧委托不发即时事件 → 秒开页不注入超时错误态红 → 实现后绿）；**变异抽查**：删 instantFinish 事件派发 → run/sheet 委托必达双红、删 evaluate 值序批分支 → save_sheet happy path 红（灵敏度实证，桥层双解码容错 = 单编码变异不红的既有面豁免于假件契约，依赖方 save_bridge_test 承重）。**验收 6 条全过**（单一平台薄层 grep 唯一命中 / 时序结构性成立 / 求值能力面不变 / navigate 错误策略差异面 / 既有回归全绿 + 可观察行为零变更 + pubspec 零 diff / 命名登记）；安全红线 grep 零命中；CONTEXT 登记「WebView 能力面」「页面就绪握手」。

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