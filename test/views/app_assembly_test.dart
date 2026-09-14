/// app.dart 装配图 seam 测试（C2 装配收敛 + 工单 05 首启指引启动分支）。
///
/// 既有语义锚点（工单 C2 验收）：DocumentParseService / GameGenerator /
/// SimulatorsController 由应用级装配图单一持有，HomeShell context 下可经
/// [Provider.of] 解析；复刻 ConverApp(database: db) 注入形态（内存执行器）。
///
/// 工单 05 追加：`ConverApp` 的 home 由首启指引启动门决定——标记缺失展示
/// [OnboardingPage]，标记已写直接进 [HomeShell]（spec §U-4 / 验收 5）。故
/// 既有装配断言须先落 `onboarding_completed` 标记使 HomeShell 出现。
library;

import 'package:conver_system_mobile/app.dart';
import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/conversation_export_service.dart';
import 'package:conver_system_mobile/services/document_parse_service.dart';
import 'package:conver_system_mobile/services/simulator/game_generator.dart';
import 'package:conver_system_mobile/view_models/simulators_controller.dart';
import 'package:conver_system_mobile/views/home_shell.dart';
import 'package:conver_system_mobile/views/onboarding/onboarding_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/in_memory_secret_store.dart';

/// 预写 `onboarding_completed` 标记，使启动门直接进 [HomeShell]（二次启动态）。
Future<void> _markOnboardingCompleted(AppDatabase db) =>
    SettingsRepository(database: db, secretStore: InMemorySecretStore())
        .setMany({'onboarding_completed': 'true'});

void main() {
  testWidgets('装配图单一持有 DocumentParseService 与 GameGenerator（C2 收敛）',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _markOnboardingCompleted(db);

    await tester.pumpWidget(ConverApp(database: db));
    await tester.pumpAndSettle();

    // HomeShell 在 MultiProvider 之下：装配图两服务实例可解析（惰性创建被
    // Provider.of 触发，覆盖 app.dart 新增装配分支）。
    final context = tester.element(find.byType(HomeShell));
    expect(
      Provider.of<DocumentParseService>(context, listen: false),
      isA<DocumentParseService>(),
      reason: 'DocumentParseService 装配点迁入 app.dart，可经公共装配图解析',
    );
    expect(
      Provider.of<GameGenerator>(context, listen: false),
      isA<GameGenerator>(),
      reason: 'GameGenerator 装配点迁入 app.dart，可经公共装配图解析',
    );
  });

  testWidgets('装配图持有 SimulatorsController（T3 proxyConfigReader 接线可构造）',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _markOnboardingCompleted(db);

    await tester.pumpWidget(ConverApp(database: db));
    await tester.pumpAndSettle();

    // 触发 SimulatorsController provider create 闭包——含 /proxy 反代凭据
    // seam 接线（SecretStore openai 槽 + SettingsRepository.baseUrl('openai')，
    // 与注入链同源）；闭包构造失败（装配断裂）即本测试失败。
    final context = tester.element(find.byType(HomeShell));
    expect(
      Provider.of<SimulatorsController>(context, listen: false),
      isA<SimulatorsController>(),
      reason: 'SimulatorsController 装配点含 proxyConfigReader 接线，可经装配图构造',
    );
  });

  testWidgets('装配图全部数据/服务 provider 可经 Provider.of 惰性构造（装配完整性）',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _markOnboardingCompleted(db);

    await tester.pumpWidget(ConverApp(database: db));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeShell));
    expect(Provider.of<SettingsRepository>(context, listen: false),
        isA<SettingsRepository>());
    expect(Provider.of<CharacterRepository>(context, listen: false),
        isA<CharacterRepository>());
    expect(Provider.of<ConversationRepository>(context, listen: false),
        isA<ConversationRepository>());
    expect(Provider.of<MessageRepository>(context, listen: false),
        isA<MessageRepository>());
    expect(Provider.of<ChatService>(context, listen: false), isA<ChatService>());
    expect(Provider.of<ConversationExportService>(context, listen: false),
        isA<ConversationExportService>());
  });

  testWidgets('首启（标记缺失）展示 OnboardingPage；跳过 → 进 HomeShell 且二次启动直接 HomeShell',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ConverApp(database: db));
    await tester.pumpAndSettle();

    // 首启：无标记 → OnboardingPage，HomeShell 未挂载。
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);

    // 跳过 → markCompleted 落库 + 状态翻转进 HomeShell。
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);

    // 标记已落库（真实 SettingsRepository 读回，非仅状态翻转）。
    final settings =
        SettingsRepository(database: db, secretStore: InMemorySecretStore());
    expect(await settings.getValue('onboarding_completed'), isNotEmpty);

    // 二次启动（全新装配、同一 db，标记已写）→ 直接 HomeShell。
    await tester.pumpWidget(ConverApp(key: UniqueKey(), database: db));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
  });
}
