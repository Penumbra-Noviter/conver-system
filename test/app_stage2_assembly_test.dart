/// PS2-08 装配层契约测试 — StageUpgradeBroker / 深链导航（SR-03）/
/// 启动排程恢复（SR-08）/ ConverApp MultiProvider 冒烟。
library;

import 'package:conver_system_mobile/app.dart';
import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/companion_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/services/companion/proactive_message_service.dart';
import 'package:conver_system_mobile/services/companion/relationship_service.dart';
import 'package:conver_system_mobile/services/companion/stage_upgrade_broker.dart';
import 'package:conver_system_mobile/services/companion/thought_service.dart';
import 'package:conver_system_mobile/services/notifications/notification_service.dart';
import 'package:conver_system_mobile/view_models/shell_navigation.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show
        AndroidScheduleMode,
        DidReceiveNotificationResponseCallback,
        InitializationSettings,
        NotificationDetails,
        NotificationResponse,
        NotificationResponseType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;

import 'helpers/chat_test_env.dart' show ChatTestEnv, FakeSettingsReader;
import 'helpers/fake_llm_provider.dart';

/// 深链导航 fake recorder（断言 select + openConversation 两动作）。
class _RecordingNavigator implements ProactiveDeepLinkNavigator {
  _RecordingNavigator({this.throwOnOpen = false});

  /// openConversation 抛错开关（W5 F2：导航失败降级路径探测）。
  final bool throwOnOpen;

  int selectCalls = 0;
  final List<({int conversationId, int? highlightMessageId})> opened = [];

  @override
  void selectChatTab() {
    selectCalls++;
  }

  @override
  Future<void> openConversation(
    int conversationId, {
    int? highlightMessageId,
  }) async {
    if (throwOnOpen) {
      throw StateError('openConversation boom');
    }
    opened.add((conversationId: conversationId, highlightMessageId: highlightMessageId));
  }
}

/// 排程 fake：记录 schedule 调用、可配置抛错与返回值（false = 失败不抛）。
class _RecordingScheduler implements ProactiveNotificationScheduler {
  _RecordingScheduler({this.throwOnSchedule = false, this.result = true});

  final bool throwOnSchedule;

  /// schedule 返回值（恢复路径静默测试用 false 断言不抛不出错）。
  final bool result;

  final List<int> scheduledIds = [];

  @override
  Future<bool> schedule(ProactivePlan plan) async {
    if (throwOnSchedule) {
      throw StateError('schedule boom');
    }
    scheduledIds.add(plan.id);
    return result;
  }
}

/// `updatePlanStatus` 选择性抛错 fake（F-83）：仅 [failPlanIds] 中的计划置
/// 状态抛错注入，其余透传真实实现——验证 restore 置 expired 分支 per-plan
/// 降级（抛错计划保持 scheduled，其余计划继续恢复）。
class _ThrowingUpdatePlanRepo extends CompanionRepository {
  _ThrowingUpdatePlanRepo(
    super.db, {
    required this.failPlanIds,
  });

  /// 置状态即抛错的计划 id 集合。
  final Set<int> failPlanIds;

  @override
  Future<void> updatePlanStatus(
    int planId,
    ProactivePlanStatus status, {
    DateTime? sentAt,
  }) async {
    if (failPlanIds.contains(planId)) {
      throw StateError('updatePlanStatus boom for plan $planId');
    }
    await super.updatePlanStatus(planId, status, sentAt: sentAt);
  }
}

/// 插件调用面 fake（F-84 热态回调装配接线）：记录 initialize 收到的
/// [DidReceiveNotificationResponseCallback]，断言首次调用即带回调。
class _RecordingChannel implements FlutterLocalNotificationsChannel {
  /// initialize 收到的热态回调（未注册为 null）。
  DidReceiveNotificationResponseCallback? registeredCallback;

  /// initialize 调用次数（幂等守卫断言：装配只应触发一次初始化）。
  int initializeCalls = 0;

  /// 重挂失败注入（F-92 告警 seam 装配面验证）。
  bool initializeShouldFail = false;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    initializeCalls++;
    registeredCallback = onDidReceiveNotificationResponse;
    if (initializeShouldFail) {
      throw Exception('init boom');
    }
    return true;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? payload,
  }) async {}

  @override
  Future<void> cancel({required int id, String? tag}) async {}

  @override
  Future<bool?> requestNotificationsPermission() async => true;
}

