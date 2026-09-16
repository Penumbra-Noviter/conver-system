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
2. ❌ 关闭条目压缩：具复核价值的关闭项保留单行摘要于「复核关闭」表（滚动保留最近 4 批关闭批次，按关闭日期计同日合并一批），更早批次整批删除。
3. 处置记录按日期分节，滚动保留最近 2 节；更早节整体删除（归档由 git 历史承担）。
4. **候选区 0 项时正文只留标题 + 空表格，不写任何「当前 0 项待立项 / 历史消费罗列」叙述**——处置事实由「技术债处置记录」与 git 历史承担（2026-09-07 用户拍板，防清空后残留历史罗列）。
5. 清出动作绑定会话末 commit 前节点执行，不新增仪式。
6. **机械约束**由 `scripts/pool_cleanup_check.py --check --tickets-file TICKETS.md --candidate-section "## 候选区"` 强制（挂 pre-commit，失败拒提交）——本库候选区节名非标准（`候选区`）且无「维护说明」footer 锚点，脚本按节名参数与「无 footer 节则不检查」自适应：候选区无 ✅/❌ 滞留、活跃工单无 ✅/❌、重复标题、非空与必要节、表格列数异常报格式问题；安装 `sh scripts/install-pre-commit.sh`（每 clone 一次，本库安装脚本按上述参数定制）。

---

## 候选区

| 编号 | 遗留项 | 来源 | 强度 | 状态 | 归属方向 |
|------|--------|------|------|------|----------|
| F-101 | notification_service_test 反序交错用例验收 reason 文本归因错误：「锁失效并行交错则为 1」与实测不符——临时移除 `_initSerial` 锁等待后反序用例仍绿（gate 巧合串行化 calls 仍 2），锁钉力由正序 gate 用例承担；建议修正 reason 文本或补调用顺序断言（钉锁机制本身） | 期末四轴 Falsify（techdebt-f98f100） | 低 | 📝 待立项 | 测试 |
| F-102 | 03 票验收①「组级 plugin 零引用」字面未达成——告警 seam 用例正常分支仍用组级 scheduler（仅 recoverable/doomed 独立实例）；字面口径与实现差异，无行为风险 | 期末四轴 Spec（techdebt-f98f100） | Speculative | 📝 待立项 | 测试 |
| F-103 | notification_service.dart 11 处存量 dart format 差异（formatter 版本漂移，基线即存在非本批引入）；全仓 format 归一批次需拍板 | 期末四轴 Standards（techdebt-f98f100） | Speculative | 📝 待立项 | 工具链 |

## 技术债处置记录

### 2026-09-17 — 技术债消费批次（F-98~F-100 全部处置）

> 来源：handoff-techdebt-f91f97-done-2026-09-17 交接指令（project-kickoff 全自动档）。3 工单并批 1 波串行 lane（F98F100-01 `76f7da8` merge `49a1b12` / F98F100-02 `562e968` merge `e9bfc10` / F98F100-03 `e378f78` merge `6f67160`）。门禁：全量 **2000 测**绿（基线 1996 → +4）/ analyze 0 / 期末四轴 **0 阻断**（结论位「需修 Recommended 2 项无 Critical」：R-S1 dart format 已修、R-S2 文档同步本 commit 收口）；非阻断落债 F-101~103。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-98 | ✅ 已修 | F98F100-01：补反序并发交错 gate 用例（无回调 initialize 挂起 → 带回调后进入 → `_initSerial` 锁串行重挂），钉 `initializeCalls==2` / `registeredCallback same(hotCallback)` / 零告警 / 重挂后可消费；纯测试生产零 diff；锁矩阵正/反双向闭合（Falsify 突变实证：反序钉结果语义、锁机制钉力由正序用例承担） |
| F-99 | ✅ 已修 | F98F100-02：`_initializeLocked` 首次/重挂两处读 `Future<bool?>` 返回值——false/null 按失败处理（首次不置 `_initialized` 返回 false 可自然重试 / 重挂走 `onHotCallbackLost` seam 返回 false 不更新 `_registeredCallback`）+ docstring 三处补注「成功 = true 且非 null」+ 插件 22.3.1 覆盖赋值实证引用 + fake `bool? initializeResult` 注入面；先红后绿 3 红实锤 |
| F-100 | ✅ 已修 | F98F100-03：告警 seam 用例 recoverable/doomed 每分支独立 `_FakePlugin`（用例内直接构造 scheduler 避开 build 工厂闭包捕获），消除共享实例顺序敏感断言；行为断言语义零变化；顺序对调双向全绿机器实证 |

### 2026-09-17 — 技术债消费批次（F-91~F-97 全部处置）

