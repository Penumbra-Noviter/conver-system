/// MemoryPalaceService 契约（WL-05）：shouldSummarize 阈值矩阵 / summarizeTurn
/// 严格 JSON 解析（非法降级不落库不抛）/ persistDrafts（keys 空跳过、同
/// keys+同 content 去重、固定 position/depth/source）/ 回合末编排（增量计数 +
/// S1 吞错）/ 验收 7 端到端（auto 条目落库后命中 keys 即注入且来源标 memory）。
library;

import 'dart:convert';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/lorebook_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/chat_service.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/lorebook/lorebook_engine.dart';
import 'package:conver_system_mobile/services/memory/memory_palace_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_env.dart' show FakeSettingsReader;
import '../../helpers/fake_llm_provider.dart';
import '../../helpers/in_memory_secret_store.dart';

/// 记录 generate temperature 的 LLM fake（记忆宫殿 seam 温度透传断言用；
/// 不修改共享 FakeLLMProvider，避免越出工单测试文件范围）。
class _TemperatureRecordingLLM extends LLMProvider {
  _TemperatureRecordingLLM({required this.reply})
      : super(apiKey: 'test-key');

  final String reply;

  double? lastTemperature;
  int generateCallCount = 0;
  String? lastModel;

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async {
    generateCallCount++;
    lastModel = model;
    lastTemperature = temperature;
    return reply;
  }

  @override
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
    double? topP,
    double? presencePenalty,
    double? frequencyPenalty,
  }) async* {
    yield reply;
  }
}

