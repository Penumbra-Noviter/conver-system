/// CharacterWizardView widget 行为契约（工单 M3-02a 验收 2/3/6/7/8）。
///
/// 语义锚点（spec §Implementation Decisions 6 步向导 + 桌面
/// character-wizard.js renderStep / validateStep / handleSave）：
/// - 全屏 Scaffold + AppBar（返回 = 上一步）+ 步骤指示器；步骤①三卡片
///   （智能导入 / 从模板开始 / 手动创建），手动直接跳步骤③；
/// - 步骤②占位页（文案含「随 M3-02b 交付」语义）；
/// - 步骤③ name 必填 maxLength=100、description maxLength=200，校验门
///   文案「角色名称不能为空」/「请选择一种创建方式」；
/// - 步骤⑥四段摘要（基本信息 / 人格设定 / 对话风格 / 设置）+ 温度滑块
///   0–2 / 默认 0.7 / 两位小数显示；空字段显示「未填写」；
/// - 保存落库（creator 恒空）→ 成功 pop；入口 = 角色页「新建角色」push
///   向导（经 context.read 读取 `CharacterRepository` 构造 WizardController），
///   保存返回后列表刷新可见新角色。
///
/// 测试 seam（公共接口边界）：[CharacterWizardView] 公开接口 +
/// [WizardController] + 真实仓储（内存 drift）。装配基座内联于本文件。
library;

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

/// [SettingsReader] 的内存假实现（与 chat 系测试同形）。
class FakeSettingsReader implements SettingsReader {
  const FakeSettingsReader([this.values = const {}]);

  final Map<String, String> values;

  @override
  Future<String> get defaultProvider async => values['default_provider'] ?? '';

  @override
  Future<String> get defaultModel async => values['default_model'] ?? '';

  @override
  Future<String> get userName async => values['user_name'] ?? '';
}

/// 本文件的装配基座：内存 drift + 角色仓储（向导保存落库用）。
class _WizEnv {
  _WizEnv({required this.db, required this.characterRepository});

  final AppDatabase db;
  final CharacterRepository characterRepository;

  static Future<_WizEnv> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    return _WizEnv(db: db, characterRepository: CharacterRepository(db));
  }

  Future<void> close() => db.close();
}

