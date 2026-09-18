/// MemoryManagementView 确认闸门 widget 契约（F-109 工单 03）：
/// AppBar 演化 action / tile 双形态（待确认可操作、已应用只读）/ SnackBar 三态。
library;

import 'dart:async';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/services/memory/persona_evolution_service.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart' show ConverTheme;
import 'package:conver_system_mobile/views/characters/memory_management_controller.dart';
import 'package:conver_system_mobile/views/characters/memory_management_view.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late MemoryRepository repo;
  late CharacterRepository characterRepo;
  late int characterId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = MemoryRepository(db);
    characterRepo = CharacterRepository(db);
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '艾莉亚',
            personality: Value('温柔体贴'),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    characterId = character.id;
  });

  tearDown(() async {
    await db.close();
  });

  MemoryManagementController buildController(
    Future<String> Function({
      required int characterId,
      required String currentPersonality,
      required String charName,
      required List<String> personaFacts,
    })
    reflector,
  ) => MemoryManagementController(
    memoryRepository: repo,
    characterId: characterId,
    evolutionService: PersonaEvolutionService(
      characterRepository: characterRepo,
      memoryRepository: repo,
      reflector: reflector,
    ),
    characterRepository: characterRepo,
  );

  Future<void> pumpView(
    WidgetTester tester,
    MemoryManagementController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: MemoryManagementView(controller: controller),
      ),
    );
    // post-frame load 触发 + load 完成（drift 内存库异步）。
    await tester.pump();
    await tester.pump();
  }

  group('AppBar 演化 action', () {
    testWidgets('存在：tooltip「提出人设演化」+ auto_awesome 图标', (tester) async {
      final controller = buildController(
        ({
          required characterId,
          required currentPersonality,
          required charName,
          required personaFacts,
        }) async => '新人格',
      );
      await pumpView(tester, controller);

      expect(find.byTooltip('提出人设演化'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.auto_awesome),
        ),
        findsOneWidget,
      );
    });

    testWidgets('proposing 期间替换为 loading 且 action 禁用', (tester) async {
      final gate = Completer<String>();
      final controller = buildController(
        ({
          required characterId,
          required currentPersonality,
          required charName,
          required personaFacts,
        }) => gate.future,
      );
      await pumpView(tester, controller);

      await tester.tap(find.byTooltip('提出人设演化'));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final buttonFinder = find.ancestor(
        of: find.byTooltip('提出人设演化'),
        matching: find.byType(IconButton),
      );
      final button = tester.widget<IconButton>(buttonFinder);
      expect(button.onPressed, isNull);

      gate.complete('新人格');
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
    });
  });

  group('tile 双形态（Q7）', () {
    testWidgets('待确认 tile 显示「应用」「拒绝」；已应用 tile 无操作按钮', (tester) async {
      final current = (await characterRepo.getCharacter(characterId))!
          .personality;
      // 已应用版本：快照 == 当前人格（只读，无按钮）。
      await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: current,
      );
      // 待确认版本：快照 != 当前人格（显示操作按钮）。
      await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: '待确认版本',
      );
      final controller = buildController(
        ({
          required characterId,
          required currentPersonality,
          required charName,
          required personaFacts,
        }) async => '新人格',
      );
      await pumpView(tester, controller);

      // 两个 tile 并存：仅待确认那个携带「应用」「拒绝」按钮。
      expect(find.text('应用'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(2));
    });

    testWidgets('全部已应用（快照 == 当前人格）→ 无操作按钮', (tester) async {
      final current = (await characterRepo.getCharacter(characterId))!
          .personality;
      await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: current,
      );
      final controller = buildController(
        ({
          required characterId,
          required currentPersonality,
          required charName,
          required personaFacts,
        }) async => '新人格',
      );
      await pumpView(tester, controller);

      expect(find.text('应用'), findsNothing);
      expect(find.text('拒绝'), findsNothing);
    });
  });

  group('记忆条目 CRUD（既有行为回归）', () {
    testWidgets('空态：无条目无版本 → 「暂无记忆」', (tester) async {
      final controller = buildController(({required characterId, required currentPersonality, required charName, required personaFacts}) async => '新人格');
      await pumpView(tester, controller);

      expect(find.text('暂无记忆'), findsOneWidget);
    });

    testWidgets('新增：预置条目后 tap 新增 → 人格事实 → 输入 → 保存 → 新条目出现', (tester) async {
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '已有条目',
      );
      final controller = buildController(({required characterId, required currentPersonality, required charName, required personaFacts}) async => '新人格');
      await pumpView(tester, controller);

      // 既有 UI：entries 非空才有「新增记忆」header action（空态 = EmptyState
      // 无操作入口，属既有行为，不在本工单范围）。
      await tester.tap(find.byTooltip('新增记忆'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, '人格事实'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '她喜欢猫');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('她喜欢猫'), findsOneWidget);
      expect(find.text('已有条目'), findsOneWidget);
    });

    testWidgets('编辑：tap 编辑 → 改内容 → 保存 → 条目更新', (tester) async {
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '原内容',
      );
      final controller = buildController(({required characterId, required currentPersonality, required charName, required personaFacts}) async => '新人格');
      await pumpView(tester, controller);

      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '新内容');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('新内容'), findsOneWidget);
    });

    testWidgets('删除：tap 删除 → 确认 → 条目消失', (tester) async {
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '待删内容',
      );
      final controller = buildController(({required characterId, required currentPersonality, required charName, required personaFacts}) async => '新人格');
      await pumpView(tester, controller);

      await tester.tap(find.byTooltip('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('待删内容'), findsNothing);
    });
  });

  group('演化交互 SnackBar', () {
    testWidgets('propose 成功 → 「已提出演化，待确认」+ 新待确认 tile', (tester) async {
      final controller = buildController(
        ({
          required characterId,
          required currentPersonality,
          required charName,
          required personaFacts,
        }) async => '温柔体贴且心思细腻',
      );
      await pumpView(tester, controller);

      await tester.tap(find.byTooltip('提出人设演化'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('已提出演化，待确认'), findsOneWidget);
      expect(find.text('应用'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
    });

    testWidgets('propose 无变化 → 「人设无变化」', (tester) async {
      final controller = buildController(
        ({
          required characterId,
          required currentPersonality,
          required charName,
          required personaFacts,
        }) async => currentPersonality,
      );
      await pumpView(tester, controller);

      await tester.tap(find.byTooltip('提出人设演化'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('人设无变化'), findsOneWidget);
    });

    testWidgets('apply 成功 → 「人设已更新」+ tile 转只读', (tester) async {
      final controller = buildController(
        ({
          required characterId,
          required currentPersonality,
          required charName,
          required personaFacts,
        }) async => '温柔体贴且心思细腻',
      );
      await pumpView(tester, controller);

      await tester.tap(find.byTooltip('提出人设演化'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('应用'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('人设已更新'), findsOneWidget);
      expect(find.text('应用'), findsNothing);
      expect(find.text('拒绝'), findsNothing);
    });
  });
}