void main() {
  group('MemoryDraft 值语义（== / hashCode）', () {
    test('同字段值相等、异字段不等、hashCode 一致', () {
      const a = MemoryDraft(title: 'T', keys: ['k1', 'k2'], content: 'c');
      const b = MemoryDraft(title: 'T', keys: ['k1', 'k2'], content: 'c');
      const c = MemoryDraft(title: 'T', keys: ['k1', 'k3'], content: 'c');
      const d = MemoryDraft(title: 'T', keys: ['k1', 'k2'], content: '其他');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse, reason: 'keys 不同 → 不等');
      expect(a == d, isFalse, reason: 'content 不同 → 不等');
      expect(a == Object(), isFalse, reason: '非 MemoryDraft → 不等');
      expect(identical(a, MemoryDraft(title: 'T', keys: ['k1', 'k2'], content: 'c')), isFalse, reason: '非同一实例');
    });
  });

  group('shouldSummarize 阈值矩阵（验收 1：everyRounds + charThreshold 双条件 or）',
      () {
    test('轮数达标（消息数 >= everyRounds * 2）→ true（字符数不达标也归纳）', () {
      expect(
        shouldSummarize(12, 0, everyRounds: 6, charThreshold: 10000),
        isTrue,
        reason: '12 条消息 = 6 轮完整回合 ≥ everyRounds → 轮数达标',
      );
    });

    test('字符数达标（charCount >= charThreshold）→ true（轮数未达标也归纳）', () {
      expect(
        shouldSummarize(4, 10001, everyRounds: 6, charThreshold: 10000),
        isTrue,
        reason: '字符数超阈值即归纳（轮数未到也触发）',
      );
    });

    test('双条件均不达标 → false', () {
      expect(
        shouldSummarize(4, 500, everyRounds: 6, charThreshold: 10000),
        isFalse,
      );
    });

    test('everyRounds <= 0 → 每回合恒归纳', () {
      expect(
        shouldSummarize(0, 0, everyRounds: 0, charThreshold: 10000),
        isTrue,
      );
    });

    test('边界：恰好 everyRounds 轮 → true；差 1 条消息 → false', () {
      expect(
        shouldSummarize(12, 0, everyRounds: 6, charThreshold: 10000),
        isTrue,
      );
      expect(
        shouldSummarize(11, 0, everyRounds: 6, charThreshold: 10000),
        isFalse,
      );
    });
  });

  group('parseMemoryDraft 严格 JSON 解析（验收 2：非法降级不抛，复用 llmJsonCandidates）',
      () {
    test('直接 JSON 对象 → MemoryDraft 三字段', () {
      final draft = parseMemoryDraft(
        '{"title":"喜欢咖啡","keys":["咖啡","拿铁"],"content":"用户喜欢喝咖啡。"}',
      );
      expect(draft, isNotNull);
      expect(draft!.title, '喜欢咖啡');
      expect(draft.keys, ['咖啡', '拿铁']);
      expect(draft.content, '用户喜欢喝咖啡。');
    });

    test('```json 代码块包裹', () {
      final draft = parseMemoryDraft('```json\n{"title":"T","keys":["k"],"content":"c"}\n```');
      expect(draft, isNotNull);
      expect(draft!.title, 'T');
    });

    test('周围有解释文字 + 大括号范围段', () {
      final draft = parseMemoryDraft(
        '以下是归纳结果：{"title":"T","keys":["k1","k2"],"content":"c"} 共一条',
      );
      expect(draft, isNotNull);
      expect(draft!.keys, ['k1', 'k2']);
    });

    test('非法 JSON → null（不抛）', () {
      expect(parseMemoryDraft('这不是 JSON'), isNull);
      expect(parseMemoryDraft(''), isNull);
      expect(parseMemoryDraft('  '), isNull);
      expect(parseMemoryDraft('[1,2,3]'), isNull,
          reason: '合法 JSON 数组但非对象 → null');
      expect(parseMemoryDraft('"纯字符串"'), isNull);
    });

    test('缺字段 / 字段类型错 → null', () {
      expect(parseMemoryDraft('{"keys":["k"],"content":"c"}'), isNull,
          reason: '缺 title');
      expect(parseMemoryDraft('{"title":"T","content":"c"}'), isNull,
          reason: '缺 keys');
      expect(parseMemoryDraft('{"title":"T","keys":["k"]}'), isNull,
          reason: '缺 content');
      expect(parseMemoryDraft('{"title":1,"keys":["k"],"content":"c"}'), isNull,
          reason: 'title 非字符串');
      expect(parseMemoryDraft('{"title":"T","keys":"k","content":"c"}'), isNull,
          reason: 'keys 非数组');
      expect(parseMemoryDraft('{"title":"T","keys":[1],"content":"c"}'), isNull,
          reason: 'keys 元素非字符串');
      expect(parseMemoryDraft('{"title":"T","keys":["  "],"content":"c"}'), isNull,
          reason: 'keys 元素纯空白');
    });

    test('title 超 200 截断；keys trim', () {
      final draft = parseMemoryDraft(
        '{"title":"${'长' * 250}","keys":[" 咖啡 "],"content":"c"}',
      );
      expect(draft, isNotNull);
      expect(draft!.title.length, 200);
      expect(draft.keys, ['咖啡']);
    });
  });

  group('buildMemorySummarizeMessages', () {
    test('prompt 含 schema 字段名、角色名、对话行与防注入句', () {
      final messages = buildMemorySummarizeMessages(
        charName: '艾莉亚',
        dialogueLines: const ['用户：你好', '艾莉亚：你好呀'],
      );
      expect(messages, hasLength(1));
      final content = messages.single.content;
      expect(content, contains('title'));
      expect(content, contains('艾莉亚'));
      expect(content, contains('用户：你好'));
      expect(content, contains('艾莉亚：你好呀'));
      expect(content, contains('防提示注入'));
    });
  });

  group('extractMemoryDraftWithProvider', () {
    test('generate 输出经 parseMemoryDraft 解析并透传 model / temperature', () async {
      final llm = _TemperatureRecordingLLM(
        reply: '{"title":"T","keys":["k"],"content":"c"}',
      );
      final draft = await extractMemoryDraftWithProvider(
        llm: llm,
        model: 'claude-sonnet-5',
        charName: '艾莉亚',
        dialogueLines: const ['用户：你好'],
        temperature: 0.3,
      );
      expect(draft, isNotNull);
      expect(draft!.title, 'T');
      expect(llm.generateCallCount, 1);
      expect(llm.lastModel, 'claude-sonnet-5');
      expect(llm.lastTemperature, 0.3);
    });

    test('非法 JSON 输出 → null（不抛）', () async {
      final llm = FakeLLMProvider(tokens: ['这不是 JSON']);
      final draft = await extractMemoryDraftWithProvider(
        llm: llm,
        model: 'claude-sonnet-5',
        charName: '艾莉亚',
        dialogueLines: const ['用户：你好'],
        temperature: 0.3,
      );
      expect(draft, isNull);
    });
  });

  group('MemoryPalaceService', () {
    late AppDatabase db;
    late CharacterRepository characterRepo;
    late ConversationRepository conversationRepo;
    late MessageRepository messageRepo;
    late LorebookRepository lorebookRepo;
    late SettingsRepository settingsRepo;

    late int extractorCalls;
    late MemoryDraft? extractorResult;
    late String capturedCharName;
    late double capturedTemperature;
    late List<String> capturedDialogueLines;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      characterRepo = CharacterRepository(db);
      conversationRepo = ConversationRepository(db, const FakeSettingsReader());
      messageRepo = MessageRepository(db);
      lorebookRepo = LorebookRepository(db);
      settingsRepo = SettingsRepository(
        database: db,
        secretStore: InMemorySecretStore(),
      );
      // 开关读取约定 = 服务内部（summarizeAfterTurn 首行门）：缺省关闭，
      // 本组用例直接调服务需先开启（断言随读取位置迁移，语义不变）。
      await settingsRepo.setMany({
        SettingsRepository.memoryPalaceEnabledKey: 'true',
      });
      extractorCalls = 0;
      extractorResult = null;
      capturedCharName = '';
      capturedTemperature = 0;
      capturedDialogueLines = const [];
    });

    tearDown(() async {
      await db.close();
    });

    Future<({int characterId, int conversationId})> seedConversation({
      String name = '艾莉亚',
    }) async {
      final character = await characterRepo.createCharacter(
        CharactersCompanion.insert(
          name: name,
          firstMes: const Value(''),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final conv = await conversationRepo.createConversation(
        characterId: character.id,
      );
      return (characterId: character.id, conversationId: conv.id);
    }

    /// 交替落 user/assistant 消息（每轮 2 条）。
    Future<void> seedMessages(int conversationId, int rounds) async {
      for (var i = 0; i < rounds; i++) {
        await messageRepo.createMessage(
          conversationId: conversationId,
          role: Role.user,
          content: '用户消息 $i',
        );
        await messageRepo.createMessage(
          conversationId: conversationId,
          role: Role.assistant,
          content: '助手消息 $i',
        );
      }
    }

    MemoryPalaceService buildService({
      MemoryDraftExtractor? extractor,
      int charThreshold = 10000,
    }) {
      return MemoryPalaceService(
        characterRepository: characterRepo,
        messageRepository: messageRepo,
        lorebookRepository: lorebookRepo,
        settingsRepository: settingsRepo,
        extractor: extractor ??
            ({
              required String charName,
              required List<String> dialogueLines,
              required double temperature,
            }) async {
              extractorCalls++;
              capturedCharName = charName;
              capturedTemperature = temperature;
              capturedDialogueLines = dialogueLines;
              return extractorResult;
            },
        charThreshold: charThreshold,
      );
    }

    group('summarizeAfterTurn 编排（验收 4/6：每 N 轮触发 + S1 吞错）', () {
      test('未到阈值（3 轮 < everyRounds 6）→ 零调用零落库', () async {
        final seed = await seedConversation();
        await seedMessages(seed.conversationId, 3);
        final service = buildService();

        final added = await service.summarizeAfterTurn(
          characterId: seed.characterId,
          conversationId: seed.conversationId,
        );

        expect(added, 0);
        expect(extractorCalls, 0);
        expect(await lorebookRepo.listEntries(seed.characterId), isEmpty);
      });

      test('到阈值（6 轮 = 12 条消息）→ 归纳并落库 auto 条目', () async {
        final seed = await seedConversation();
        await seedMessages(seed.conversationId, 6);
        extractorResult = const MemoryDraft(
          title: '用户喜欢咖啡',
          keys: ['咖啡'],
          content: '用户喜欢喝咖啡。',
        );
        final service = buildService();

        final added = await service.summarizeAfterTurn(
          characterId: seed.characterId,
          conversationId: seed.conversationId,
        );

        expect(added, 1);
        expect(extractorCalls, 1);
        expect(capturedCharName, '艾莉亚');
        final entries = await lorebookRepo.listEntries(seed.characterId);
        expect(entries, hasLength(1));
        expect(entries.single.keys, ['咖啡']);
        expect(entries.single.content, '用户喜欢喝咖啡。');
      });

      test('字符数阈值达标（轮数未到也归纳）', () async {
        final seed = await seedConversation();
        await seedMessages(seed.conversationId, 2);
        extractorResult = const MemoryDraft(
          title: 'T',
          keys: ['k'],
          content: 'c',
        );
        // charThreshold=1 → 2 条消息内容即达标。
        final service = buildService(charThreshold: 1);

        final added = await service.summarizeAfterTurn(
          characterId: seed.characterId,
          conversationId: seed.conversationId,
        );

        expect(added, 1);
        expect(extractorCalls, 1);
      });

      test('增量计数：已有 auto 条目消耗已归纳轮次，未新增 2N 条不重复触发', () async {
        final seed = await seedConversation();
        await seedMessages(seed.conversationId, 6);
        extractorResult = const MemoryDraft(
          title: 'T',
          keys: ['k'],
          content: 'c',
        );
        final service = buildService();

        // 第一轮触发 → 1 条 auto 落库（消耗 1 轮 = 2 条消息）。
        expect(
          await service.summarizeAfterTurn(
            characterId: seed.characterId,
            conversationId: seed.conversationId,
          ),
          1,
        );

        // 消息数未变（仍 12 条），auto_count=1 → incremental=10 < 12 → 不触发。
        final again = await service.summarizeAfterTurn(
          characterId: seed.characterId,
          conversationId: seed.conversationId,
        );
        expect(again, 0);
        expect(extractorCalls, 1, reason: '增量计数下不应再次调用 extractor');
      });

      test('extractor 抛错 → 服务内吞错返回 0，不落库不向上抛（验收 4）', () async {
        final seed = await seedConversation();
        await seedMessages(seed.conversationId, 6);
        final service = buildService(
          extractor: ({
            required String charName,
            required List<String> dialogueLines,
            required double temperature,
          }) async {
            throw StateError('LLM boom（测试注入）');
          },
        );

        final added = await service.summarizeAfterTurn(
          characterId: seed.characterId,
          conversationId: seed.conversationId,
        );

        expect(added, 0);
        expect(await lorebookRepo.listEntries(seed.characterId), isEmpty);
      });

      test('extractor 返回 null（非法 JSON 降级）→ 0 不落库', () async {
        final seed = await seedConversation();
        await seedMessages(seed.conversationId, 6);
        extractorResult = null;
        final service = buildService();

        final added = await service.summarizeAfterTurn(
          characterId: seed.characterId,
          conversationId: seed.conversationId,
        );

        expect(added, 0);
        expect(await lorebookRepo.listEntries(seed.characterId), isEmpty);
      });

      test('角色不存在 / 对话无消息 → 0（防御性早退）', () async {
        final seed = await seedConversation();
        await seedMessages(seed.conversationId, 6);
        final service = buildService();

        expect(
          await service.summarizeAfterTurn(
            characterId: 99999,
            conversationId: seed.conversationId,
          ),
          0,
          reason: '角色不存在 → 早退 0',
        );

        final emptyConv = await conversationRepo.createConversation(
          characterId: seed.characterId,
        );
        expect(
          await service.summarizeAfterTurn(
            characterId: seed.characterId,
            conversationId: emptyConv.id,
          ),
          0,
          reason: '对话无消息 → 早退 0',
        );
      });

      test('温度沿用角色/全局链：角色显式温度优先；缺省回退全局（验收高不确定点 1）', () async {
        final seed = await seedConversation();
        await seedMessages(seed.conversationId, 6);
        extractorResult = const MemoryDraft(title: 'T', keys: ['k'], content: 'c');
        final service = buildService();

        // 全局缺省 0.7，角色 DB 缺省 0.7（== defaultTemperature → 回退全局 0.7）。
        expect(
          await service.summarizeAfterTurn(
            characterId: seed.characterId,
            conversationId: seed.conversationId,
          ),
          1,
        );
        expect(capturedTemperature, 0.7, reason: '角色温度 == 缺省 → 用全局 0.7');

        // 角色显式 1.5 → 优先角色温度。
        final hotCharacter = await characterRepo.createCharacter(
          CharactersCompanion.insert(
            name: '火热角色',
            temperature: const Value(1.5),
            firstMes: const Value(''),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        final hotConv = await conversationRepo.createConversation(
          characterId: hotCharacter.id,
        );
        await seedMessages(hotConv.id, 6);
        expect(
          await service.summarizeAfterTurn(
            characterId: hotCharacter.id,
            conversationId: hotConv.id,
          ),
          1,
        );
        expect(capturedTemperature, 1.5, reason: '角色显式温度优先');
      });
    });

    group('persistDrafts（验收 3：keys 空跳过 / 去重 / 固定字段）', () {
      test('keys 空 → 跳过不落库；返回 0', () async {
        final seed = await seedConversation();
        final service = buildService();

        final added = await service.persistDrafts(
          seed.characterId,
          const [MemoryDraft(title: '无键', keys: [], content: 'c')],
        );

        expect(added, 0);
        expect(await lorebookRepo.listEntries(seed.characterId), isEmpty);
      });

      test('产出固定字段：position=world / depth=20 / source=auto / 其余默认', () async {
        final seed = await seedConversation();
        final service = buildService();

        await service.persistDrafts(
          seed.characterId,
          const [MemoryDraft(title: 'T', keys: ['k'], content: 'c')],
        );

        final entries = await lorebookRepo.listEntries(seed.characterId);
        expect(entries, hasLength(1));
        final e = entries.single;
        expect(e.position, 'world');
        expect(e.depth, 20);
        expect(e.source, 'auto');
        expect(e.enabled, isTrue);
        expect(e.constant, isFalse);
        expect(e.order, 100);
        expect(e.matchMode, 'or');
      });

      test('去重：同 keys+同 content（含 keys 顺序不同）不重复入库', () async {
        final seed = await seedConversation();
        final service = buildService();

        final added1 = await service.persistDrafts(
          seed.characterId,
          const [MemoryDraft(title: 'T', keys: ['a', 'b'], content: 'c')],
        );
        final added2 = await service.persistDrafts(
          seed.characterId,
          const [MemoryDraft(title: 'T', keys: ['b', 'a'], content: 'c')],
        );

        expect(added1, 1);
        expect(added2, 0, reason: 'keys 顺序无关 + content 相同 → 去重');
        expect(await lorebookRepo.listEntries(seed.characterId), hasLength(1));
      });

      test('同 keys 不同 content / 不同 keys → 均落库', () async {
        final seed = await seedConversation();
        final service = buildService();

        final added = await service.persistDrafts(seed.characterId, const [
          MemoryDraft(title: 'T1', keys: ['a'], content: 'c1'),
          MemoryDraft(title: 'T2', keys: ['a'], content: 'c2'),
          MemoryDraft(title: 'T3', keys: ['b'], content: 'c1'),
        ]);

        expect(added, 3);
        expect(await lorebookRepo.listEntries(seed.characterId), hasLength(3));
      });

      test('空列表 / 全部重复 → 0', () async {
        final seed = await seedConversation();
        final service = buildService();
        await service.persistDrafts(
          seed.characterId,
          const [MemoryDraft(title: 'T', keys: ['a'], content: 'c')],
        );

        expect(
          await service.persistDrafts(seed.characterId, const []),
          0,
        );
        expect(
          await service.persistDrafts(
            seed.characterId,
            const [MemoryDraft(title: 'T', keys: ['a'], content: 'c')],
          ),
          0,
        );
      });

      test('title 超 200 → 落库截断（防列表路由 500）', () async {
        final seed = await seedConversation();
        final service = buildService();

        await service.persistDrafts(
          seed.characterId,
          [MemoryDraft(title: '长' * 250, keys: ['k'], content: 'c')],
        );

        final entries = await lorebookRepo.listEntries(seed.characterId);
        expect(entries.single.title.length, 200);
      });
    });

    test('消息数超归纳窗口（>20 条）→ sublist 截断分支照常归纳', () async {
      final seed = await seedConversation();
      await seedMessages(seed.conversationId, 11); // 22 条消息 > 20 窗口
      extractorResult = const MemoryDraft(title: 'T', keys: ['k'], content: 'c');
      final service = buildService();

      final added = await service.summarizeAfterTurn(
        characterId: seed.characterId,
        conversationId: seed.conversationId,
      );

      expect(added, 1, reason: '超窗口消息截断分支照常归纳');
    });

    test('署名逐字：user「用户：」/ assistant「role.value：」（recentMessages + 单源窗口）',
        () async {
      final seed = await seedConversation();
      await seedMessages(seed.conversationId, 6); // 6 轮 = 12 条 → 触发归纳。
      extractorResult = const MemoryDraft(title: 'T', keys: ['k'], content: 'c');
      final service = buildService();

      final added = await service.summarizeAfterTurn(
        characterId: seed.characterId,
        conversationId: seed.conversationId,
      );

      expect(added, 1);
      expect(extractorCalls, 1);
      expect(capturedDialogueLines, [
        // seedMessages 逐轮交替落 user/assistant（每轮 2 条），窗口保序。
        for (var i = 0; i < 6; i++) ...[
          '用户：用户消息 $i',
          'assistant：助手消息 $i',
        ],
      ], reason: '署名逐字：用户:/role.value 各自保持');
    });

    group('验收 7 端到端：auto 条目落库后命中 keys 即注入且来源标 memory', () {
      test('persistDrafts → listEntries(source=auto) → buildWorldInjection 来源标 memory', () async {
        final seed = await seedConversation();
        final service = buildService();
        await service.persistDrafts(
          seed.characterId,
          const [
            MemoryDraft(
              title: '剑之知识',
              keys: ['剑', 'sword'],
              content: '主角的剑是家族传承之物。',
            ),
          ],
        );

        // 落库即 source='auto'（注入链 sourceById 依赖的仓库列）。
        final entries = await lorebookRepo.listEntries(seed.characterId);
        expect(entries, hasLength(1));
        expect(entries.single.source, 'auto');

        // 后续对话命中 keys → 注入段来源标 memory（buildWorldInjection
        // source_by_id 断言；与 ChatService._buildLorebookInjection 同构）。
        final data = [
          for (final e in entries)
            LorebookEntryData(
              id: e.id,
              keys: e.keys,
              content: e.content,
              constant: e.constant,
              order: e.order,
              probability: e.probability,
              groupName: e.groupName,
              groupWeight: e.groupWeight,
              matchMode: e.matchMode,
              position: e.position,
              enabled: e.enabled,
            ),
        ];
        final activated = activateLorebookEntries(data, '他握着那把剑沉思');
        final sourceById = {for (final e in entries) e.id: e.source};
        final blocks = buildWorldInjection(
          activated,
          charName: '艾莉亚',
          sourceById: sourceById,
        );

        expect(blocks['system'], hasLength(1));
        expect(blocks['system']!.single.content, contains('家族传承'));
        expect(blocks['system']!.single.source, sourceMemory,
            reason: 'auto 条目命中注入 → 来源标 memory');
      });

      test('auto 条目未命中 keys → 不注入（空注入块）', () async {
        final seed = await seedConversation();
        final service = buildService();
        await service.persistDrafts(
          seed.characterId,
          const [MemoryDraft(title: 'T', keys: ['无关'], content: 'c')],
        );

        final entries = await lorebookRepo.listEntries(seed.characterId);
        final data = [
          for (final e in entries)
            LorebookEntryData(id: e.id, keys: e.keys, content: e.content),
        ];
        final activated = activateLorebookEntries(data, '今天天气不错');
        final blocks = buildWorldInjection(
          activated,
          sourceById: {for (final e in entries) e.id: e.source},
        );
        expect(blocks['system'], isEmpty);
      });
    });
  });

  group('回合末 EndOfTurnHook 挂接（验收 6：真实 ChatService 回合触发归纳）', () {
    test('开关开启 + 达阈值 → 回合结束后 auto 条目落库', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = InMemorySecretStore();
      await secretStore.write(key: 'claude_api_key', value: 'sk-test');
      final characterRepo = CharacterRepository(db);
      final conversationRepo = ConversationRepository(
        db,
        const FakeSettingsReader(),
      );
      final messageRepo = MessageRepository(db);
      final settingsRepo = SettingsRepository(
        database: db,
        secretStore: secretStore,
      );
      final lorebookRepo = LorebookRepository(db);

      final character = await characterRepo.createCharacter(
        CharactersCompanion.insert(
          name: '艾莉亚',
          firstMes: const Value(''),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final conv = await conversationRepo.createConversation(
        characterId: character.id,
      );

      // 开关开启 + 每 1 轮归纳（消息数达 2 即触发）。
      await settingsRepo.setMany({
        SettingsRepository.memoryPalaceEnabledKey: 'true',
        SettingsRepository.memoryPalaceEveryRoundsKey: '1',
      });

      final palace = MemoryPalaceService(
        characterRepository: characterRepo,
        messageRepository: messageRepo,
        lorebookRepository: lorebookRepo,
        settingsRepository: settingsRepo,
        extractor: ({
          required String charName,
          required List<String> dialogueLines,
          required double temperature,
        }) async =>
            const MemoryDraft(title: 'T', keys: ['k'], content: 'c'),
      );

      final service = ChatService(
        lorebookRepository: lorebookRepo,
        conversationRepository: conversationRepo,
        characterRepository: characterRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: FixedLLMProviderFactory(
          FakeLLMProvider(tokens: const ['你好']),
        ),
        // S1：hook 列表序，记忆宫殿钩子追加在后（装配层同构闭包；开关 +
        // everyRounds 读取约定 = 服务内部，闭包零设置读取）。
        endOfTurnHooks: [
          (ctx) async {
            final characterId = ctx.characterId;
            if (characterId == null) {
              return;
            }
            await palace.summarizeAfterTurn(
              characterId: characterId,
              conversationId: ctx.conversationId,
            );
          },
        ],
      );

      await service.streamReply(
        conversationId: conv.id,
        content: '嗨',
      ).drain<Object?>(); // 消费至结束（hook fire-and-forget）。

      // 回合落库后 fire-and-forget 归纳：轮询等待落库。
      var entries = await lorebookRepo.listEntries(character.id);
      for (var i = 0; i < 200 && entries.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        entries = await lorebookRepo.listEntries(character.id);
      }
      expect(entries, hasLength(1), reason: '回合结束经 hook 落 auto 条目');
      expect(entries.single.source, 'auto');
    });

    test('开关缺省关闭 → 回合结束不触发归纳（opt-in 成本敏感）', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secretStore = InMemorySecretStore();
      await secretStore.write(key: 'claude_api_key', value: 'sk-test');
      final characterRepo = CharacterRepository(db);
      final conversationRepo = ConversationRepository(
        db,
        const FakeSettingsReader(),
      );
      final messageRepo = MessageRepository(db);
      final settingsRepo = SettingsRepository(
        database: db,
        secretStore: secretStore,
      );
      final lorebookRepo = LorebookRepository(db);

      final character = await characterRepo.createCharacter(
        CharactersCompanion.insert(
          name: '艾莉亚',
          firstMes: const Value(''),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final conv = await conversationRepo.createConversation(
        characterId: character.id,
      );
      // 预置 12 条消息（6 轮完整回合 ≥ everyRounds 缺省 6 的阈值）：若开关
      // 门失效，本轮（+2 条）后 shouldSummarize 必达 → extractor 被调用——
      // 确保本用例唯一拦截因素是服务内开关门（开关缺省关闭语义）。
      for (var i = 0; i < 6; i++) {
        await messageRepo.createMessage(
          conversationId: conv.id,
          role: Role.user,
          content: '预置用户消息 $i',
        );
        await messageRepo.createMessage(
          conversationId: conv.id,
          role: Role.assistant,
          content: '预置助手消息 $i',
        );
      }

      var extractorCalls = 0;
      final palace = MemoryPalaceService(
        characterRepository: characterRepo,
        messageRepository: messageRepo,
        lorebookRepository: lorebookRepo,
        settingsRepository: settingsRepo,
        extractor: ({
          required String charName,
          required List<String> dialogueLines,
          required double temperature,
        }) async {
          extractorCalls++;
          return const MemoryDraft(title: 'T', keys: ['k'], content: 'c');
        },
      );

      final service = ChatService(
        lorebookRepository: lorebookRepo,
        conversationRepository: conversationRepo,
        characterRepository: characterRepo,
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
        providerFactory: FixedLLMProviderFactory(
          FakeLLMProvider(tokens: const ['你好']),
        ),
        endOfTurnHooks: [
          (ctx) async {
            final characterId = ctx.characterId;
            if (characterId == null) {
              return;
            }
            await palace.summarizeAfterTurn(
              characterId: characterId,
              conversationId: ctx.conversationId,
            );
          },
        ],
      );

      await service.streamReply(
        conversationId: conv.id,
        content: '嗨',
      ).drain<Object?>();

      // 缺省关闭 → 服务内首行门早退（summarizeAfterTurn 读开关），零归纳零落库。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(extractorCalls, 0);
      expect(await lorebookRepo.listEntries(character.id), isEmpty);
    });
  });

  group('MEMORY_DRAFT_SCHEMA 常量（单源锚定）', () {
    test('三字段键齐全（title / keys / content）', () {
      expect(MEMORY_DRAFT_SCHEMA, containsPair('title', isNotEmpty));
      expect(MEMORY_DRAFT_SCHEMA, containsPair('keys', isNotEmpty));
      expect(MEMORY_DRAFT_SCHEMA, containsPair('content', isNotEmpty));
      // 可 jsonEncode（prompt 组装复用）。
      expect(jsonEncode(MEMORY_DRAFT_SCHEMA), isNotEmpty);
    });
  });
}
