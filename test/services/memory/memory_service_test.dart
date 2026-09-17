/// MemoryService 行为契约（AC-02/AC-03 + VR-07 混合检索）：注入组装 + 指令解析落库。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/services/embedding/embedding_client.dart';
import 'package:conver_system_mobile/services/embedding/embedding_config.dart';
import 'package:conver_system_mobile/services/embedding/embedding_service.dart';
import 'package:conver_system_mobile/services/memory/memory_prompt.dart';
import 'package:conver_system_mobile/services/memory/memory_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录调用并返回预设向量的 fake [EmbeddingClient]（VR-07 混合检索 seam）。
class _FakeEmbeddingClient implements EmbeddingClient {
  int embedCalls = 0;

  /// 置位后每次 embed 抛该失败（模拟 API 失败降级路径）。
  EmbeddingFailure? failure;

  @override
  Future<List<EmbeddingVector>> embed(List<String> texts) async {
    embedCalls += 1;
    if (failure != null) {
      throw failure!;
    }
    // 恒等向量：query 与条目向量余弦 = 1 ≥ 0.5 阈值，稳定命中。
    return [
      for (final _ in texts) EmbeddingVector(const [1, 0, 0]),
    ];
  }
}

/// 队列读写抛错的仓储包装（buildInjection 队列失败降级路径）。
class _QueueFailRepository extends MemoryRepository {
  _QueueFailRepository(super.database);

  @override
  Future<List<SemanticHit>> listPendingSemanticHits(
    int characterId, {
    int limit = 3,
  }) {
    throw StateError('队列读失败（测试注入）');
  }

  @override
  Future<bool> deleteSemanticHit(int hitId) {
    throw StateError('队列写失败（测试注入）');
  }
}

