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
| F-104 | `characters_view_stage2_test`「publish 驱动确认/拒绝」全量首跑偶发失败（1999+1），单跑/重跑全绿，与本批 diff 零交集——存量 flaky | 期末四轴 F101F103（Spec 门禁实测） | 低 | 📝 待立项 | 测试 |
| F-105 | 票面纠偏表述精确化：「若锁失效并行交错则为 1」从未存在于**代码 reason**（`git log -S` 命中均为文档/注释引述），非「从未存在于仓库」——核心结论（A 方案修正对象不存在）成立，仅表述收窄 | 期末四轴 F101F103（Falsify） | Speculative | 📝 待立项 | 测试/文档 |

## 技术债处置记录

### 2026-09-17 — 技术债消费批次（F-101~F-103 全部处置）

> 来源：handoff-techdebt-f98f100-done-2026-09-17 交接指令（project-kickoff 全自动档）。2 工单并批 1 波串行 lane（F101F103-01 `8fd29fe` merge `61c9ca3` / F101F103-02 `3d2b8b1` merge `61c9ca3`）。门禁：全量 **2000 测**绿 / analyze 0 / 期末四轴 **0 阻断**（F-103 复核关闭；无新落债）。票面纠偏：F-101 票面「修正 reason 文本」修正对象不存在（「若锁失效并行交错则为 1」从未存在于**代码 reason**（文档/注释引述除外），`git log -S` 命中 4 commit（`8fd29fe`/`5aeffe7`/`2d26a0f`/`1fc3987`）均为文档/注释引述，`git show 76f7da8` 原文为「若早退拦截则为 1」）；B′ 双 gate 中间态断言为唯一零生产改动独立钉锁方案，突变实验实锤（移除 `await previous` → 中间态期望 1 实际 2 红）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-101 | ✅ 已修 | F101F103-01：反序 gate 用例重构双 gate 两阶段 + 中间态 `initializeCalls==1` 断言独立钉 `_initSerial` 锁等待（锁失效突变下红）；fake 零改动、生产零 diff；先红后绿（临时移除 `await previous` → 期望 1 实际 2 红，恢复全绿） |
| F-102 | ✅ 已修 | F101F103-02：告警 seam 用例正常分支独立 `_FakePlugin` + 独立 scheduler，用例内组级 plugin/scheduler 零引用（字面验收线达成）；行为断言语义零变化；顺序对调双向全绿机器实证；生产零 diff |
| F-103 | ❌ 复核关闭 | 全仓 188 文件/223 检查 format 差异为存量 formatter 版本漂移（上批基线 `3943bf8` 同检查失败、hunk 一一对应），无行为风险；全仓归一大 diff 噪音，用户已拍板不立项 |

### 2026-09-17 — 技术债消费批次（F-98~F-100 全部处置）

> 来源：handoff-techdebt-f91f97-done-2026-09-17 交接指令（project-kickoff 全自动档）。3 工单并批 1 波串行 lane（F98F100-01 `76f7da8` merge `49a1b12` / F98F100-02 `562e968` merge `e9bfc10` / F98F100-03 `e378f78` merge `6f67160`）。门禁：全量 **2000 测**绿（基线 1996 → +4）/ analyze 0 / 期末四轴 **0 阻断**（结论位「需修 Recommended 2 项无 Critical」：R-S1 dart format 已修、R-S2 文档同步本 commit 收口）；非阻断落债 F-101~103。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-98 | ✅ 已修 | F98F100-01：补反序并发交错 gate 用例（无回调 initialize 挂起 → 带回调后进入 → `_initSerial` 锁串行重挂），钉 `initializeCalls==2` / `registeredCallback same(hotCallback)` / 零告警 / 重挂后可消费；纯测试生产零 diff；锁矩阵正/反双向闭合（Falsify 突变实证：反序钉结果语义、锁机制钉力由正序用例承担） |
| F-99 | ✅ 已修 | F98F100-02：`_initializeLocked` 首次/重挂两处读 `Future<bool?>` 返回值——false/null 按失败处理（首次不置 `_initialized` 返回 false 可自然重试 / 重挂走 `onHotCallbackLost` seam 返回 false 不更新 `_registeredCallback`）+ docstring 三处补注「成功 = true 且非 null」+ 插件 22.3.1 覆盖赋值实证引用 + fake `bool? initializeResult` 注入面；先红后绿 3 红实锤 |
| F-100 | ✅ 已修 | F98F100-03：告警 seam 用例 recoverable/doomed 每分支独立 `_FakePlugin`（用例内直接构造 scheduler 避开 build 工厂闭包捕获），消除共享实例顺序敏感断言；行为断言语义零变化；顺序对调双向全绿机器实证 |

## 复核关闭（最近 4 批，滚动保留）

> 具复核价值的 Speculative 类关闭项单行摘要，防 review 重复提出；更早批次由 git 历史承担（`git log -p -- TECH_DEBT.md`）。

| 编号 | 关闭批次 | 单行摘要 |
|------|----------|----------|
| F-103 | 2026-09-17 | 全仓 188 文件/223 检查 format 差异为存量 formatter 版本漂移（基线 `3943bf8` 同失败、hunk 一一对应），无行为风险；全仓归一大 diff 噪音已拍板不立项 |
| F-86/F-87 | 2026-09-16 | extractThought 1MiB 截断切破代理对（thought_service.dart:32 现状成立）／关系域读契约双依赖点（chat_service.dart:278/315 注入现状成立），本批聚焦通知域关闭留档 |
| F-74 | 2026-09-10 | 模拟器 server 仅回环绑定 + proxy 目标恒取配置 base + spec 声明不鉴权——加鉴权属过度工程，纵深防御提示留 DEV_LOG |
| F-71/F-72 | 2026-09-10 | patterns= 为 privacy_audit 测试 seam 合法扩展点（非死代码）／FileNameEdgeTrim.none 是默认配置完整性基座（设计意图保留） |
| F-57 | 2026-09-09 | sub.cancel 停滞挂起经三重覆盖收窄，「停止收尾不可跳过」结构性成立，剩余 3s 为 F-17 既定有界契约 |
| F-53/F-54 | 2026-09-09 | `EmptyState.action`／`StatusView.hint` 参数槽 TP-4 共识保留（W1 复核关闭）→ 后被 AR-6 按授权删除（见处置记录） |
| F-58 | 2026-09-09 | 首 token 前 idle 3×60s+退避纯时长 UX 观察，各环行为与契约一致无错判；随 AR-1 行为变更 B1 消亡 |