# ADR-0006：人机恋板块——关系状态机（阶段 2）

## 决策背景

阶段 2 需要给角色一个可感知的「关系成长」维度：好感度（affinity 0-100）启发式推进 + 五档阶段（stranger → acquainted → familiar → intimate → soulmate）。核心矛盾：推进逻辑必须零 LLM（每回合评估不能新增 API 调用），但「亲密/挚爱」是强情感门槛，自动跨档会破坏陪伴信任（用户还没准备好，角色就「表白」了）——需要用户确认闸门。

## 前提拆解（第一性原理）

- **不可变事实**：Flutter + 本地优先；阶段 1/1.5 确立「记忆失败不阻断主回复」「LLM 成本用户可控」硬约束；`RelationshipStates` 表（PS2-01 冻结）字段 = characterId（unique）+ stage + affinity + updatedAt，无额外列可加（schemaVersion 已冻结）。
- **习得惯例**：`now` 注入 + 纯函数阈值集中常量（`ReflectionService` interval 先例）；断言性测试先红后绿（W3 F1 返修先例）。

## 可选方案

### 推进启发式
1. 方案A 每回合 +1 + 近 7 天活跃 +2 + 点开主动消息 +5（常量集中可注入）：低成本、可测、参数单点。
2. 方案B LLM 语义评估：更「智能」但每回合多一次调用，违背零 LLM 约束。

### 门槛处理
1. 方案A 自动跨档：简单但亲密/挚爱无用户确认，破坏信任。
2. 方案B 亲密/挚爱确认闸门：proposal 不落库（spec 判定⑤），确认才写（SR-10）。

### 状态写入边界
1. 服务层唯一写口（`confirmStageUpgrade` 合法后继校验 F1）：仓储不设防，约束在服务契约面成立。
2. 仓储层防：破坏只读共享边界（仓储被多服务复用）。

## 最终选择

✅ 启发式 = **方案A**（`RelationshipThresholds` 常量类 + 构造可注入；每回合 +1 / 近 7 天活跃 +2 / 点开主动消息 +5；五档阈值 0-19/20-39/40-59/60-79/80-100 含端点）
✅ 评估 = `evaluateAfterTurn` 返回 `StageUpgradeProposal?` 不写库；普通推进（目标非 intimate/soulmate）直接落库；跨亲密/挚爱门槛只出 proposal
✅ 闸门 = `confirmStageUpgrade({characterId, targetStage})` 唯一写口 + **F1 合法后继域校验**（单向自增，拒降档/越级/原地）；`rejectStageUpgrade` 显式 no-op
✅ 注入 = `buildRelationshipInjection` 每轮 system 注入「当前关系阶段 + 好感度」（判定⑧：有状态行才注入，首回合不注入）
✅ 活跃口径 = `activeDays`（distinct 本地日期数）/ `isRecentlyActive`（最近消息 ≥ now−7d），判定⑨单一来源
> **退役注记（2026-09-21 架构批次）**：`activeDays` 已退役删除（F-81/F-91 后无生产消费方），活跃口径执行侧收敛于 `latestMessageAt` → `isRecentlyActive`（F-81 单源）；名字可按未来展示需求重开。
✅ 广播 = ChatService 回调 → `StageUpgradeBroker.publish`（装配层 ChangeNotifier），UI 消费 `lastProposal`

## 理由

- 零 LLM 推进把关系成长成本压到常数级，与计费敏感（ADR-0003）一致；启发式参数单点可调。
- 确认闸门让「亲密/挚爱」成为用户显式选择：proposal 不落库意味着未确认状态零残留（SR-10），重复评估天然幂等。
- F1 域校验（W3 返修）补上闸门的合法域约束：即使 UI 误调 confirm(familiar) 也不能降档写库。
- `now` 注入使时间边界（== now / ±7d）可精确测试，Falsify 面完整。

## 影响

- 正面：关系状态零成本演进、确认即信任、状态写入单口可审计（SR-10/SR-15 updatedAt=now 即转移轨迹）。
- 代价：启发式是产品参数无外部权威（数值快照不锁，按常量引用标定）；`evaluateAfterTurn.conversationId` 当前为预留参数（F4 观察，活跃口径以角色维度计算）。