void main() {
  late AppDatabase db;
  late MemoryRepository repo;
  late MemoryService service;
  late _FakeEmbeddingClient fake;
  late EmbeddingService embedding;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MemoryRepository(db);
    service = MemoryService(repo);
    fake = _FakeEmbeddingClient();
    embedding = EmbeddingService(
      memoryRepository: repo,
      resolveConfig: () async => const EmbeddingEndpointConfig(
        enabled: true,
        apiKey: 'sk-test',
        baseUrl: null,
        model: 'text-embedding-3-small',
      ),
      clientFactory: (_) => fake,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedCharacter() async {
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: '艾莉亚',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    return character.id;
  }

  group('buildInjection', () {
    test('无记忆时仅返回指令模板（一条 system）', () async {
      final characterId = await seedCharacter();
      final injection = await service.buildInjection(
        characterId,
        mode: MemoryPromptMode.strong,
      );
      expect(injection.length, 1);
      expect(injection.single.role, 'system');
      expect(injection.single.content, contains('严重健忘症模式'));
    });

    test('有记忆时返回指令 + 记忆库内容（两条 system，人格事实全量）', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '她叫艾莉亚',
      );
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '今天聊了天气',
      );

      final injection = await service.buildInjection(characterId);
      expect(injection.length, 2);
      expect(injection[0].content, contains('关键信息记录模式'));
      expect(injection[1].content, contains('人格事实：'));
      expect(injection[1].content, contains('- 她叫艾莉亚'));
      expect(injection[1].content, contains('近期经历：'));
      expect(injection[1].content, contains('- 今天聊了天气'));
    });
  });

  group('applyAssistantReply', () {
    test('解析 add/persona/search：落库 + 剥离展示文本', () async {
      final characterId = await seedCharacter();
      final reply = '好的。\n<persona:她叫艾莉亚>\n<add:她今天心情不好>\n<search:艾莉亚>';

      final result = await service.applyAssistantReply(characterId, reply);

      expect(result.displayContent, '好的。\n\n\n');
      expect(result.personaAdded, 1);
      expect(result.episodicAdded, 1);
      expect(result.searchCount, 1);

      final facts = await repo.listPersonaFacts(characterId);
      expect(facts.map((e) => e.content), ['她叫艾莉亚']);
      final episodic = await repo.listRecentEpisodic(characterId);
      expect(episodic.map((e) => e.content), ['她今天心情不好']);
    });

    test('无标签：原样返回、零落库', () async {
      final characterId = await seedCharacter();
      final result = await service.applyAssistantReply(characterId, '普通回复');
      expect(result.displayContent, '普通回复');
      expect(result.personaAdded, 0);
      expect(result.episodicAdded, 0);
      expect(await repo.listEntries(characterId), isEmpty);
    });
  });

  group('混合检索（VR-07）', () {
    test('关键词命中：原路径直返，零 embedding 调用', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '她喜欢咖啡',
      );
      final hybrid = MemoryService(repo, embeddingService: embedding);

      final result = await hybrid.applyAssistantReply(
        characterId,
        '<search:咖啡>',
      );

      expect(result.searchCount, 1);
      expect(fake.embedCalls, 0); // 零成本路径：不触发任何 embedding 调用。
      expect(await repo.listPendingSemanticHits(characterId), isEmpty);
    });

    test('关键词零命中 + embedding 未启用：返回不抛、队列空', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '她喜欢咖啡',
      );
      final disabledEmbedding = EmbeddingService(
        memoryRepository: repo,
        resolveConfig: () async => const EmbeddingEndpointConfig(
          enabled: false,
          apiKey: '',
          baseUrl: null,
          model: 'text-embedding-3-small',
        ),
        clientFactory: (_) => fake,
      );
      final hybrid = MemoryService(repo, embeddingService: disabledEmbedding);

      final result = await hybrid.applyAssistantReply(
        characterId,
        '<search:大海>',
      );

      expect(result.displayContent, '');
      expect(result.searchCount, 1);
      expect(fake.embedCalls, 0); // 未启用 → 零 API 调用（SR-19 语义）。
      expect(await repo.listPendingSemanticHits(characterId), isEmpty);
    });

    test('关键词零命中 + embedding 命中：入队语义结果，同条目不重复入队', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '她喜欢咖啡',
      );
      final hybrid = MemoryService(repo, embeddingService: embedding);

      final first = await hybrid.applyAssistantReply(
        characterId,
        '<search:大海>',
      );
      expect(first.searchCount, 1);
      final hits = await repo.listPendingSemanticHits(characterId);
      expect(hits, hasLength(1));

      // 同 query 重复检索同一命中：仓储级去重，不重复入队。
      await hybrid.applyAssistantReply(characterId, '<search:大海>');
      expect(await repo.listPendingSemanticHits(characterId), hasLength(1));
    });

    test('embedding 失败：不抛、返回空、不阻断主回复', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '她喜欢咖啡',
      );
      fake.failure = const EmbeddingFailure(
        EmbeddingFailureKind.network,
        'embedding 网络失败（测试注入）',
      );
      final hybrid = MemoryService(repo, embeddingService: embedding);

      final result = await hybrid.applyAssistantReply(
        characterId,
        '<search:大海>',
      );

      expect(result.searchCount, 1);
      expect(await repo.listPendingSemanticHits(characterId), isEmpty);
    });

    test('兼容：无 embeddingService 构造零命中行为与阶段 2 一致', () async {
      final characterId = await seedCharacter();
      final result = await service.applyAssistantReply(
        characterId,
        '<search:不存在>',
      );
      expect(result.displayContent, '');
      expect(result.searchCount, 1);
      expect(await repo.listPendingSemanticHits(characterId), isEmpty);
    });
  });

  group('语义队列注入（VR-07）', () {
    test('buildInjection 至多注入 3 条并消费（再次构建不再出现）', () async {
      final characterId = await seedCharacter();
      final entries = <MemoryEntry>[];
      for (final content in ['记忆一', '记忆二', '记忆三', '记忆四']) {
        entries.add(
          await repo.createEntry(
            characterId: characterId,
            kind: MemoryKind.episodic,
            content: content,
          ),
        );
      }
      for (final entry in entries) {
        await repo.enqueueSemanticHit(
          characterId: characterId,
          entryId: entry.id,
          query: '大海',
        );
      }

      final first = await service.buildInjection(characterId);
      expect(first.length, 2);
      expect(first[1].content, contains('语义相关记忆：'));
      final firstSemantic = first[1].content.substring(
        first[1].content.indexOf('语义相关记忆：'),
      );
      for (final content in ['记忆一', '记忆二', '记忆三']) {
        expect(firstSemantic, contains('- $content'));
      }
      expect(firstSemantic, isNot(contains('记忆四')));
      expect(await repo.listPendingSemanticHits(characterId), hasLength(1));

      final second = await service.buildInjection(characterId);
      final secondSemantic = second[1].content.substring(
        second[1].content.indexOf('语义相关记忆：'),
      );
      expect(secondSemantic, contains('- 记忆四'));
      expect(secondSemantic, isNot(contains('记忆一')));
      expect(await repo.listPendingSemanticHits(characterId), isEmpty);

      final third = await service.buildInjection(characterId);
      expect(third.length, 2); // episodic 仍在 → 记忆库块仍存在。
      expect(third[1].content, isNot(contains('语义相关记忆：')));
    });

    test('队列持久：未消费命中经新仓储实例仍可读（跨重启不丢）', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '她喜欢咖啡',
      );
      await repo.enqueueSemanticHit(
        characterId: characterId,
        entryId: entry.id,
        query: '大海',
      );

      // 新仓储实例 = 模拟重开数据层；未消费队列仍在。
      final reopened = MemoryRepository(db);
      expect(await reopened.listPendingSemanticHits(characterId), hasLength(1));
    });

    test('队列读失败：降级无语义小节，不阻断注入', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '她叫艾莉亚',
      );
      final failing = MemoryService(_QueueFailRepository(db));

      final injection = await failing.buildInjection(characterId);
      expect(injection.length, 2);
      expect(injection[1].content, contains('人格事实：'));
      expect(injection[1].content, isNot(contains('语义相关记忆：')));
    });
  });
}
