# TECH_DEBT: conver system mobile

> **技术债候选池**（未立项子集）与**处置记录**。本文件与 [TICKETS.md](TICKETS.md)（任务池）分离——候选不等于任务，不自动进入任何 session 的 preflight 认领；消费 = 显式「立项」（从候选区取出 → 转入 `TICKETS.md` 活跃工单，或标记 ❌ 不立项附理由）。
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
2. ❌ 关闭条目压缩：具复核价值的关闭项保留单行摘要，其余删除。
3. 处置记录按日期分节，滚动保留最近 2 节；更早节整体删除（归档由 git 历史承担）。
4. **候选区 0 项时正文只留标题 + 空表格，不写任何「当前 0 项待立项 / 历史消费罗列」叙述**——处置事实由「技术债处置记录」与 git 历史承担（2026-09-07 用户拍板，防清空后残留历史罗列）。
5. 清出动作绑定会话末 commit 前节点执行，不新增仪式。
6. **机械约束**由 `scripts/pool_cleanup_check.py --check --tickets-file TICKETS.md --candidate-section "## 候选区"` 强制（挂 pre-commit，失败拒提交）——本库候选区节名非标准（`候选区`）且无「维护说明」footer 锚点，脚本按节名参数与「无 footer 节则不检查」自适应：候选区无 ✅/❌ 滞留、活跃工单无 ✅/❌、重复标题、非空与必要节、表格列数异常报格式问题；安装 `sh scripts/install-pre-commit.sh`（每 clone 一次，本库安装脚本按上述参数定制）。

---

## 候选区

| 编号 | 遗留项 | 来源 | 强度 | 状态 | 归属方向 |
|------|--------|------|------|------|----------|

## 技术债处置记录

### 2026-09-14 — 技术债消费批次（F-75/F-76/F-77，候选区清零）

> 来源：用户「消费技术债」指令。F-76 消费（✅ 已修），F-75/F-77 复核关闭（❌）。**候选区清零**（0 项开放）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-76 | ✅ 已修 | `_resolveTemperature`（chat_service.dart）加 NaN/Infinity 回退全局 + 越界 clamp 到 [0,2]（对齐 `SettingsRepository.getTemperature` 契约）；3 复现测试（上界 9.9→2.0 / 下界 -1.5→0.0 / Infinity→全局 0.9）红→绿 |
| F-77 | ❌ 复核关闭 | git grep 复核：SettingsReader 4 getter 稳定（defaultProvider/defaultModel/userName/templateVars，近期仅 U-UX 加 templateVars 一个）；16 处 implements 中 15 处测试假实现，Dart `implements` 编译期强制（加 getter 时编译器提醒所有实现方同步）是防漏测的正确成本，非结构性脆弱——关闭不立项 |
| F-75 | ❌ 复核关闭 | 复核现状：22 款种子 HTML 均已带 viewport meta + @media 断点（768/420 等），响应式已有基础；根因是内容资产 CSS 质量（固定宽度面板 270/300px 在异形屏截断），非 Flutter 代码债；WebView setInitialScale 兜底治标（整体缩放文字变小、破坏布局，且 Android 专属 API 与 iOS 引入平台分歧），正解是内容更新通道逐款改 CSS + 真机验证——关闭不立项，真实 UX 问题转内容更新专项、不进代码债候选区 |

### 2026-09-10 — 技术债折回批次（F-73/F-74，候选区清零）

> 来源：用户「消费技术债区」指令。F-73 消费（✅ 已修），F-74 复核关闭（❌）。全量 **1613 测**绿 / analyze 0。**候选区清零**（0 项开放）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-73 | ✅ 已修 | injection_test.dart 新增交叉校验测试「F-73 交叉校验：JS 模板 toProxyEndpoint 语义 token 与 Dart mirror 行为矩阵联动」——四个语义步骤（非字符串短路 / origin 回退 / pathname 提取+尾斜杠剥离 / 前缀拼接）逐一 token 断言 + mirror 行为锚调用；改 JS 逻辑（含同步改金样）删任一步骤结构即红，与 Dart mirror 行为矩阵形成双向联动 |
| F-74 | ❌ 复核关闭 | git grep 复核：server 仅回环绑定（`HttpServer.bind(InternetAddress.loopbackIPv4)`，simulator_server.dart:138，无公网暴露）；`_buildProxyTarget` 目标 netloc 恒取配置 base（无任意 URL 转发面）；spec Out of Scope 已声明不做鉴权；桌面同构先例（后端同样不鉴权）——加鉴权属过度工程，纵深防御提示保留在 DEV_LOG |

### 2026-09-10 — 技术债折回批次（F-68~72 全部处置，候选区清零）

