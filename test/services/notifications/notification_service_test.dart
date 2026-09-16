/// PS2-06 通知平台薄层行为契约 — 深链 payload 编解码（SR-02/SR-03）+
/// scheduler 实现降级语义（验收 1/2/5）。
///
/// 单测不触真平台通道（zonedSchedule 实际排程留模拟器冒烟，对齐「平台薄层
/// 经 seam 隔离」约定）：scheduler 经注入 _FakePlugin（继承插件类覆写平台
/// 方法）与注入 isAndroid 守卫可控路径；payload 纯函数穷举非法输入矩阵。
library;

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

/// 记录调用并可控成败的 channel fake（覆写插件调用面，不触真实通道）。
class _FakePlugin implements FlutterLocalNotificationsChannel {
  int initializeCalls = 0;
  bool initializeShouldFail = false;
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
    if (initializeShouldFail) {
      throw Exception('init boom');
    }
    return true;
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
      final raw = ProactiveDeepLink.encode(
        conversationId: 101,
        messageId: 202,
      );
      expect(raw, 'conver://proactive?conversationId=101&messageId=202');
      final parsed = ProactiveDeepLink.tryParse(raw);
      expect(parsed?.conversationId, 101);
      expect(parsed?.messageId, 202);
    });

    test('合法变体：参数顺序无关 + 多余参数宽容忽略', () {
      expect(
        ProactiveDeepLink.tryParse(
            'conver://proactive?messageId=9&conversationId=8'),
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
        ProactiveDeepLink.tryParse('conver://proactive?conversationId=abc&messageId=2'),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse('conver://proactive?conversationId=1.5&messageId=2'),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse('conver://proactive?conversationId=1&messageId=xyz'),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse('conver://proactive?conversationId=-&messageId=2'),
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
              'conver://proactive?conversationId=$id&messageId=2'),
          isNull,
          reason: 'conversationId=$id 应拒绝',
        );
        expect(
          ProactiveDeepLink.tryParse(
              'conver://proactive?conversationId=1&messageId=$id'),
          isNull,
          reason: 'messageId=$id 应拒绝',
        );
      }
    });

    test('正值域：多位数合法正整数 → 解析成功（十进制无符号正整数契约）', () {
      final parsed = ProactiveDeepLink.tryParse(
          'conver://proactive?conversationId=987654321&messageId=123456789');
      expect(parsed?.conversationId, 987654321);
      expect(parsed?.messageId, 123456789);
    });

    test('溢出整数 → null（int.tryParse 语义）', () {
      expect(
        ProactiveDeepLink.tryParse(
            'conver://proactive?conversationId=99999999999999999999999&messageId=2'),
        isNull,
      );
    });

    test('缺字段 / 空值 → null', () {
      expect(ProactiveDeepLink.tryParse('conver://proactive?conversationId=1'), isNull);
      expect(ProactiveDeepLink.tryParse('conver://proactive?messageId=2'), isNull);
      expect(
        ProactiveDeepLink.tryParse('conver://proactive?conversationId=&messageId=2'),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse('conver://proactive?conversationId=1&messageId='),
        isNull,
      );
      expect(ProactiveDeepLink.tryParse('conver://proactive'), isNull);
    });

    test('空串 / 非 URI / 错误 scheme / 错误 host → null（不抛）', () {
      expect(ProactiveDeepLink.tryParse(''), isNull);
      expect(ProactiveDeepLink.tryParse('随便什么文本'), isNull);
      expect(
        ProactiveDeepLink.tryParse('https://proactive?conversationId=1&messageId=2'),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse('conver://other?conversationId=1&messageId=2'),
        isNull,
      );
      expect(
        ProactiveDeepLink.tryParse('conver://proactive?conversationId=1&messageId=2#frag'),
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

    test('schedule 成功 → true；zonedSchedule 收到 id/payload/摘要/inexact 模式', () async {
      final plan = buildPlan(
        id: 7,
        conversationId: 101,
        messageId: 202,
        scheduledAt: DateTime(2026, 9, 16, 12, 0, 0),
      );

      final ok = await scheduler.schedule(plan);

      expect(ok, isTrue);
      expect(plugin.lastZonedId, 7);
      expect(plugin.lastPayload,
          'conver://proactive?conversationId=101&messageId=202');
      expect(plugin.lastScheduleMode, AndroidScheduleMode.inexactAllowWhileIdle);
      expect(plugin.lastScheduledDate, tz.TZDateTime.from(
          DateTime(2026, 9, 16, 12, 0, 0), tz.local));
    });

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

    test('initialize 透传 onDidReceiveNotificationResponse 至 channel（回调注册且可触发）', () async {
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
      expect(received?.payload,
          'conver://proactive?conversationId=101&messageId=202');
      expect(received?.id, 7);
    });

    test('initialize 幂等：再次调用不重注册、不丢失首次回调', () async {
      void first(NotificationResponse response) {}
      void second(NotificationResponse response) {}

      expect(
        await scheduler.initialize(onDidReceiveNotificationResponse: first),
        isTrue,
      );
      expect(plugin.initializeCalls, 1);
      expect(plugin.registeredCallback, same(first));

      expect(
        await scheduler.initialize(onDidReceiveNotificationResponse: second),
        isTrue,
      );
      expect(plugin.initializeCalls, 1, reason: '幂等：_initialized 后不重复初始化');
      expect(plugin.registeredCallback, same(first),
          reason: '首次注册的回调不被二次调用覆盖');
    });

    test('requestNotificationsPermission：Android 真路径经 channel 转发（true/false 透传）', () async {
      plugin.permissionResult = true;
      expect(await scheduler.requestNotificationsPermission(), isTrue);
      expect(plugin.permissionCalls, 1);

      plugin.permissionResult = false;
      expect(await scheduler.requestNotificationsPermission(), isFalse);
      expect(plugin.permissionCalls, 2);
    });

    test('requestNotificationsPermission：非 Android → null 且不调 channel', () async {
      final nonAndroid = build(isAndroid: false);
      expect(await nonAndroid.requestNotificationsPermission(), isNull);
      expect(plugin.permissionCalls, 0);
    });

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