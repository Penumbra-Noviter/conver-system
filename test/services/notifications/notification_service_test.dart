/// PS2-06 通知平台薄层行为契约 — 深链 payload 编解码（SR-02/SR-03）+
/// scheduler 实现降级语义（验收 1/2/5）。
///
/// 单测不触真平台通道（zonedSchedule 实际排程留模拟器冒烟，对齐「平台薄层
/// 经 seam 隔离」约定）：scheduler 经注入 _FakePlugin（继承插件类覆写平台
/// 方法）与注入 isAndroid 守卫可控路径；payload 纯函数穷举非法输入矩阵。
library;

import 'dart:async';

import 'package:conver_system_mobile/data/database/app_database.dart'
    show ProactivePlan;
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/services/companion/proactive_message_service.dart'
    show ProactiveNotificationScheduler;
import 'package:conver_system_mobile/services/notifications/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/debug_print_capture.dart';

/// 记录调用并可控成败的 channel fake（覆写插件调用面，不触真实通道）。
class _FakePlugin implements FlutterLocalNotificationsChannel {
  int initializeCalls = 0;
  bool initializeShouldFail = false;

  /// initialize 返回值注入开关（F-99 契约面）：缺省 true 保持既有用例
  /// 零改动；false/null 模拟插件通道初始化失败（服务按 false/null 处理）。
  bool? initializeResult = true;

  /// 可选挂起闸门（波末审核并发用例）：非 null 时 initialize 等待该
  /// Completer 完成后再返回，用于构造「带回调装配」与「懒初始化」交错。
  Completer<void>? initializeGate;
  bool scheduleShouldFail = false;
  bool cancelShouldFail = false;

  /// 最近一次 initialize 注册的热态回调（F-84：可被触发断言透传）。
  DidReceiveNotificationResponseCallback? registeredCallback;

  int permissionCalls = 0;
  bool? permissionResult = true;
  bool permissionShouldFail = false;

  int? lastZonedId;
  String? lastTitle;
  String? lastBody;
  tz.TZDateTime? lastScheduledDate;
  AndroidScheduleMode? lastScheduleMode;
  String? lastPayload;

  int? lastCancelId;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    initializeCalls++;
    registeredCallback = onDidReceiveNotificationResponse;
    final gate = initializeGate;
    if (gate != null) {
      await gate.future;
    }
    if (initializeShouldFail) {
      throw Exception('init boom');
    }
    return initializeResult;
  }

  @override
  Future<bool?> requestNotificationsPermission() async {
    permissionCalls++;
    if (permissionShouldFail) {
      throw Exception('permission boom');
    }
    return permissionResult;
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
  }) async {
    if (scheduleShouldFail) {
      throw Exception('schedule boom');
    }
    lastZonedId = id;
    lastTitle = title;
    lastBody = body;
    lastScheduledDate = scheduledDate;
    lastScheduleMode = androidScheduleMode;
    lastPayload = payload;
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    if (cancelShouldFail) {
      throw Exception('cancel boom');
    }
    lastCancelId = id;
  }
}

/// 验收 5 的假 seam：记录 schedule/cancel 调用（供 PS2-05 消费方替换）。
class FakeNotificationScheduler implements ProactiveNotificationScheduler {
  final List<int> scheduledIds = <int>[];
  final List<int> cancelledIds = <int>[];
  bool failNextSchedule = false;

  @override
  Future<bool> schedule(ProactivePlan plan) async {
    if (failNextSchedule) {
      failNextSchedule = false;
      return false;
    }
    scheduledIds.add(plan.id);
    return true;
  }

  Future<bool> cancel(int planId) async {
    cancelledIds.add(planId);
    return true;
  }
}

