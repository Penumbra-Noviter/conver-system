/// CharacterWizardView 步骤②行为契约（工单 M3-02b 验收 1–6）。
///
/// 语义锚点（spec §Solution 2 / 共识 A2 / 桌面 character-wizard.js
/// renderStep2 + validateStep case 2）：
/// - template 模式步骤②渲染 5 模板卡（name/description/tags 逐字来自
///   `characterTemplates.dart`），点击 → `selectTemplate(id)` 填充并高亮选中；
///   再次进入步骤②保持上次选中态（controller.selectedTemplateId 承载）；
/// - import 模式步骤②渲染多行 textarea（占位含「粘贴角色设定文档」语义）、
///   「AI 智能解析」按钮 disabled + 边上逐字文案「文档 AI 解析随 M4 交付」，
///   text 输入不触发任何解析调用（no-op，不调 parse 接口）；
/// - 步骤②校验：template 未选下一步 → 「请选择一个模板」拦截（视图层
///   校验；controller 只读既有状态机，本层拦截不越权）；import 模式下一步
///   放行（不受内容影响）；
/// - 模板应用端到端：选模板 → 步骤③/④/⑤ 回显已填字段；手动路径回归
///   （manual 直接跳③，步骤②不出现）；template 保存落库字段与模板一致
///   （DB 断言，creator 空串）+ 列表可见（复用角色页渲染）。
///
/// 测试 seam（spec Testing Decisions）：真实「控制器 + 内存 drift 库」，
/// 不 mock 仓储内部；widget 层注入装配基座同 `character_wizard_view_test`
/// 同形。
library;

import 'package:conver_system_mobile/data/character_templates.dart';
import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/character_file_exchange.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/shell_navigation.dart';
import 'package:conver_system_mobile/views/characters/characters_controller.dart';
import 'package:conver_system_mobile/views/characters/characters_view.dart';
import 'package:conver_system_mobile/views/characters/wizard/character_wizard_controller.dart';
import 'package:conver_system_mobile/views/characters/wizard/character_wizard_view.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../helpers/fake_llm_provider.dart';
import '../../../helpers/in_memory_secret_store.dart';

/// [SettingsReader] 的内存假实现（与 chat 系测试同形；本文件仅用默认空值）。
class _FakeSettingsReader implements SettingsReader {
  const _FakeSettingsReader();

  @override
  Future<String> get defaultProvider async => '';

  @override
  Future<String> get defaultModel async => '';

  @override
  Future<String> get userName async => '';
}

/// 全装配（角色页入口 → 向导 → 列表可见测试用），同
/// `character_wizard_view_test._CharsEnv` 同形。
class _CharsEnv {
  _CharsEnv({
    required this.db,
    required this.characterRepository,
    required this.controller,
  });

  final AppDatabase db;
  final CharacterRepository characterRepository;
  final CharactersController controller;

  static Future<_CharsEnv> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    final characterRepository = CharacterRepository(db);
    final conversationRepository =
        ConversationRepository(db, const _FakeSettingsReader());
    final messageRepository = MessageRepository(db);
    final chatController = ChatController(
      chatService: ChatService(
        database: db,
        conversationRepository: conversationRepository,
        characterRepository: characterRepository,
        messageRepository: messageRepository,
        settingsRepository:
            SettingsRepository(database: db, secretStore: InMemorySecretStore()),
        providerFactory:
            FixedLLMProviderFactory(FakeLLMProvider(tokens: const ['ok'])),
      ),
      conversationRepository: conversationRepository,
      characterRepository: characterRepository,
      messageRepository: messageRepository,
    );
    final controller = CharactersController(
      characterRepository: characterRepository,
      fileExchange: const CharacterFileExchangeStub(),
      navigation: ShellNavigation(),
      chatController: chatController,
    );
    return _CharsEnv(
      db: db,
      characterRepository: characterRepository,
      controller: controller,
    );
  }

  Future<void> close() => db.close();
}