/// C1 送达收口 fake（implements 最小公开面）：记录 markDeliveredByMessageId
/// 调用并返回可配置计划（null = 计划不存在/非 scheduled）。
class _FakeProactiveMessageService implements ProactiveMessageService {
  _FakeProactiveMessageService({this.delivered});

  /// markDeliveredByMessageId 返回值。
  final ProactivePlan? delivered;

  /// 收到送达收口的 messageId 列表（调用记录）。
  final List<int> markedMessageIds = [];

  @override
  Future<ProactivePlan?> markDeliveredByMessageId(
    int messageId, {
    DateTime? at,
  }) async {
    markedMessageIds.add(messageId);
    return delivered;
  }

  @override
  Future<int> planAfterTurn({
    required int characterId,
    required int conversationId,
  }) async {
    return 0;
  }
}

/// C1 关系侧 fake：记录 recordProactiveMessageOpened 收到的 characterId。
class _FakeRelationshipService implements RelationshipService {
  /// 收到「点开主动消息」记录的角色 id 列表。
  final List<int> openedCharacterIds = [];

  @override
  Future<StageUpgradeProposal?> recordProactiveMessageOpened(
    int characterId,
  ) async {
    openedCharacterIds.add(characterId);
    return null;
  }

  @override
  Future<StageUpgradeProposal?> evaluateAfterTurn({
    required int characterId,
    required int conversationId,
  }) async {
    return null;
  }

  @override
  Future<bool> confirmStageUpgrade({
    required int characterId,
    required RelationshipStage targetStage,
  }) async {
    return false;
  }

  @override
  Future<void> rejectStageUpgrade({required int characterId}) async {}

  @override
  Future<int> activeDays(int characterId) async => 0;

  @override
  Future<bool> isRecentlyActive(int characterId) async => false;
}

