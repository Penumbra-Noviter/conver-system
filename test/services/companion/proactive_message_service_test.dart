/// PS2-05 ProactiveMessageService 行为契约 — 节流纯函数 / 三级解析 / 规划
/// seam 编排 / 过期核对 / 失败降级（spec §2 P1/P2/P6 + §6 判定③④⑥⑦ +
/// threat-model SR-01/SR-04/SR-07/SR-08）。
///
/// 沿 ReflectionService 测试惯例：内存 drift + 固定 now 注入 + seam fake
/// （planner / scheduler），并发 in-flight 用 Future.wait 实名构造。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/companion_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/companion/proactive_message_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_env.dart' show FakeSettingsReader;
import '../../helpers/fake_llm_provider.dart' show FakeLLMProvider;
import '../../helpers/in_memory_secret_store.dart' show InMemorySecretStore;

class _FakeScheduler implements ProactiveNotificationScheduler {
  _FakeScheduler(this._onCall);

  final void Function(ProactivePlan plan) _onCall;

  @override
  Future<void> schedule(ProactivePlan plan) async {
    _onCall(plan);
  }
}

void main() {
  group('ProactiveThresholds 常量锚定', () {
    test('每日上限 6 / 冷却 6h / 活跃窗口 7d / minutes 边界 10..360', () {
      expect(ProactiveThresholds.dailyLimit, 6);
      expect(ProactiveThresholds.roleCooldown, const Duration(hours: 6));
      expect(ProactiveThresholds.activeWindow, const Duration(days: 7));
      expect(ProactiveThresholds.minMinutesFromNow, 10);
      expect(ProactiveThresholds.maxMinutesFromNow, 360);
    });
  });

  group('evaluateSchedule 节流纯函数', () {
    final now = DateTime(2026, 9, 15, 12, 0, 0);

    test('全条件通过 → allowed', () {
      final d = evaluateSchedule(
        sentToday: 0,
        lastSentAt: now.subtract(const Duration(hours: 6)),
        lastActiveAt: now.subtract(const Duration(days: 1)),
        hasInFlightPlan: false,
        now: now,
      );
      expect(d.allowed, isTrue);
      expect(d.reason, 'ok');
    });

    test('sentToday == dailyLimit 边界拒绝', () {
      expect(
        evaluateSchedule(
          sentToday: ProactiveThresholds.dailyLimit,
          lastSentAt: now.subtract(const Duration(hours: 6)),
          lastActiveAt: now.subtract(const Duration(days: 1)),
          hasInFlightPlan: false,
          now: now,
        ).reason,
        'daily_limit',
      );
      expect(
        evaluateSchedule(
          sentToday: ProactiveThresholds.dailyLimit + 1,
          lastSentAt: now.subtract(const Duration(hours: 6)),
          lastActiveAt: now.subtract(const Duration(days: 1)),
          hasInFlightPlan: false,
          now: now,
        ).allowed,
        isFalse,
      );
    });

    test('sentToday 未达上限不因日限拒绝', () {
      final d = evaluateSchedule(
        sentToday: ProactiveThresholds.dailyLimit - 1,
        lastSentAt: now.subtract(const Duration(hours: 6)),
        lastActiveAt: now.subtract(const Duration(days: 1)),
        hasInFlightPlan: false,
        now: now,
      );
      expect(d.allowed, isTrue);
      expect(d.reason, 'ok');
    });

    test('冷却边界：距今恰好 6h 允许，不足 6h 拒绝', () {
      expect(
        evaluateSchedule(
          sentToday: 0,
          lastSentAt: now.subtract(ProactiveThresholds.roleCooldown),
          lastActiveAt: now.subtract(const Duration(days: 1)),
          hasInFlightPlan: false,
          now: now,
        ).allowed,
        isTrue,
      );
      expect(
        evaluateSchedule(
          sentToday: 0,
          lastSentAt: now
              .subtract(ProactiveThresholds.roleCooldown)
              .subtract(const Duration(seconds: 1)),
          lastActiveAt: now.subtract(const Duration(days: 1)),
          hasInFlightPlan: false,
          now: now,
        ).allowed,
        isTrue,
      );
      expect(
        evaluateSchedule(
          sentToday: 0,
          lastSentAt: now
              .subtract(ProactiveThresholds.roleCooldown)
              .add(const Duration(seconds: 1)),
          lastActiveAt: now.subtract(const Duration(days: 1)),
          hasInFlightPlan: false,
          now: now,
        ).reason,
        'cooldown',
      );
    });

    test('活跃窗口边界：距今恰好 7d 允许，超 7d 拒绝', () {
      expect(
        evaluateSchedule(
          sentToday: 0,
          lastSentAt: null,
          lastActiveAt: now.subtract(ProactiveThresholds.activeWindow),
          hasInFlightPlan: false,
          now: now,
        ).allowed,
        isTrue,
      );
      expect(
        evaluateSchedule(
          sentToday: 0,
          lastSentAt: null,
          lastActiveAt: now
              .subtract(ProactiveThresholds.activeWindow)
              .subtract(const Duration(seconds: 1)),
          hasInFlightPlan: false,
          now: now,
        ).reason,
        'inactive',
      );
    });

    test('无任何活跃消息 → inactive 拒绝', () {
      expect(
        evaluateSchedule(
          sentToday: 0,
          lastSentAt: null,
          lastActiveAt: null,
          hasInFlightPlan: false,
          now: now,
        ).reason,
        'inactive',
      );
    });

    test('已有在途计划 → in_flight 拒绝', () {
      expect(
        evaluateSchedule(
          sentToday: 0,
          lastSentAt: null,
          lastActiveAt: now.subtract(const Duration(days: 1)),
          hasInFlightPlan: true,
          now: now,
        ).reason,
        'in_flight',
      );
    });

    test('每日上限判定优先于冷却（双命中只报 daily_limit）', () {
      expect(
        evaluateSchedule(
          sentToday: ProactiveThresholds.dailyLimit,
          lastSentAt: now.subtract(const Duration(minutes: 1)),
          lastActiveAt: now.subtract(const Duration(days: 1)),
          hasInFlightPlan: true,
          now: now,
        ).reason,
        'daily_limit',
      );
    });
  });

  group('parseProactivePlan 三级容错', () {
    test('一级：直接 JSON 对象', () {
      final d = parseProactivePlan(
          '{"shouldSend": true, "minutesFromNow": 30, "content": "想你了"}');
      expect(d, isNotNull);
      expect(d!.shouldSend, isTrue);
      expect(d.minutesFromNow, 30);
      expect(d.content, '想你了');
    });

    test('二级：```json 代码块包裹', () {
      final d = parseProactivePlan('你的计划是：\n```json\n{"shouldSend": true, "minutesFromNow": 120, "content": "在吗"}\n```\n请确认。');
      expect(d?.shouldSend, isTrue);
      expect(d?.minutesFromNow, 120);
      expect(d?.content, '在吗');
    });

    test('三级：解释文字 + 大括号范围', () {
      final d = parseProactivePlan(
          '决策结果 { "shouldSend": false, "minutesFromNow": 60, "content": "占位" } 以上。');
      expect(d?.shouldSend, isFalse);
      expect(d?.minutesFromNow, 60);
    });

    test('多余字段宽容忽略，content 保留原样', () {
      final d = parseProactivePlan(
          '{"shouldSend": true, "minutesFromNow": 45, "content": " 带空白的文案 ", "reason": "闲了"}');
      expect(d?.content, ' 带空白的文案 ');
    });

    test('minutesFromNow 边界 10 / 360 接受，9 / 361 拒绝', () {
      expect(
        parseProactivePlan(
                '{"shouldSend": true, "minutesFromNow": 10, "content": "a"}')
            ?.minutesFromNow,
        10,
      );
      expect(
        parseProactivePlan(
                '{"shouldSend": true, "minutesFromNow": 360, "content": "a"}')
            ?.minutesFromNow,
        360,
      );
      expect(
        parseProactivePlan(
            '{"shouldSend": true, "minutesFromNow": 9, "content": "a"}'),
        isNull,
      );
      expect(
        parseProactivePlan(
            '{"shouldSend": true, "minutesFromNow": 361, "content": "a"}'),
        isNull,
      );
    });

    test('minutesFromNow 非整数 / 字符串 / null / bool → 拒绝', () {
      expect(
        parseProactivePlan(
            '{"shouldSend": true, "minutesFromNow": 12.5, "content": "a"}'),
        isNull,
      );
      expect(
        parseProactivePlan(
            '{"shouldSend": true, "minutesFromNow": "30", "content": "a"}'),
        isNull,
      );
      expect(
        parseProactivePlan(
            '{"shouldSend": true, "minutesFromNow": null, "content": "a"}'),
        isNull,
      );
      expect(
        parseProactivePlan(
            '{"shouldSend": true, "minutesFromNow": true, "content": "a"}'),
        isNull,
      );
    });

    test('minutesFromNow 整数 double（30.0）接受（数学上为整数）', () {
      expect(
        parseProactivePlan(
                '{"shouldSend": true, "minutesFromNow": 30.0, "content": "a"}')
            ?.minutesFromNow,
        30,
      );
    });

    test('shouldSend 非 bool / 缺失 → 拒绝', () {
      expect(
        parseProactivePlan(
            '{"shouldSend": "yes", "minutesFromNow": 30, "content": "a"}'),
        isNull,
      );
      expect(
        parseProactivePlan('{"minutesFromNow": 30, "content": "a"}'),
        isNull,
      );
    });

    test('content 空 / 纯空白 / 缺失 / 非字符串 → 拒绝', () {
      expect(
        parseProactivePlan(
            '{"shouldSend": true, "minutesFromNow": 30, "content": ""}'),
        isNull,
      );
      expect(
        parseProactivePlan(
            '{"shouldSend": true, "minutesFromNow": 30, "content": "   "}'),
        isNull,
      );
      expect(
        parseProactivePlan('{"shouldSend": true, "minutesFromNow": 30}'),
        isNull,
      );
      expect(
        parseProactivePlan(
            '{"shouldSend": true, "minutesFromNow": 30, "content": 42}'),
        isNull,
      );
    });

    test('非 JSON / 空串 / JSON 数组 → null 且不抛', () {
      expect(parseProactivePlan(''), isNull);
      expect(parseProactivePlan('这不是 JSON'), isNull);
      expect(parseProactivePlan('[1, 2, 3]'), isNull);
      expect(parseProactivePlan('null'), isNull);
      expect(parseProactivePlan('{"a": 1}'), isNull);
    });

    test('无花括号的伪 JSON → null（粗解析分支）', () {
      expect(parseProactivePlan('shouldSend: true'), isNull);
    });
  });

  group('buildProactiveMessages prompt 组装', () {
    test('system 限定 JSON 对象契约；user 附对话历史', () {
      final messages = buildProactiveMessages(
        dialogueLines: const ['用户：你好', '在吗'],
      );
      expect(messages.length, 2);
      expect(messages[0].role, 'system');
      expect(messages[0].content, contains('shouldSend'));
      expect(messages[0].content, contains('minutesFromNow'));
      expect(messages[0].content, contains('content'));
      expect(messages[1].role, 'user');
      expect(messages[1].content, contains('用户：你好'));
      expect(messages[1].content, contains('在吗'));
    });

    test('无对话历史 → （暂无对话记录）占位且不抛', () {
      final messages = buildProactiveMessages(dialogueLines: const []);
      expect(messages[1].content, contains('（暂无对话记录）'));
    });
  });

  group('planProactiveWithProvider 生产装配', () {
    test('generate 输出 → 三级解析后返回 decision', () async {
      final llm = FakeLLMProvider(
        tokens: const [
          '```json\n{"shouldSend": true, "minutesFromNow": 90, "content": "晚上好"}\n```',
        ],
      );
      final d = await planProactiveWithProvider(
        llm: llm,
        model: 'claude-sonnet-5',
        characterId: 1,
        conversationId: 2,
        dialogueLines: const ['用户：在吗'],
      );
      expect(d?.shouldSend, isTrue);
      expect(d?.minutesFromNow, 90);
      expect(d?.content, '晚上好');
      expect(llm.generateCallCount, 1);
      expect(llm.lastModel, 'claude-sonnet-5');
    });

    test('generate 抛错 → 上抛给调用方（由服务降级）', () async {
      final llm = FakeLLMProvider(error: Exception('llm down'));
      await expectLater(
        planProactiveWithProvider(
          llm: llm,
          model: 'claude-sonnet-5',
          characterId: 1,
          conversationId: 2,
          dialogueLines: const [],
        ),
        throwsException,
      );
    });

    test('generate 输出非法 → null（不抛）', () async {
      final llm = FakeLLMProvider(tokens: const ['乱七八糟']);
      final d = await planProactiveWithProvider(
        llm: llm,
        model: 'claude-sonnet-5',
        characterId: 1,
        conversationId: 2,
        dialogueLines: const [],
      );
      expect(d, isNull);
    });
  });

  group('ProactiveMessageService.planAfterTurn', () {
    late AppDatabase db;
    late CompanionRepository companionRepo;
    late SettingsRepository settingsRepo;
    late ConversationRepository conversationRepo;
    late MessageRepository messageRepo;
    late DateTime fixedNow;

    late int plannerCalls;
    late ProactivePlanDecision? plannerResult;
    late Object? plannerError;
    late int schedulerCalls;
    late List<ProactivePlan> scheduledPlans;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      fixedNow = DateTime(2026, 9, 15, 12, 0, 0);
      companionRepo = CompanionRepository(db, now: () => fixedNow);
      settingsRepo = SettingsRepository(
        database: db,
        secretStore: InMemorySecretStore(),
      );
      conversationRepo = ConversationRepository(
        db,
        const FakeSettingsReader(),
        now: () => fixedNow,
      );
      messageRepo = MessageRepository(db, now: () => fixedNow);
      plannerCalls = 0;
      plannerResult = const (
        shouldSend: true,
        minutesFromNow: 30,
        content: '想你了',
      );
      plannerError = null;
      schedulerCalls = 0;
      scheduledPlans = [];
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> enableProactive() async {
      await settingsRepo.setMany({'proactive_message_enabled': 'true'});
    }

    Future<({int characterId, int conversationId})> seedChain({
      DateTime? lastActiveAt,
    }) async {
      final character = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(
              name: '艾莉亚',
              createdAt: fixedNow,
              updatedAt: fixedNow,
            ),
          );
      final conversation = await db.into(db.conversations).insertReturning(
            ConversationsCompanion.insert(
              characterId: character.id,
              createdAt: fixedNow,
              updatedAt: fixedNow,
            ),
          );
      final at = lastActiveAt ?? fixedNow.subtract(const Duration(days: 1));
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: conversation.id,
              role: Role.assistant,
              content: '开场白',
              createdAt: at,
            ),
          );
      return (characterId: character.id, conversationId: conversation.id);
    }

    Future<ProactivePlan> seedSentPlan({
      required int characterId,
      required int conversationId,
      required DateTime sentAt,
    }) async {
      final plan = await companionRepo.createPlan(
        characterId: characterId,
        conversationId: conversationId,
        content: '已发送',
        scheduledAt: sentAt.subtract(const Duration(minutes: 10)),
      );
      await companionRepo.updatePlanStatus(
        plan.id,
        ProactivePlanStatus.sent,
        sentAt: sentAt,
      );
      return plan;
    }

    Future<ProactivePlan> seedScheduledPlan({
      required int characterId,
      required int conversationId,
      required DateTime scheduledAt,
      String content = '在途计划',
    }) async {
      final message = await messageRepo.createMessage(
        conversationId: conversationId,
        role: Role.assistant,
        content: content,
      );
      return companionRepo.createPlan(
        characterId: characterId,
        conversationId: conversationId,
        content: content,
        scheduledAt: scheduledAt,
        messageId: message.id,
      );
    }

    ProactivePlanner fakePlanner() {
      return ({
        required int characterId,
        required int conversationId,
        required List<String> dialogueLines,
      }) async {
        plannerCalls++;
        final err = plannerError;
        if (err != null) {
          throw err;
        }
        return plannerResult;
      };
    }

    ProactiveMessageService buildService() {
      return ProactiveMessageService(
        companionRepository: companionRepo,
        settingsRepository: settingsRepo,
        conversationRepository: conversationRepo,
        messageRepository: messageRepo,
        planner: fakePlanner(),
        scheduler: _FakeScheduler((plan) {
          schedulerCalls++;
          scheduledPlans.add(plan);
        }),
        now: () => fixedNow,
      );
    }

    test('开关关 → 0 且零副作用（不 reconcile 不调 seam 不落库）', () async {
      final ids = await seedChain();
      await companionRepo.createPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        content: '已过期在途',
        scheduledAt: fixedNow.subtract(const Duration(hours: 1)),
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      expect(plannerCalls, 0);
      expect(schedulerCalls, 0);
      final plans = await db.select(db.proactivePlans).get();
      expect(plans.single.status, ProactivePlanStatus.scheduled);
      expect(await messageRepo.getMessages(ids.conversationId), hasLength(1));
    });

    test('开关存储值非 true（缺失）→ 0 不调 planner', () async {
      final ids = await seedChain();
      final service = buildService();
      expect(
        await service.planAfterTurn(
          characterId: ids.characterId,
          conversationId: ids.conversationId,
        ),
        0,
      );
      expect(plannerCalls, 0);
    });

    test('每日上限已满（今日 6 条 sent）→ 0 不调 planner', () async {
      final ids = await seedChain();
      await enableProactive();
      for (var i = 0; i < ProactiveThresholds.dailyLimit; i++) {
        await seedSentPlan(
          characterId: ids.characterId,
          conversationId: ids.conversationId,
          sentAt: fixedNow.subtract(Duration(hours: i)),
        );
      }
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      expect(plannerCalls, 0);
      expect(schedulerCalls, 0);
    });

    test('冷却未过（最近 sentAt 距 now 不足 6h）→ 0 不调 planner', () async {
      final ids = await seedChain();
      await enableProactive();
      await seedSentPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        sentAt: fixedNow.subtract(const Duration(hours: 5, minutes: 59)),
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      expect(plannerCalls, 0);
    });

    test('W3-F2：冷却按角色隔离——A 刚发不影响从未发过的 B 首次规划', () async {
      final idsA = await seedChain();
      final idsB = await seedChain();
      await enableProactive();
      await seedSentPlan(
        characterId: idsA.characterId,
        conversationId: idsA.conversationId,
        sentAt: fixedNow.subtract(const Duration(minutes: 5)),
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: idsB.characterId,
        conversationId: idsB.conversationId,
      );

      expect(result, 1);
      expect(plannerCalls, 1);
    });

    test('W3-F2：B 自己冷却窗口内仍拒绝（本角色口径）', () async {
      final ids = await seedChain();
      await enableProactive();
      await seedSentPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        sentAt: fixedNow.subtract(const Duration(minutes: 5)),
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      expect(plannerCalls, 0);
    });

    test('W3-F2：全局日限跨角色——A 满 6 次后 B 也被 daily_limit 拒绝', () async {
      final idsA = await seedChain();
      final idsB = await seedChain();
      await enableProactive();
      for (var i = 0; i < ProactiveThresholds.dailyLimit; i++) {
        await seedSentPlan(
          characterId: idsA.characterId,
          conversationId: idsA.conversationId,
          sentAt: fixedNow.subtract(Duration(hours: i)),
        );
      }
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: idsB.characterId,
        conversationId: idsB.conversationId,
      );

      expect(result, 0);
      expect(plannerCalls, 0);
    });

    test('冷却边界：最近 sentAt 距今恰好 6h → 允许规划', () async {
      final ids = await seedChain();
      await enableProactive();
      await seedSentPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        sentAt: fixedNow.subtract(const Duration(hours: 6)),
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 1);
      expect(plannerCalls, 1);
    });

    test('今日计数口径：昨日 sent 不计入今日上限', () async {
      final ids = await seedChain();
      await enableProactive();
      for (var i = 1; i <= 5; i++) {
        await seedSentPlan(
          characterId: ids.characterId,
          conversationId: ids.conversationId,
          sentAt: fixedNow.subtract(Duration(days: i)),
        );
      }
      // 5 条昨日 sent + 1 条 7 小时前（今日且冷却已过）→ 今日计数 1，未达上限。
      await seedSentPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        sentAt: fixedNow.subtract(const Duration(hours: 7)),
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 1);
      expect(plannerCalls, 1);
    });

    test('无活跃消息（最近消息距今 7d 外）→ inactive 拒绝', () async {
      final ids = await seedChain(
        lastActiveAt: fixedNow
            .subtract(ProactiveThresholds.activeWindow)
            .subtract(const Duration(seconds: 1)),
      );
      await enableProactive();
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      expect(plannerCalls, 0);
    });

    test('活跃窗口边界：最近消息距今恰好 7d → 允许规划', () async {
      final ids = await seedChain(
        lastActiveAt: fixedNow.subtract(ProactiveThresholds.activeWindow),
      );
      await enableProactive();
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 1);
      expect(plannerCalls, 1);
    });

    test('多对话活跃：最近消息取全部对话最大值（较新者胜）', () async {
      final ids = await seedChain(); // 对话1 消息在 1 天前。
      await enableProactive();
      // 对话2 消息在 2 小时前 → lastActive 取对话2 → 允许规划。
      final conv2 = await db.into(db.conversations).insertReturning(
            ConversationsCompanion.insert(
              characterId: ids.characterId,
              createdAt: fixedNow,
              updatedAt: fixedNow,
            ),
          );
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: conv2.id,
              role: Role.assistant,
              content: '对话2消息',
              createdAt: fixedNow.subtract(const Duration(hours: 2)),
            ),
          );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 1);
      expect(plannerCalls, 1);
    });

    test('对话历史超 20 条 → 截断取最近（sublist 分支）', () async {
      final ids = await seedChain();
      await enableProactive();
      for (var i = 0; i < 25; i++) {
        await messageRepo.createMessage(
          conversationId: ids.conversationId,
          role: Role.user,
          content: '追加消息 $i',
        );
      }
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 1);
      expect(plannerCalls, 1);
    });

    test('已有未过期在途计划 → 0 不调 planner', () async {
      final ids = await seedChain();
      await enableProactive();
      await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      expect(plannerCalls, 0);
    });

    test('同角色双 scheduled（一过期一在途）→ 不崩：过期置 expired，在途触发拒绝', () async {
      final ids = await seedChain();
      await enableProactive();
      await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.subtract(const Duration(hours: 2)),
        content: '已过期',
      );
      await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        content: '在途',
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      expect(plannerCalls, 0);
      final plans = await db.select(db.proactivePlans).get();
      expect(plans.map((p) => p.status),
          unorderedEquals([ProactivePlanStatus.expired, ProactivePlanStatus.scheduled]));
    });

    test('全过 + planner 返回 null → 0 不落库不调 scheduler', () async {
      final ids = await seedChain();
      await enableProactive();
      plannerResult = null;
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      expect(plannerCalls, 1);
      expect(schedulerCalls, 0);
      expect(await db.select(db.proactivePlans).get(), isEmpty);
      expect(await messageRepo.getMessages(ids.conversationId), hasLength(1));
    });

    test('shouldSend=false → 0 不落库不调 scheduler', () async {
      final ids = await seedChain();
      await enableProactive();
      plannerResult = const (
        shouldSend: false,
        minutesFromNow: 30,
        content: '不必发',
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      expect(schedulerCalls, 0);
      expect(await db.select(db.proactivePlans).get(), isEmpty);
      expect(await messageRepo.getMessages(ids.conversationId), hasLength(1));
    });

    test('shouldSend=true → 落真实 assistant 消息 + scheduled 计划（scheduledAt=now+minutes, messageId 回填）+ scheduler 恰好一次', () async {
      final ids = await seedChain();
      await enableProactive();
      plannerResult = const (
        shouldSend: true,
        minutesFromNow: 45,
        content: '今晚想聊聊天吗',
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 1);
      expect(schedulerCalls, 1);
      final messages = await messageRepo.getMessages(ids.conversationId);
      expect(messages, hasLength(2));
      final added = messages.last;
      expect(added.role, Role.assistant);
      expect(added.content, '今晚想聊聊天吗');
      expect(added.createdAt, fixedNow);

      final plans = await db.select(db.proactivePlans).get();
      expect(plans, hasLength(1));
      final plan = plans.single;
      expect(plan.status, ProactivePlanStatus.scheduled);
      expect(plan.scheduledAt, fixedNow.add(const Duration(minutes: 45)));
      expect(plan.messageId, added.id);
      expect(plan.characterId, ids.characterId);
      expect(plan.conversationId, ids.conversationId);
      expect(plan.content, '今晚想聊聊天吗');

      final scheduled = scheduledPlans.single;
      expect(scheduled.id, plan.id);
      expect(scheduled.scheduledAt, plan.scheduledAt);
      expect(scheduled.messageId, added.id);
    });

    test('过期核对：scheduled 且 scheduledAt <= now → expired（清理后允许新规划）', () async {
      final ids = await seedChain();
      await enableProactive();
      await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.subtract(const Duration(minutes: 1)),
        content: '已到点',
      );
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 1);
      final plans =
          await db.select(db.proactivePlans).get().then((p) => p.map((e) => e.status));
      expect(plans, unorderedEquals([
        ProactivePlanStatus.expired,
        ProactivePlanStatus.scheduled,
      ]));
    });

    test('过期核对：messageId 为 null 且 scheduled → dropped（消息删除后 FK setNull）', () async {
      final ids = await seedChain();
      await enableProactive();
      final plan = await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        content: '消息已删',
      );
      // 模拟重生成截断：删除计划指向的消息 → FK setNull（PS2-02 锁定语义）。
      await messageRepo.deleteMessagesFrom(ids.conversationId, plan.messageId!);
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 1);
      final plans =
          await db.select(db.proactivePlans).get().then((p) => p.map((e) => e.status));
      expect(plans, unorderedEquals([
        ProactivePlanStatus.dropped,
        ProactivePlanStatus.scheduled,
      ]));
    });

    test('两者命中（messageId null + 已过期）→ dropped 优先', () async {
      final ids = await seedChain();
      await enableProactive();
      final plan = await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.subtract(const Duration(hours: 2)),
        content: '残废计划',
      );
      await messageRepo.deleteMessagesFrom(ids.conversationId, plan.messageId!);
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 1);
      final plans =
          await db.select(db.proactivePlans).get().then((p) => p.map((e) => e.status));
      expect(plans, unorderedEquals([
        ProactivePlanStatus.dropped,
        ProactivePlanStatus.scheduled,
      ]));
    });

    test('过期核对只处理本角色计划（他角色 scheduled 不动）', () async {
      final ids = await seedChain();
      final other = await seedChain();
      await enableProactive();
      await seedScheduledPlan(
        characterId: other.characterId,
        conversationId: other.conversationId,
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        content: '他角色在途',
      );
      final service = buildService();

      await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      final plans = await db.select(db.proactivePlans).get();
      expect(plans, hasLength(2));
      final otherPlan = plans.singleWhere((p) => p.content == '他角色在途');
      expect(otherPlan.status, ProactivePlanStatus.scheduled);
    });

    test('planner 抛错 → debugPrint 降级返回 0，不落库不调 scheduler', () async {
      final ids = await seedChain();
      await enableProactive();
      plannerError = Exception('planner boom');
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      expect(schedulerCalls, 0);
      expect(await db.select(db.proactivePlans).get(), isEmpty);
      expect(await messageRepo.getMessages(ids.conversationId), hasLength(1));
    });

    test('scheduler 抛错 → 0 降级；消息与计划均已落库（持久化一致，仅通知失败）', () async {
      final ids = await seedChain();
      await enableProactive();
      final service = ProactiveMessageService(
        companionRepository: companionRepo,
        settingsRepository: settingsRepo,
        conversationRepository: conversationRepo,
        messageRepository: messageRepo,
        planner: fakePlanner(),
        scheduler: _FakeScheduler((plan) {
          throw Exception('notify boom');
        }),
        now: () => fixedNow,
      );

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );

      expect(result, 0);
      final messages = await messageRepo.getMessages(ids.conversationId);
      expect(messages, hasLength(2));
      expect(messages.last.content, '想你了');
      final plans = await db.select(db.proactivePlans).get();
      expect(plans.single.status, ProactivePlanStatus.scheduled);
      expect(plans.single.messageId, messages.last.id);
    });

    test('并发 in-flight：同角色两次 planAfterTurn → 仅一条计划一次调度', () async {
      final ids = await seedChain();
      await enableProactive();
      final service = buildService();

      final results = await Future.wait([
        service.planAfterTurn(
          characterId: ids.characterId,
          conversationId: ids.conversationId,
        ),
        service.planAfterTurn(
          characterId: ids.characterId,
          conversationId: ids.conversationId,
        ),
      ]);

      expect(results, unorderedEquals([1, 0]));
      expect(plannerCalls, 1);
      expect(schedulerCalls, 1);
      final plans = await db.select(db.proactivePlans).get();
      expect(plans, hasLength(1));
      expect(await messageRepo.getMessages(ids.conversationId), hasLength(2));
    });

    test('不同角色并发规划互不阻塞 → 各一条计划', () async {
      final idsA = await seedChain();
      final idsB = await seedChain();
      await enableProactive();
      final service = buildService();

      final results = await Future.wait([
        service.planAfterTurn(
          characterId: idsA.characterId,
          conversationId: idsA.conversationId,
        ),
        service.planAfterTurn(
          characterId: idsB.characterId,
          conversationId: idsB.conversationId,
        ),
      ]);

      expect(results, [1, 1]);
      expect(schedulerCalls, 2);
      expect(await db.select(db.proactivePlans).get(), hasLength(2));
    });

    test('对话不存在（FK 失败）→ 降级返回 0 不向上抛', () async {
      final ids = await seedChain();
      await enableProactive();
      final service = buildService();

      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: 99999,
      );

      expect(result, 0);
      expect(schedulerCalls, 0);
    });

    test('planAfterTurn 连续两次（串行）→ 第二次被 in-flight 节流拒绝', () async {
      final ids = await seedChain();
      await enableProactive();
      final service = buildService();

      expect(
        await service.planAfterTurn(
          characterId: ids.characterId,
          conversationId: ids.conversationId,
        ),
        1,
      );
      expect(
        await service.planAfterTurn(
          characterId: ids.characterId,
          conversationId: ids.conversationId,
        ),
        0,
      );
      expect(plannerCalls, 1);
      expect(schedulerCalls, 1);
      expect(await db.select(db.proactivePlans).get(), hasLength(1));
    });
  });

  group('ProactiveMessageService.markDeliveredByMessageId（C1 送达收口 + 节流生产可达）', () {
    late AppDatabase db;
    late CompanionRepository companionRepo;
    late SettingsRepository settingsRepo;
    late ConversationRepository conversationRepo;
    late MessageRepository messageRepo;
    late DateTime fixedNow;

    late int plannerCalls;
    late int schedulerCalls;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      fixedNow = DateTime(2026, 9, 15, 12, 0, 0);
      companionRepo = CompanionRepository(db, now: () => fixedNow);
      settingsRepo = SettingsRepository(
        database: db,
        secretStore: InMemorySecretStore(),
      );
      conversationRepo = ConversationRepository(
        db,
        const FakeSettingsReader(),
        now: () => fixedNow,
      );
      messageRepo = MessageRepository(db, now: () => fixedNow);
      plannerCalls = 0;
      schedulerCalls = 0;
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> enableProactive() async {
      await settingsRepo.setMany({'proactive_message_enabled': 'true'});
    }

    Future<({int characterId, int conversationId})> seedChain() async {
      final character = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(
              name: '艾莉亚',
              createdAt: fixedNow,
              updatedAt: fixedNow,
            ),
          );
      final conversation = await db.into(db.conversations).insertReturning(
            ConversationsCompanion.insert(
              characterId: character.id,
              createdAt: fixedNow,
              updatedAt: fixedNow,
            ),
          );
      await db.into(db.messages).insert(
            MessagesCompanion.insert(
              conversationId: conversation.id,
              role: Role.assistant,
              content: '开场白',
              createdAt: fixedNow.subtract(const Duration(days: 1)),
            ),
          );
      return (characterId: character.id, conversationId: conversation.id);
    }

    Future<ProactivePlan> seedScheduledPlan({
      required int characterId,
      required int conversationId,
      required DateTime scheduledAt,
      String content = '在途计划',
    }) async {
      final message = await messageRepo.createMessage(
        conversationId: conversationId,
        role: Role.assistant,
        content: content,
      );
      return companionRepo.createPlan(
        characterId: characterId,
        conversationId: conversationId,
        content: content,
        scheduledAt: scheduledAt,
        messageId: message.id,
      );
    }

    ProactiveMessageService buildService() {
      return ProactiveMessageService(
        companionRepository: companionRepo,
        settingsRepository: settingsRepo,
        conversationRepository: conversationRepo,
        messageRepository: messageRepo,
        planner: ({
          required int characterId,
          required int conversationId,
          required List<String> dialogueLines,
        }) async {
          plannerCalls++;
          return const (
            shouldSend: true,
            minutesFromNow: 30,
            content: '想你了',
          );
        },
        scheduler: _FakeScheduler((plan) {
          schedulerCalls++;
        }),
        now: () => fixedNow,
      );
    }

    test('scheduled 计划送达：置 sent + sentAt 写入，listPlansByStatus(sent) 可查回，返回 plan（characterId 正确）', () async {
      final ids = await seedChain();
      final plan = await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        content: '待送达',
      );
      final service = buildService();

      final delivered = await service.markDeliveredByMessageId(plan.messageId!);

      // 任务契约：返回 plan 且 characterId 正确；状态/sentAt 以库内查回为准
      // （返回对象为更新前快照——concern C1-1，消费面仅用 characterId）。
      expect(delivered, isNotNull);
      expect(delivered!.id, plan.id);
      expect(delivered.characterId, ids.characterId);
      final sent = await companionRepo.listPlansByStatus(ProactivePlanStatus.sent);
      expect(sent, hasLength(1));
      expect(sent.single.id, plan.id);
      expect(sent.single.status, ProactivePlanStatus.sent);
      expect(sent.single.sentAt, fixedNow);
      expect(
        await companionRepo.listPlansByStatus(ProactivePlanStatus.scheduled),
        isEmpty,
      );
    });

    test('幂等：重复送达 → null 且 sentAt 不被覆盖（显式 at 也不生效）', () async {
      final ids = await seedChain();
      final plan = await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
      );
      final service = buildService();

      final first = await service.markDeliveredByMessageId(plan.messageId!);
      final second = await service.markDeliveredByMessageId(
        plan.messageId!,
        at: fixedNow.add(const Duration(hours: 1)),
      );

      expect(first, isNotNull);
      expect(second, isNull);
      final sent = await companionRepo.listPlansByStatus(ProactivePlanStatus.sent);
      expect(sent.single.sentAt, fixedNow, reason: '重复点按不得覆盖首次送达时间');
      expect(sent.single.status, ProactivePlanStatus.sent);
    });

    test('不存在 messageId → null 零写库', () async {
      await seedChain();
      final service = buildService();

      final result = await service.markDeliveredByMessageId(999999);

      expect(result, isNull);
      expect(await db.select(db.proactivePlans).get(), isEmpty);
      expect(await companionRepo.listPlansByStatus(ProactivePlanStatus.sent), isEmpty);
    });

    test('dropped 计划（消息消失 messageId setNull）→ null 零写库', () async {
      final ids = await seedChain();
      final plan = await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
      );
      final messageId = plan.messageId!;
      // 生产 dropped 链：消息载体删除 → FK setNull。按已消失的 messageId
      // 点按，getPlanByMessageId 查不到 → null（dropped 天然排除）。
      await messageRepo.deleteMessagesFrom(ids.conversationId, messageId);
      final service = buildService();

      final result = await service.markDeliveredByMessageId(messageId);

      expect(result, isNull);
      expect(await companionRepo.listPlansByStatus(ProactivePlanStatus.sent), isEmpty);
      final plans = await db.select(db.proactivePlans).get();
      expect(plans.single.messageId, isNull);
    });

    test('expired 计划点按 → 同样收口置 sent + sentAt（F-88：点按即送达证据）', () async {
      final ids = await seedChain();
      final plan = await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.subtract(const Duration(hours: 1)),
        content: '已过期',
      );
      await companionRepo.updatePlanStatus(plan.id, ProactivePlanStatus.expired);
      final service = buildService();

      final delivered = await service.markDeliveredByMessageId(plan.messageId!);

      // F-88 新语义：expired 计划被点按 = 送达证据（与 expired「不重排不
      // 发送」正交——过期仅表示不再重排/发送，用户触达仍是事实）。
      expect(delivered, isNotNull);
      expect(delivered!.id, plan.id);
      expect(delivered.characterId, ids.characterId);
      expect(
        await companionRepo.listPlansByStatus(ProactivePlanStatus.expired),
        isEmpty,
      );
      final sent = await companionRepo.listPlansByStatus(ProactivePlanStatus.sent);
      expect(sent, hasLength(1));
      expect(sent.single.id, plan.id);
      expect(sent.single.status, ProactivePlanStatus.sent);
      expect(sent.single.sentAt, fixedNow);
    });

    test('C1 节流生产可达：markDelivered 送达 1 条后同角色 planAfterTurn 被 gate 拒绝，planner 零调用', () async {
      final ids = await seedChain();
      await enableProactive();
      final plan = await seedScheduledPlan(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
        scheduledAt: fixedNow.add(const Duration(hours: 1)),
        content: '送达即节流',
      );
      final service = buildService();

      // 生产送达收口：scheduled → sent + sentAt = fixedNow（今日）。状态以库
      // 查回为准（返回对象为更新前快照，见 concern C1-1）。
      final delivered = await service.markDeliveredByMessageId(plan.messageId!);
      expect(delivered, isNotNull);

      // 再规划：sentToday=1（今日计数读到送达写入）、冷却未过（sentAt 距 now
      // 0h < 6h）→ evaluateSchedule gate 拒绝，planner/scheduler 零调用——
      // 实证 sent 零写入问题修复后节流在生产路径可达。
      final result = await service.planAfterTurn(
        characterId: ids.characterId,
        conversationId: ids.conversationId,
      );
      expect(result, 0);
      expect(plannerCalls, 0);
      expect(schedulerCalls, 0);

      // 口径复核：gate 输入来自 markDelivered 写入的 sent 计划回读（非手工种）。
      final sent = await companionRepo.listPlansByStatus(ProactivePlanStatus.sent);
      expect(sent, hasLength(1));
      expect(sent.single.sentAt, fixedNow);
      final gate = evaluateSchedule(
        sentToday: sent.length,
        lastSentAt: sent.single.sentAt,
        lastActiveAt: fixedNow.subtract(const Duration(days: 1)),
        hasInFlightPlan: false,
        now: fixedNow,
      );
      expect(gate.allowed, isFalse);
      expect(gate.reason, 'cooldown');
    });
  });
}