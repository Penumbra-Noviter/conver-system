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
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/chat_test_env.dart' show FakeSettingsReader;

/// 深链导航 fake recorder（断言 select + openConversation 两动作）。
class _RecordingNavigator implements ProactiveDeepLinkNavigator {
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
    opened.add((conversationId: conversationId, highlightMessageId: highlightMessageId));
  }
}

/// 排程 fake：记录 schedule 调用、可配置抛错。
class _RecordingScheduler implements ProactiveNotificationScheduler {
  _RecordingScheduler({this.throwOnSchedule = false});

  final bool throwOnSchedule;
  final List<int> scheduledIds = [];

  @override
  Future<void> schedule(ProactivePlan plan) async {
    if (throwOnSchedule) {
      throw StateError('schedule boom');
    }
    scheduledIds.add(plan.id);
  }
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
        currentStage: RelationshipStage.familiar,
        targetStage: RelationshipStage.intimate,
        affinity: 61,
      );
      final second = StageUpgradeProposal(
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