void main() {
  late AppDatabase db;
  late CharacterRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = CharacterRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// 泵向导页（全屏 Scaffold，ConverTheme 装配）。
  Future<void> pumpWizard(
    WidgetTester tester,
    WizardController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: CharacterWizardView(controller: controller),
      ),
    );
  }

  /// 从步骤①进入步骤②（指定方式）。
  Future<void> enterStep2(
    WidgetTester tester,
    WizardController controller, {
    required WizardCreationMode mode,
  }) async {
    await pumpWizard(tester, controller);
    await tester.tap(find.text(mode == WizardCreationMode.template
        ? '从模板开始'
        : '智能导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(controller.step, 2, reason: '进入步骤②');
  }

  group('步骤② template 模板网格（验收 1）', () {
    testWidgets('渲染 5 张模板卡（名称/描述/标签来自 character_templates）',
        (tester) async {
      expect(characterTemplates, hasLength(5), reason: '既有 5 模板常量契约');
      final c = WizardController(characterRepository: repository);

      await enterStep2(tester, c, mode: WizardCreationMode.template);

      // 5 模板名称逐字可见。
      for (final template in characterTemplates) {
        expect(find.text(template.name), findsOneWidget,
            reason: '模板「${template.name}」卡片渲染');
      }
      // 描述与标签（逐字来自常量表）。
      expect(find.text('温柔体贴、学识渊博的学姐'), findsOneWidget);
      expect(find.text('#校园'), findsOneWidget);
      expect(find.text('#猫娘'), findsOneWidget);
    });

    testWidgets('点击模板卡 → selectTemplate(id) 填充；再次进入步骤②保持选中态',
        (tester) async {
      final c = WizardController(characterRepository: repository);
      await enterStep2(tester, c, mode: WizardCreationMode.template);

      await tester.tap(find.text('知性学姐'));
      await tester.pumpAndSettle();

      expect(c.selectedTemplateId, 'senpai', reason: '点击卡片 → selectTemplate(id)');
      expect(c.name, '知性学姐');
      expect(c.tags, ['校园', '温柔', '学姐', '文学']);

      // 下一步进入③，再上一步回② → 选中态保持（controller 承载）。
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(c.step, 3);
      await tester.tap(find.byTooltip('上一步'));
      await tester.pumpAndSettle();
      expect(c.step, 2);
      expect(c.selectedTemplateId, 'senpai', reason: '重新进入步骤②保持选中态');
      expect(c.name, '知性学姐');
    });
  });

  group('步骤② import 占位（验收 2）', () {
    testWidgets('多行 textarea + AI 解析按钮 disabled + M4 文案逐字',
        (tester) async {
      final c = WizardController(characterRepository: repository);
      await enterStep2(tester, c, mode: WizardCreationMode.import);

      final textarea = tester.widget<TextField>(find.byType(TextField));
      expect(textarea.maxLines, greaterThan(1), reason: '多行 textarea');
      expect(textarea.decoration?.hintText, contains('粘贴角色设定文档'),
          reason: '占位文案含「粘贴角色设定文档」语义');

      final parseBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'AI 智能解析'),
      );
      expect(parseBtn.onPressed, isNull, reason: '解析按钮 disabled');

      expect(find.text('文档 AI 解析随 M4 交付'), findsOneWidget,
          reason: 'M4 文案逐字');
    });

    testWidgets('text 输入不触发任何解析调用（no-op）', (tester) async {
      final c = WizardController(characterRepository: repository);
      await enterStep2(tester, c, mode: WizardCreationMode.import);

      await tester.enterText(
          find.byType(TextField), '把这段角色设定文档粘贴进来……');
      await tester.pump();

      expect(c.step, 2, reason: '输入不跳步');
      expect(c.error, isNull, reason: '输入不产生解析错误');
      final parseBtn = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'AI 智能解析'),
      );
      expect(parseBtn.onPressed, isNull, reason: '输入后按钮仍 disabled');
    });
  });

  group('步骤②校验（验收 3）', () {
    testWidgets('template 未选下一步 → 「请选择一个模板」拦截', (tester) async {
      final c = WizardController(characterRepository: repository);
      await enterStep2(tester, c, mode: WizardCreationMode.template);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('请选择一个模板'), findsOneWidget,
          reason: 'template 未选拦截文案');
      expect(c.step, 2, reason: '拦截不前进');
    });

    testWidgets('template 已选 → 下一步放行到③', (tester) async {
      final c = WizardController(characterRepository: repository);
      await enterStep2(tester, c, mode: WizardCreationMode.template);
      await tester.tap(find.text('神秘旅人'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(c.step, 3);
      expect(c.selectedTemplateId, 'wanderer');
    });

    testWidgets('import 模式下一步放行（不受内容影响）', (tester) async {
      final c = WizardController(characterRepository: repository);
      await enterStep2(tester, c, mode: WizardCreationMode.import);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(c.step, 3, reason: 'import 空内容放行');

      // 带内容同样放行。
      final c2 = WizardController(characterRepository: repository);
      await enterStep2(tester, c2, mode: WizardCreationMode.import);
      await tester.enterText(find.byType(TextField), '有内容的设定文档');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(c2.step, 3, reason: 'import 有内容放行');
    });
  });

  group('模板应用端到端（验收 4/5）', () {
    testWidgets('选模板 → 步骤③/④/⑤ 回显已填字段', (tester) async {
      final c = WizardController(characterRepository: repository);
      await enterStep2(tester, c, mode: WizardCreationMode.template);
      await tester.tap(find.text('神秘旅人'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('神秘旅人'), findsOneWidget, reason: '③名称回显');
      expect(find.text('游历四方的神秘旅者，见多识广'), findsOneWidget,
          reason: '③描述回显');
      expect(find.text('奇幻, 神秘, 旅行, 冒险'), findsOneWidget, reason: '③标签回显');

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.textContaining('{{char}}'), findsWidgets, reason: '④人格/场景回显');

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.textContaining('要听听我刚才在路上遇到的事吗'), findsOneWidget,
          reason: '⑤开场白回显');
    });

    testWidgets('手动编辑不被模板回填覆盖', (tester) async {
      final c = WizardController(characterRepository: repository);
      await enterStep2(tester, c, mode: WizardCreationMode.template);
      await tester.tap(find.text('知性学姐'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, '角色名称'), '自定义学姐');

      // 回步骤②重选同一模板 → 手动编辑的 name 不被覆盖。
      await tester.tap(find.byTooltip('上一步'));
      await tester.pumpAndSettle();
      expect(c.step, 2);
      await tester.tap(find.text('知性学姐'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('自定义学姐'), findsOneWidget,
          reason: '手动编辑优先，模板不回填覆盖');
      expect(c.name, '自定义学姐');
      expect(c.description, '温柔体贴、学识渊博的学姐',
          reason: '未手动编辑字段仍按模板填充');
    });

    testWidgets('手动路径回归：manual 直接跳③，步骤②不出现', (tester) async {
      final c = WizardController(characterRepository: repository);
      await pumpWizard(tester, c);

      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();

      expect(c.step, 3, reason: 'manual 直接跳③');
      expect(find.text('知性学姐'), findsNothing, reason: '步骤②模板网格不出现');
      expect(find.text('AI 智能解析'), findsNothing, reason: '步骤② import 不出现');
    });
  });

  group('template → 保存端到端（验收 6）', () {
    testWidgets('选模板保存 → 落库字段与模板一致（creator 空串）→ 列表可见',
        (tester) async {
      // 5 模板网格在 600px 表面下有卡片滚出视口，放大表面避免滚动/命中问题。
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final env = await _CharsEnv.create();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            // 入口经 context.read<CharacterRepository>() 构造 WizardController。
            Provider<CharacterRepository>.value(
              value: env.characterRepository,
            ),
          ],
          child: MaterialApp(
            theme: ConverTheme.dark(),
            home: Scaffold(body: CharactersView(controller: env.controller)),
          ),
        ),
      );
      for (var i = 0; i < 100 && env.controller.loading; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump();

      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();

      // 从模板开始 → 选「活力猫娘」→ 下一步走完向导（②→③→④→⑤→⑥）。
      await tester.tap(find.text('从模板开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('活力猫娘'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存角色'));
      await tester.pumpAndSettle();

      // DB 断言：字段与模板数据一致，creator 空串。
      final rows = await env.characterRepository.listCharacters();
      expect(rows, hasLength(1), reason: '恰好保存一个角色');
      final char = rows.single.character;
      final nekomimi =
          characterTemplates.firstWhere((t) => t.id == 'nekomimi');
      expect(char.name, nekomimi.name);
      expect(char.description, nekomimi.description);
      expect(char.personality, nekomimi.personality);
      expect(char.scenario, nekomimi.scenario);
      expect(char.firstMes, nekomimi.firstMes);
      expect(char.tags, nekomimi.tags);
      expect(char.creator, '', reason: 'creator 恒空');

      // 列表可见（保存后 pop 回角色页，名单含新角色）。
      await tester.pumpAndSettle();
      expect(find.text('新建角色'), findsOneWidget, reason: '保存后回角色页');
      expect(
        env.controller.characters.map((r) => r.character.name),
        contains('活力猫娘'),
        reason: '模板建角色后列表可见',
      );
      await env.close();
    });
  });
}