> 来源：用户「消费技术债 F-68~72」指令。F-68/F-69/F-70 消费（工单 A `769368f` merge `e0b1bd7` + 工单 B `2de3b89` merge `a1ce47a`），F-71/F-72 复核关闭。全量 1579 测绿 / analyze 0 / pytest 66（覆盖 99.24%）。**候选区清零**（0 项开放）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-68 | ✅ 已修 | build.gradle.kts release 打包任务双 exists() 守卫——key.properties/keystore 缺失时清晰报错含路径 + docs §5 指引；debug 构建不受影响；正常路径指纹不变（7B:7C:00:A6...） |
| F-69 | ✅ 已修 | generate_app_icon.py 新增 assert_icon_colors_consistent 双向守卫（yaml 权威源，双键分叉/缺段/非法色均拒生成）+ 突变灵敏度实证 |
| F-70 | ✅ 已修 | privacy_audit 删 _packages_from_mapping Speculative 分支 + audit_lockfile 收敛单 str 输入 + dict 拒绝 TypeError 契约锁；25 测 / 覆盖 99.24% |
| F-71 | ❌ 复核关闭 | git grep：patterns= 参数被 test_privacy_audit.py:215-216 消费（自定义/空名单测试 seam，负样本注入正当性）——公开 API 合法扩展点非死代码，YAGNI 无实害 |
| F-72 | ❌ 复核关闭 | git grep：FileNameEdgeTrim.none 是 FileNameSanitizerConfig.edgeTrim 默认值（file_name.dart:31）+ _applyEdgeTrim case（:71）——删除破坏默认配置完整性（none=不修剪是导出锚行为基座），属设计意图保留 |

### 2026-09-09 — 技术债折回批次（全部折回：F-56/F-65/F-67 消费，候选区清零）

> 来源：用户「全部折回」指令（覆盖防循环单条限制，5 条候选全部处置：F-59/63/66 已收 + F-57 复核关闭 + F-56/F-65/F-67 本批消费）。**候选区清零**（0 项开放）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-56 | ✅ 已修 | 假活连接终态化缺口：stream_wire 终态帧后 terminalTimeout 守卫（可注入缺省 2s，终态后无新帧到期 force-close → 干净 EOF 正常完成不触发重试；正常终态 09 验收 4 零回归）；commit 972aea8（merge fd9aafb） |
| F-65 | ✅ 已修 | 断流重试边界收口 ③④：③ hasRetryableInterrupted 加 !_reloadPending（窗口内按钮不可达无静默 no-op）；④ NoticeRunner seq + banner noticeId 身份守卫（同文案新旧不误清，未接入回退文案相等；先错者胜零变）；commit 0708dcc（merge 2b2b4d5） |
| F-67 | ✅ 已修 | characters_view 覆盖缺口补齐（87.6%→99.1%/100%，5 缺口路径测试 + 5 处突变全红；零产品代码改动）；commit 517aad6（merge 508efaf 冲突手工共存） |

三票联合审核 0 阻断；N 观察（非阻断）：F-56 doc「不抛断流」与平台行为耦合（字面措辞）/ F-65 _isRegenerating 相邻静默 no-op 窗口（预存在、③ 作用域外，再生态按钮有视觉状态）/ F-65 协议面 6 文件涟漪（issue 显式授权）。

### 2026-09-09 — 技术债折回批次（全部折回：F-57 复核关闭）

> 来源：用户「全部折回」指令——剩余 5 条候选全处置：F-67/F-65③④/F-56 立项消费（工单已立），F-57 复核关闭（本条）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-57 | ❌ 复核关闭 | sub.cancel 停滞挂起（W2 09 相邻发现 1）：git grep 复核现状——3s 有界兜底（F-17 契约）+ AR-2 `userWriteSettled` 门 + F-55 finally 结构保证三重覆盖后，取消路径暴露窗口已收窄且「停止收尾不可跳过」结构性成立；剩余 3s 停止延迟为 F-17 既定契约（有界取消语义），非缺陷面——关闭不立项 |

### 2026-09-09 — 技术债折回 F-66 消费（「回复中断」小标语义断言落位）

> 来源：技术债折回（用户「继续折回」→ best-judgment 取推荐 F-66——W6 F-6 + 期末 F-N8，最小闭口）。交付：**断言首跑即绿（现状小标已可读——气泡 MergeSemantics 外独立可读 label 节点）→ 零产品代码改动**；并列对照双锁 2 断言（断流面「回复中断」findsOneWidget + 「已停止」findsNothing / 停止面反向）+ 突变灵敏度实证（ExcludeSemantics 包裹 → 双红还原）。commit `d2fce63`（merge `34bd231`），基线 f55bbee。门禁：全量 **1500 测**绿（+2）/ analyze 0 / 审核 0 阻断（灵敏度独立复现、既有 15 断言保绿；N 观察：文本锚非结构锚低位风险 / find.text 类型敏感 / 时序硬编码 / 预置 flake 无关）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-66 | ✅ 已修 | 「回复中断」小标 a11y 断言零覆盖（W6 F-6 / 期末 F-N8）：并列对照双锁断言落位（断流「回复中断」+ 停止「已停止」互斥标注界），现状小标屏读可读实证、零产品代码改动 |

### 2026-09-09 — 技术债折回 F-63 消费（光标 reduce-motion 面缺口收口）

