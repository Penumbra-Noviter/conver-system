/// CharactersView 导入/导出端到端（M3-03，fake seam 驱动）。
///
/// 验收语义（工单 03 验收 8）：
/// - 导入：点头部「导入角色卡」→ fake seam 返回 draft → 新角色入库并出现
///   在列表（notice「已导入角色「...」」）；取消（null）→ 零副作用；
/// - 导入错误分级（验收 2）：格式错（[CardFormatException]）→ notice 含
///   「无法识别的角色卡格式」等引导；校验错（[CardValidationException]）→
///   notice 纯原因「角色名称不能为空」——均为非阻塞提示条；
/// - 导出：点卡片「导出」→ fake seam 收到该角色（调用链断言），notice 展示
///   返回文案。
///
/// 测试 seam：注入内存 fake [CharacterFileExchange]，永不触真平台通道
/// （真通道行为归模拟器冒烟，services 层 seam 测试已覆盖 fake 注入）。
library;

import 'dart:async';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/character_card.dart';
import 'package:conver_system_mobile/services/character_file_exchange.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/shell_navigation.dart';
import 'package:conver_system_mobile/views/characters/characters_controller.dart';
import 'package:conver_system_mobile/views/characters/characters_view.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_llm_provider.dart';
import '../../helpers/in_memory_secret_store.dart';

/// [SettingsReader] 的内存假实现（与 characters 系测试同形）。
class _FakeSettingsReader implements SettingsReader {
  const _FakeSettingsReader();

  @override
  Future<String> get defaultProvider async => '';

  @override
  Future<String> get defaultModel async => '';

  @override
  Future<String> get userName async => '';
}

/// 可配置的 seam fake：控制 import 返回 / 抛出，记录 export 调用链。
/// 未显式配置时 import 默认返回 null（取消），永不触真平台通道。
class _ConfigurableExchange implements CharacterFileExchange {
  CharacterDraft? importResult;
  Object? importError;
  final List<Character> exported = <Character>[];

  @override
  Future<CharacterDraft?> importCharacter() async {
    if (importError != null) {
      throw importError!;
    }
    return importResult;
  }

  @override
  Future<String> exportCharacter(Character character) async {
    exported.add(character);
    return '已导出 ${character.name}.json（分享面板已打开）';
  }
}

/// exportCharacter 必抛的 seam fake——命中「导出失败 → notice 兜底」路径。
class _ThrowingExportExchange implements CharacterFileExchange {
  @override
  Future<CharacterDraft?> importCharacter() async => null;

  @override
  Future<String> exportCharacter(Character character) {
    throw StateError('share failed');
  }
}

/// import 挂起（永不完成）的 seam fake——命中控制器 `.timeout(3s)` 双层防御
/// 降级路径（平台通道挂起不抛错场景）。
class _HangingImportExchange implements CharacterFileExchange {
  @override
  Future<CharacterDraft?> importCharacter() => Completer<CharacterDraft?>().future;

  @override
  Future<String> exportCharacter(Character character) async {
    return '导出占位';
  }
}

/// 本文件的装配基座（与 characters_view_test._CharsEnv 同形）。
class _Env {
  _Env({
    required this.db,
    required this.repository,
    required this.controller,
    required this.exchange,
    required this.chatController,
  });

  final AppDatabase db;
  final CharacterRepository repository;
  final CharactersController controller;
  final _ConfigurableExchange exchange;
  final ChatController chatController;

  static Future<_Env> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    final repository = CharacterRepository(db);
    final conversationRepository = ConversationRepository(db, const _FakeSettingsReader());
    final messageRepository = MessageRepository(db);
    final chatController = ChatController(
      chatService: ChatService(
        database: db,
        conversationRepository: conversationRepository,
        characterRepository: repository,
        messageRepository: messageRepository,
        settingsRepository: SettingsRepository(
          database: db,
          secretStore: InMemorySecretStore(),
        ),
        providerFactory: FixedLLMProviderFactory(FakeLLMProvider(tokens: const ['ok'])),
      ),
      conversationRepository: conversationRepository,
      characterRepository: repository,
      messageRepository: messageRepository,
    );
    final exchange = _ConfigurableExchange();
    final controller = CharactersController(
      characterRepository: repository,
      fileExchange: exchange,
      navigation: ShellNavigation(),
      chatController: chatController,
    );
    return _Env(
      db: db,
      repository: repository,
      controller: controller,
      exchange: exchange,
      chatController: chatController,
    );
  }

  Future<void> close() => db.close();
}

/// 构造一个可供 fake seam 返回的 draft（字段全集）。
CharacterDraft _draft({
  String name = '导入角色',
  String personality = '导入人格',
  String firstMes = '你好。',
}) {
  return CharacterDraft(
    name: name,
    description: '导入描述',
    personality: personality,
    scenario: '导入场景',
    firstMes: firstMes,
    mesExample: '导入范例',
    systemPrompt: '导入系统提示',
    postHistoryInstructions: '导入后记',
    alternateGreetings: const ['备选'],
    tags: const ['导入标签'],
    creator: '导入作者',
    version: '1.5',
    creatorNotes: const {'note': '导入备注'},
    extensions: const {},
    avatar: null,
    temperature: 0.9,
  );
}

