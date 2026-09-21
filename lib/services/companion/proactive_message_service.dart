/// ProactiveMessageService — 主动消息业务层（人机恋阶段 2 PS2-05）。
///
/// 深模块：协议表面 = [ProactiveThresholds] / [ProactiveDecision] /
/// [evaluateSchedule] / [ProactivePlanDecision] / [ProactivePlanner] /
/// [parseProactivePlan] / [buildProactiveMessages] /
/// [planProactiveWithProvider] / [ProactiveNotificationScheduler] /
/// [ProactiveMessageService.planAfterTurn] 一个编排入口。实现内聚「开关 →
/// 过期核对 → 节流判定 → LLM 规划 seam → 落真实 assistant 消息 + scheduled
/// 计划 → 通知排程 seam」完整闭环，失败一律 debugPrint + 返回 0 降级，
/// 不阻断回合收尾（spec §2 横切，与反思同构）。
///
/// 语义锚点：
/// - P1/P2/P6：预生成 + OS 本地通知排程；回合末异步规划；落真实 assistant
///   消息（进会话历史、深链可定位）。
/// - §6 判定③：每日计数/冷却口径 = `ProactivePlans.sentAt`（sent 时写入）。
/// - §6 判定④：LLM 产出 `minutesFromNow` 整数（10–360），服务端
///   `nextAt = now + minutes`——规避 ISO/时区解析坑。
/// - §6 判定⑥：messageId 为 null 且 scheduled → dropped；scheduledAt 已过
///   → expired（两者都命中时 dropped 优先——消息载体已消失，计划残废）。
/// - SR-01：三级容错 + 字段级校验，任一失败 → null 不写库不调 scheduler。
/// - SR-04：pending 单条约束——过期核对 + in-flight 节流 + 每角色内存锁
///   三重保证（F-125 后：in-flight 经 [CompanionRepository.getActivePlan]
///   单角色查询，`limit(1)` 多行不抛，不再全表拉取绕路）。
/// - SR-07：本票为规划侧（createPlan 语义）；发送 CAS 落发送服务。
/// - SR-08：启动重建排程恢复留给 PS2-08 装配调用，本票提供
///   [_reconcileOverdue] 的回合入口版本（只处理本角色）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../utils/llm_json_candidates.dart';
import '../../data/database/app_database.dart' show ProactivePlan;
import '../../data/database/tables.dart' show ProactivePlanStatus, Role;
import '../../data/repositories/companion_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../llm/dialogue_window.dart';
import '../llm/llm_provider.dart' show LlmMessage, LLMProvider;
import 'companion_time_windows.dart' show CompanionTimeWindows;

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（对齐 reflection_service 惯例）。
// ignore_for_file: prefer_initializing_formals

/// 主动消息节流与排程阈值 — 产品参数的单一归属（spec §2 P2 + §6 判定③④）。
/// 活跃窗口常量引用 [CompanionTimeWindows.activeWindow]（F-91 单源，与
/// relationship 侧共享；改窗口只动伴侣域单源模块）。
abstract final class ProactiveThresholds {
  /// 每日发送上限（判定③：当日 sentAt 计数，全局口径）。
  static const int dailyLimit = 6;

  /// 角色冷却（判定③：最近 sentAt 距今 ≥ 6h 才可再规划）。
  static const Duration roleCooldown = Duration(hours: 6);

  /// 活跃窗口（P2：仅 7 天内有活动的角色可规划；F-91 单源引用，边界语义
  /// 「最近活跃时间 >= now − 7d 允许、< now − 7d 拒绝」，恰 7 天允许）。
  static const Duration activeWindow = CompanionTimeWindows.activeWindow;

  /// LLM 决策 minutesFromNow 下界（判定④；SR-04 防短间隔通知风暴）。
  static const int minMinutesFromNow = 10;

  /// LLM 决策 minutesFromNow 上界（判定④；SR-04 防无限延迟累积）。
  static const int maxMinutesFromNow = 360;

  /// 送入规划的最近对话消息条数上限（对齐反思 historyLimit 惯例）。
  static const int historyLimit = 20;
}

/// 节流判定结果 — [allowed] 为 true 时 [reason] 恒为 'ok'。
class ProactiveDecision {
  const ProactiveDecision({required this.allowed, required this.reason});

