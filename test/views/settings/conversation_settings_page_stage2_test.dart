/// 「对话」设置子页阶段 2 widget 契约（PS2-09）——「主动消息」与「内心独白」
/// 两开关：加载回显 / 切换写 `proactive_message_enabled`、`inner_thought_enabled`
/// 键 / 写失败回滚 + SnackBar / 加载失败保持缺省。
///
/// F-84 契约（Android 13+ 通知权限请求挂点）：开关 true 且落库成功后经
/// `requestNotificationsPermission` seam 恰请求一次；false 路径零请求；
/// 返回 false/null/抛错均不回滚开关（权限与开关语义正交）；未注入 seam 时
/// provider 兜底可解析（装配冒烟），provider 缺位降级不崩。
///
/// seam：ConversationSettingsPage 公开构造（仓储注入 + 可空权限请求 seam），
/// 读写经真实 SettingsRepository（内存 drift 真 schema），断言落在仓储
/// 可观察值上，不锁内部实现（对齐 conversation_settings_widget_test 基建）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/notifications/notification_service.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/settings/conversation_settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../helpers/in_memory_secret_store.dart';

/// 写失败的仓储替身：setMany 抛错 → 覆盖两开关的写失败回滚分支。
class _SaveFailRepo extends SettingsRepository {
  _SaveFailRepo(AppDatabase db)
    : super(database: db, secretStore: InMemorySecretStore());

  @override
  Future<void> setMany(Map<String, String> data) async =>
      throw StateError('save fail');
}

/// 加载失败的仓储替身：innerThoughtEnabled getter 抛错 → 覆盖 `_load` 的
/// 阶段 2 读取失败分支（开关保持缺省 false，页面不崩溃）。
class _Stage2LoadFailRepo extends SettingsRepository {
  _Stage2LoadFailRepo(AppDatabase db)
    : super(database: db, secretStore: InMemorySecretStore());

  @override
  Future<bool> get innerThoughtEnabled async => throw StateError('load fail');
}

