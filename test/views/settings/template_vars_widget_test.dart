/// 「模板变量」编辑子页 widget 契约（工单 04 / spec §U-3）。
///
/// seam：TemplateVarsPage 公开构造（SettingsRepository 注入）。断言外部行为：
/// - 空态提示 + 添加变量行；
/// - key/value 增删改后保存 → 序列化 JSON 写入 Settings 表（`template_vars` 键）；
/// - 重进回显已保存变量；
/// - 空 key 行在保存时被过滤。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/settings/template_vars_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';

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

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: TemplateVarsPage(settingsRepository: repo),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('TemplateVarsPage（工单 04）', () {
    testWidgets('空态显示提示与添加/保存按钮', (tester) async {
      await pumpPage(tester);

      expect(find.text('模板变量'), findsOneWidget);
      expect(find.text('尚未添加变量'), findsOneWidget);
      expect(find.text('添加变量'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('添加 key/value 并保存 → 序列化 JSON 写入 Settings 表', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('添加变量'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '变量名'), 'city');
      await tester.enterText(find.widgetWithText(TextField, '变量值'), '长安');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(await repo.templateVars, {'city': '长安'});
    });

    testWidgets('保存后重进回显已保存变量', (tester) async {
      await repo.setMany({'template_vars': '{"city":"长安","mood":"冷静"}'});
      await pumpPage(tester);

      expect(find.text('city'), findsOneWidget);
      expect(find.text('长安'), findsOneWidget);
      expect(find.text('mood'), findsOneWidget);
      expect(find.text('冷静'), findsOneWidget);
      expect(find.text('尚未添加变量'), findsNothing);
    });

    testWidgets('空 key 行在保存时被过滤（不产生空键）', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('添加变量'));
      await tester.pumpAndSettle();

      // 只填 value，不填 key → 该行应在保存时被过滤。
      await tester.enterText(find.widgetWithText(TextField, '变量值'), '无键值');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(await repo.templateVars, isEmpty);
    });

    testWidgets('删除变量行后保存 → 该变量不落库', (tester) async {
      await repo.setMany({'template_vars': '{"city":"长安","mood":"冷静"}'});
      await pumpPage(tester);

      expect(find.text('city'), findsOneWidget);
      expect(find.text('mood'), findsOneWidget);

      // 删除第一行（city），保留 mood。
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(await repo.templateVars, {'mood': '冷静'});
    });
  });
}