  /// 是否允许本轮规划。
  final bool allowed;

  /// 节流原因标识：'ok' / 'daily_limit' / 'cooldown' / 'inactive' / 'in_flight'。
  final String reason;
}

/// 节流纯函数（可单测，now 注入精确断言阈值边界）。
///
/// 判定顺序与原因：每日上限 → 冷却 → 活跃窗口 → 在途计划。边界口径
/// （F-91 统一语义锚，与 relationship 侧 `>= now − 7d 允许` 一致）：
/// `sentToday >= dailyLimit` 拒绝；冷却 `now - lastSentAt < 6h` 拒绝（恰好
/// 6h 允许）；活跃 `lastActiveAt < now − 7d` 或从未活跃拒绝（恰 7d 允许）。
ProactiveDecision evaluateSchedule({
  required int sentToday,
  required DateTime? lastSentAt,
  required DateTime? lastActiveAt,
  required bool hasInFlightPlan,
  required DateTime now,
}) {
  if (sentToday >= ProactiveThresholds.dailyLimit) {
    return const ProactiveDecision(allowed: false, reason: 'daily_limit');
  }
  if (lastSentAt != null &&
      now.difference(lastSentAt) < ProactiveThresholds.roleCooldown) {
    return const ProactiveDecision(allowed: false, reason: 'cooldown');
  }
  if (lastActiveAt == null ||
      lastActiveAt.isBefore(now.subtract(ProactiveThresholds.activeWindow))) {
    return const ProactiveDecision(allowed: false, reason: 'inactive');
  }
  if (hasInFlightPlan) {
    return const ProactiveDecision(allowed: false, reason: 'in_flight');
  }
  return const ProactiveDecision(allowed: true, reason: 'ok');
}

/// LLM 主动规划决策（判定④）：`shouldSend` 是否发、`minutesFromNow` 多少分钟
/// 后（整数，10–360）、`content` 预生成文案。
typedef ProactivePlanDecision = ({
  bool shouldSend,
  int minutesFromNow,
  String content,
});

/// 规划 seam：输入角色与对话上下文，产出 [ProactivePlanDecision]；返回 null
/// 表示「本次不规划 / 解析失败」（调用方降级，不写库不调 scheduler）。
///
/// 生产装配用 [planProactiveWithProvider]（generate + [parseProactivePlan]），
/// 测试注入 fake。PS2-06 只负责 [ProactiveNotificationScheduler] 平台实现。
typedef ProactivePlanner = Future<ProactivePlanDecision?> Function({
  required int characterId,
  required int conversationId,
  required List<String> dialogueLines,
});

/// 通知排程 seam（接口声明于本票，PS2-06 实现平台薄层）— 为已落库计划注册
/// 一次 OS 本地通知（判定⑦ inexact 模式细节归实现方）。
abstract interface class ProactiveNotificationScheduler {
  /// 排程 [plan] 的本地通知；**false = 失败不抛**（P3 站内兜底信号，对齐
  /// PS2-06 `FlutterLocalNotificationsScheduler` 实现——平台/权限/初始化
  /// 异常由实现内部消化为 false）。调用方依据返回值决定是否展示站内失败
  /// 提示；本 seam 不向上抛。
  Future<bool> schedule(ProactivePlan plan);
}

/// 解析 LLM 输出的 JSON 对象（SR-01 三级容错，对齐 [parseReflectionFacts]
/// 思路但目标为对象）：
///
/// 1. 直接 JSON 对象；
/// 2. ```json / ``` 代码块提取；
/// 3. 大括号范围提取（首个 `{` 到末个 `}`）。
///
/// 字段级校验（任一失败 → null，不抛异常）：`shouldSend` 必须 bool；
/// `minutesFromNow` 必须有限数值且为整数（12.5 拒绝；NaN/Infinity 经
/// isFinite 拒绝）且落在 [ProactiveThresholds.minMinutesFromNow,
/// maxMinutesFromNow]；`content` 必须字符串且 trim 非空。多余字段宽容忽略。
ProactivePlanDecision? parseProactivePlan(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }

  // 候选段枚举（直接 trim 原文 → fenced 段 → 大括号范围段）由
  // [llmJsonCandidates] 单源承载；本函数只保留 object 字段校验解码。
  for (final candidate in llmJsonCandidates(text, open: '{', close: '}')) {
    final decoded = _decodePlan(candidate);
    if (decoded != null) {
      return decoded;
    }
  }

  return null;
}