> 来源：技术债折回（用户「继续折回消费技术债」→ best-judgment 取推荐 F-63——W4 审核 F-1/F-2/F-5/F-6 方向锁定；⑤ DBG print 残留已由期末 hygiene 9221a9f 顺手修）。交付：① 同挂载 MediaQuery 翻转测试 / ② 瞬态缺陷修复（`..value=0.0 ..repeat(reverse:true)` → `repeat(reverse:true)` 自当前 value 续循环——SDK _RepeatingSimulation 源码实证，翻转帧 opacity 连续、无 0.25 暗帧）/ ③ _appliedOnce 注释修正（真实作用 = 防无关 didChangeDependencies 重跑闪断，非 Ticker 泄漏）/ ④ large_text_probe 流式占位面真实触发（改回空 provider 必红实证）。commit `3b929f4`（merge `31d3056`），基线 f7b90fe。门禁：全量 **1498 测**绿 / analyze 0 / chat_view 92.5% 覆盖（守卫行全覆）/ 审核四轴 **0 阻断**（② 修复机制 SDK 源码链核验成立、验收 2/4 红阶段独立复现、4 N 观察均既有形态）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-63 | ✅ 已修 | 光标 reduce-motion 面测试与实现小缺口（W4 F-1/F-2/F-5/F-6 + 期末 S-N1）：① 翻转测试落位 ② 一帧暗帧修复（repeat 自当前 value）③ 注释修正 ④ 流式占位面真实化（⑤ DBG print 已由 9221a9f 修） |

### 2026-09-09 — 技术债折回 F-59 消费（角色卡语义按钮守卫对齐）

> 来源：技术债折回（用户指令，best-judgment 取推荐 F-59——W3 F1 + 期末 F-N7 复证方向锁定）。交付：`characters_view.dart:347` `button: true` → `button: selectionMode`（对齐游戏卡 `button: onOpen != null` 守卫——tap 有效才宣告；hint「长按可多选」三态保持）+ 双态/退出往返断言 + semantics_test 镜像断言同步（方案 A 影响面扩展，主会话批准——M6-03 验收 4 同源镜像，doc 自指 characters_view_test）。commit `672b9d8`（merge `f6fd709`）。门禁：全量 **1496 测**绿 / analyze 0 / 变异灵敏度（mutant revert → 常态+往返双红）/ 审核 0 阻断。**行为变更**：TalkBack 常态角色卡不再宣告「按钮」（对齐实际可点性——修复目标）。覆盖率 87.6%（守卫行全覆，缺口 12.4% 既有面落债 F-67）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-59 | ✅ 已修 | 角色卡语义失真（W3 F1 / 期末 F-N7）：Semantics button 守卫对齐游戏卡——常态（非多选 onTap null）不宣告 button、多选态宣告 + hint 长按可多选三态保持；semantics_test 镜像断言同步翻转 |

### 2026-09-09 — 架构深化 AR-5/AR-6 消费（F-64 关闭 + F-65 缩减 + F-53/54 逆向）

> 来源：improve-codebase-architecture 候选 5（断流生命周期）/ 候选 6（组件协议面）。交付：AR-5 `6dc67ad`（merge 5172e34——hasRetryableInterrupted 判据入 round + replacedMessageId 结算键 + 配对门/推进/文案门三条件结算 + _resolveLastAssistantId 删除；chat_round 24 + service 73 + view 30 / 覆盖 96.71% / 三处突变全红 / B1 双锚零改动）；AR-6 `fefe870`（merge 7089384——EmptyState.action + StatusView.hint 删除，纯删减 / 1489 测 / 双组件覆盖 100% / NoticeBanner 零 diff 承重墙）。AR-5/AR-6 联合审核 0 阻断（待确认——以审核报告为准）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-64 | ✅ 已修 | 聊天 regenerate 目标解析重复（_resolveLastAssistantId vs _resolveRegenerateTarget 两处末条判定）：AR-5 收编——RegenerateResult.replacedMessageId（服务实际替换 id）+ round 图标路径零预解析 + _resolveLastAssistantId 整体删除，「末条 assistant」判定唯余 _resolveRegenerateTarget；B1 死重试按钮双锚零改动实证 |
| F-65 | 🔄 缩减 | ② 条件清理 / ① 目标推进已由 AR-5 修（移出候选区条目已更新描述）；续期 ③④（③ reload 一帧窗口低值面 / ④ 出口过渡陈旧回调——关闭成本陈述落档：需增协议面 + 理论级低值，与 AR-5/AR-6 裁决一致） |
| F-53 | ❌→✅ 逆向已删 | [逆向 M6 W1 复核关闭] EmptyState.action 参数槽——AR-6 按 TP-4 授权删除（「不预建参数槽，未来需要经版本控制恢复」）；4 调用点零 diff + 锚句改写 |
| F-54 | ❌→✅ 逆向已删 | [逆向 M6 W1 复核关闭] StatusView.hint 半面——AR-6 对称删除（与 F-53 同判据，且 hint 无 TP-4 有意保留背书）；2 调用点零 diff |

### 2026-09-09 — 架构深化 AR-1 消费（F-52/F-55 已修 + F-56 缩减）

