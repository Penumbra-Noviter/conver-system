/// 关系状态机服务 — P4 零 LLM 启发式核心（spec §3 / P4 + 判定⑤⑧⑨ + SR-10）。
///
/// 职责边界（SR-10 强约束）：
/// - **亲密/挚爱候选转移不落库**：`evaluateAfterTurn` 只返回 [StageUpgradeProposal]，
///   写库仅发生在 `confirmStageUpgrade`（服务层唯一写 stage/affinity 的闸门入口）；
///   普通推进（目标非亲密/挚爱）直接落库无需闸门。
/// - UI 只能调请求/确认接口；直接调 repository 不受本服务保护（服务层约束，
///   repository 不设防——评审面确认）。
///
/// 启发式（[RelationshipThresholds] 集中定义，构造可注入；默认值见类内）：
/// 每回合 +1、近 7 天活跃 +2、点开主动消息 +5；五档阈值
/// stranger 0-19 / acquainted 20-39 / familiar 40-59 / intimate 60-79 /
/// soulmate 80-100（含端点语义）。
///
/// 活跃口径（判定⑨）：该角色全部对话最近消息的 distinct 本地日期数
/// （[activeDays]）；「最近 7 天有活动」= 最近消息 createdAt ≥ now − 7d
/// （[isRecentlyActive]，≥ 语义）。
library;

import '../../data/database/app_database.dart' show Message, RelationshipState;
import '../../data/database/tables.dart';
import '../../data/repositories/companion_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/message_repository.dart';

/// 升级提议（亲密/挚爱候选）— 不落库的评估产物（spec 判定⑤）。
class StageUpgradeProposal {
  const StageUpgradeProposal({
    required this.currentStage,
    required this.targetStage,
    required this.affinity,
  });

  /// 当前（DB）阶段。
  final RelationshipStage currentStage;

  /// 候选目标阶段（intimate / soulmate）。
  final RelationshipStage targetStage;

  /// 跨门槛后的应得好感度（确认时写入）。
  final int affinity;
}

/// 启发式阈值常量类 — 产品参数单点（无外部权威，P4 语义自洽默认值）。
///
/// 构造可注入（测试确定性；测试用自定义阈值隔离默认快照）。验收按
/// 常量引用标定，不锁数值快照。
class RelationshipThresholds {
  const RelationshipThresholds({
    this.turnAffinityGain = 1,
    this.activeDayAffinityGain = 2,
    this.proactiveOpenAffinityGain = 5,
    this.strangerMax = 19,
    this.acquaintedMax = 39,
    this.familiarMax = 59,
    this.intimateMax = 79,
  });

  /// 每回合好感度增量。
  final int turnAffinityGain;

  /// 近 7 天活跃的回合额外增量（判定⑨口径的启发式信号）。
  final int activeDayAffinityGain;

  /// 点开主动消息的好感度增量（PS2-08 深链点开触发）。
  final int proactiveOpenAffinityGain;

  /// 五档上限（含端点语义：affinity ≤ max 属本档）。
  final int strangerMax;
  final int acquaintedMax;
  final int familiarMax;
  final int intimateMax;

  /// affinity 合法区间下界。
  static const int affinityMin = 0;

  /// affinity 合法区间上界。
  static const int affinityMax = 100;

  /// 「最近活跃」窗口（spec 判定⑨：now − 7d）。
  static const Duration recentWindow = Duration(days: 7);

  /// affinity → 阶段映射（含端点语义，[RelationshipThresholds.intimateMax]
  /// 之上即 soulmate）。
  RelationshipStage stageForAffinity(int affinity) {
    if (affinity <= strangerMax) {
      return RelationshipStage.stranger;
    }
    if (affinity <= acquaintedMax) {
      return RelationshipStage.acquainted;
    }
    if (affinity <= familiarMax) {
      return RelationshipStage.familiar;
    }
    if (affinity <= intimateMax) {
      return RelationshipStage.intimate;
    }
    return RelationshipStage.soulmate;
  }
}

/// 关系状态机服务 — 评估 / 推进 / 闸门 / 注入 / 活跃口径。
class RelationshipService {
  /// [now] 时间戳注入点（测试确定性，活跃口径共用）；[thresholds] 启发式阈值
  /// 注入点（测试确定性）。
  RelationshipService({
    required CompanionRepository companionRepository,
    required ConversationRepository conversationRepository,
    required MessageRepository messageRepository,
    DateTime Function()? now,
    RelationshipThresholds? thresholds,
  }) : _companion = companionRepository,
       _conversations = conversationRepository,
       _messages = messageRepository,
       _now = now ?? DateTime.now,
       _thresholds = thresholds ?? const RelationshipThresholds();

  final CompanionRepository _companion;
  final ConversationRepository _conversations;
  final MessageRepository _messages;
  final DateTime Function() _now;
  final RelationshipThresholds _thresholds;

  /// clamp 好感度到 [RelationshipThresholds.affinityMin, affinityMax]。
  static int clampAffinity(int value) => value.clamp(
        RelationshipThresholds.affinityMin,
        RelationshipThresholds.affinityMax,
      ).toInt();

  /// 推进好感度：current + delta 后恒 clamp（负增量与超上限均收敛）。
  static int nextAffinity(int current, int delta) =>
      clampAffinity(current + delta);

  /// 构建每轮注入片段（spec P4：每轮 system 注入「当前关系阶段」）。
  ///
  /// 内容含 stage 英文值与 affinity 数值。
  static String buildRelationshipInjection({
    required RelationshipStage stage,
    required int affinity,
  }) {
    return '当前关系阶段：${stage.value}；好感度：$affinity';
  }