/// 全装配（角色页入口测试用）：内存 drift + 四仓储 + CharactersController。
/// 同时暴露 characterRepository 供 `Provider<CharacterRepository>` 注入
/// （characters_view 入口经 context.read 构造 WizardController）。
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
        ConversationRepository(db, const FakeSettingsReader());
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

  /// 从步骤①走手动路径到步骤⑥。
  Future<void> walkToStep6(
    WidgetTester tester,
    WizardController controller, {
    String name = '向导角色',
  }) async {
    await tester.tap(find.text('手动创建'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '角色名称'), name);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle(); // ③→④
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle(); // ④→⑤
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle(); // ⑤→⑥
  }

  group('步骤渲染 · ①②③ + 手动跳步（验收 2/3）', () {
    testWidgets('步骤①三卡片 + 步骤指示器渲染', (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await pumpWizard(tester, c);

      expect(find.text('智能导入'), findsOneWidget);
      expect(find.text('从模板开始'), findsOneWidget);
      expect(find.text('手动创建'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget,
          reason: '步骤指示器（进度条）渲染');
      await env.close();
    });

    testWidgets('手动创建选中直接跳步骤③（基本信息表单出现）', (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await pumpWizard(tester, c);
      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();

      expect(find.text('基本信息'), findsOneWidget);
      expect(find.widgetWithText(TextField, '角色名称'), findsOneWidget);
      expect(c.step, 3);
      await env.close();
    });

    testWidgets('智能导入进入步骤②占位页（文案含「随 M3-02b 交付」）',
        (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await pumpWizard(tester, c);
      await tester.tap(find.text('智能导入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.textContaining('随 M3-02b 交付'), findsOneWidget,
          reason: '步骤②占位文案（M3-02b 交付语义）');
      expect(c.step, 2);
      await env.close();
    });
  });

  group('校验门 · 步骤①/③（验收 2/3）', () {
    testWidgets('步骤①未选方式点下一步 → 「请选择一种创建方式」', (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await pumpWizard(tester, c);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('请选择一种创建方式'), findsOneWidget);
      expect(c.step, 1);
      await env.close();
    });

    testWidgets('步骤③ name 空点下一步 → 「角色名称不能为空」', (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await pumpWizard(tester, c);
      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('角色名称不能为空'), findsOneWidget);
      expect(c.step, 3);
      await env.close();
    });

    testWidgets('步骤③ name maxLength=100、description maxLength=200',
        (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await pumpWizard(tester, c);
      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();

      final nameField =
          tester.widget<TextField>(find.widgetWithText(TextField, '角色名称'));
      final descField = tester
          .widget<TextField>(find.widgetWithText(TextField, '简短描述'));
      expect(nameField.maxLength, 100);
      expect(descField.maxLength, 200);
      await env.close();
    });
  });

  group('导航 · AppBar 返回 = 上一步 / 取消（验收 1）', () {
    testWidgets('step>1 点 AppBar 返回 → 上一步（manual 3→1 跳过②）',
        (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);
      c.selectMode(WizardCreationMode.manual);
      expect(c.step, 3);

      await pumpWizard(tester, c);

      await tester.tap(find.byTooltip('上一步'));
      await tester.pumpAndSettle();

      expect(c.step, 1, reason: 'AppBar 返回 = 上一步（manual 跳过②回①）');
      expect(find.text('手动创建'), findsOneWidget, reason: '回到步骤①三卡片');
      await env.close();
    });

    testWidgets('底部「上一步」按钮（step>1）→ 上一步', (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);
      c.selectMode(WizardCreationMode.manual);
      c.setName('名');
      c.next(); // ③→④
      expect(c.step, 4);

      await pumpWizard(tester, c);

      // 底部栏「上一步」OutlinedButton（AppBar leading 为 tooltip，不冲突）。
      await tester.tap(find.text('上一步'));
      await tester.pumpAndSettle();

      expect(c.step, 3, reason: '底部「上一步」= 上一步');
      await env.close();
    });

    testWidgets('step1 点 AppBar 返回 → 退出向导（零副作用）', (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CharacterWizardView(controller: c),
                    ),
                  ),
                  child: const Text('宿主'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('宿主'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('退出'));
      await tester.pumpAndSettle();

      expect(find.text('宿主'), findsOneWidget, reason: 'step1 返回 = 退出向导');
      expect(await env.characterRepository.listCharacters(), isEmpty,
          reason: '退出零副作用');
      await env.close();
    });

    testWidgets('点「取消」→ 退出向导且零副作用', (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CharacterWizardView(controller: c),
                    ),
                  ),
                  child: const Text('宿主'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('宿主'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, '角色名称'), '取消我');

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('宿主'), findsOneWidget, reason: '取消退出向导');
      expect(await env.characterRepository.listCharacters(), isEmpty,
          reason: '取消零副作用（不落库）');
      await env.close();
    });

    testWidgets('从模板开始卡片选中 → 步骤②占位（template 模式）',
        (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await pumpWizard(tester, c);
      await tester.tap(find.text('从模板开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(c.mode, WizardCreationMode.template);
      expect(c.step, 2);
      expect(find.textContaining('随 M3-02b 交付'), findsOneWidget);
      await env.close();
    });
  });

  group('步骤⑥ · 四段摘要 + 温度滑块（验收 6）', () {
    testWidgets('空字段显示「未填写」；四段摘要标题渲染；温度默认 0.70',
        (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await pumpWizard(tester, c);
      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '角色名称'), '名');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('基本信息'), findsOneWidget);
      expect(find.text('人格设定'), findsOneWidget);
      expect(find.text('对话风格'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('未填写'), findsWidgets, reason: '空字段显示「未填写」');
      expect(find.text('0.70'), findsOneWidget, reason: '温度默认 0.7 两位小数');
      expect(find.text('保存角色'), findsOneWidget);
      await env.close();
    });

    testWidgets('填写后摘要显示实际值（含标签）', (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await pumpWizard(tester, c);
      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, '角色名称'), '小狐狸');
      await tester.enterText(
          find.widgetWithText(TextField, '简短描述'), '森林里的小狐狸');
      await tester.enterText(
          find.widgetWithText(TextField, '标签'), '冒险, 可爱');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('小狐狸'), findsOneWidget, reason: '摘要显示名称');
      expect(find.text('森林里的小狐狸'), findsOneWidget);
      expect(find.text('#冒险'), findsOneWidget);
      expect(find.text('#可爱'), findsOneWidget);
      await env.close();
    });

    testWidgets('填写 systemPrompt → 摘要显示「系统提示」行', (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      await pumpWizard(tester, c);
      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, '角色名称'), '有提示');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, '自定义 System Prompt（可选）'),
          '自定义系统提示');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('系统提示'), findsOneWidget);
      expect(find.text('自定义系统提示'), findsOneWidget);
      await env.close();
    });
  });

  group('保存 · 落库 + 成功 pop（验收 7）', () {
    testWidgets('走完六步保存 → 角色入库（creator 恒空）→ 向导 pop',
        (tester) async {
      final env = await _WizEnv.create();
      final c = WizardController(characterRepository: env.characterRepository);

      // 宿主页 push 向导，便于断言保存后 pop 返回。
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CharacterWizardView(controller: c),
                    ),
                  ),
                  child: const Text('打开向导'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开向导'));
      await tester.pumpAndSettle();

      await walkToStep6(tester, c, name: '落库角色');
      expect(find.text('保存角色'), findsOneWidget);

      await tester.tap(find.text('保存角色'));
      await tester.pumpAndSettle();

      expect(c.saved, isTrue);
      final rows = await env.characterRepository.listCharacters();
      expect(rows, hasLength(1));
      expect(rows.single.character.name, '落库角色');
      expect(rows.single.character.creator, '', reason: 'creator 恒空');
      expect(find.text('打开向导'), findsOneWidget, reason: '保存成功后 pop 回宿主');
      await env.close();
    });
  });

  group('入口接线 · 角色页「新建角色」→ 向导（验收 8）', () {
    testWidgets('点「新建角色」push 向导；向导内创建角色 → 列表可见',
        (tester) async {
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
      // 等列表 initState 后帧刷新完成。
      for (var i = 0; i < 100 && env.controller.loading; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump();

      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();

      // 向导出现（步骤①）——M3-01 stub 已被真实导航替换。
      expect(find.text('智能导入'), findsOneWidget);
      expect(find.text('从模板开始'), findsOneWidget);
      expect(find.text('手动创建'), findsOneWidget);

      // 走手动路径创建角色（向导经 context.read 构造的 WizardController）。
      await tester.tap(find.text('手动创建'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, '角色名称'), '入口角色');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存角色'));
      await tester.pumpAndSettle();

      // 保存后 pop 回列表；列表 refresh 后可见新角色。
      expect(find.text('新建角色'), findsOneWidget, reason: '保存后 pop 回角色页');
      expect(
        env.controller.characters.map((r) => r.character.name),
        contains('入口角色'),
        reason: '向导建角色后列表可见（同一仓储落库）',
      );
      await env.close();
    });
  });
}
