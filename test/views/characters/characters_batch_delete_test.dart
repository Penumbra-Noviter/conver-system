/// CharactersController 多选批量删除 + CharactersView 长按多选交互契约
/// （M3-05 切片：长按进入 / 勾选切换 / 确认文案含选中数 / 批量级联 /
/// 退出零副作用 / 下拉刷新互斥）。
///
/// 测试 seam（公共接口边界，与既有 characters_controller_test /
/// characters_view_test 同形）：
/// - controller 层：[CharactersController] 多选公开 API（selectionMode /
///   selection / enterSelectionMode / exitSelectionMode / toggleSelection /
///   deleteSelected）+ 真实仓储（内存 drift）+ 真实 ChatController；
/// - widget 层：[CharactersView] 公开接口 + 同装配基座。
///
/// 级联断言复用仓储契约：批量删除后各角色对话与消息经 FK CASCADE 同空
/// （character_repository_test.dart:172 同源语义）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
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

/// 记录调用链 + 返回标注文案的 seam fake（同既有测试契约）。
class FakeCharacterFileExchange implements CharacterFileExchange {
  final List<Character> exported = <Character>[];

  @override
  Future<String> exportCharacter(Character character) async {
    exported.add(character);
    return '已导出 ${character.name}.json（角色导出随后续批次交付）';
  }

  @override
  Future<CharacterDraft?> importCharacter() async => null;
}