> 来源：improve-codebase-architecture 候选 1（Strong）+ Grilling 共识 `r1-phase-encoding`。交付：wire 连接相位编码 + 重试判据收束（双子类 ConnectPhase/ReadPhaseInterruptedError + 判据单行 + producedToken 删除 + F-55 try/catch/finally 结构保证），commit 613fcd4 / merge 89fd1bf；范围 183 测 + 受影响 92 测全绿 / analyze 0 / 覆盖率 99.32%；code-review 四轴 0 阻断（B1 首 token 前 idle 收窄 / B2 基类兜底语义，影响面核验干净）。行为变更点随交付汇报（F-58 观察随 B1 消亡）。审核 N-F1（「ConnectPhase 无 token」依赖 wire 构造 + translateError 直通）标注为**未来 provider 扩展复核点**，非债。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-52 | ✅ 已修 | 重试判据宽于文档契约（空 200 体 EOF 与连接失败同型 → 最坏 3 次 billable POST）：AR-1 双子类相位编码——空 200 体 EOF 落 ReadPhaseInterruptedError，判据收敛 `error is ConnectPhaseInterruptedError` 单行，同一 user 内容 ≤1 次 billable POST；先红后绿实证（红 callCount 2 → 绿 1） |
| F-55 | ✅ 已修 | cancel-unwind 未处理错误（_stopStreamReply cancel().timeout 以错误完成 → 落库/close 被跳过）：AR-1 try/catch（Dart Future.timeout 无 onError 参数——事实校准）+ 落库/close 收尾进 finally 结构保证；_CancelErrorProvider 回归（部分落库 + close + zone 零未处理异常），先红后绿实证 |
| F-56 | 🔄 缩减 | ② 注释失真 / ③ N4 断言 + flake 容差已由 AR-1 收编；仅剩 ① 假活连接终态化缺口待专项（正交于相位编码，重开 wire 终态语义）——候选区条目已缩减 |

### 2026-09-08 — M6 W1 增量审核落债（O-N1/O-N2 复核关闭）

> 来源：project-kickoff M6 W1 波末增量审核（固定点 d5b8c03，diff = 01/04/06 三 merge）。阻断 0。F-N1（重试判据宽于契约）与 F-N2（无总预算）并入 F-52 进候选区；O-N3（chat/characters 私有 `_NoticeBanner` 逐字重复）已在 W2 工单 02 收编，无需落债。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-53 | ❌ 复核关闭 | EmptyState.action 参数槽零生产消费方——TP-4 共识「保留可选 action 参数供未来需要」设计意图，git grep 复核「4 处调用零传 action」现状与设计一致（来源：W1 增量审核 O-N1） |
| F-54 | ❌ 复核关闭 | StatusView.hint 参数槽同族（两处生产调用零传参，仅测试驱动）——设计意图保留，复核现状成立（来源：W1 增量审核 O-N2） |

### 2026-09-08 — M6 W2 增量审核落债（F-55~F-57 进候选区 + F-58 观察关闭）

> 来源：project-kickoff M6 W2 波末增量审核（固定点 6b03d2c，diff = 02/09 两 merge）。阻断 0；文件范围 02/09 全合规；过度工程 0（动作槽判定非 Speculative——spec §4.3 契约既定 + 08 排期接线，记入 08 票；idleTimeout 最小化）。09 票 Implement 自审发现的两个相邻既有问题经审核实证判定：发现 2（cancel-unwind 未处理错误）Strong 真缺陷、发现 1（sub.cancel 停滞挂起）Worth exploring。N1/N2/N4 并入 F-56。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-58 | ❌ 复核关闭 | N3 观察：首 token 前 idle → 06 自动重试 → 最坏 3×60s+退避 ≈3.5 分钟静默才「回复已中断」——各环行为与 06×09 契约一致、无错判（首 token 后 idle → `producedToken` 分流正确），纯时长 UX 观察，不入债（来源：W2 增量审核 N3） |

### 2026-09-08 — M6 W3 增量审核落债（F-59 进候选区 + 观察关闭）

> 来源：project-kickoff M6 W3 波末增量审核（固定点 14a49a7，diff = 03 一 merge）。阻断 0；文件范围：2 处申报（chat_controller 只读 getter / api_config tooltip 补丁）均核验**合理成立**（警告档）；过度工程 0（activeCharacterName 状态机 1:1 镜像既有生命周期、游戏卡 null 分支防御语义保留合理）。F1 落债 F-59；F2/F4/F7 观察关闭；F8（stream_wire_test 时序 flake）并入 F-56 随修。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-60 | ❌ 复核关闭 | F2 观察：activeCharacterName 状态机零泄漏（逐路径审计），仅装饰性陈旧——同会话幂等重开不重解析、会话中角色改名/删除不刷新（来源：W3 增量审核 F2） |
| F-61 | ❌ 复核关闭 | F4 观察：`_BlinkingCursor` 自带 `ExcludeSemantics` 与父级 `Semantics(excludeSemantics: true)` 冗余（唯一实例化点在父级内）——2 行冗余无行为影响，测试自锁（来源：W3 增量审核 F4） |
| F-62 | ❌ 复核关闭 | F7 观察：openConversation 快速双击竞态（activeConversationId 与 _activeConversation 错配）对既有字段早已存在，+27 行仅加入既有竞态非新类非本波回归（来源：W3 增量审核 F7） |

### 2026-09-07 — 技术债消费批次 TD-1~TD-4（F-25~F-51 全部处置：19 待修已修 + 8 复核关闭）

