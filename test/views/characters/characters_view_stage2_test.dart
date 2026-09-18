/// PS2-10 角色卡关系进度 + 升级确认闸门 UI（widget 行为契约）。
///
/// 验收语义（工单 PS2-10 验收 1–9 + Falsify）：
/// - 关系区：角色卡显示五段中文 label（陌生/相识/熟悉/亲密/挚爱，UI 层映射
///   全覆盖）+ affinity 进度条（0-100）；无状态行角色不渲染关系区（判定⑧
///   零噪音）；
/// - 升级提议：`StageUpgradeBroker.publish`（proposal 带 characterId）→ 目标
///   角色卡出现「升级建议：X」+ 确认/拒绝操作；确认 →
///   `RelationshipService.confirmStageUpgrade` 落库 + UI 刷新 + broker 清除；
///   拒绝 → 不写库 + broker 清除 + 本会话同角色不再弹（UI 侧拒绝记录语义）；
/// - SR-10 / F1：确认闸门只经 RelationshipService（视图零直写
///   relationship_states）；F1 域校验拒绝（confirm 返回 false）→ UI 不崩、
///   刷新为现状；
/// - 批量删除带关系行角色 → FK CASCADE 清理关系行，UI 不特判不崩；
/// - 既有结构零回归：无 stage2 provider 装配（既有测试形态）不崩且无关系区；
///   关系区与四按钮/对话数徽标共存；多选态隐藏升级操作（防误触）。
///
/// 测试 seam：CharactersView 公开接口 + 装配图 provider（CompanionRepository /
/// RelationshipService / StageUpgradeBroker，沿 app.dart 装配单源）——视图
/// 经 context.read 消费；既有无 provider 用例验证降级兼容。
library;

import 'dart:async';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/companion_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/character_card.dart';
import 'package:conver_system_mobile/services/character_file_exchange.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/companion/relationship_service.dart';
import 'package:conver_system_mobile/services/companion/stage_upgrade_broker.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/shell_navigation.dart';
import 'package:conver_system_mobile/views/characters/characters_controller.dart';
import 'package:conver_system_mobile/views/characters/characters_view.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../helpers/chat_test_env.dart' show FakeSettingsReader;
import '../../helpers/fake_llm_provider.dart';
import '../../helpers/in_memory_secret_store.dart';
import '../../helpers/pump_until.dart';

/// seam fake（导出调用链记录，与 characters_view_test 同契约）。
class _FakeExchange implements CharacterFileExchange {
  @override
  Future<String> exportCharacter(Character character) async =>
      '已导出 ${character.name}.json（角色导出随后续批次交付）';

  @override
  Future<CharacterDraft?> importCharacter() async => null;
}

/// 可控确认闸门：先暴露“操作已开始”，再释放真实服务完成落库。
class _GateRelationshipService extends RelationshipService {
  _GateRelationshipService({
    required super.companionRepository,
    required super.conversationRepository,
    required super.messageRepository,
  });

  final Completer<void> _confirmStarted = Completer<void>();
  final Completer<void> _releaseConfirm = Completer<void>();

  /// 确认请求已进入服务层。
  Future<void> get confirmStarted => _confirmStarted.future;

  /// 释放被门闩住的确认请求。
  void releaseConfirm() => _releaseConfirm.complete();

  @override
  Future<bool> confirmStageUpgrade({
    required int characterId,
    required RelationshipStage targetStage,
  }) async {
    _confirmStarted.complete();
    await _releaseConfirm.future;
    return super.confirmStageUpgrade(
      characterId: characterId,
      targetStage: targetStage,
    );
  }
}

/// 本文件装配基座：内存 drift + 仓储全集 + RelationshipService +
/// StageUpgradeBroker + CharactersController。
class _Env {
  _Env({
    required this.db,
    required this.characterRepository,
    required this.companionRepository,
    required this.conversationRepository,
    required this.messageRepository,
    required this.chatController,
    required this.navigation,
    required this.exchange,
    required this.relationshipService,
    required this.broker,
    required this.controller,
  });

  final AppDatabase db;
  final CharacterRepository characterRepository;
  final CompanionRepository companionRepository;
  final ConversationRepository conversationRepository;
  final MessageRepository messageRepository;
  final ChatController chatController;
  final ShellNavigation navigation;
  final _FakeExchange exchange;
  final RelationshipService relationshipService;
  final StageUpgradeBroker broker;
  final CharactersController controller;