void main() {
  late AppDatabase db;
  late ConversationRepository convRepo;
  late MessageRepository messageRepo;
  late CharacterRepository charRepo;
  late ChatController chatController;
  late FakeCharacterFileExchange exchange;
  late CharactersController controller;

  var fakeNow = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
  void advanceSeconds(int seconds) {
    fakeNow = fakeNow.add(Duration(seconds: seconds));
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    convRepo = ConversationRepository(db, const FakeSettingsReader(),
        now: () => fakeNow);
    messageRepo = MessageRepository(db, now: () => fakeNow);
    charRepo = CharacterRepository(db, now: () => fakeNow);
    final service = ChatService(
      database: db,
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: messageRepo,
      settingsRepository:
          SettingsRepository(database: db, secretStore: InMemorySecretStore()),
      providerFactory:
          FixedLLMProviderFactory(FakeLLMProvider(tokens: const ['ok'])),
    );
    chatController = ChatController(
      chatService: service,
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: messageRepo,
    );
    exchange = FakeCharacterFileExchange();
    controller = CharactersController(
      characterRepository: charRepo,
      fileExchange: exchange,
      navigation: ShellNavigation(),
      chatController: chatController,
    );
  });

  tearDown(() async {
    controller.dispose();
    chatController.dispose();
    await db.close();
  });

  Future<Character> seedCharacter({String name = '艾莉亚', int secondsAgo = 0}) {
    advanceSeconds(secondsAgo);
    return charRepo.createCharacter(
      CharactersCompanion(name: Value(name)),
    );
  }

  Future<Conversation> seedConversation(int characterId) {
    return convRepo.createConversation(characterId: characterId);
  }

  Future<Message> seedMessage({
    required int conversationId,
    required Role role,
    required String content,
  }) {
    return messageRepo.createMessage(
      conversationId: conversationId,
      role: role,
      content: content,
    );
  }

  group('多选状态 · 长按进入 / 勾选切换 / 退出（验收 1/2）', () {
    test('初始非多选态；enterSelectionMode 进入且清空选中', () async {
      await seedCharacter(name: '甲');
      await controller.refresh();

      expect(controller.selectionMode, isFalse);
      expect(controller.selection, isEmpty);

      controller.enterSelectionMode();

      expect(controller.selectionMode, isTrue);
      expect(controller.selection, isEmpty, reason: '进入时选中集为空');
    });

    test('toggleSelection 勾选 / 取消切换（选中数实时反映）', () async {
      final a = await seedCharacter(name: '甲');
      final b = await seedCharacter(name: '乙', secondsAgo: 3);
      await controller.refresh();
      controller.enterSelectionMode();

      controller.toggleSelection(a.id);
      expect(controller.selection, {a.id});

      controller.toggleSelection(b.id);
      expect(controller.selection, {a.id, b.id}, reason: '追加勾选');

      controller.toggleSelection(a.id);
      expect(controller.selection, {b.id}, reason: '再点同一卡片取消勾选');
    });

    test('非多选态下 toggleSelection 零副作用', () async {
      final a = await seedCharacter(name: '甲');
      await controller.refresh();

      controller.toggleSelection(a.id);

      expect(controller.selectionMode, isFalse);
      expect(controller.selection, isEmpty);
    });

    test('exitSelectionMode 退出且清空选中（再次进入不残留）', () async {
      final a = await seedCharacter(name: '甲');
      await controller.refresh();
      controller.enterSelectionMode();
      controller.toggleSelection(a.id);
      expect(controller.selection, isNotEmpty);

      controller.exitSelectionMode();

      expect(controller.selectionMode, isFalse);
      expect(controller.selection, isEmpty, reason: '退出清空选中');
      controller.enterSelectionMode();
      expect(controller.selection, isEmpty, reason: '再次进入选中集干净');
    });
  });

  group('deleteSelected · 批量删除 + 级联（验收 3/4/5）', () {
    test('空选中调用 → 零副作用（不删除不提示不退出）', () async {
      await seedCharacter(name: '保留');
      await controller.refresh();
      controller.enterSelectionMode();

      await controller.deleteSelected();

      expect(controller.characters, hasLength(1), reason: '零删除');
      expect(controller.notice, isNull);
      expect(controller.selectionMode, isTrue, reason: '仍在多选态');
    });

    test('批量删除后各角色对话与消息从数据层消失，列表清空，退出多选',
        () async {
      final a = await seedCharacter(name: '甲');
      final b = await seedCharacter(name: '乙', secondsAgo: 3);
      final convA = await seedConversation(a.id);
      final convB = await seedConversation(b.id);
      await seedMessage(conversationId: convA.id, role: Role.user, content: 'a1');
      await seedMessage(conversationId: convB.id, role: Role.user, content: 'b1');
      await controller.refresh();
      controller.enterSelectionMode();
      controller.toggleSelection(a.id);
      controller.toggleSelection(b.id);

      await controller.deleteSelected();

      expect(controller.characters, isEmpty, reason: '删除后列表即时刷新');
      expect(controller.selectionMode, isFalse, reason: '删除完成自动退出多选');
      expect(controller.selection, isEmpty);
      expect(await convRepo.listConversations(characterId: a.id), isEmpty,
          reason: '甲名下对话经 FK CASCADE 消失');
      expect(await convRepo.listConversations(characterId: b.id), isEmpty,
          reason: '乙名下对话经 FK CASCADE 消失');
      expect(await messageRepo.getMessages(convA.id), isEmpty,
          reason: '甲对话名下消息消失');
      expect(await messageRepo.getMessages(convB.id), isEmpty,
          reason: '乙对话名下消息消失');
    });

    test('部分选中：仅删除勾选角色，未选角色及其对话保留', () async {
      final a = await seedCharacter(name: '甲');
      final b = await seedCharacter(name: '乙', secondsAgo: 3);
      final c = await seedCharacter(name: '丙', secondsAgo: 6);
      await seedConversation(a.id);
      await seedConversation(c.id);
      await controller.refresh();
      controller.enterSelectionMode();
      controller.toggleSelection(a.id);
      controller.toggleSelection(b.id);

      await controller.deleteSelected();

      expect(controller.characters.map((r) => r.character.id), [c.id],
          reason: '未选角色保留');
      expect(controller.characters.single.conversationCount, 1,
          reason: '剩余角色 conversation_count 反映数据层实况（refresh 重算）');
      expect(await convRepo.listConversations(characterId: c.id), hasLength(1),
          reason: '未选角色的对话保留');
      expect(await convRepo.listConversations(characterId: a.id), isEmpty);
    });

    test('删除进行中防重入：_deleting 期间二次调用返回 0 零副作用', () async {
      final a = await seedCharacter(name: '甲');
      final b = await seedCharacter(name: '乙', secondsAgo: 3);
      await controller.refresh();
      controller.enterSelectionMode();
      controller.toggleSelection(a.id);
      controller.toggleSelection(b.id);
      expect(controller.deleting, isFalse);

      final first = controller.deleteSelected(); // 不 await，挂起于删除循环前。
      final reentrant = await controller.deleteSelected();

      expect(reentrant, 0, reason: '删除进行中二次调用防重入');
      expect(await first, 2, reason: '首次调用实际删除 2 个角色');
      expect(controller.characters, isEmpty);
      expect(controller.deleting, isFalse, reason: '删除完成复位');
    });

    test('批量删除当前打开会话所属角色 → 聊天回入口（backToEntry 语义）',
        () async {
      final a = await seedCharacter(name: '甲');
      final b = await seedCharacter(name: '乙', secondsAgo: 3);
      final convA = await seedConversation(a.id);
      await chatController.openConversation(convA.id);
      expect(chatController.isEntry, isFalse);
      await controller.refresh();
      controller.enterSelectionMode();
      controller.toggleSelection(a.id);
      controller.toggleSelection(b.id);

      await controller.deleteSelected();

      expect(chatController.isEntry, isTrue,
          reason: '打开的会话归属被删角色 → 删除后回聊天入口');
      expect(controller.characters, isEmpty);
    });
  });

  group('多选与刷新互斥（验收 5）', () {
    test('多选态下拉刷新（refresh）→ 自动退出多选不乱态', () async {
      final a = await seedCharacter(name: '甲');
      await controller.refresh();
      controller.enterSelectionMode();
      controller.toggleSelection(a.id);
      expect(controller.selectionMode, isTrue);

      await controller.refresh();

      expect(controller.selectionMode, isFalse, reason: '刷新完成退出多选');
      expect(controller.selection, isEmpty);
      expect(controller.characters, hasLength(1), reason: '列表数据不受影响');
    });
  });

  // =========================================================================
  // CharactersView 长按多选交互（验收 1/2/3/4/5 的 widget 面）。
  // 装配基座复用本文件 setUp 的 controller / 仓储，包一层 MaterialApp。
  // =========================================================================

  Future<void> pumpChars(WidgetTester tester) async {
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

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String why = '',
  }) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: why);
  }

  group('长按进入多选模式（验收 1）', () {
    testWidgets('长按任意卡片 → 勾选标记 + 批量操作栏 + 退出返回普通列表态',
        (tester) async {
      // 多字名：头像首字（'阿'）与全名（'阿甲'）不歧义。
      await seedCharacter(name: '阿甲');
      await seedCharacter(name: '阿乙');
      await controller.refresh();

      await pumpChars(tester);

      // 普通列表态：无批量操作栏 / 无勾选。
      expect(find.textContaining('已选'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);

      await tester.longPress(find.text('阿甲'));
      await tester.pump();

      expect(controller.selectionMode, isTrue, reason: '长按进入多选');
      expect(controller.selection, hasLength(1), reason: '长按的卡片默认勾选');
      expect(find.text('已选 1 个角色'), findsOneWidget, reason: '批量栏实时选中数');
      expect(find.byTooltip('批量删除'), findsOneWidget);
      expect(find.byTooltip('退出多选'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(2), reason: '每张卡片勾选标记');

      // 退出按钮返回普通列表态。
      await tester.tap(find.byTooltip('退出多选'));
      await tester.pump();

      expect(controller.selectionMode, isFalse, reason: '退出多选');
      expect(controller.selection, isEmpty);
      expect(find.textContaining('已选'), findsNothing, reason: '批量栏消失');
      expect(find.byType(Checkbox), findsNothing, reason: '勾选标记消失');
      expect(find.text('新建角色'), findsOneWidget, reason: '普通头部恢复');
    });
  });

  group('多选态 tap 切换选中 · 空选删除禁用（验收 2）', () {
    testWidgets('tap 切换勾选 / 取消，选中数实时更新；空选时批量删除禁用',
        (tester) async {
      await seedCharacter(name: '阿甲');
      await seedCharacter(name: '阿乙');
      await controller.refresh();

      await pumpChars(tester);
      await tester.longPress(find.text('阿甲'));
      await tester.pump();

      // 长按阿甲已选 1；tap 阿乙追加 → 已选 2。
      await tester.tap(find.text('阿乙'));
      await tester.pump();
      expect(controller.selection, hasLength(2));
      expect(find.text('已选 2 个角色'), findsOneWidget);

      // tap 阿甲取消 → 已选 1。
      await tester.tap(find.text('阿甲'));
      await tester.pump();
      expect(controller.selection, hasLength(1));
      expect(find.text('已选 1 个角色'), findsOneWidget);

      // 取消最后一张 → 空选，批量删除禁用。
      await tester.tap(find.text('阿乙'));
      await tester.pump();
      expect(controller.selection, isEmpty);
      expect(find.text('已选 0 个角色'), findsOneWidget);
      // 多选态下卡片四按钮已隐藏，批量删除按钮是唯一的 delete_outline。
      final deleteButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(deleteButton.onPressed, isNull, reason: '空选删除禁用');
    });

    testWidgets('点勾选框本身亦切换选中（勾选框 onChanged 直连 toggle）',
        (tester) async {
      await seedCharacter(name: '阿甲');
      await controller.refresh();

      await pumpChars(tester);
      await tester.longPress(find.text('阿甲'));
      await tester.pump();
      expect(controller.selection, hasLength(1), reason: '长按已选中');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(controller.selection, isEmpty, reason: '点勾选框取消选中');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(controller.selection, hasLength(1), reason: '再点勾选框重新选中');
    });
  });

  group('批量删除确认弹窗（验收 3）', () {
    testWidgets('确认文案含选中数与级联说明；取消零副作用', (tester) async {
      final a = await seedCharacter(name: '阿甲');
      await seedCharacter(name: '阿乙');
      await seedConversation(a.id);
      await controller.refresh();

      await pumpChars(tester);
      await tester.longPress(find.text('阿甲'));
      await tester.pump();
      await tester.tap(find.text('阿乙'));
      await tester.pump();
      expect(find.text('已选 2 个角色'), findsOneWidget);

      await tester.tap(find.byTooltip('批量删除'));
      await tester.pumpAndSettle();

      expect(find.textContaining('删除将移除 2 个角色'), findsOneWidget,
          reason: '确认文案含选中数');
      expect(find.textContaining('对话与消息'), findsOneWidget,
          reason: '级联说明：对话与消息一并删除');

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(controller.characters, hasLength(2), reason: '取消零副作用');
      expect(controller.selectionMode, isTrue, reason: '取消后仍在多选态');
    });
  });

  group('批量删除确认执行（验收 4）', () {
    testWidgets('确认后逐角色删除 + 级联跨库断言 + 列表刷新 + 自动退出多选',
        (tester) async {
      final a = await seedCharacter(name: '阿甲');
      final b = await seedCharacter(name: '阿乙');
      await seedCharacter(name: '阿丙');
      final convA = await seedConversation(a.id);
      final convB = await seedConversation(b.id);
      await messageRepo.createMessage(
        conversationId: convA.id,
        role: Role.user,
        content: '甲的消息',
      );
      await messageRepo.createMessage(
        conversationId: convB.id,
        role: Role.user,
        content: '乙的消息',
      );
      await controller.refresh();

      await pumpChars(tester);
      await tester.longPress(find.text('阿甲'));
      await tester.pump();
      await tester.tap(find.text('阿乙'));
      await tester.pump();
      await tester.tap(find.byTooltip('批量删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      await pumpUntil(
        tester,
        () => controller.characters.length == 1,
        why: '批量删除后列表刷新为剩余角色',
      );

      expect(controller.characters.map((r) => r.character.name), ['阿丙'],
          reason: '未选角色保留');
      expect(controller.selectionMode, isFalse, reason: '删除完成自动退出多选');
      expect(find.text('已选'), findsNothing, reason: '批量栏消失');
      expect(await convRepo.listConversations(characterId: a.id), isEmpty,
          reason: '级联：甲名下对话消失');
      expect(await convRepo.listConversations(characterId: b.id), isEmpty,
          reason: '级联：乙名下对话消失');
      expect(await messageRepo.getMessages(convA.id), isEmpty,
          reason: '级联：甲对话名下消息消失');
      expect(await messageRepo.getMessages(convB.id), isEmpty,
          reason: '级联：乙对话名下消息消失');
    });
  });

  group('多选态下拉刷新互斥（验收 5 widget 面）', () {
    testWidgets('多选态下拉刷新 → 自动退出多选不乱态', (tester) async {
      await seedCharacter(name: '阿甲');
      await controller.refresh();

      await pumpChars(tester);
      await tester.longPress(find.text('阿甲'));
      await tester.pump();
      expect(find.text('已选 1 个角色'), findsOneWidget);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(controller.selectionMode, isFalse, reason: '下拉刷新退出多选');
      expect(find.text('已选'), findsNothing);
      expect(find.text('阿甲'), findsOneWidget, reason: '列表数据不受影响');
    });
  });
}