> 来源：用户「消费 F-25~F-51」显式立项。19 条拆 4 工单 2 波合入（波1 398d610：TD-1 异常链 9e8f696 + TD-2 契约层 1f64ef4；波2 027bcd3：TD-3 hooks/注入 4677597 + TD-4 生成链路 ed8dfbd）；全量 **1360 测**全绿 / analyze 0 / MUTATION 零残留；波内复核修正 3 条（F-27 桌面等价不改行为只补锚 / F-29 Dart 3.13 jsonDecode 迭代解析器不可复现改深度预扫 / F-39 SDK 已剥离 BOM 改显式防御）。交付见 [DEV_LOG.md](DEV_LOG.md)〈技术债消费批次 TD-1~TD-4〉。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-25 | 种子单游戏缺失裸抛中止整次 | W1 增量审核 F-2 | Speculative | ✅ 已修（TD-1）：单游戏缺失 `continue` 跳过其余款照常落盘；FileSystemException（目录不可用）保持上抛 |
| F-27 | validateImportPayload 非字符串键静默跳过 | W1 增量审核 F-3 | Speculative | ✅ 已修（TD-2）：复核桌面 save-manager.js——JS 对象键恒字符串、桌面无拒绝路径，移动端行为即桌面等价；补 docstring 结论 + 3 锚测试 |
| F-29 | parseManifest 深嵌套 StackOverflowError 裸抛 | W1 增量审核 F-5 | Speculative | ✅ 已修（TD-2）：实证 Dart 3.13 jsonDecode 迭代解析器 400 万层不溢出（审计快照过期）→ 确定性深度预扫 maxManifestDepth=4096 + on StackOverflowError 二道降级 |
| F-31 | refresh 不入 in-flight（last-writer-wins） | W3 增量审核 NB-1 | Worth exploring | ✅ 已修（TD-1）：refresh 入 `_inFlight` 同轨道 + whenComplete 清理，重叠合并一条链，迟到失败不盖成功 |
| F-32 | F-25 兜底捕获面过宽（目录错误被吞成泛化 404） | W3 增量审核 NB-2 | Worth exploring | ✅ 已修（TD-1）：新增 `on FileSystemException` 分支 → 「模拟器数据目录不可用: ${path}」路径文案 |
| F-33 | .timeout 不取消底层 HttpClient | W3 增量审核 NB-3 | Speculative | ✅ 已修（TD-1）：loadManifestViaHttp 可选 timeout 参数 + getUrl/close/body 逐阶段 timeout + finally `close(force: true)` |
| F-34 | import_flow 超时后仍落盘注册 | W4 增量审核 NB-1 | Worth exploring | ✅ 已修（TD-2）：`_ImportCancellation` 取消令牌 + `_compensateCancelledImport`（删文件 + 注销 manifest）——「超时 = 未发生导入」 |
| F-35 | appendImportHook doc 与实现错位 | W4 增量审核 NB-2 | Speculative | ✅ 已修（TD-3）：随 F-44 删除合成器消化（变更最小） |
| F-36 | InjectionScript 占位符替换碰撞静默跳过 | W4 增量审核 NB-3 | Speculative | ✅ 已修（TD-3）：4 连 replaceAll 改单遍 replaceAllMapped（payload 永不被重扫）+ 2 锚测试 |
| F-38 | 枚举 5MB 超返回值通道降级空 Map | W5 增量审核 N1 | Worth exploring | ✅ 已修（TD-2）：两步分片协议（键名 + 按 batch 32 取键值），enumerate seam 契约不变 |
| F-39 | 导入 JSON BOM 误拒 | W5 增量审核 N2 | Speculative | ✅ 已修（TD-2）：实证 SDK utf8.decode 已剥离 BOM → 显式 `_stripBom` 防御 + 测试锚锁定可观察契约 |
| F-40 | 生成校验 script 大小写敏感 + <!-- 误报 | W5 增量审核 N3 | Worth exploring | ✅ 已修（TD-4）：开/闭 script 统一 lowercased 判定 + RAW TEXT 块内 `<!--` 不做注释配对 |
| F-43 | run view 委托时序与 W5 B1 同构未同步 | 期末四轴 Falsify F-1 | Speculative | ✅ 已修（TD-3）：工厂无参化 + navigate 两步序对齐 save_sheet + 调用序 spy + 秒开页回归；有意保留 navigate 错误即时降级语义 |
| F-44 | append* 合成器 + registerHooks 生产死面 | 期末四轴 S-NB2/A-NB2 | Worth exploring | ✅ 已修（TD-3）：删三合成器 + registerHooks + 对应测试，grep 全仓零残留；wireViewDefaults 语义不变 |
| F-45 | 生成 409 未映射无限重试 | 期末四轴 Falsify（W6 N1） | Worth exploring | ✅ 已修（TD-4）：捕获 SimulatorDuplicateError → field='duplicate' + 「已存在相同游戏」终态不重试 |
| F-46 | 取消不拦在途成功 | 期末四轴 Falsify（W6 N2） | Worth exploring | ✅ 已修（TD-4）：服务层落盘前置 isCancelled 断言 + 对话框迟到结果丢弃（对齐 F-34 令牌模式） |
| F-47 | 生成空描述无守卫 | 期末四轴 Falsify（W6 N3） | Speculative | ✅ 已修（TD-4）：generatedDescriptionFallback + deriveGeneratedDescription（GAME_CONFIG.world 兜底），落盘后补写 manifest |
| F-48 | 装饰标题怪文件名 | 期末四轴 Falsify（W6 N4） | Speculative | ✅ 已修（TD-4）：sanitizeTitle 空白/连字符压缩 + 首尾分隔符剥除 + 纯分隔符回退 |
| F-49 | _persistGenerated 恒假死分支 | 期末四轴 Falsify | Speculative | ✅ 已修（TD-4）：grep 确认 `.html` 后缀条件恒假 → 删死分支为无条件拼接，行为零变化 |