ProactivePlan buildPlan({
  int id = 7,
  int conversationId = 101,
  int? messageId = 202,
  DateTime? scheduledAt,
}) {
  return ProactivePlan(
    id: id,
    characterId: 1,
    conversationId: conversationId,
    content: '这是一条主动消息的完整内容，含私密细节',
    scheduledAt: scheduledAt ?? DateTime(2026, 9, 16, 12, 0, 0),
    sentAt: null,
    status: ProactivePlanStatus.scheduled,
    messageId: messageId,
  );
}

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
  });

  group('ProactiveDeepLink payload 编解码', () {
    test('encode → tryParse round-trip', () {
      final raw = ProactiveDeepLink.encode(conversationId: 101, messageId: 202);
      expect(raw, 'conver://proactive?conversationId=101&messageId=202');
      final parsed = ProactiveDeepLink.tryParse(raw);
      expect(parsed?.conversationId, 101);
      expect(parsed?.messageId, 202);
    });

    test('合法变体：参数顺序无关 + 多余参数宽容忽略', () {
      expect(
        ProactiveDeepLink.tryParse(
          'conver://proactive?messageId=9&conversationId=8',
        ),
        isNotNull,
      );
      final parsed = ProactiveDeepLink.tryParse(
        'conver://proactive?conversationId=1&messageId=2&from=whatever',
      );
      expect(parsed?.conversationId, 1);
      expect(parsed?.messageId, 2);
    });

    test('非数字 id → null 不抛（SR-02 int.tryParse，无 as 强转）', () {
      expect(
        ProactiveDeepLink.tryParse(
          'conver://proactive?conversationId=abc&messageId=2',
        ),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse(
          'conver://proactive?conversationId=1.5&messageId=2',
        ),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse(
          'conver://proactive?conversationId=1&messageId=xyz',
        ),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse(
          'conver://proactive?conversationId=-&messageId=2',
        ),
        isNull,
      );
    });

    test('正值域：非十进制无符号正整数形态 → null（参数化，两字段均覆盖）', () {
      const invalidIds = <String>[
        '0x10', // int.tryParse 会解析为 16（0x 前缀），形态校验必须拒绝
        '+7', // int.tryParse 会解析为 7（+ 前缀）
        '-7', // 负数（int.tryParse 解析为 -7，仅 >0 检查会漏）
        '0', // 零（仅 >0 检查会漏）
        ' 7', // 前导空白
        '7 ', // 尾随空白
        '%207', // 前导空白（百分号编码形态）
        '7%20', // 尾随空白（百分号编码形态）
        '007', // 前导 0
      ];
      for (final id in invalidIds) {
        expect(
          ProactiveDeepLink.tryParse(
            'conver://proactive?conversationId=$id&messageId=2',
          ),
          isNull,
          reason: 'conversationId=$id 应拒绝',
        );
        expect(
          ProactiveDeepLink.tryParse(
            'conver://proactive?conversationId=1&messageId=$id',
          ),
          isNull,
          reason: 'messageId=$id 应拒绝',
        );
      }
    });

    test('正值域：多位数合法正整数 → 解析成功（十进制无符号正整数契约）', () {
      final parsed = ProactiveDeepLink.tryParse(
        'conver://proactive?conversationId=987654321&messageId=123456789',
      );
      expect(parsed?.conversationId, 987654321);
      expect(parsed?.messageId, 123456789);
    });

    test('溢出整数 → null（int.tryParse 语义）', () {
      expect(
        ProactiveDeepLink.tryParse(
          'conver://proactive?conversationId=99999999999999999999999&messageId=2',
        ),
        isNull,
      );
    });

    test('缺字段 / 空值 → null', () {
      expect(
        ProactiveDeepLink.tryParse('conver://proactive?conversationId=1'),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse('conver://proactive?messageId=2'),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse(
          'conver://proactive?conversationId=&messageId=2',
        ),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse(
          'conver://proactive?conversationId=1&messageId=',
        ),
        isNull,
      );
      expect(ProactiveDeepLink.tryParse('conver://proactive'), isNull);
    });

    test('空串 / 非 URI / 错误 scheme / 错误 host → null（不抛）', () {
      expect(ProactiveDeepLink.tryParse(''), isNull);
      expect(ProactiveDeepLink.tryParse('随便什么文本'), isNull);
      expect(
        ProactiveDeepLink.tryParse(
          'https://proactive?conversationId=1&messageId=2',
        ),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse(
          'conver://other?conversationId=1&messageId=2',
        ),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse(
          'conver://proactive?conversationId=1&messageId=2#frag',
        ),
        isNotNull,
      );
    });
  });

  group('FlutterLocalNotificationsScheduler', () {
    late _FakePlugin plugin;
    late FlutterLocalNotificationsScheduler scheduler;

    FlutterLocalNotificationsScheduler build({required bool isAndroid}) {
      return FlutterLocalNotificationsScheduler(
        channel: plugin,
        isAndroid: () => isAndroid,
      );
    }

    setUp(() {
      plugin = _FakePlugin();
      scheduler = build(isAndroid: true);
    });

    test('默认构造（不注入）可实例化（生产装配路径，不触平台方法）', () {
      final defaultScheduler = FlutterLocalNotificationsScheduler();
      expect(defaultScheduler, isNotNull);
    });

    test(
      'schedule 成功 → true；zonedSchedule 收到 id/payload/摘要/inexact 模式',
      () async {
        final plan = buildPlan(
          id: 7,
          conversationId: 101,
          messageId: 202,
          scheduledAt: DateTime(2026, 9, 16, 12, 0, 0),
        );

        final ok = await scheduler.schedule(plan);

        expect(ok, isTrue);
        expect(plugin.lastZonedId, 7);
        expect(
          plugin.lastPayload,
          'conver://proactive?conversationId=101&messageId=202',
        );
        expect(
          plugin.lastScheduleMode,
          AndroidScheduleMode.inexactAllowWhileIdle,
        );
        expect(
          plugin.lastScheduledDate,
          tz.TZDateTime.from(DateTime(2026, 9, 16, 12, 0, 0), tz.local),
        );
      },
    );

    test('SR-11：body 用摘要，content 全文不落任何可见字段', () async {
      final plan = buildPlan();
      await scheduler.schedule(plan);

      expect(plugin.lastBody, isNot(contains(plan.content)));
      expect(plugin.lastBody, contains('消息'));
      expect(plugin.lastTitle, isNot(contains(plan.content)));
    });

    test('schedule 平台/权限异常 → false 不抛（P3 站内兜底信号）', () async {
      plugin.scheduleShouldFail = true;
      final ok = await scheduler.schedule(buildPlan());
      expect(ok, isFalse);
    });

    test('schedule 非 Android → false 不排（iOS 延后注记）', () async {
      final nonAndroid = build(isAndroid: false);
      final ok = await nonAndroid.schedule(buildPlan());
      expect(ok, isFalse);
      expect(plugin.lastZonedId, isNull);
    });

    test('messageId 缺失 → false 不排（深链定位不可用）', () async {
      final plan = buildPlan(messageId: null);
      final ok = await scheduler.schedule(plan);
      expect(ok, isFalse);
      expect(plugin.lastZonedId, isNull);
    });

    test('initialize 成功 → true；重复调用幂等（fake 仅一次）', () async {
      expect(await scheduler.initialize(), isTrue);
      expect(await scheduler.initialize(), isTrue);
      expect(plugin.initializeCalls, 1);
    });

    test('initialize 异常 → false 不抛；schedule 随之降级 false', () async {
      plugin.initializeShouldFail = true;
      expect(await scheduler.initialize(), isFalse);
      final ok = await scheduler.schedule(buildPlan());
      expect(ok, isFalse);
    });

    test(
      'initialize 透传 onDidReceiveNotificationResponse 至 channel（回调注册且可触发）',
      () async {
        NotificationResponse? received;
        void callback(NotificationResponse response) {
          received = response;
        }

        await scheduler.initialize(onDidReceiveNotificationResponse: callback);

        expect(plugin.registeredCallback, same(callback));
        plugin.registeredCallback!(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'conver://proactive?conversationId=101&messageId=202',
            id: 7,
          ),
        );
        expect(
          received?.payload,
          'conver://proactive?conversationId=101&messageId=202',
        );
        expect(received?.id, 7);
      },
    );

    test('initialize 带新回调晚到 → 重挂生效；同一回调重复 → 幂等零副作用（F-92 验收4）', () async {
      final logs = captureDebugPrint();

      void first(NotificationResponse response) {}
      void second(NotificationResponse response) {}

      expect(
        await scheduler.initialize(onDidReceiveNotificationResponse: first),
        isTrue,
      );
      expect(plugin.initializeCalls, 1);
      expect(plugin.registeredCallback, same(first));

      // 带不同回调晚到：仅重挂回调一次（再次 initialize 透传新回调），
      // 不重复 timezone/通道之外的初始化副作用；可补救路径零告警。
      expect(
        await scheduler.initialize(onDidReceiveNotificationResponse: second),
        isTrue,
      );
      expect(
        plugin.initializeCalls,
        2,
        reason: '晚到新回调触发一次重挂（修复前 _initialized 早退为 1）',
      );
      expect(
        plugin.registeredCallback,
        same(second),
        reason: '重挂语义：晚到装配回调成为最终生效回调（修复前此断言红）',
      );
      expect(
        logs.any((line) => line?.contains('热态回调丢失') ?? false),
        isFalse,
        reason: '可补救路径（重挂成功）零告警',
      );

      // 同一回调重复晚到：幂等零副作用（不再重挂、无新增通道副作用）。
      expect(
        await scheduler.initialize(onDidReceiveNotificationResponse: second),
        isTrue,
      );
      expect(plugin.initializeCalls, 2, reason: '同一回调重复调用幂等：不产生新增副作用');
      expect(plugin.registeredCallback, same(second));
    });

    test('并发反序真丢失修复：带回调先完成、无回调后完成 → 插件回调仍非 null（F-92 验收1）', () async {
      final logs = captureDebugPrint();

      NotificationResponse? received;
      void hotCallback(NotificationResponse response) {
        received = response;
      }

      // 构造交错：带回调装配先进入 initialize（挂起在 gate），
      // 无回调懒初始化后进入（此时 _initialized 仍 false，同样挂起）。
      final gate = Completer<void>();
      plugin.initializeGate = gate;
      final wired = scheduler.initialize(
        onDidReceiveNotificationResponse: hotCallback,
      );
      final lazy = scheduler.initialize();
      // 释放闸门：A（带回调）先注册恢复完成，B（无回调）后完成——
      // 修复前 B 会把插件回调槽覆盖为 null（hot=true 与插件实际不一致，
      // 真丢失面；F-92 已落债）。
      gate.complete();
      await Future.wait([wired, lazy]);

      // 锁串行语义：B 在 A 完成后走已初始化早退（无回调 → 静默），
      // 不再触碰插件回调槽——修复前 B 覆盖为 null，此断言红。
      expect(plugin.initializeCalls, 1, reason: '无回调后到路径早退，不重复初始化、不覆盖回调槽');
      expect(
        plugin.registeredCallback,
        isNotNull,
        reason: '并发反序交错后插件侧最终回调非 null（修复前此断言红）',
      );
      expect(plugin.registeredCallback, same(hotCallback));

      // 触发走消费路径：payload 经 registeredCallback 到达消费侧。
      plugin.registeredCallback!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'conver://proactive?conversationId=101&messageId=202',
          id: 7,
        ),
      );
      expect(
        received?.payload,
        'conver://proactive?conversationId=101&messageId=202',
      );

      // 早退路径：已注册回调事实应保持 → 零告警。
      await scheduler.initialize();
      expect(
        logs.any((line) => line?.contains('热态回调丢失') ?? false),
        isFalse,
        reason: '并发交错后首次已注册回调的事实不得被无回调路径降级',
      );
    });

    test('并发反序交错：无回调先挂起、带回调后进入 → 双 gate 两阶段锁串行（F-101）', () async {
      final logs = captureDebugPrint();

      NotificationResponse? received;
      void hotCallback(NotificationResponse response) {
        received = response;
      }

      // 票面纠偏（F-101）：A 方案修正对象「若锁失效并行交错则为 1」从未
      // 存在于仓库（git log -S 零命中，76f7da8 原文为「若早退拦截则为 1」）；
      // 单 gate 下 gate FIFO 巧合串行化掩盖锁失效（fake 记录调用顺序不钉锁），
      // 双 gate 中间态断言 initializeCalls == 1 为唯一零生产改动钉锁方案。
      // 反序交错：无回调懒初始化先进入（挂起在 gate1，首次置位未完成），
      // 带回调装配后进入——锁生效时 wired 挂在服务层 await previous，
      // 尚未到达 fake；锁失效（移除 await previous）时 wired 直走首次路径
      // 直达 fake，中间态为 2，断言红。
      final gate1 = Completer<void>();
      final gate2 = Completer<void>();
      plugin.initializeGate = gate1;
      final lazy = scheduler.initialize();
      plugin.initializeGate = gate2;
      final wired = scheduler.initialize(
        onDidReceiveNotificationResponse: hotCallback,
      );
      // 先放行 gate2（wired 的重挂通道调用）：此刻 wired 仍挂 await previous
      // 未达 fake，中间态断言 initializeCalls == 1 钉住等待依赖。
      gate2.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        plugin.initializeCalls,
        1,
        reason: '中间态 initializeCalls == 1：wired 挂在 await previous（锁失效则直达为 2，本断言红）',
      );
      // 放行 gate1：lazy 首次完成 → wired 恢复走已初始化重挂（gate2 已放行）。
      gate1.complete();
      final results = await Future.wait([lazy, wired]);

      expect(results[1], isTrue, reason: '带回调后到方走可补救重挂路径，按成功返回（无悬挂）');
      expect(
        plugin.initializeCalls,
        2,
        reason: '反序交错锁串行：无回调首次 + 带回调重挂各一次（若早退拦截则为 1；锁失效由中间态断言钉住）',
      );
      expect(
        plugin.registeredCallback,
        same(hotCallback),
        reason: '重挂语义：晚到装配回调成为最终生效回调',
      );
      expect(
        logs.any((line) => line?.contains('热态回调丢失') ?? false),
        isFalse,
        reason: '可补救路径（重挂成功）零告警',
      );

      // 重挂后的回调可触发消费（payload 经 registeredCallback 到达消费侧）。
      plugin.registeredCallback!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'conver://proactive?conversationId=101&messageId=202',
          id: 7,
        ),
      );
      expect(
        received?.payload,
        'conver://proactive?conversationId=101&messageId=202',
      );
    });

    test('先 schedule 后装配（可补救）：装配晚到重挂生效且零告警（F-92/F-97）', () async {
      final logs = captureDebugPrint();

      NotificationResponse? received;
      void hotCallback(NotificationResponse response) {
        received = response;
      }

      // 先经 schedule 触发懒初始化：首次 initialize 无回调（异常装配顺序）。
      expect(await scheduler.schedule(buildPlan()), isTrue);
      expect(plugin.initializeCalls, 1, reason: 'schedule 懒初始化恰好一次');
      expect(plugin.registeredCallback, isNull, reason: '懒初始化路径不含热态回调');

      // 后装配带回调 initialize：晚到重挂（再次 initialize 透传新回调）。
      expect(
        await scheduler.initialize(
          onDidReceiveNotificationResponse: hotCallback,
        ),
        isTrue,
      );
      expect(
        plugin.initializeCalls,
        2,
        reason: '装配晚到触发一次重挂（修复前 _initialized 早退为 1）',
      );
      expect(
        plugin.registeredCallback,
        same(hotCallback),
        reason: '装配回调最终注册生效——重挂语义（修复前此断言红）',
      );
      expect(
        logs.any((line) => line?.contains('热态回调丢失') ?? false),
        isFalse,
        reason: '可补救路径零告警（修复前此断言红：现实现早退打告警）',
      );

      // 重挂后的回调可触发消费（payload 到达消费侧）。
      plugin.registeredCallback!(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'conver://proactive?conversationId=101&messageId=202',
          id: 7,
        ),
      );
      expect(
        received?.payload,
        'conver://proactive?conversationId=101&messageId=202',
      );
    });

    test('验收2反例：懒初始化完成后、装配晚到前的无回调早退零误告警（F-92）', () async {
      final logs = captureDebugPrint();

      void hotCallback(NotificationResponse response) {}

      // 无回调懒初始化先完成（_initialized 已置）。
      expect(await scheduler.schedule(buildPlan()), isTrue);
      expect(plugin.initializeCalls, 1);
      expect(plugin.registeredCallback, isNull);

      // 装配挂起窗口内 third-party 无回调早退：不得误报「热态回调丢失」。
      expect(await scheduler.initialize(), isTrue);
      expect(plugin.initializeCalls, 1, reason: '无回调早退不触碰插件回调槽');
      expect(
        logs.any((line) => line?.contains('热态回调丢失') ?? false),
        isFalse,
        reason: '无回调早退不得误打假告警（修复前此断言红：现实现此路径告警）',
      );

      // 装配带回调晚到：重挂生效，全程零告警。
      expect(
        await scheduler.initialize(
          onDidReceiveNotificationResponse: hotCallback,
        ),
        isTrue,
      );
      expect(plugin.initializeCalls, 2);
      expect(
        plugin.registeredCallback,
        same(hotCallback),
        reason: '装配回调最终注册生效（重挂语义）',
      );
      expect(
        logs.any((line) => line?.contains('热态回调丢失') ?? false),
        isFalse,
        reason: '可补救路径（重挂成功）全程零告警',
      );
    });

    test('告警 seam（F-92 验收3）：正常/可补救路径 0 次，不可补救路径 ≥1 次', () async {
      // 正常装配路径：首次 initialize 即带回调 → 零告警。
      // 独立 _FakePlugin + 独立 scheduler（F-102）：与 recoverable/doomed
      // 分支同构，用例内不再经组级 scheduler/plugin，断言语义不依赖分支
      // 执行顺序。
      final normalPlugin = _FakePlugin();
      final normal = FlutterLocalNotificationsScheduler(
        channel: normalPlugin,
        isAndroid: () => true,
      );
      var lost = 0;
      expect(
        await normal.initialize(
          onDidReceiveNotificationResponse: (r) {},
          onHotCallbackLost: (reason) => lost++,
        ),
        isTrue,
      );
      expect(lost, 0, reason: '正常装配路径零告警');

      // 可补救路径：懒初始化后装配重挂成功 → 零告警。
      // 每分支独立 _FakePlugin（F-100）：断言语义不依赖分支执行顺序。
      final recoverablePlugin = _FakePlugin();
      final recoverable = FlutterLocalNotificationsScheduler(
        channel: recoverablePlugin,
        isAndroid: () => true,
      );
      final recoverableLost = <String>[];
      expect(await recoverable.schedule(buildPlan()), isTrue);
      expect(
        await recoverable.initialize(
          onDidReceiveNotificationResponse: (r) {},
          onHotCallbackLost: (reason) => recoverableLost.add(reason),
        ),
        isTrue,
      );
      expect(recoverableLost, isEmpty, reason: '可补救路径（重挂成功）零告警');
      expect(recoverablePlugin.initializeCalls, 2, reason: '懒初始化 1 次 + 重挂 1 次');
      expect(recoverablePlugin.registeredCallback, isNotNull);

      // 不可补救路径：重挂失败（插件 initialize 异常）→ seam 触发 ≥1 次。
      final doomedPlugin = _FakePlugin();
      final doomed = FlutterLocalNotificationsScheduler(
        channel: doomedPlugin,
        isAndroid: () => true,
      );
      expect(await doomed.schedule(buildPlan()), isTrue, reason: '懒初始化（无回调）成功');
      doomedPlugin.initializeShouldFail = true; // 重挂失败注入（仅本分支实例）
      var doomedLost = 0;
      expect(
        await doomed.initialize(
          onDidReceiveNotificationResponse: (r) {},
          onHotCallbackLost: (reason) => doomedLost++,
        ),
        isFalse,
        reason: '重挂失败按调用失败返回 false',
      );
      expect(doomedPlugin.initializeCalls, 2, reason: '懒初始化 1 次 + 重挂 1 次');
      expect(
        doomedLost,
        greaterThanOrEqualTo(1),
        reason: '不可补救路径告警 ≥1 次，经可注入 seam 上达调用方',
      );
    });

    test(
      'initialize 首次返回 false/null → false 不抛 + 失败不缓存可重试（F-99 验收2/3）',
      () async {
        final logs = captureDebugPrint();

        plugin.initializeResult = null;
        expect(await scheduler.initialize(), isFalse, reason: 'null 按失败处理');

        plugin.initializeResult = false;
        expect(await scheduler.initialize(), isFalse, reason: 'false 按失败处理');
        expect(
          logs.any(
            (line) => line?.contains('proactive notify init failed') ?? false,
          ),
          isTrue,
          reason: 'SR-12 摘要日志：失败路径带 proactive notify 前缀',
        );

        // 失败不缓存成功态：_initialized 未置位 → 恢复 true 后再次初始化
        // 递增调用（若误置 _initialized 则早退为 1，行为断言区分两策略）。
        plugin.initializeResult = true;
        expect(await scheduler.initialize(), isTrue);
        expect(
          plugin.initializeCalls,
          3,
          reason: '失败不缓存：再调递增（误置 _initialized 则早退不递增）',
        );
      },
    );

    test(
      '重挂返回 false → false + onHotCallbackLost ≥1 + 保留旧回调值（F-99 验收4）',
      () async {
        final logs = captureDebugPrint();

        void first(NotificationResponse response) {}
        void second(NotificationResponse response) {}

        expect(
          await scheduler.initialize(onDidReceiveNotificationResponse: first),
          isTrue,
        );
        expect(plugin.initializeCalls, 1);
        expect(plugin.registeredCallback, same(first));

        // 重挂注入 false：与异常路径同处理——seam 上报 + 返回 false，
        // 服务不更新 _registeredCallback 旧值（C2 残余 edge）。
        final reasons = <String>[];
        plugin.initializeResult = false;
        expect(
          await scheduler.initialize(
            onDidReceiveNotificationResponse: second,
            onHotCallbackLost: (reason) => reasons.add(reason),
          ),
          isFalse,
          reason: '重挂路径返回值 false → initialize 返回 false',
        );
        expect(
          reasons.length,
          greaterThanOrEqualTo(1),
          reason: '重挂失败经 onHotCallbackLost seam 上达（与异常路径同处理）',
        );
        expect(reasons.first, startsWith('hot callback re-register failed'));
        expect(
          logs.any(
            (line) =>
                line?.contains(
                  'proactive notify hot callback re-register failed',
                ) ??
                false,
          ),
          isTrue,
          reason: 'SR-12 摘要日志：失败路径带 proactive notify 前缀',
        );
        expect(
          plugin.registeredCallback,
          same(second),
          reason: '插件契约实证：返回值 false 前回调槽已覆盖为新回调（C2 前提）',
        );

        // 服务保留旧值的行为断言：second 与 first 不 identical → 再调仍
        // 触发重挂（initializeCalls 递增）；若服务误更新旧值则幂等不递增。
        plugin.initializeResult = true;
        expect(
          await scheduler.initialize(
            onDidReceiveNotificationResponse: second,
            onHotCallbackLost: (reason) => reasons.add(reason),
          ),
          isTrue,
        );
        expect(
          plugin.initializeCalls,
          3,
          reason: '服务保留旧值：晚到同一 second 可再重挂（C2 可补救）',
        );
      },
    );

    test('schedule 联动：初始化返回 false → schedule 降级 false（F-99 验收6）', () async {
      plugin.initializeResult = false;
      final ok = await scheduler.schedule(buildPlan());
      expect(ok, isFalse, reason: '初始化失败后 schedule 返回站内兜底信号');
    });

    test(
      'requestNotificationsPermission：Android 真路径经 channel 转发（true/false 透传）',
      () async {
        plugin.permissionResult = true;
        expect(await scheduler.requestNotificationsPermission(), isTrue);
        expect(plugin.permissionCalls, 1);

        plugin.permissionResult = false;
        expect(await scheduler.requestNotificationsPermission(), isFalse);
        expect(plugin.permissionCalls, 2);
      },
    );

    test(
      'requestNotificationsPermission：非 Android → null 且不调 channel',
      () async {
        final nonAndroid = build(isAndroid: false);
        expect(await nonAndroid.requestNotificationsPermission(), isNull);
        expect(plugin.permissionCalls, 0);
      },
    );

    test('requestNotificationsPermission：通道异常 → null 不抛（SR-12 摘要日志）', () async {
      plugin.permissionShouldFail = true;
      expect(await scheduler.requestNotificationsPermission(), isNull);
      expect(plugin.permissionCalls, 1);
    });

    test('cancel(planId) → true 且映射到通知 id；异常 → false 不抛', () async {
      expect(await scheduler.cancel(42), isTrue);
      expect(plugin.lastCancelId, 42);

      plugin.cancelShouldFail = true;
      expect(await scheduler.cancel(43), isFalse);
    });
  });

  group('FakeNotificationScheduler 假 seam 语义（验收 5）', () {
    test('记录 schedule/cancel 调用并可模拟失败', () async {
      final fake = FakeNotificationScheduler();
      final plan = buildPlan(id: 11);

      expect(await fake.schedule(plan), isTrue);
      expect(await fake.cancel(11), isTrue);
      expect(fake.scheduledIds, [11]);
      expect(fake.cancelledIds, [11]);

      fake.failNextSchedule = true;
      expect(await fake.schedule(buildPlan(id: 12)), isFalse);
      expect(fake.scheduledIds, [11]);
    });
  });
}