/// F-84 通知权限 channel fake：记录请求次数并可控成败，不触真实平台通道。
class _FakeChannel implements FlutterLocalNotificationsChannel {
  int permissionCalls = 0;
  bool? permissionResult = true;
  bool permissionShouldFail = false;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async =>
      true;

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
  Future<bool?> requestNotificationsPermission() async {
    permissionCalls++;
    if (permissionShouldFail) {
      throw Exception('permission boom');
    }
    return permissionResult;
  }
}

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(database: db, secretStore: InMemorySecretStore());
  });

  tearDown(() async {
    await db.close();
  });

  /// 高视口 + 深色暖灰主题（注册 ConverPalette ThemeExtension）包一层
  /// MaterialApp，直接挂载子页。
  ///
  /// [requestNotificationsPermission] 注入 F-84 权限请求 seam（recorder）；
  /// [scheduler] 非空时以 Provider 装配 [FlutterLocalNotificationsScheduler]
  /// （模拟生产装配形态，验证未注入 seam 时 provider 兜底可解析）。
  Future<void> pumpPage(
    WidgetTester tester, {
    Future<bool?> Function()? requestNotificationsPermission,
    FlutterLocalNotificationsScheduler? scheduler,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final page = ConversationSettingsPage(
      settingsRepository: repo,
      requestNotificationsPermission: requestNotificationsPermission,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: scheduler == null
            ? page
            : Provider<FlutterLocalNotificationsScheduler>.value(
                value: scheduler,
                child: page,
              ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 重建子页（强制重新 `_load`）→ 回显存储中的最新值。
  Future<void> rebuildPage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester);
  }

  /// 读取指定开关的当前 UI 值。
  bool switchValue(WidgetTester tester, String title) => tester
      .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title))
      .value;

  testWidgets('加载回显：proactive=true / inner_thought=false 与存储一致', (
    tester,
  ) async {
    await repo.setMany({
      SettingsRepository.proactiveMessageEnabledKey: 'true',
      SettingsRepository.innerThoughtEnabledKey: 'false',
    });
    await pumpPage(tester);

    expect(switchValue(tester, '主动消息'), isTrue);
    expect(switchValue(tester, '内心独白'), isFalse);
    expect(find.text('角色会在合适时机主动发消息'), findsOneWidget);
    expect(find.text('角色以 <thought> 形式表达内心想法'), findsOneWidget);
  });

  testWidgets('切换「主动消息」→ 写 proactiveMessageEnabledKey 且重建回显一致', (tester) async {
    await pumpPage(tester);
    expect(switchValue(tester, '主动消息'), isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, '主动消息'));
    await tester.pumpAndSettle();
    expect(
      await repo.getValue(SettingsRepository.proactiveMessageEnabledKey),
      'true',
    );
    expect(switchValue(tester, '主动消息'), isTrue);

    // 卸载重建 → 从存储回显 true。
    await rebuildPage(tester);
    expect(switchValue(tester, '主动消息'), isTrue);
  });

  testWidgets('切换「内心独白」→ 写 innerThoughtEnabledKey 且重建回显一致', (tester) async {
    await pumpPage(tester);
    expect(switchValue(tester, '内心独白'), isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, '内心独白'));
    await tester.pumpAndSettle();
    expect(
      await repo.getValue(SettingsRepository.innerThoughtEnabledKey),
      'true',
    );
    expect(switchValue(tester, '内心独白'), isTrue);

    await rebuildPage(tester);
    expect(switchValue(tester, '内心独白'), isTrue);
  });

  testWidgets('主动消息写失败 → UI 回滚 + SnackBar「保存失败」', (tester) async {
    final failing = _SaveFailRepo(db);
    repo = failing;
    await pumpPage(tester);
    expect(switchValue(tester, '主动消息'), isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, '主动消息'));
    await tester.pumpAndSettle();

    expect(switchValue(tester, '主动消息'), isFalse, reason: '写失败应回滚 UI');
    expect(find.text('保存失败'), findsOneWidget);
  });

  testWidgets('内心独白写失败 → UI 回滚 + SnackBar「保存失败」', (tester) async {
    final failing = _SaveFailRepo(db);
    repo = failing;
    await pumpPage(tester);
    expect(switchValue(tester, '内心独白'), isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, '内心独白'));
    await tester.pumpAndSettle();

    expect(switchValue(tester, '内心独白'), isFalse, reason: '写失败应回滚 UI');
    expect(find.text('保存失败'), findsOneWidget);
  });

  testWidgets('加载失败（阶段 2 getter 抛错）→ 两开关缺省 false，页面不崩溃', (tester) async {
    final failing = _Stage2LoadFailRepo(db);
    repo = failing;
    await pumpPage(tester);

    expect(switchValue(tester, '主动消息'), isFalse);
    expect(switchValue(tester, '内心独白'), isFalse);
    expect(find.widgetWithText(SwitchListTile, '主动消息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重复切换「主动消息」→ 值在 true/false 间往返且落库一致', (tester) async {
    await pumpPage(tester);

    final tile = find.widgetWithText(SwitchListTile, '主动消息');
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(
      await repo.getValue(SettingsRepository.proactiveMessageEnabledKey),
      'true',
    );

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(
      await repo.getValue(SettingsRepository.proactiveMessageEnabledKey),
      'false',
    );
    expect(switchValue(tester, '主动消息'), isFalse);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(
      await repo.getValue(SettingsRepository.proactiveMessageEnabledKey),
      'true',
    );
    expect(switchValue(tester, '主动消息'), isTrue);
  });

  testWidgets('F-84 开关 true → 落库成功后通知权限请求恰一次', (tester) async {
    var calls = 0;
    await pumpPage(tester, requestNotificationsPermission: () async {
      calls += 1;
      return true;
    });

    await tester.tap(find.widgetWithText(SwitchListTile, '主动消息'));
    await tester.pumpAndSettle();

    expect(calls, 1, reason: '启用路径应恰请求一次权限');
    expect(
      await repo.getValue(SettingsRepository.proactiveMessageEnabledKey),
      'true',
    );
    expect(switchValue(tester, '主动消息'), isTrue);
  });

  testWidgets('F-84 开关 false（关闭路径）→ 不请求权限', (tester) async {
    await repo.setMany({
      SettingsRepository.proactiveMessageEnabledKey: 'true',
    });
    var calls = 0;
    await pumpPage(tester, requestNotificationsPermission: () async {
      calls += 1;
      return true;
    });

    await tester.tap(find.widgetWithText(SwitchListTile, '主动消息'));
    await tester.pumpAndSettle();

    expect(calls, 0, reason: '关闭路径不应请求权限');
    expect(
      await repo.getValue(SettingsRepository.proactiveMessageEnabledKey),
      'false',
    );
    expect(switchValue(tester, '主动消息'), isFalse);
  });

  testWidgets('F-84 权限请求返回 false → 开关不回滚、功能照常生效', (tester) async {
    await pumpPage(tester, requestNotificationsPermission: () async => false);

    await tester.tap(find.widgetWithText(SwitchListTile, '主动消息'));
    await tester.pumpAndSettle();

    expect(switchValue(tester, '主动消息'), isTrue, reason: '权限被拒不回滚开关');
    expect(
      await repo.getValue(SettingsRepository.proactiveMessageEnabledKey),
      'true',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('F-84 权限请求返回 null → 开关不回滚、无崩溃', (tester) async {
    await pumpPage(tester, requestNotificationsPermission: () async => null);

    await tester.tap(find.widgetWithText(SwitchListTile, '主动消息'));
    await tester.pumpAndSettle();

    expect(switchValue(tester, '主动消息'), isTrue);
    expect(
      await repo.getValue(SettingsRepository.proactiveMessageEnabledKey),
      'true',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('F-84 权限请求抛错 → 开关不回滚、无崩溃（降级 debugPrint）', (tester) async {
    await pumpPage(
      tester,
      requestNotificationsPermission: () async =>
          throw StateError('permission boom'),
    );

    await tester.tap(find.widgetWithText(SwitchListTile, '主动消息'));
    await tester.pumpAndSettle();

    expect(switchValue(tester, '主动消息'), isTrue, reason: '请求异常不回滚开关');
    expect(
      await repo.getValue(SettingsRepository.proactiveMessageEnabledKey),
      'true',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('F-84 未注入 seam → provider 兜底经 scheduler 请求恰一次（装配冒烟）', (tester) async {
    final channel = _FakeChannel();
    final scheduler = FlutterLocalNotificationsScheduler(
      channel: channel,
      isAndroid: () => true,
    );
    await pumpPage(tester, scheduler: scheduler);

    await tester.tap(find.widgetWithText(SwitchListTile, '主动消息'));
    await tester.pumpAndSettle();

    expect(channel.permissionCalls, 1, reason: 'provider 兜底应转发到 scheduler');
    expect(switchValue(tester, '主动消息'), isTrue);
    expect(
      await repo.getValue(SettingsRepository.proactiveMessageEnabledKey),
      'true',
    );
    expect(tester.takeException(), isNull);
  });
}