### 2026-09-07 — 技术债消费批次 TD-1~TD-4（F-25~F-51 全部处置：19 待修立项 + 8 复核关闭）

> 来源：用户「消费 F-25~F-51」显式立项。立项前逐条现场复核现状（审计快照过期须复核惯例）：F-26 已在 M5 内修复（saveKeyMetaRe 单一来源收口，manifest_parser 改 import show）；F-42 已在 M5 内修复（W6 B1 wireViewDefaults + mounted 守卫）。19 条待修拆 4 工单（TD-1 seed/controller 异常链 F-25/31/32/33 / TD-2 契约层防御 F-27/29/34/38/39 / TD-3 hooks/注入面 F-35/36/43/44 / TD-4 生成链路 F-40/45/46/47/48/49），见 TICKETS 活跃表。8 条复核关闭（见下）。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-26 | saveKeyMetaRe 顶层常量双重定义（manifest_parser + save_key_meta 同名） | W1 增量审核 F-1 | Strong | ❌ 复核关闭：已在 M5 内修复（manifest_parser 删重复声明改 `import save_key_meta.dart show saveKeyMetaRe`，grep 全仓唯一定义于 save_key_meta.dart:24） |
| F-28 | 白名单正则 `$` 锚点对尾部换行键名宿主匹配 | W1 增量审核 F-4 | Speculative | ❌ 复核关闭：与桌面 save-key-meta.js 同构（逐字移植锚），跨端行为一致性成立，非缺陷 |
| F-30 | `/simulators/..` 折叠返回 200 index 而非契约字面 404 | W2 增量审核 NB-1 | Speculative | ❌ 复核关闭：Dart Uri 规范化折叠目标恒为根合法路由，零泄漏零崩溃，仅字面口径偏差，目录墙安全目标未破坏 |
| F-37 | isOfficialEndpoint 裸域/尾点盲区（anthropic.com 裸域不命中） | W4 增量审核 NB-4 | Speculative | ❌ 复核关闭：与票面定义边界一致（Q8 契约锚 domain 结尾匹配），观察记录非缺陷 |
| F-41 | saveSheetBootingText 死常量 + booting 分支字面量重复 | W5 增量审核 N4 | Speculative | ❌ 复核关闭：常量声明已按文档契约保留为导出文案锚（save_sheet.dart:58），booting 分支消费同一语义字符串，非行为问题 |
| F-42 | tab 往返 AppBar 四入口死 context（原缺陷面） | W6 增量审核 B1 | Speculative | ❌ 复核关闭：已在 M5 内修复（W6 B1 9630423 wireViewDefaults + mounted 守卫 + 4 回归测试），本条为防回归记录 |
| F-50 | saveKeyPrefix 解析后零消费 | 期末四轴 Architecture | Speculative | ❌ 复核关闭：manifest_parser docstring 明示「saveKeyPrefix 仅 v1 数据携带并透传，已退役不参与存档匹配」——设计意图，保留透传为数据完整性 |
| F-51 | hook 接线三文件散落（轻微 Shotgun Surgery） | 期末四轴 Architecture | Speculative | ❌ 复核关闭：wireViewDefaults 统一接线后接线点已收敛至 simulators_view，docstring 声明的结构契约成立，进一步收敛引入跨层耦合 |

### 2026-09-07 — 技术债消费批次 F-24（1 项全部处置）

> 来源：improve-codebase-architecture 探索报告备选 B（Speculative）+ 用户指令「先消费技术债」显式立项。交付见 [DEV_LOG.md](DEV_LOG.md)〈技术债消费 F-24〉；全量 819 测全绿 / analyze 0（行为零变化，重构型收敛）。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-24 | SettingsReader 契约语义与实现语义收敛靠碰巧 | improve-codebase-architecture 探索报告备选 B | Speculative | ✅ 已修：兜底常量**单一归属** `SettingsDefaults`（`settings_reader.dart` 新增 `abstract final class`：provider/model/userName 三常量）；`SettingsRepository` 三 getter 填充与 `ConversationRepository._fallback*` 兜底均改为引用同一常量（原为各自字面量、碰巧相等）；契约文档对齐「实现方填充」现状（原声明「返回空串由消费方回退」与实现矛盾）；消费方 `_resolveValue` 逻辑不动（测试 fake 返回空串的兜底语义保留）——任一侧常量改动全局生效，静默破约风险消除；数据层 88 测原样绿（行为零变化实证） |

### 2026-09-07 — 技术债消费批次 F-18/F-23（2 项全部处置）