void main() {
  late AppDatabase db;
  late CharacterRepository characterRepo;
  late ConversationRepository conversationRepo;
  late MessageRepository messageRepo;
  late CompanionRepository companionRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    characterRepo = CharacterRepository(db);
    conversationRepo = ConversationRepository(db, const FakeSettingsReader());
    messageRepo = MessageRepository(db);
    companionRepo = CompanionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<({int conversationId, int messageId})> seedConversationWithMessage() async {
    final character = await characterRepo.createCharacter(
          CharactersCompanion.insert(
            name: '艾莉亚',
            firstMes: Value(''),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    final conversation =
        await conversationRepo.createConversation(characterId: character.id);
    final message = await messageRepo.createMessage(
      conversationId: conversation.id,
      role: Role.assistant,
      content: '主动消息正文',
    );
    return (conversationId: conversation.id, messageId: message.id);
  }

  Future<ProactivePlan> seedPlan({
    required int conversationId,
    required int? messageId,
    required ProactivePlanStatus status,
    required DateTime scheduledAt,
  }) async {
    return companionRepo.createPlan(
      characterId: 1,
      conversationId: conversationId,
      content: '计划内容',
      scheduledAt: scheduledAt,
      messageId: messageId,
    ).then((plan) async {
      if (status != ProactivePlanStatus.scheduled) {
        await companionRepo.updatePlanStatus(plan.id, status);
      }
      return plan;
    });
  }

  group('StageUpgradeBroker（PS2-07 回调 → UI 广播）', () {
    test('publish 更新 lastProposal 并通知监听者', () {
      final broker = StageUpgradeBroker();
      var notified = 0;
      broker.addListener(() => notified++);
      final proposal = StageUpgradeProposal(
        characterId: 1,
        currentStage: RelationshipStage.familiar,
        targetStage: RelationshipStage.intimate,
        affinity: 61,
      );

      broker.publish(proposal);

      expect(broker.lastProposal, same(proposal));
      expect(notified, 1);
    });

    test('多次 publish 取最新；clear 清空', () {
      final broker = StageUpgradeBroker();
      final first = StageUpgradeProposal(
        characterId: 1,
        currentStage: RelationshipStage.familiar,
        targetStage: RelationshipStage.intimate,
        affinity: 61,
      );
      final second = StageUpgradeProposal(
        characterId: 2,
        currentStage: RelationshipStage.intimate,
        targetStage: RelationshipStage.soulmate,
        affinity: 81,
      );

      broker.publish(first);
      broker.publish(second);
      expect(broker.lastProposal, same(second));

      broker.clear();
      expect(broker.lastProposal, isNull);
    });
  });

  group('handleProactiveDeepLink（SR-03 归属校验）', () {
    test('payload 解析成功且归属通过：select chat + openConversation 高亮', () async {
      final seed = await seedConversationWithMessage();
      final payload = ProactiveDeepLink.encode(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
      );
      final navigator = _RecordingNavigator();

      await handleProactiveDeepLink(
        payload: payload,
        navigator: navigator,
        messageRepository: messageRepo,
      );

      expect(navigator.selectCalls, 1);
      expect(navigator.opened, hasLength(1));
      expect(
        navigator.opened.single.conversationId,
        seed.conversationId,
      );
      expect(
        navigator.opened.single.highlightMessageId,
        seed.messageId,
      );
    });

    test('归属失败（messageId 不属于对话）：回落普通导航打开对话列表', () async {
      final seed = await seedConversationWithMessage();
      final payload = ProactiveDeepLink.encode(
        conversationId: seed.conversationId,
        messageId: seed.messageId + 999, // 不存在于该对话
      );
      final navigator = _RecordingNavigator();

      await handleProactiveDeepLink(
        payload: payload,
        navigator: navigator,
        messageRepository: messageRepo,
      );

      expect(navigator.selectCalls, 1);
      expect(navigator.opened, isEmpty);
    });

    test('payload 非法：回落普通导航且不抛', () async {
      final navigator = _RecordingNavigator();
      await handleProactiveDeepLink(
        payload: 'not-a-deeplink',
        navigator: navigator,
        messageRepository: messageRepo,
      );
      expect(navigator.selectCalls, 1);
      expect(navigator.opened, isEmpty);
    });

    test('payload 只含 conversationId/messageId（消费端零内容，SR-03）', () {
      final payload = ProactiveDeepLink.encode(conversationId: 7, messageId: 9);
      expect(payload, contains('conversationId=7'));
      expect(payload, contains('messageId=9'));
      expect(payload, isNot(contains('content=')));
    });

    test('F2（W5）：归属通过后 openConversation 抛错 → 降级不抛、已切 tab（不回退）',
        () async {
      final seed = await seedConversationWithMessage();
      final payload = ProactiveDeepLink.encode(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
      );
      final navigator = _RecordingNavigator(throwOnOpen: true);

      await handleProactiveDeepLink(
        payload: payload,
        navigator: navigator,
        messageRepository: messageRepo,
      );

      expect(navigator.selectCalls, 1, reason: '导航失败不崩溃，tab 已切到聊天列表');
      expect(navigator.opened, isEmpty, reason: 'openConversation 抛错被消化');
    });

    test('C1：传服务 → 归属通过后 markDelivered 被调用 + recordProactiveMessageOpened 收到 characterId', () async {
      final seed = await seedConversationWithMessage();
      final plan = await seedPlan(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
        status: ProactivePlanStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 20, 10),
      );
      final payload = ProactiveDeepLink.encode(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
      );
      final navigator = _RecordingNavigator();
      final proactive = _FakeProactiveMessageService(delivered: plan);
      final relationship = _FakeRelationshipService();

      await handleProactiveDeepLink(
        payload: payload,
        navigator: navigator,
        messageRepository: messageRepo,
        proactiveMessageService: proactive,
        relationshipService: relationship,
      );

      expect(proactive.markedMessageIds, [seed.messageId]);
      expect(relationship.openedCharacterIds, [plan.characterId]);
      expect(navigator.selectCalls, 1);
      expect(navigator.opened.single.conversationId, seed.conversationId);
      expect(navigator.opened.single.highlightMessageId, seed.messageId);
    });

    test('C1：markDelivered 返回 null（已送达/不存在）→ 不调 relationship，导航照常', () async {
      final seed = await seedConversationWithMessage();
      final payload = ProactiveDeepLink.encode(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
      );
      final navigator = _RecordingNavigator();
      final proactive = _FakeProactiveMessageService(delivered: null);
      final relationship = _FakeRelationshipService();

      await handleProactiveDeepLink(
        payload: payload,
        navigator: navigator,
        messageRepository: messageRepo,
        proactiveMessageService: proactive,
        relationshipService: relationship,
      );

      expect(proactive.markedMessageIds, [seed.messageId]);
      expect(relationship.openedCharacterIds, isEmpty, reason: '未实际送达（幂等重放）不计点开');
      expect(navigator.opened, hasLength(1));
    });

    test('C1：不传服务（既有测试形态）→ 行为不变，导航照常', () async {
      final seed = await seedConversationWithMessage();
      final payload = ProactiveDeepLink.encode(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
      );
      final navigator = _RecordingNavigator();

      await handleProactiveDeepLink(
        payload: payload,
        navigator: navigator,
        messageRepository: messageRepo,
      );

      expect(navigator.selectCalls, 1);
      expect(navigator.opened, hasLength(1));
      expect(navigator.opened.single.conversationId, seed.conversationId);
      expect(navigator.opened.single.highlightMessageId, seed.messageId);
    });
  });

  group('restoreProactiveSchedules（SR-08 启动排程恢复）', () {
    test('pending 且未过期：scheduler 重建一次，状态保持 scheduled', () async {
      final seed = await seedConversationWithMessage();
      final plan = await seedPlan(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
        status: ProactivePlanStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 20, 10),
      );
      final scheduler = _RecordingScheduler();
      final now = DateTime(2026, 9, 15, 12);

      await restoreProactiveSchedules(
        companion: companionRepo,
        scheduler: scheduler,
        now: now,
      );

      expect(scheduler.scheduledIds, [plan.id]);
      final scheduled = await companionRepo.listPlansByStatus(ProactivePlanStatus.scheduled);
      expect(scheduled.map((p) => p.id), contains(plan.id));
    });

    test('pending 且已过期（scheduledAt ≤ now）：不排不发送，置 expired', () async {
      final seed = await seedConversationWithMessage();
      final plan = await seedPlan(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
        status: ProactivePlanStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 15, 12), // == now
      );
      final scheduler = _RecordingScheduler();
      final now = DateTime(2026, 9, 15, 12);

      await restoreProactiveSchedules(
        companion: companionRepo,
        scheduler: scheduler,
        now: now,
      );

      expect(scheduler.scheduledIds, isEmpty);
      final expired = await companionRepo.listPlansByStatus(ProactivePlanStatus.expired);
      expect(expired.map((p) => p.id), contains(plan.id));
    });

    test('sent/expired/dropped 一律不重排不改状态', () async {
      final seed = await seedConversationWithMessage();
      final statuses = [
        ProactivePlanStatus.sent,
        ProactivePlanStatus.expired,
        ProactivePlanStatus.dropped,
      ];
      final planIds = <int>[];
      for (final status in statuses) {
        final plan = await seedPlan(
          conversationId: seed.conversationId,
          messageId: seed.messageId,
          status: status,
          scheduledAt: DateTime(2026, 9, 20, 10),
        );
        planIds.add(plan.id);
      }
      final scheduler = _RecordingScheduler();

      await restoreProactiveSchedules(
        companion: companionRepo,
        scheduler: scheduler,
        now: DateTime(2026, 9, 15, 12),
      );

      expect(scheduler.scheduledIds, isEmpty);
      final plans = await companionRepo.listPlansByStatus(ProactivePlanStatus.sent);
      expect(plans, hasLength(1));
    });

    test('单计划 schedule 抛错：其余计划仍恢复，不整体抛', () async {
      final seed = await seedConversationWithMessage();
      final first = await seedPlan(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
        status: ProactivePlanStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 20, 10),
      );
      final second = await seedPlan(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
        status: ProactivePlanStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 21, 10),
      );
      final scheduler = _RecordingScheduler(throwOnSchedule: true);

      // 不抛未处理异常（per-plan 降级）。
      await restoreProactiveSchedules(
        companion: companionRepo,
        scheduler: scheduler,
        now: DateTime(2026, 9, 15, 12),
      );
      expect(scheduler.scheduledIds, isEmpty);
      final scheduled = await companionRepo.listPlansByStatus(ProactivePlanStatus.scheduled);
      expect(scheduled.map((p) => p.id), containsAll([first.id, second.id]));
    });

    test('schedule 返回 false → 恢复路径静默：不抛、计划保持 scheduled（不接失败回调）', () async {
      final seed = await seedConversationWithMessage();
      final plan = await seedPlan(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
        status: ProactivePlanStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 20, 10),
      );
      final scheduler = _RecordingScheduler(result: false);

      await restoreProactiveSchedules(
        companion: companionRepo,
        scheduler: scheduler,
        now: DateTime(2026, 9, 15, 12),
      );

      expect(scheduler.scheduledIds, [plan.id], reason: '恢复仍尝试重建排程');
      final scheduled = await companionRepo.listPlansByStatus(ProactivePlanStatus.scheduled);
      expect(scheduled.map((p) => p.id), contains(plan.id), reason: 'false 不置位、状态保持 scheduled');
    });

    test('单计划置 expired 抛错：保持 scheduled 不排程，其余计划仍恢复，不整体抛', () async {
      final seed = await seedConversationWithMessage();
      final throwing = await seedPlan(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
        status: ProactivePlanStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 10, 10), // 已过期；置 expired 抛错
      );
      final okExpired = await seedPlan(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
        status: ProactivePlanStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 15, 12), // == now，已过期；正常置 expired
      );
      final future = await seedPlan(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
        status: ProactivePlanStatus.scheduled,
        scheduledAt: DateTime(2026, 9, 20, 10), // 未过期；重建排程
      );
      final scheduler = _RecordingScheduler();
      final companion = _ThrowingUpdatePlanRepo(
        db,
        failPlanIds: {throwing.id},
      );

      // 不抛未处理异常（per-plan 降级，对齐 schedule 分支语义）。
      await restoreProactiveSchedules(
        companion: companion,
        scheduler: scheduler,
        now: DateTime(2026, 9, 15, 12),
      );

      // 抛错计划 scheduledAt 最早、最先处理——未捕获时后续计划无法执行。
      expect(scheduler.scheduledIds, [future.id], reason: '仅未过期计划重建一次');
      final scheduled = await companion.listPlansByStatus(ProactivePlanStatus.scheduled);
      expect(scheduled.map((p) => p.id), contains(throwing.id),
          reason: '置 expired 抛错计划保持 scheduled，不重排不置位');
      final expired = await companion.listPlansByStatus(ProactivePlanStatus.expired);
      expect(expired.map((p) => p.id), [okExpired.id],
          reason: '其余过期计划仍置 expired，恢复不中断');
    });
  });

  group('深链生产接线（PS2-10 验收 8）', () {
    test('AppDeepLinkNavigator：selectChatTab 切聊天 tab；openConversation 打开'
        '会话并高亮消息（生产导航实现）', () async {
      final env = await ChatTestEnv.create();
      final character = await env.seedCharacter(name: '艾莉亚');
      final conversation = await env.seedConversation(character.id);
      final message = await env.seedMessage(
        conversationId: conversation.id,
        role: Role.assistant,
        content: '主动消息正文',
      );
      final controller = env.controllerOf(FakeLLMProvider(tokens: const ['ok']));
      final navigation = ShellNavigation();
      navigation.select(ShellTab.characters);
      final navigator = AppDeepLinkNavigator(
        navigation: navigation,
        chatController: controller,
      );

      navigator.selectChatTab();
      expect(navigation.current, ShellTab.chat);

      await navigator.openConversation(
        conversation.id,
        highlightMessageId: message.id,
      );
      expect(controller.activeConversation?.id, conversation.id);
      expect(controller.highlightMessageIds, contains(message.id));
      await env.close();
    });

    test('consumeProactiveLaunchDeepLink：无 payload / 取参失败 → 静默跳过'
        '（验收 8 零导航）', () async {
      final voidN = _RecordingNavigator();
      await consumeProactiveLaunchDeepLink(
        navigator: voidN,
        messageRepository: messageRepo,
        readPayload: () async => null,
      );
      expect(voidN.selectCalls, 0);
      expect(voidN.opened, isEmpty, reason: '无 payload 静默');

      final throwN = _RecordingNavigator();
      await consumeProactiveLaunchDeepLink(
        navigator: throwN,
        messageRepository: messageRepo,
        readPayload: () async => throw StateError('plugin 缺失'),
      );
      expect(throwN.selectCalls, 0, reason: '取参失败静默');
    });

    test('非法 payload → 回落 select chat（handleProactiveDeepLink 语义）',
        () async {
      final navigator = _RecordingNavigator();
      await consumeProactiveLaunchDeepLink(
        navigator: navigator,
        messageRepository: messageRepo,
        readPayload: () async => 'not-a-deeplink',
      );
      expect(navigator.selectCalls, 1);
      expect(navigator.opened, isEmpty);
    });

    test('合法 payload → select chat + openConversation 高亮（冷启动端到端）',
        () async {
      final seed = await seedConversationWithMessage();
      final payload = ProactiveDeepLink.encode(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
      );
      final navigator = _RecordingNavigator();
      await consumeProactiveLaunchDeepLink(
        navigator: navigator,
        messageRepository: messageRepo,
        readPayload: () async => payload,
      );
      expect(navigator.selectCalls, 1);
      expect(navigator.opened, hasLength(1));
      expect(navigator.opened.single.conversationId, seed.conversationId);
      expect(navigator.opened.single.highlightMessageId, seed.messageId);
    });
  });

  group('consumeProactiveNotificationResponse（F-84 热态桥接）', () {
    test('payload null / 空字符串 → 零导航（静默）', () async {
      final voidN = _RecordingNavigator();
      await consumeProactiveNotificationResponse(
        payload: null,
        navigator: voidN,
        messageRepository: messageRepo,
      );
      expect(voidN.selectCalls, 0, reason: '无 payload 静默，不切 tab');

      final emptyN = _RecordingNavigator();
      await consumeProactiveNotificationResponse(
        payload: '',
        navigator: emptyN,
        messageRepository: messageRepo,
      );
      expect(emptyN.selectCalls, 0, reason: '空 payload 静默');
      expect(emptyN.opened, isEmpty);
    });

    test('非法 payload → 回落 select chat（与冷启动共享回落语义）', () async {
      final navigator = _RecordingNavigator();
      await consumeProactiveNotificationResponse(
        payload: 'not-a-deeplink',
        navigator: navigator,
        messageRepository: messageRepo,
      );
      expect(navigator.selectCalls, 1);
      expect(navigator.opened, isEmpty);
    });

    test('合法 payload → select chat + openConversation 高亮（handleProactiveDeepLink 契约）', () async {
      final seed = await seedConversationWithMessage();
      final payload = ProactiveDeepLink.encode(
        conversationId: seed.conversationId,
        messageId: seed.messageId,
      );
      final navigator = _RecordingNavigator();
      await consumeProactiveNotificationResponse(
        payload: payload,
        navigator: navigator,
        messageRepository: messageRepo,
      );
      expect(navigator.selectCalls, 1);
      expect(navigator.opened, hasLength(1));
      expect(navigator.opened.single.conversationId, seed.conversationId);
      expect(navigator.opened.single.highlightMessageId, seed.messageId);
    });
  });

  group('F-84 热态回调装配接线（SB: 启动哑 Provider → scheduler.initialize）', () {
    testWidgets('注入 fake channel → 首次 initialize 即携带热态回调（幂等守卫后再传无效）', (tester) async {
      final channel = _RecordingChannel();
      final scheduler = FlutterLocalNotificationsScheduler(
        channel: channel,
        isAndroid: () => true,
      );
      await tester.pumpWidget(ConverApp(database: db, scheduler: scheduler));
      await tester.pump();
      await tester.pump();

      expect(channel.initializeCalls, 1);
      expect(channel.registeredCallback, isNotNull,
          reason: '回调必须在首次 initialize 注册——幂等守卫使后续调用直接 return');
    });

    testWidgets('热态回调触发 → 归属通过后切聊天 tab 并打开会话高亮（装配端到端）', (tester) async {
      final seed = await seedConversationWithMessage();
      final channel = _RecordingChannel();
      final scheduler = FlutterLocalNotificationsScheduler(
        channel: channel,
        isAndroid: () => true,
      );
      await tester.pumpWidget(ConverApp(database: db, scheduler: scheduler));
      await tester.pump();
      await tester.pump();

      final context = tester.element(find.byType(Scaffold).first);
      context.read<ShellNavigation>().select(ShellTab.characters);
      channel.registeredCallback!(NotificationResponse(
        payload: ProactiveDeepLink.encode(
          conversationId: seed.conversationId,
          messageId: seed.messageId,
        ),
        notificationResponseType: NotificationResponseType.selectedNotification,
      ));
      await tester.pump();
      await tester.pump();

      expect(context.read<ShellNavigation>().current, ShellTab.chat,
          reason: '热态点按 → select chat');
      final controller = context.read<ChatController>();
      expect(controller.activeConversationId, seed.conversationId);
      expect(controller.highlightMessageIds, contains(seed.messageId));
    });

    testWidgets('装配晚到重挂：scheduler 已被无回调初始化 → 装配重挂回调并端到端触发（F-92 验收8）',
        (tester) async {
      final channel = _RecordingChannel();
      final scheduler = FlutterLocalNotificationsScheduler(
        channel: channel,
        isAndroid: () => true,
      );
      // 先模拟 schedule 懒初始化（无回调）完成——装配晚到窗口。
      expect(await scheduler.initialize(), isTrue);
      expect(channel.initializeCalls, 1);
      expect(channel.registeredCallback, isNull);

      final seed = await seedConversationWithMessage();
      await tester.pumpWidget(ConverApp(database: db, scheduler: scheduler));
      await tester.pump();
      await tester.pump();

      expect(channel.initializeCalls, 2, reason: '装配晚到触发一次重挂');
      expect(channel.registeredCallback, isNotNull,
          reason: '重挂语义：装配回调最终注册生效（F-92 修复前为 null）');
      final context = tester.element(find.byType(Scaffold).first);
      context.read<ShellNavigation>().select(ShellTab.characters);
      channel.registeredCallback!(NotificationResponse(
        payload: ProactiveDeepLink.encode(
          conversationId: seed.conversationId,
          messageId: seed.messageId,
        ),
        notificationResponseType: NotificationResponseType.selectedNotification,
      ));
      await tester.pump();
      await tester.pump();

      expect(context.read<ShellNavigation>().current, ShellTab.chat,
          reason: '重挂后的回调闭包仍走深链消费（导航 + 归属校验）');
      expect(context.read<ChatController>().activeConversationId,
          seed.conversationId);
    });

    testWidgets('装配接线消费告警 seam：重挂失败不阻断启动且重挂尝试上达（F-92 验收3/8）',
        (tester) async {
      final channel = _RecordingChannel();
      final scheduler = FlutterLocalNotificationsScheduler(
        channel: channel,
        isAndroid: () => true,
      );

      // 懒初始化（无回调）成功；随后装配带回调 → 重挂失败。seam 触发语义
      // （正常/可补救 0 次、不可补救 ≥1 次）由 notification_service_test
      // 的注入 seam 断言覆盖；此处锚定装配面：重挂尝试确实发生且不阻断
      // 启动（装配方已把带回调的 initialize 打在 scheduler 上）。
      expect(await scheduler.initialize(), isTrue);
      channel.initializeShouldFail = true;
      await tester.pumpWidget(ConverApp(database: db, scheduler: scheduler));
      await tester.pump();
      await tester.pump();

      expect(channel.initializeCalls, 2,
          reason: '装配晚到触发重挂尝试（装配方接线 consume 告警 seam 路径）');
      expect(tester.takeException(), isNull, reason: '重挂失败不阻断启动');
      // 注：插件 22.3.1 的 initialize 会在平台调用前覆盖赋值回调，故重挂
      // 失败时插件侧回调槽可能已被写入——服务侧 `_hotCallbackRegistered`
      // 保持 false（保守），下次晚到带回调仍会再尝试重挂。此细节以 service
      // 层 seam 测试锁定，装配面只锚重挂尝试与启动不阻断。
    });
  });

  group('SnackBar 兜底（F-84 P3 + SR-12 摘要文案）', () {
    testWidgets('触发 showScheduleFailedNotice → 站内出现「通知排程失败」', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );

      showScheduleFailedNotice();
      await tester.pump();

      expect(find.text('通知排程失败'), findsOneWidget);
    });

    testWidgets('messenger 未挂载（key 未绑定 MaterialApp）→ 静默不抛', (tester) async {
      showScheduleFailedNotice();
      expect(tester.takeException(), isNull);
    });
  });

  group('ConverApp 装配冒烟（PS2-08 MultiProvider）', () {
    testWidgets('装配完整：六实例可读 + 启动编排不阻断构建', (tester) async {
      await tester.pumpWidget(ConverApp(database: db));
      await tester.pump();

      // 在 MultiProvider 之下取 context（provider 声明于 ConverApp build 内）。
      final context = tester.element(find.byType(Scaffold).first);
      expect(context.read<CompanionRepository>(), isNotNull);
      expect(context.read<ThoughtService>(), isNotNull);
      expect(context.read<RelationshipService>(), isNotNull);
      expect(context.read<ProactiveMessageService>(), isNotNull);
      expect(context.read<StageUpgradeBroker>(), isNotNull);
      expect(context.read<FlutterLocalNotificationsScheduler>(), isNotNull);
      // 通知初始化（真插件缺失 → 降级 false）+ SR-08 恢复（空计划）不抛。
      expect(tester.takeException(), isNull);
    });
  });
}