  static Future<_Env> create({
    RelationshipService Function({
      required CompanionRepository companionRepository,
      required ConversationRepository conversationRepository,
      required MessageRepository messageRepository,
    })? relationshipServiceFactory,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final characterRepository = CharacterRepository(db);
    final conversationRepository = ConversationRepository(
      db,
      const FakeSettingsReader(),
    );
    final messageRepository = MessageRepository(db);
    final companionRepository = CompanionRepository(db);
    final chatController = ChatController(
      chatService: ChatService(
        database: db,
        conversationRepository: conversationRepository,
        characterRepository: characterRepository,
        messageRepository: messageRepository,
        settingsRepository: SettingsRepository(
          database: db,
          secretStore: InMemorySecretStore(),
        ),
        providerFactory: FixedLLMProviderFactory(
          FakeLLMProvider(tokens: const ['ok']),
        ),
      ),
      conversationRepository: conversationRepository,
      characterRepository: characterRepository,
      messageRepository: messageRepository,
    );
    final navigation = ShellNavigation();
    final exchange = _FakeExchange();
    final resolvedRelationshipService = relationshipServiceFactory?.call(
          companionRepository: companionRepository,
          conversationRepository: conversationRepository,
          messageRepository: messageRepository,
        ) ??
        RelationshipService(
          companionRepository: companionRepository,
          conversationRepository: conversationRepository,
          messageRepository: messageRepository,
        );
    final broker = StageUpgradeBroker();
    return _Env(
      db: db,
      characterRepository: characterRepository,
      companionRepository: companionRepository,
      conversationRepository: conversationRepository,
      messageRepository: messageRepository,
      chatController: chatController,
      navigation: navigation,
      exchange: exchange,
      relationshipService: resolvedRelationshipService,
      broker: broker,
      controller: CharactersController(
        characterRepository: characterRepository,
        fileExchange: exchange,
        navigation: navigation,
        chatController: chatController,
      ),
    );
  }

  Future<Character> seedCharacter(
    String name, {
    String description = '',
    String firstMes = '',
  }) {
    return characterRepository.createCharacter(
      CharactersCompanion(
        name: Value(name),
        description: Value(description),
        personality: Value(''),
        firstMes: Value(firstMes),
        tags: const Value([]),
        temperature: const Value(0.7),
      ),
    );
  }

  /// 直接写 relationship_states 行（测试铺数据；UI 路径禁止直写——SR-10）。
  Future<void> seedRelationship(
    int characterId,
    RelationshipStage stage,
    int affinity,
  ) {
    return companionRepository.upsertRelationship(
      characterId: characterId,
      stage: stage,
      affinity: affinity,
    );
  }

  Future<Conversation> seedConversation(int characterId) =>
      conversationRepository.createConversation(characterId: characterId);

  Future<void> close() => db.close();
}

void main() {

  /// 带 stage2 装配图（provider 形状对齐 app.dart）pump CharactersView。
  ///
  /// 视口放大：关系区使卡片变高，ListView.builder 懒渲染下后置卡片（如五段
  /// 用例的「亲密/挚爱」）可能落在默认 800×600 视口外未构建——统一放大
  /// 避免误判渲染缺失。
  Future<void> pumpStage2(WidgetTester tester, _Env env) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CompanionRepository>.value(value: env.companionRepository),
          Provider<RelationshipService>.value(value: env.relationshipService),
          ChangeNotifierProvider<StageUpgradeBroker>.value(value: env.broker),
        ],
        child: MaterialApp(
          theme: ConverTheme.dark(),
          home: Scaffold(body: CharactersView(controller: env.controller)),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => !env.controller.loading,
      why: '角色列表加载未在轮询窗口内完成',
    );
    await tester.pump();
  }

  /// 构造目标角色升级提议（characterId 恒必填——UI 定位角色卡 / 确认闸门）。
  StageUpgradeProposal proposalFor(
    int characterId,
    RelationshipStage current,
    RelationshipStage target,
    int affinity,
  ) => StageUpgradeProposal(
    characterId: characterId,
    currentStage: current,
    targetStage: target,
    affinity: affinity,
  );

  group('关系区 · 五段中文 label + affinity 进度条（验收 1）', () {
    testWidgets('五段全覆盖：陌生/相识/熟悉/亲密/挚爱各一，进度条 0-100 映射', (tester) async {
      final env = await _Env.create();
      final stages = [
        (name: '甲', stage: RelationshipStage.stranger, affinity: 0),
        (name: '乙', stage: RelationshipStage.acquainted, affinity: 20),
        (name: '丙', stage: RelationshipStage.familiar, affinity: 50),
        (name: '丁', stage: RelationshipStage.intimate, affinity: 70),
        (name: '戊', stage: RelationshipStage.soulmate, affinity: 95),
      ];
      for (final entry in stages) {
        final character = await env.seedCharacter(entry.name);
        await env.seedRelationship(character.id, entry.stage, entry.affinity);
      }

      await pumpStage2(tester, env);

      expect(find.text('陌生'), findsOneWidget);
      expect(find.text('相识'), findsOneWidget);
      expect(find.text('熟悉'), findsOneWidget);
      expect(find.text('亲密'), findsOneWidget);
      expect(find.text('挚爱'), findsOneWidget);
      final values = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((bar) => bar.value)
          .toSet();
      expect(values, {
        0.0,
        0.2,
        0.5,
        0.7,
        0.95,
      }, reason: '进度条 value = affinity / 100 映射');
      await env.close();
    });

    testWidgets('零噪音：无状态行角色不渲染关系区（判定⑧）', (tester) async {
      final env = await _Env.create();
      final withRow = await env.seedCharacter('有行');
      await env.seedCharacter('无行');
      await env.seedRelationship(withRow.id, RelationshipStage.familiar, 55);

      await pumpStage2(tester, env);

      expect(find.text('熟悉'), findsOneWidget, reason: '有行角色显示关系区');
      expect(
        find.byType(LinearProgressIndicator),
        findsNWidgets(1),
        reason: '仅一行 → 仅一条进度条',
      );
      expect(
        find.text('陌生'),
        findsNothing,
        reason: '无行角色不默认补 stranger 行展示（零噪音）',
      );
      await env.close();
    });
  });

  group('升级提议 · publish 驱动确认/拒绝（验收 3）', () {
    testWidgets('broker.publish → 目标角色卡出现「升级建议：亲密」+确认/拒绝；'
        '其他卡无（归属按 characterId）', (tester) async {
      final env = await _Env.create();
      final target = await env.seedCharacter('目标');
      await env.seedCharacter('旁观');
      await env.seedRelationship(target.id, RelationshipStage.familiar, 58);
      await env.seedRelationship(
        (await env.characterRepository.listCharacters())[1].character.id,
        RelationshipStage.familiar,
        60,
      );

      await pumpStage2(tester, env);
      env.broker.publish(
        proposalFor(
          target.id,
          RelationshipStage.familiar,
          RelationshipStage.intimate,
          61,
        ),
      );
      await tester.pump();

      expect(find.text('升级建议：亲密'), findsOneWidget);
      expect(find.text('确认'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
      expect(find.text('熟悉'), findsNWidgets(2), reason: '两卡关系 label 均在');
      await env.close();
    });

    testWidgets('多选态隐藏升级操作（防误触），关系 label 保留', (tester) async {
      final env = await _Env.create();
      final target = await env.seedCharacter('目标');
      await env.seedRelationship(target.id, RelationshipStage.familiar, 58);

      await pumpStage2(tester, env);
      env.broker.publish(
        proposalFor(
          target.id,
          RelationshipStage.familiar,
          RelationshipStage.intimate,
          61,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('目标'));
      await tester.pump();

      expect(find.text('确认'), findsNothing, reason: '多选态隐藏确认');
      expect(find.text('拒绝'), findsNothing, reason: '多选态隐藏拒绝');
      expect(find.text('熟悉'), findsOneWidget, reason: '被动 label 保留');
      await env.close();
    });
  });

  group('确认 · 落库 + UI 刷新 + broker 清除（验收 4）', () {
    testWidgets('点确认 → getRelationship.stage 变 targetStage + 卡片显示亲密 + '
        'broker 提议清除', (tester) async {
      final env = await _Env.create();
      final target = await env.seedCharacter('目标');
      await env.seedRelationship(target.id, RelationshipStage.familiar, 58);

      await pumpStage2(tester, env);
      env.broker.publish(
        proposalFor(
          target.id,
          RelationshipStage.familiar,
          RelationshipStage.intimate,
          61,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('确认'));
      await pumpUntil(
        tester,
        () => env.broker.lastProposal == null &&
            find.text('确认').evaluate().isEmpty,
        why: '确认后提议未在轮询窗口内清除',
      );

      final state = await env.companionRepository.getRelationship(target.id);
      expect(state, isNotNull);
      expect(
        state!.stage,
        RelationshipStage.intimate,
        reason: '确认经服务层落库（SR-10：UI 不直写）',
      );
      // F-82 观察：confirm 重算 affinity = 58 + 回合增量(1) = 59，可能短期
      // 低于 intimate 档下界（下回合自愈）——UI 以落库值实时渲染不修正；
      // 断言只锁「不回退 + 单调推进」。
      expect(
        state.affinity,
        greaterThanOrEqualTo(58),
        reason: '确认重算 affinity 单调不后退（回合增量 ≥ 0）',
      );
      expect(find.text('亲密'), findsOneWidget, reason: 'UI 刷新为新阶段');
      expect(env.broker.lastProposal, isNull, reason: '确认后提议清除');
      expect(find.text('确认'), findsNothing);
      expect(find.text('升级建议'), findsNothing);
      await env.close();
    });

    testWidgets('提议文本已存在时，确认等待仍停在服务未完成态', (tester) async {
      final env = await _Env.create(
        relationshipServiceFactory: ({
          required companionRepository,
          required conversationRepository,
          required messageRepository,
        }) =>
            _GateRelationshipService(
          companionRepository: companionRepository,
          conversationRepository: conversationRepository,
          messageRepository: messageRepository,
        ),
      );
      final gate = env.relationshipService as _GateRelationshipService;
      final target = await env.seedCharacter('目标');
      await env.seedRelationship(target.id, RelationshipStage.familiar, 58);

      await pumpStage2(tester, env);
      env.broker.publish(
        proposalFor(
          target.id,
          RelationshipStage.familiar,
          RelationshipStage.intimate,
          61,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('确认'));
      await gate.confirmStarted;

      expect(
        env.broker.lastProposal,
        isNotNull,
        reason: '服务未完成前提议仍在（等待不得被目标阶段文本提前解除）',
      );
      expect(find.text('升级建议：亲密'), findsOneWidget);
      expect(find.text('确认'), findsOneWidget, reason: '确认中操作仍未收敛');

      gate.releaseConfirm();
      await pumpUntil(
        tester,
        () => env.broker.lastProposal == null &&
            find.text('确认').evaluate().isEmpty,
        why: '释放门闩后提议未在轮询窗口内清除',
      );

      final state = await env.companionRepository.getRelationship(target.id);
      expect(
        state!.stage,
        RelationshipStage.intimate,
        reason: '门闩释放后真实服务落库',
      );
      expect(find.text('确认'), findsNothing);
      expect(find.text('升级建议'), findsNothing);
      await env.close();
    });
  });

  group('拒绝 · 不写库 + 提议清除 + 同角色本会话不重弹（验收 5）', () {
    testWidgets('点拒绝 → DB stage 不变 + broker 清除 + 重新 publish 同角色不弹', (
      tester,
    ) async {
      final env = await _Env.create();
      final target = await env.seedCharacter('目标');
      await env.seedRelationship(target.id, RelationshipStage.familiar, 58);

      await pumpStage2(tester, env);
      env.broker.publish(
        proposalFor(
          target.id,
          RelationshipStage.familiar,
          RelationshipStage.intimate,
          61,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('拒绝'));
      await pumpUntil(
        tester,
        () => env.broker.lastProposal == null &&
            find.text('确认').evaluate().isEmpty,
        why: '拒绝后提议未在轮询窗口内清除',
      );

      final state = await env.companionRepository.getRelationship(target.id);
      expect(state!.stage, RelationshipStage.familiar, reason: '拒绝不写库');
      expect(env.broker.lastProposal, isNull, reason: '拒绝后提议清除');
      expect(find.text('确认'), findsNothing);
      expect(find.text('升级建议'), findsNothing);

      // 同角色再次 publish → 本会话不再弹（UI 侧拒绝记录语义）。
      env.broker.publish(
        proposalFor(
          target.id,
          RelationshipStage.familiar,
          RelationshipStage.intimate,
          62,
        ),
      );
      await tester.pump();
      expect(find.text('确认'), findsNothing, reason: '本会话同角色不重弹');
      expect(find.text('升级建议'), findsNothing);
      await env.close();
    });
  });

  group('SR-10 / F1 · confirm 返回 false 时 UI 不崩（验收 6）', () {
    testWidgets('F1 域校验拒绝（targetStage 非合法后继）→ confirm false → '
        'UI 不崩 + broker 清除 + 刷新为现状', (tester) async {
      final env = await _Env.create();
      final target = await env.seedCharacter('目标');
      await env.seedRelationship(target.id, RelationshipStage.familiar, 58);

      await pumpStage2(tester, env);
      // 非法提议：familiar(index 2) → acquainted(index 1) 非 index+1 后继。
      env.broker.publish(
        proposalFor(
          target.id,
          RelationshipStage.familiar,
          RelationshipStage.acquainted,
          61,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('确认'));
      await pumpUntil(
        tester,
        () => env.broker.lastProposal == null &&
            find.text('确认').evaluate().isEmpty,
        why: '无效确认后提议未在轮询窗口内清除',
      );

      expect(tester.takeException(), isNull, reason: 'confirm false 不崩');
      final state = await env.companionRepository.getRelationship(target.id);
      expect(state!.stage, RelationshipStage.familiar, reason: 'F1 拒绝：DB 保持现状');
      expect(env.broker.lastProposal, isNull, reason: 'false 后提议清除');
      expect(find.text('熟悉'), findsOneWidget, reason: 'UI 刷新为现状');
      expect(find.text('确认'), findsNothing);
      await env.close();
    });
  });

  group('批量删除 · 关系行 FK CASCADE（Falsify）', () {
    testWidgets('删除带关系行角色 → 关系行随级联消失，UI 不特判不崩', (tester) async {
      final env = await _Env.create();
      final doomed = await env.seedCharacter('删除我');
      await env.seedCharacter('留我');
      await env.seedRelationship(doomed.id, RelationshipStage.familiar, 58);
      await env.seedConversation(doomed.id);

      await pumpStage2(tester, env);
      // 两卡均有「删除」tooltip——锚定目标卡（最近 GestureDetector = 卡片根）
      // 内的删除按钮，避免歧义。
      final doomedCard = find
          .ancestor(
            of: find.text('删除我'),
            matching: find.byType(GestureDetector),
          )
          .first;
      await tester.tap(
        find.descendant(of: doomedCard, matching: find.byTooltip('删除')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await pumpUntil(
        tester,
        () => env.controller.characters.length == 1,
        why: '删除后列表刷新',
      );

      expect(
        await env.companionRepository.getRelationship(doomed.id),
        isNull,
        reason: '关系行随角色 FK CASCADE 清理（无 UI 特判代码）',
      );
      expect(tester.takeException(), isNull, reason: '关系 map 残留不含崩溃');
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: '无关系行可显示的后删除态零噪音',
      );
      await env.close();
    });
  });

  group('既有结构零回归（验收 9）', () {
    testWidgets('关系区与四按钮/对话数徽标共存', (tester) async {
      final env = await _Env.create();
      final target = await env.seedCharacter('共存', firstMes: '你好。');
      await env.seedRelationship(target.id, RelationshipStage.acquainted, 25);
      await env.seedConversation(target.id);

      await pumpStage2(tester, env);

      expect(find.text('相识'), findsOneWidget);
      expect(find.text('开始对话'), findsOneWidget);
      expect(find.byTooltip('记忆'), findsOneWidget);
      expect(find.byTooltip('编辑'), findsOneWidget);
      expect(find.byTooltip('导出'), findsOneWidget);
      expect(find.byTooltip('删除'), findsOneWidget);
      expect(find.text('1 对话'), findsOneWidget);
      await env.close();
    });

    testWidgets('无 stage2 provider 装配（既有测试形态）→ 不崩、角色正常、'
        '无关系区', (tester) async {
      final env = await _Env.create();
      await env.seedCharacter('旧形态', firstMes: '开场。');
      await env.seedRelationship(
        (await env.characterRepository.listCharacters()).single.character.id,
        RelationshipStage.familiar,
        55,
      );

      // 与 characters_view_test.dart 同形：无 MultiProvider 包裹。
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: Scaffold(body: CharactersView(controller: env.controller)),
        ),
      );
      await pumpUntil(
        tester,
        () => !env.controller.loading,
        why: '角色列表加载未在轮询窗口内完成',
      );
      await tester.pump();

      expect(find.text('旧形态'), findsOneWidget);
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: 'provider 缺位降级：不渲染关系区（既有测试零回归）',
      );
      expect(tester.takeException(), isNull);
      await env.close();
    });
  });
}