  /// 回合末评估：推进好感度并决定是否触发升级提议。
  ///
  /// - 无状态行：首次 upsert 默认 stranger/affinity 0，返回 null（判定⑧，
  ///   首回合不注入）。
  /// - 普通推进（目标非 intimate/soulmate）：直接落库 stage+affinity，返回 null。
  /// - 跨 intimate/soulmate 门槛：返回 [StageUpgradeProposal]，**不写库**
  ///   （SR-10：确认前绝不留痕；proposal 不落库 → 同回合重复调用天然幂等）。
  Future<StageUpgradeProposal?> evaluateAfterTurn({
    required int characterId,
    required int conversationId,
  }) async {
    var state = await _companion.getRelationship(characterId);
    if (state == null) {
      await _companion.upsertRelationship(
        characterId: characterId,
        stage: RelationshipStage.stranger,
        affinity: 0,
      );
      return null;
    }

    final gain = await _turnGain(characterId);
    final newAffinity = nextAffinity(state.affinity, gain);
    return _applyOrPropose(state, newAffinity, characterId);
  }

  /// 确认升级闸门（SR-10 唯一写 intimate/soulmate 的入口）。
  ///
  /// 重算当前应得 affinity（确定性推进，与 [evaluateAfterTurn] 同源），
  /// 写 stage=targetStage + affinity + updatedAt=now（SR-15 观察：
  /// 确认时 updatedAt 即转移轨迹时间）。无状态行 → no-op（防御路径）。
  Future<void> confirmStageUpgrade({
    required int characterId,
    required RelationshipStage targetStage,
  }) async {
    final state = await _companion.getRelationship(characterId);
    if (state == null) {
      return;
    }
    final newAffinity = nextAffinity(state.affinity, await _turnGain(characterId));
    await _companion.upsertRelationship(
      characterId: characterId,
      stage: targetStage,
      affinity: newAffinity,
    );
  }

  /// 拒绝升级：丢弃提议，零写库副作用（proposal 本就未落库）。
  ///
  /// 「本回合不再重复提议」的幂等由调用方（PS2-08 broker）状态保证。
  Future<void> rejectStageUpgrade({required int characterId}) async {
    // 显式 no-op：确认闸门拒绝路径的语义占位，防未来误写库。
  }

  /// 点开主动消息 + [RelationshipThresholds.proactiveOpenAffinityGain]
  /// （spec P4 启发式来源；PS2-08 深链点开调用）。
  ///
  /// 与 [evaluateAfterTurn] 同构：无行先建默认；跨亲密/挚爱门槛返回
  /// proposal 不写库，否则直接落库。
  Future<StageUpgradeProposal?> recordProactiveMessageOpened(
    int characterId,
  ) async {
    var state = await _companion.getRelationship(characterId);
    if (state == null) {
      await _companion.upsertRelationship(
        characterId: characterId,
        stage: RelationshipStage.stranger,
        affinity: 0,
      );
      state = await _companion.getRelationship(characterId);
    }
    final newAffinity = nextAffinity(
      state!.affinity,
      _thresholds.proactiveOpenAffinityGain,
    );
    return _applyOrPropose(state, newAffinity, characterId);
  }

  /// 该角色全部对话最近消息的 distinct 本地日期数（判定⑨；PS2-05 复用）。
  Future<int> activeDays(int characterId) async {
    final messages = await _allMessagesFor(characterId);
    return messages
        .map((m) => DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day))
        .toSet()
        .length;
  }

  /// 「最近 7 天有活动」：最近消息 createdAt ≥ now − 7d（≥ 语义，判定⑨）。
  Future<bool> isRecentlyActive(int characterId) async {
    final messages = await _allMessagesFor(characterId);
    if (messages.isEmpty) {
      return false;
    }
    final latest = messages
        .map((m) => m.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return !latest.isBefore(_now().subtract(RelationshipThresholds.recentWindow));
  }

  /// 回合推进增量：每回合 + 近 7 天活跃额外增量。
  ///
  /// 「每日活跃 +2」取活跃信号（isRecentlyActive）而非 activeDays 乘法——
  /// 防单次评估因历史活跃天数过多产生跳档跳跃；数值经 [nextAffinity] 恒 clamp。
  Future<int> _turnGain(int characterId) async {
    var gain = _thresholds.turnAffinityGain;
    if (await isRecentlyActive(characterId)) {
      gain += _thresholds.activeDayAffinityGain;
    }
    return gain;
  }

  /// 推进或提议：目标为 intimate/soulmate 且跨档 → 返回 proposal（不写库）；
  /// 其余（同档推进 / 普通跨档）→ 直接落库 stage+affinity。
  Future<StageUpgradeProposal?> _applyOrPropose(
    RelationshipState state,
    int newAffinity,
    int characterId,
  ) async {
    final newStage = _thresholds.stageForAffinity(newAffinity);
    final crossesGate = (newStage == RelationshipStage.intimate ||
            newStage == RelationshipStage.soulmate) &&
        newStage != state.stage;
    if (crossesGate) {
      return StageUpgradeProposal(
        currentStage: state.stage,
        targetStage: newStage,
        affinity: newAffinity,
      );
    }
    await _companion.upsertRelationship(
      characterId: characterId,
      stage: newStage,
      affinity: newAffinity,
    );
    return null;
  }

  /// 该角色全部对话的全部消息（活跃口径数据源）。
  Future<List<Message>> _allMessagesFor(int characterId) async {
    final conversations = await _conversations.listConversations(
      characterId: characterId,
    );
    final messages = <Message>[];
    for (final entry in conversations) {
      messages.addAll(await _messages.getMessages(entry.conversation.id));
    }
    return messages;
  }
}