> 来源：用户指令「消费技术债 F-18 F-23」显式立项（非 Grilling 拍板，两候选均 Worth exploring 由用户拍板做）。交付见 [DEV_LOG.md](DEV_LOG.md)〈技术债消费批次 F-18/F-23〉；F-23 证据 `.scratch/techdebt-f18-f23/evidence/F-23.md`；F-18 全量 803 测全绿 / analyze 0 / code-review 四轴 PASS。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-18 | 向导校验门分置两处（Locality） | M3 期末四轴（Architecture） | Worth exploring | ✅ 已修：步骤②模板门移入 `WizardController.next()` case 2（template 未选 → 拦「请选择一个模板」+ 不前进；import 放行），`selectTemplate` 补 `_error = null`；视图删 `_step2Error` 字段与视图层拦截，统一读 `controller.error`——分步校验单一载体 = next() 的 case 1/2/3 switch；测试拆分新契约 + 文案锚保持（controller_test +17 行 / step2 测试原样绿） |
| F-23 | file_picker / 批量删除手势真机面未触达（share_plus 分面已关闭） | M3 冒烟 4.5 覆盖说明 | Worth exploring | ✅ 已闭合：file_picker 导入系统选择器弹出（`com.android.documentsui` 前台实证）+ 批量删除长按多选手势（长按进多选/自动勾选/加选计数「已选 2 个角色」/退出恢复）模拟器冒烟 PASS，零代码改动；share_plus 分面已于 2026-09-06 M4-06 关闭 → F-23 整条三分面全部闭环 |

### 2026-09-06 — M4 里程碑收口：F-23 share_plus 分面并入 M4 验收关闭

> 来源：M4-06 模拟器真通道冒烟（spec 修订：share_plus 分面并入 M4 验收，file_picker 与批量多选手势归 M5）。证据 `.scratch/m4-kickoff/evidence/M4-06.md` + `smoke-share-sheet.png`；代码 merge 42099eb + 25c7696（2026-08-30），冒烟 2026-09-06 PASS。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-23 | V2 卡平台真通道冒烟（share_plus 分享面板分面） | M3 冒烟 4.5 覆盖说明 | Worth exploring | ✅ 分面关闭（非整条关闭）：share_plus 分享面板真通道已由 M4-06 冒烟实证（ShareSheet 弹出 ×2 / 临时文件生成且文件名=角色名净化 / 导出内容语义 / **platformTimeout 超时兜底实测**——模拟器无分享接收 app → Future 不 resolve → 3s 超时 → 非阻塞 SnackBar，app 零崩溃）；剩余 file_picker 与批量多选手势两分面在候选区重定界保留，归 M5/真机验证 |

### 2026-08-30 — F-10~F-17 批次期末非阻断观察追溯补录（3 项复核关闭）

> 来源：F-10~F-17 批次期末四轴非阻断观察——原批次交付时误标「不入债」，2026-08-30 按契约追溯补录；Speculative 项 git grep 复核现状仍成立后关闭。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-24 | `translate_helpers.dart` 公开函数命名偏通用（`decodeJson` / `responseText` / `errorMessageFromMap`） | F-10~F-17 批次期末四轴（Standards/Architecture） | Speculative | ❌ 复核关闭：git grep 复核三函数在位且均有完整 docstring 消解歧义（`responseText` L92 / `errorMessageFromMap` L121 / `decodeJson` L135），共享模块命名由工单明确，后续新增 provider 时如需统一可随改随重命名 |
| F-25 | `api_config_section._save` `snapshot`（Map）+ `_apiKeySlots` 旁置集合 + `_rollback(snapshot, written)` 成对参数（Primitive Obsession / Data Clumps） | F-10~F-17 批次期末四轴（Architecture） | Speculative | ❌ 复核关闭：git grep 复核 `_apiKeySlots` L76 / `snapshot` L120-127 / `_rollback` L161 均在位，doc 注释已解释槽位类型区分，私有内部实现零公共 API 影响，捆类型纯美容性 |
| F-26 | `chat_service_test.dart` A3 停滞流用例以 6s 上界断言（慢 CI 机理论 flaky） | F-10~F-17 批次期末四轴（Falsify） | Speculative | ❌ 复核关闭：git grep 复核用例 L1081 存在，flutter_test fake clock 推进可控（测试内显式 pump 时间），无实际 flaky 记录，改为等待模式属过度防御 |

### 2026-08-30 — M3 期末四轴非阻断观察处置（4 项复核关闭 + 1 项待立项）

> 来源：M3 期末四轴 code-review（Standards/Falsify/Architecture 非阻断判断）——按「非阻断发现落盘 TECH_DEBT」契约入账，Speculative 项 git grep 复核现状仍成立后关闭（清出机制：关闭项移出候选区，留单行摘要）。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-18 | 向导校验门分置两处（Locality） | M3 期末四轴（Architecture） | Worth exploring | 📝 待立项（候选区保留，供下轮 Grilling 拍板做/关闭） |
| F-19 | `CharacterDraft` 13 个公开字段无独立 docstring | M3 期末四轴（Standards） | Speculative | ❌ 复核关闭：git grep 复核字段不在「公开函数必须 docstring」字面范围，`toCompanion()` 单一映射源兜底语义，补写纯美容性、零行为价值 |
| F-20 | 高亮清除双 timer 冗余 | M3 期末四轴（Architecture） | Speculative | ❌ 复核关闭：git grep 复核 controller 与 view 各自为 dispose 独立取消（跨层生命周期），握手幂等无正确性问题，收敛引入跨层耦合 |
| F-21 | F-7 修复后 light 主题高亮 alpha 0.13 vs 原 0.12（位级不等） | M3 期末四轴（Falsify） | Speculative | ❌ 复核关闭：git grep 复核 `withValues(alpha:0.13)` 为统一常量，感知不可辨（差 2/255），dark 位级相等已确认，为 colorScheme 消费的固有近似 |
| F-22 | `searchPreview('', q)` 空内容取首命中分支而非 120 字回退 | M3 期末四轴（Falsify） | Speculative | ❌ 复核关闭：git grep 复核 UI 五态门禁保证实际不空串调用，纯函数层防御分支冗余 |