/// 尝试把 [text] 解析为合法决策对象；失败或字段非法返回 null。
ProactivePlanDecision? _decodePlan(String text) {
  Object? data;
  try {
    data = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (data is! Map) {
    return null;
  }

  final shouldSend = data['shouldSend'];
  if (shouldSend is! bool) {
    return null;
  }

  final minutes = data['minutesFromNow'];
  if (minutes is! num || !minutes.isFinite) {
    return null;
  }
  final minutesInt = minutes.toInt();
  if (minutes != minutesInt) {
    return null;
  }
  if (minutesInt < ProactiveThresholds.minMinutesFromNow ||
      minutesInt > ProactiveThresholds.maxMinutesFromNow) {
    return null;
  }

  final content = data['content'];
  if (content is! String || content.trim().isEmpty) {
    return null;
  }

  return (shouldSend: shouldSend, minutesFromNow: minutesInt, content: content);
}

/// 组装规划 prompt（纯函数，可单测）。
///
/// system 教导 LLM 只输出 JSON 对象（shouldSend bool / minutesFromNow 整数
/// 10–360 / content 文案），无解释/前缀/Markdown 代码块；user 附对话历史
/// （user 行带「用户：」前缀，assistant 行原文直给——角色名不在本票仓储
/// 共享面内，由 LLM 从对话上下文自明）。
List<LlmMessage> buildProactiveMessages({required List<String> dialogueLines}) {
  final dialogueBlock = dialogueLines.isEmpty
      ? '（暂无对话记录）'
      : dialogueLines.join('\n');
  return [
    LlmMessage(
      role: 'system',
      content:
          '你是这段对话中的 AI 伴侣角色。判断是否应该在近期主动给用户发'
          '一条消息：如果适合，content 写一句自然、贴合当前关系的主动问候或'
          '话题（简洁，1-2 句）；如果不适合，shouldSend 为 false。'
          '只输出一个 JSON 对象：{"shouldSend": true/false, '
          '"minutesFromNow": 10到360之间的整数, "content": "消息内容"}。'
          '不要任何解释、前缀或 Markdown 代码块。minutesFromNow 必须是整数。',
    ),
    LlmMessage(
      role: 'user',
      content: '对话记录：\n$dialogueBlock\n\n请输出主动消息决策（JSON 对象）：',
    ),
  ];
}

/// 生产装配用的规划实现：组装 prompt 并经 [llm].generate 产出决策。
///
/// [model] 为调用模型名（透传 provider）；返回 [ProactivePlanDecision?] 与
/// [ProactivePlanner] 签名同形（装配层闭包绑定 llm/model 后传入服务）。
/// generate 抛错 → 上抛（由服务降级）；输出非法 → null（不抛）。
Future<ProactivePlanDecision?> planProactiveWithProvider({
  required LLMProvider llm,
  required String model,
  required int characterId,
  required int conversationId,
  required List<String> dialogueLines,
}) async {
  final messages = buildProactiveMessages(dialogueLines: dialogueLines);
  final raw = await llm.generate(messages: messages, model: model);
  return parseProactivePlan(raw);
}

/// 主动消息服务 — 回合末异步规划编排。
class ProactiveMessageService {
  /// [now] 为时间戳来源注入点（测试确定性用），缺省 [DateTime.now]；
  /// [onScheduleFailed] 为排程失败站内兜底回调（P3：schedule 返回 false 时
  /// 触发，收到对应 plan；装配层经它展示 SnackBar，启动恢复路径不接）。
  ProactiveMessageService({
    required CompanionRepository companionRepository,
    required SettingsRepository settingsRepository,
    required MessageRepository messageRepository,
    required ProactivePlanner planner,
    required ProactiveNotificationScheduler scheduler,
    DateTime Function()? now,
    void Function(ProactivePlan plan)? onScheduleFailed,
  }) : _companion = companionRepository,
       _settings = settingsRepository,
       _messages = messageRepository,
       _planner = planner,
       _scheduler = scheduler,
       _now = now ?? DateTime.now,
       _onScheduleFailed = onScheduleFailed;

  final CompanionRepository _companion;
  final SettingsRepository _settings;
  final MessageRepository _messages;
  final ProactivePlanner _planner;
  final ProactiveNotificationScheduler _scheduler;
  final DateTime Function() _now;
  final void Function(ProactivePlan plan)? _onScheduleFailed;

  /// 每角色在途规划链（并发 in-flight 串行化，SR-04）：同角色第二次并发
  /// 调用直接返回 0，不产生第二条计划。
  final Map<int, Future<int>> _inflight = <int, Future<int>>{};

  /// 回合落库后触发一次主动规划（异步 fire-and-forget）。
  ///
  /// 编排：开关关 → 0 且零副作用；过期核对（判定⑥）→ 节流数据与判定 →
  /// [planner] 决策 → 落真实 assistant 消息 + scheduled 计划（scheduledAt =
  /// now + minutes，messageId 回填）→ [scheduler] 恰好一次。任何阶段失败
  /// （含仓储异常）→ debugPrint + 返回 0，不向上抛（spec 横切）。
  ///
  /// 返回值为本次落库计划数（0 = 未规划/被拒/降级；1 = 落了一条 scheduled）。
  Future<int> planAfterTurn({
    required int characterId,
    required int conversationId,
  }) async {
    if (!await _settings.proactiveMessageEnabled) {
      return 0;
    }
    final existing = _inflight[characterId];
    if (existing != null) {
      return 0;
    }
    final future = _planForCharacter(characterId, conversationId);
    _inflight[characterId] = future;
    try {
      return await future;
    } finally {
      if (identical(_inflight[characterId], future)) {
        _inflight.remove(characterId);
      }
    }
  }

  Future<int> _planForCharacter(int characterId, int conversationId) async {
    try {
      final now = _now();

      // 判定⑥ + SR-08 回合入口版：本角色 scheduled 计划核对（dropped 优先）。
      await _reconcileOverdue(characterId, now);

      final sentPlans = await _companion.listPlansByStatus(
        ProactivePlanStatus.sent,
      );
      var sentToday = 0;
      DateTime? lastSentAt;
      for (final plan in sentPlans) {
        final at = plan.sentAt;
        if (at == null) {
          continue;
        }
        // 口径（spec §2 P2 + 判定③ / W3-F2）：每日上限为**全局**（全角色
        // 当日 sentAt 合计），角色冷却为**本角色**最近 sentAt（角色间互不
        // 影响——角色 A 已发不会冷却角色 B）。
        if (CompanionTimeWindows.isSameLocalDay(at, now)) {
          sentToday++;
        }
        if (plan.characterId == characterId &&
            (lastSentAt == null || at.isAfter(lastSentAt))) {
          lastSentAt = at;
        }
      }
      final lastActiveAt = await _lastActiveAt(characterId);
      final hasInFlight = await _hasInFlightPlan(characterId);
      final gate = evaluateSchedule(
        sentToday: sentToday,
        lastSentAt: lastSentAt,
        lastActiveAt: lastActiveAt,
        hasInFlightPlan: hasInFlight,
        now: now,
      );
      if (!gate.allowed) {
        return 0;
      }

      final dialogueLines = await _dialogueLines(conversationId);
      final decision = await _planner(
        characterId: characterId,
        conversationId: conversationId,
        dialogueLines: dialogueLines,
      );
      if (decision == null) {
        debugPrint('proactive plan: planner returned null, skip');
        return 0;
      }
      if (!decision.shouldSend) {
        return 0;
      }

      final message = await _messages.createMessage(
        conversationId: conversationId,
        role: Role.assistant,
        content: decision.content,
      );
      final plan = await _companion.createPlan(
        characterId: characterId,
        conversationId: conversationId,
        content: decision.content,
        scheduledAt: now.add(Duration(minutes: decision.minutesFromNow)),
        messageId: message.id,
      );
      final scheduled = await _scheduler.schedule(plan);
      if (!scheduled) {
        // P3 站内兜底信号：排程失败不抛、不阻断回合收尾，仅通知装配层。
        _onScheduleFailed?.call(plan);
        return 0;
      }
      return 1;
    } catch (e) {
      debugPrint('proactive plan degraded: $e');
      return 0;
    }
  }

  /// 送达收口（期末四轴 C1 / SR-07 / F-88 收口放宽）：通知点按/触达后置
  /// sent + sentAt。
  ///
  /// 状态白名单 = {scheduled, expired}：scheduled 计划点按 → 置 sent（sentAt
  /// 缺省取本层 now）；expired 计划点按 → 同样置 sent（F-88：点按即送达
  /// 证据——expired 仅表示「不重排不发送」，用户实际触达仍是事实，计入节流
  /// 计数与亲密值）。sent 幂等（重复点按返回 null 且零写库，sentAt 不被
  /// 覆盖）；dropped / 不存在（含 messageId null 查不到）→ null 且零写库。
  /// 返回**送达操作对应的计划快照**（status 仍为 scheduled/expired、sentAt
  /// null——更新前状态），消费面仅用 characterId 记录「点开主动消息 +5」
  /// （P4 启发式）；状态/sentAt 以库内查回为准。
  Future<ProactivePlan?> markDeliveredByMessageId(
    int messageId, {
    DateTime? at,
  }) async {
    final plan = await _companion.getPlanByMessageId(messageId);
    if (plan == null ||
        (plan.status != ProactivePlanStatus.scheduled &&
            plan.status != ProactivePlanStatus.expired)) {
      return null;
    }
    await _companion.updatePlanStatus(
      plan.id,
      ProactivePlanStatus.sent,
      sentAt: at ?? _now(),
    );
    return plan;
  }

  /// 过期核对（判定⑥）：本角色 scheduled 计划中 messageId 为 null → dropped
  /// （消息载体已消失，优先）；scheduledAt ≤ now → expired。幂等：置位后不再
  /// 命中 scheduled 查询。
  ///
  /// F-151：谓词单源进 SQL——dropped 经
  /// [CompanionRepository.listScheduledWithNullMessage]（无时间条件），
  /// expired 经 [CompanionRepository.listOverdueScheduled]（scheduledAt ≤ now，
  /// 含端点）；两定位读均按 characterId 过滤，不再全表拉 scheduled 再内存
  /// 过滤。dropped 先置位，随后的 overdue 查询因此自然排除已置 dropped 的
  /// 计划（状态不再是 scheduled），保持「两者命中 dropped 优先」判定⑥。
  Future<void> _reconcileOverdue(int characterId, DateTime now) async {
    final noMessage = await _companion.listScheduledWithNullMessage(
      characterId: characterId,
    );
    for (final plan in noMessage) {
      await _companion.updatePlanStatus(plan.id, ProactivePlanStatus.dropped);
    }
    final overdue = await _companion.listOverdueScheduled(
      now,
      characterId: characterId,
    );
    for (final plan in overdue) {
      await _companion.updatePlanStatus(plan.id, ProactivePlanStatus.expired);
    }
  }

  /// 角色活跃时间 = 该角色全部对话最近消息 createdAt 全局最大值（判定⑨
  /// 「最近消息」口径）；无消息返回 null。改调
  /// [MessageRepository.latestMessageAt] 单源实现（F-81：不再按对话
  /// getMessages 自算，消除对消息返回顺序的隐式依赖）。
  Future<DateTime?> _lastActiveAt(int characterId) {
    return _messages.latestMessageAt(characterId);
  }

  /// 在途判定（SR-04）：本角色存在 scheduled 计划（reconcile 后剩余即真正
  /// 在途）。F-125：改调 [CompanionRepository.getActivePlan]（`limit(1)` 后
  /// 多行不再抛），替代此前全表拉取再按角色过滤的绕路。
  Future<bool> _hasInFlightPlan(int characterId) async {
    return await _companion.getActivePlan(characterId) != null;
  }

  /// 组装对话行（user 署名「用户」，assistant 原文直给），截取最近
  /// [ProactiveThresholds.historyLimit] 条（经
  /// [MessageRepository.recentMessages] 定位读 + [recentDialogueWindow]
  /// 单源窗口 builder）。
  Future<List<String>> _dialogueLines(int conversationId) async {
    return [
      for (final m in recentDialogueWindow(
        await _messages.recentMessages(
          conversationId,
          ProactiveThresholds.historyLimit,
        ),
        limit: ProactiveThresholds.historyLimit,
      ))
        m.role == Role.user ? '用户：${m.content}' : m.content,
    ];
  }
}