> 来源：handoff-techdebt-f78f90-done-2026-09-17 交接指令（project-kickoff 全自动档）。6 工单全部合入（FD-01 `8508af1` / FD-02 `c2e6f0f` / FD-03 `5762ec7` W1 merge `2778ad9`；FD-04 `22672d1` / FD-06 `43efb82` / FD-05 `25eef77` W2 merge；期末修复 R-S1/R-S2 `b0c3650`）。门禁：全量 **1996 测**绿（基线 1987 → +9）/ analyze 0 / 期末四轴 **0 阻断**（Recommended 5 条：R-S1/R-S2 已修，R-F1/R-F2/I-F4 落债 F-98~100）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-92+F-97 | ✅ 已修 | FD-01：通知初始化锁串行 `_initSerial`（并发按序执行，无回调后到者早退静默不触碰插件回调槽——消灭覆盖丢失面）+ 重挂语义（新回调再次 initialize 透传，插件 22.3.1 覆盖赋值实证）+ 告警 seam `initialize(..., onHotCallbackLost:)` 上达装配方（正常/可补救 0、不可补救 ≥1）+ `_hotCallbackRegistered` 语义强化（hot=true ⇔ 插件侧已注册非 null 回调）；先红后绿（7 失败→全绿）；SR-02/03/F-85 消费路径零改动 |
| F-91 | ✅ 已修 | FD-02：新建 `companion_time_windows.dart` 深模块（协议表面 1 符号 `CompanionTimeWindows.activeWindow`），`ProactiveThresholds.activeWindow` 与 `RelationshipThresholds.recentWindow` 双侧引用收敛单源；判定表述统一「≥now−7d 允许、<now−7d 拒绝」；恰 7 天边界锚测试 + 两常量同源锚（主会话补齐） |
| F-93 | ✅ 已修 | FD-03：`sqliteMasterNames`（db_meta.dart）/ `_SaveFailRepo`（save_fail_repo.dart）双份 fixture 迁 test/helpers 单源；notification_service_test 三波末用例 + FD-01 新增反例 setup 收敛 `captureDebugPrint()`（debug_print_capture.dart）；纯搬移行为零变化 |
| F-94 | ✅ 已修 | FD-04：删 `ProactiveMessageService` 构造死参数 `conversationRepository`（按实际 5 处调用点执行：1 装配 + 4 测试）+ 测试替身 super 转发连带清理；grep 零残留、净删 15 行 |
| F-95 | ✅ 已修 | FD-05：`Messages` 新增 `idx_messages_created_at` + schemaVersion 3→4 + onUpgrade `from<4` 分支（CREATE INDEX IF NOT EXISTS 幂等三机制延续）+ 迁移测试断言链同步（冻结 4/索引/user_version=4/自愈四要素）+ 秒精度复证 docstring（F-3 契约不改存储精度）；先红后绿（8 失败→全绿），v1/v2 夹具 DROP INDEX 逼真走补建路径 |
| F-96 | ✅ 已修 | FD-06：`RelationshipThresholds` 构造 assert 链（全档 max 严格递增 + intimateMax+1 ≤ affinityMax + 隐含 gap≥1）；非法注入（intimateMax:100 / max 递减）构造失败先红后绿；默认/自定义合法阈值全档反向自洽增强断言；docstring 注明 assert 仅 debug 生效（防御定位装配/测试期契约，release 无注入面） |

## 复核关闭（最近 4 批，滚动保留）

> 具复核价值的 Speculative 类关闭项单行摘要，防 review 重复提出；更早批次由 git 历史承担（`git log -p -- TECH_DEBT.md`）。

| 编号 | 关闭批次 | 单行摘要 |
|------|----------|----------|
| F-86/F-87 | 2026-09-16 | extractThought 1MiB 截断切破代理对（thought_service.dart:32 现状成立）／关系域读契约双依赖点（chat_service.dart:278/315 注入现状成立），本批聚焦通知域关闭留档 |
| F-74 | 2026-09-10 | 模拟器 server 仅回环绑定 + proxy 目标恒取配置 base + spec 声明不鉴权——加鉴权属过度工程，纵深防御提示留 DEV_LOG |
| F-71/F-72 | 2026-09-10 | patterns= 为 privacy_audit 测试 seam 合法扩展点（非死代码）／FileNameEdgeTrim.none 是默认配置完整性基座（设计意图保留） |
| F-57 | 2026-09-09 | sub.cancel 停滞挂起经三重覆盖收窄，「停止收尾不可跳过」结构性成立，剩余 3s 为 F-17 既定有界契约 |
| F-53/F-54 | 2026-09-09 | `EmptyState.action`／`StatusView.hint` 参数槽 TP-4 共识保留（W1 复核关闭）→ 后被 AR-6 按授权删除（见处置记录） |
| F-58 | 2026-09-09 | 首 token 前 idle 3×60s+退避纯时长 UX 观察，各环行为与契约一致无错判；随 AR-1 行为变更 B1 消亡 |
| F-60/F-61/F-62 | 2026-09-08 | activeCharacterName 状态机零泄漏仅装饰性陈旧／`_BlinkingCursor` ExcludeSemantics 冗余 2 行无行为影响／openConversation 双击竞态为既有字段竞态非本波回归 |