void main() {
  Future<void> pumpChars(
    WidgetTester tester,
    CharactersController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: CharactersView(controller: controller)),
      ),
    );
    for (var i = 0; i < 100 && controller.loading; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump();
  }

  group('导入角色卡（验收 8：fake seam 选文件 → 列表出现）', () {
    testWidgets('点「导入角色卡」→ 新角色入库并出现在列表 + 成功 notice',
        (tester) async {
      final env = await _Env.create();
      env.exchange.importResult = _draft(name: '导入我');
      await pumpChars(tester, env.controller);

      await tester.tap(find.byTooltip('导入角色卡'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(env.controller.characters.map((r) => r.character.name),
          ['导入我'], reason: '导入角色入库并出现在列表');
      expect(env.controller.characters.single.character.personality, '导入人格');
      expect(env.controller.characters.single.character.temperature, 0.9);
      expect(find.text('已导入角色「导入我」'), findsOneWidget);
      await env.close();
    });

    testWidgets('用户在系统选择器取消（seam 返回 null）→ 零副作用',
        (tester) async {
      final env = await _Env.create();
      env.exchange.importResult = null;
      await pumpChars(tester, env.controller);

      await tester.tap(find.byTooltip('导入角色卡'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(env.controller.characters, isEmpty, reason: '取消 → 无新角色');
      expect(env.controller.notice, isNull, reason: '取消 → 无提示');
      await env.close();
    });

    testWidgets('seam 挂起不抛错 → 控制器超时兜底「导入失败」（验收 7 双层防御）',
        (tester) async {
      final env = await _Env.create();
      final broken = CharactersController(
        characterRepository: env.repository,
        fileExchange: _HangingImportExchange(),
        navigation: ShellNavigation(),
        chatController: env.chatController,
      );
      try {
        await pumpChars(tester, broken);
        await tester.tap(find.byTooltip('导入角色卡'));
        // 控制器层 .timeout(3s) 兜底：推进假时钟越过 3s。
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(find.textContaining('导入角色失败'), findsOneWidget,
            reason: '挂起不抛错 → 控制器超时降级为 notice（不挂死）');
        expect(env.controller.characters, isEmpty, reason: '超时降级零落库');
      } finally {
        broken.dispose();
      }
      await env.close();
    });

    testWidgets('格式错 → 非阻塞提示含「无法识别的角色卡格式」引导，零落库',
        (tester) async {
      final env = await _Env.create();
      env.exchange.importError = const CardFormatException('无法识别的角色卡格式');
      await pumpChars(tester, env.controller);

      await tester.tap(find.byTooltip('导入角色卡'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('无法识别的角色卡格式'), findsOneWidget,
          reason: '格式错含格式引导');
      expect(env.controller.characters, isEmpty, reason: '格式错 → 零落库');
      await env.close();
    });

    testWidgets('校验错 → 非阻塞提示纯原因「角色名称不能为空」，零落库',
        (tester) async {
      final env = await _Env.create();
      env.exchange.importError = const CardValidationException('角色名称不能为空');
      await pumpChars(tester, env.controller);

      await tester.tap(find.byTooltip('导入角色卡'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('角色名称不能为空'), findsOneWidget,
          reason: '校验错纯原因（无格式引导）');
      expect(env.controller.characters, isEmpty);
      await env.close();
    });
  });

  group('导出角色卡（验收 8：fake seam 收到调用链）', () {
    testWidgets('点「导出」→ fake seam 收到该角色 + notice 返回文案',
        (tester) async {
      final env = await _Env.create();
      await env.repository.createCharacter(
        const CharactersCompanion(name: Value('导出我'), firstMes: Value('你好。')),
      );
      await pumpChars(tester, env.controller);

      await tester.tap(find.byTooltip('导出'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(env.exchange.exported.map((c) => c.name), ['导出我'],
          reason: '导出经 seam 调用');
      expect(find.text('已导出 导出我.json（分享面板已打开）'), findsOneWidget);
      await env.close();
    });

    testWidgets('seam 抛异常 → 非阻塞提示「导出失败」兜底', (tester) async {
      final env = await _Env.create();
      final throwing = _ThrowingExportExchange();
      final broken = CharactersController(
        characterRepository: env.repository,
        fileExchange: throwing,
        navigation: ShellNavigation(),
        chatController: env.chatController,
      );
      try {
        await env.repository.createCharacter(
          const CharactersCompanion(name: Value('导我'), firstMes: Value('你好。')),
        );
        await pumpChars(tester, broken);
        await tester.tap(find.byTooltip('导出'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump();
        expect(find.textContaining('导出失败'), findsOneWidget);
      } finally {
        broken.dispose();
      }
      await env.close();
    });
  });
}