### 2026-08-30 — techdebt-f10-f17 批次收口：F-10~F-17 全部处置（7 做 + 1 关闭）

> 来源：project-kickoff 全自动档技术债消费批次（Grilling 共识 8 候选 7 做 1 关闭、零真拍点；6 工单 2 波 DAG 全零阻断）。交付见 [DEV_LOG.md](DEV_LOG.md)〈技术债消费批次 F-10~F-17〉，证据 `.scratch/techdebt-f10-f17/evidence/`，merge b9dc9bc（基线 5334075）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-10 | ✅ 已修 | T1 `_save` 事务化：写前快照四键（两 Key 槽位 + 两 base_url）→ 逐 provider 写/删 → 任一失败即止 + 回滚已写项（旧非空 write 旧值 / 旧空 delete 或写回空串），回滚失败仅 debugPrint；`_saving` finally 复位；文案逐字不变；重试幂等（+6 新测试 442 行，回滚核心用例 red→green） |
| F-11 | ✅ 已修 | T2 `ConverPalette.of/maybeOf` + 未注册描述性 FlutterError（消息含「未注册」+ ConverTheme/MaterialApp 装配指引）；41 处（7 文件）`extension<ConverPalette>()!` 机械迁移；token 名/值/深浅零改动（theme_tokens + view_theme_tokens 只读全绿）；grep 零残留 |
| F-12 | ✅ 已修 | T3 `_themeController.load().timeout(3s)` 补 `.catchError` → debugPrint，DB 读失败保持缺省 dark、无 zone 未处理异常；`theme_controller.dart` 零改动 |
| F-13 | ✅ 已修 | T3 ThemeSection Stateless→Stateful 持 `_switching` 重入守卫（首行 return + in-flight 禁用 SegmentedButton 双保险），反向连点不再被陈旧守卫吞掉；守卫复位可再切 |
| F-14 | ✅ 已修 | T4 新增 `translate_helpers.dart`（DioException 分类/408/504 特判/文本提取/JSON 解析/HttpStatusError 单实例 6 成员），双 provider 删除 ~120 行私有重复改调共享；claude 独有 `_StreamApiError`/`_errorEventMessage` 保留原位；errors.dart 零 dio 契约保持 |
| F-15 | ❌ 复核关闭 | git grep 复核 lib 生产零消费成立，但为桌面 ChatResponse 契约对齐 + F-6 先例（零消费者系设计意图）+ 4 组测试锁定（chat_service_test 断言 reply/messageId/conversationId），删除拉大双端契约距离——保留不立项 |
| F-16 | ✅ 已修 | T5 新增 `CharacterNotFoundError extends DomainError`（消息「角色不存在: <id>」），streamReply/regenerate 两抛点 StateError→替换，`domainErrorResponse` 404 一族归类（对齐桌面 error_mapping.py）；断言更新 + 404 用例 |
| F-17 | ✅ 已修 | T6 `_stopStreamReply` cancel 包 `.timeout(3s)` + onTimeout 兜底（不抛错、继续回合收尾：部分落库 + 关流）；`_StalledProvider` 停滞流用例锁有界完成 |

### 2026-08-29 — techdebt-f7-f9 批次收口：F-7/F-8/F-9 全部消费

> 来源：project-kickoff 全自动档技术债消费批次（Grilling 共识三候选全做、零真拍点；3 工单单串行链）。交付见 [DEV_LOG.md](DEV_LOG.md)〈技术债消费批次 F-7/F-8/F-9〉，证据 `.scratch/techdebt-f7-f9/evidence/`，commit 68e8d19（基线 78b8a94）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-7 | ✅ 已修 | 新增 `ConverPalette` ThemeExtension（ink1-ink4/border 5 枚，dark/light 注册于 ConverTheme）替代视图层硬编码深色 token；5 视图 25 处消费改经 `extension<ConverPalette>()!`；M1 同构契约（token 值/名/名集）零改动；浅色/深色 widget 断言 + 静态不变量测试锁定 |
| F-8 | ✅ 已修 | api_config/default_model 保存与主题切换失败路径统一「失败 SnackBar + debugPrint」，`_saving` 必复位；theme onSelectionChanged async + await（失败不改控制器态，UI 保持旧值）；settings_view 去 `catch (_) {}` 与空 onTimeout（`_loadEcho` 空回显契约保留）；控制器/仓储零改动 |
| F-9 | ✅ 已修 | `SettingsView`/`ApiConfigSection` 构造 required 注入化，删 `AppDatabase.open()`/`FlutterSecretStore()` 视图层缺省分支与 app_database import；装配链收编 home_shell（SecretStore ← app.dart provider）；`settings_repository.dart:49` 数据层 seam 保留（边界） |

### 2026-08-28 — M1-T08/T07 批次收口（已归档，折叠为一行摘要）

> F-3 按方案 a 处置（时间存储维持 drift INTEGER、schemaVersion 恒 1；ISO 口径契约与亚秒精度移交 M4 导出 JSON 层）；F-4 装配收口（契约锁 `test/app_contract_test.dart` 退役，行为断言迁入主题测试 `app_theme_binding_test.dart` + `theme_tokens_test.dart`）。细节由 git 历史承担。