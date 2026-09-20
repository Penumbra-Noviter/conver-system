/// PersonaEvolutionService 行为契约（AC-04）：LLM 反思 → 版本化快照 → 确认闸门。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/services/embedding/embedding_client.dart';
import 'package:conver_system_mobile/services/embedding/embedding_config.dart';
import 'package:conver_system_mobile/services/embedding/embedding_service.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/memory/persona_evolution_service.dart';
import 'package:conver_system_mobile/utils/utf16_truncate.dart'
    show maxSnapshotLength;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CharacterRepository characterRepo;
  late MemoryRepository memoryRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    characterRepo = CharacterRepository(db);
    memoryRepo = MemoryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Character> seedCharacter({String personality = '温柔体贴'}) {
    return characterRepo.createCharacter(
      CharactersCompanion.insert(
        name: '艾莉亚',
        personality: Value(personality),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  PersonaEvolutionService buildService(CharacterScopedReflector reflector) {
    return PersonaEvolutionService(
      characterRepository: characterRepo,
      memoryRepository: memoryRepo,
      reflector: reflector,
    );
  }

  group('proposeEvolution', () {
    test('反思产出新人格 → 落快照且不回写 personality', () async {
      final character = await seedCharacter();
      final service = buildService(({
        required characterId,
        required currentPersonality,
        required charName,
        required personaFacts,
      }) async {
        expect(characterId, character.id);
        expect(currentPersonality, '温柔体贴');
        expect(charName, '艾莉亚');
        return '温柔体贴且心思细腻';
      });

      final revision = await service.proposeEvolution(character.id);

      expect(revision, isNotNull);
      expect(revision!.personalitySnapshot, '温柔体贴且心思细腻');
      expect(revision.reason, 'AI 反思演化');

      // 快照落库但 personality 未回写（等待用户确认）。
      final stillCharacter = await characterRepo.getCharacter(character.id);
      expect(stillCharacter!.personality, '温柔体贴');
      expect(await memoryRepo.listRevisions(character.id), hasLength(1));
    });

    test('反思产出空串 → 返回 null 不落快照', () async {
      final character = await seedCharacter();
      final service = buildService(({
        required characterId,
        required currentPersonality,
        required charName,
        required personaFacts,
      }) async {
        return '   ';
      });

      final revision = await service.proposeEvolution(character.id);
      expect(revision, isNull);
      expect(await memoryRepo.listRevisions(character.id), isEmpty);
    });

    test('反思产出与当前人格相同 → 返回 null 不落快照', () async {
      final character = await seedCharacter();
      final service = buildService(({
        required characterId,
        required currentPersonality,
        required charName,
        required personaFacts,
      }) async {
        return currentPersonality;
      });

      final revision = await service.proposeEvolution(character.id);
      expect(revision, isNull);
    });

    test('角色不存在 → 抛 CharacterNotFoundError', () async {
      final service = buildService(({
        required characterId,
        required currentPersonality,
        required charName,
        required personaFacts,
      }) async {
        return '新人格';
      });
      expect(
        () => service.proposeEvolution(99999),
        throwsA(isA<CharacterNotFoundError>()),
      );
    });

    test('SR-22：产出恰好上限长度 → 原样落库', () async {
      final character = await seedCharacter();
      final exactlyMax = '格' * maxSnapshotLength;
      final service = buildService(({
        required characterId,
        required currentPersonality,
        required charName,
        required personaFacts,
      }) async {
        return exactlyMax;
      });

      final revision = await service.proposeEvolution(character.id);

      expect(revision!.personalitySnapshot, exactlyMax);
    });

    test('SR-22：产出超上限 → 截断至前 maxSnapshotLength 字符落库', () async {
      final character = await seedCharacter();
      final overlong = 'x' * (maxSnapshotLength + 5) + 'TAIL';
      final service = buildService(({
        required characterId,
        required currentPersonality,
        required charName,
        required personaFacts,
      }) async {
        return overlong;
      });

      final revision = await service.proposeEvolution(character.id);

      expect(
        revision!.personalitySnapshot.length,
        maxSnapshotLength,
      );
      expect(revision.personalitySnapshot, 'x' * maxSnapshotLength);
      expect(revision.personalitySnapshot, isNot(contains('TAIL')));
    });

    test('SR-22：clamp 后恰等于当前人格 → 返回 null 不落快照', () async {
      // 当前人格恰好 2000 字符；reflector 产出 2001 字符 → 截断后 == 当前人格
      // → 与「产出 == 当前人格」同判：无变化，不落快照（F-116）。
      final currentPersonality = 'a' * maxSnapshotLength;
      final character = await seedCharacter(personality: currentPersonality);
      final service = buildService(({
        required characterId,
        required currentPersonality,
        required charName,
        required personaFacts,
      }) async {
        return '${currentPersonality}x';
      });

      final revision = await service.proposeEvolution(character.id);

      expect(revision, isNull);
      expect(await memoryRepo.listRevisions(character.id), isEmpty);
    });

    test('SR-22：超限截断输出 debugPrint 摘要且不含完整原文', () async {
      final character = await seedCharacter();
      final overlong = '人格' * (maxSnapshotLength ~/ 2 + 3);
      final captured = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        captured.add(message ?? '');
      };
      addTearDown(() => debugPrint = original);
      final service = buildService(({
        required characterId,
        required currentPersonality,
        required charName,
        required personaFacts,
      }) async {
        return overlong;
      });

      await service.proposeEvolution(character.id);

      final log = captured.join('\n');
      expect(log, contains('截断'));
      expect(log, contains('$maxSnapshotLength'));
      expect(log, isNot(contains(overlong)));
    });
  });

  group('applyRevision / discardRevision', () {
    test('applyRevision 回写 personality；版本不存在返回 false', () async {
      final character = await seedCharacter();
      final service = buildService(({
        required characterId,
        required currentPersonality,
        required charName,
        required personaFacts,
      }) async {
        return '温柔体贴且心思细腻';
      });
      final revision = await service.proposeEvolution(character.id);

      final applied = await service.applyRevision(revision!.id);
      expect(applied, isTrue);
      final updated = await characterRepo.getCharacter(character.id);
      expect(updated!.personality, '温柔体贴且心思细腻');

      // 版本不存在 → false 且零副作用。
      expect(await service.applyRevision(99999), isFalse);
    });

    test('discardRevision 删除快照且不回写 personality', () async {
      final character = await seedCharacter();
      final service = buildService(({
        required characterId,
        required currentPersonality,
        required charName,
        required personaFacts,
      }) async {
        return '新人格';
      });
      final revision = await service.proposeEvolution(character.id);

      final discarded = await service.discardRevision(revision!.id);
      expect(discarded, isTrue);
      expect(await memoryRepo.listRevisions(character.id), isEmpty);
      final unchanged = await characterRepo.getCharacter(character.id);
      expect(unchanged!.personality, '温柔体贴');
    });
  });

  group('buildEvolutionMessages', () {
    test('含当前人格 + 已记录人格事实', () {
      final messages = buildEvolutionMessages(
        currentPersonality: '温柔',
        charName: '艾莉亚',
        personaFacts: const ['她喜欢猫'],
      );
      expect(messages, hasLength(2));
      expect(messages.first.role, 'system');
      expect(messages.first.content, contains('艾莉亚'));
      expect(messages.last.role, 'user');
      expect(messages.last.content, contains('温柔'));
      expect(messages.last.content, contains('- 她喜欢猫'));
    });
  });

  group('VR-08 聚类摘要注入', () {
    test('buildEvolutionMessages 非空 similarClusters → 语义相近段落位于事实之后', () {
      final messages = buildEvolutionMessages(
        currentPersonality: '温柔',
        charName: '艾莉亚',
        personaFacts: const ['她喜欢猫'],
        similarClusters: const ['喜欢猫；养了三只猫', '怕黑；睡觉留灯'],
      );
      final user = messages.last.content;
      expect(
        user.indexOf('以下事实语义相近，可能重复：'),
        greaterThan(user.indexOf('- 她喜欢猫')),
      );
      expect(
        user,
        contains(
          '以下事实语义相近，可能重复：\n- 喜欢猫；养了三只猫\n'
          '- 怕黑；睡觉留灯',
        ),
      );
    });

    test('buildEvolutionMessages 空列表/缺省 → 无聚类段落', () {
      final withEmpty = buildEvolutionMessages(
        currentPersonality: '温柔',
        charName: '艾莉亚',
        personaFacts: const ['她喜欢猫'],
        similarClusters: const [],
      );
      expect(withEmpty.last.content, isNot(contains('以下事实语义相近')));
      final omitted = buildEvolutionMessages(
        currentPersonality: '温柔',
        charName: '艾莉亚',
        personaFacts: const ['她喜欢猫'],
      );
      expect(omitted.last.content, isNot(contains('以下事实语义相近')));
    });

    test(
      'buildClusteredReflector 聚类非空 → 摘要注入 inner 且 characterId 透传',
      () async {
        final character = await seedCharacter();
        final f1 = await memoryRepo.createEntry(
          characterId: character.id,
          kind: MemoryKind.personaFact,
          content: '喜欢猫',
        );
        final f2 = await memoryRepo.createEntry(
          characterId: character.id,
          kind: MemoryKind.personaFact,
          content: '养了三只猫',
        );
        final calls = <int>[];
        final embedding = _FakeEmbeddingService(
          memory: memoryRepo,
          result: [
            [f1, f2],
            [f1],
          ],
          calls: calls,
        );
        List<String>? received;
        final reflector = buildClusteredReflector(
          embeddingService: embedding,
          inner:
              ({
                required currentPersonality,
                required charName,
                required personaFacts,
                List<String> similarClusters = const [],
              }) async {
                received = similarClusters;
                return '聚类演化人格';
              },
        );

        final out = await reflector(
          characterId: character.id,
          currentPersonality: '现人格',
          charName: '艾莉亚',
          personaFacts: const ['喜欢猫'],
        );

        expect(out, '聚类演化人格');
        expect(calls, [character.id]);
        expect(received, isNotNull);
        expect(received, ['喜欢猫；养了三只猫', '喜欢猫']);
      },
    );

    test('buildClusteredReflector 聚类空（降级）→ inner 收空列表且不抛', () async {
      final calls = <int>[];
      final embedding = _FakeEmbeddingService(
        memory: memoryRepo,
        result: const <List<MemoryEntry>>[],
        calls: calls,
      );
      List<String>? received;
      final reflector = buildClusteredReflector(
        embeddingService: embedding,
        inner:
            ({
              required currentPersonality,
              required charName,
              required personaFacts,
              List<String> similarClusters = const [],
            }) async {
              received = similarClusters;
              return currentPersonality;
            },
      );

      final out = await reflector(
        characterId: 3,
        currentPersonality: '原人格',
        charName: '艾莉亚',
        personaFacts: const [],
      );

      expect(out, '原人格');
      expect(calls, [3]);
      expect(received, isEmpty);
    });

    test('reflectPersonaWithProvider 透传 similarClusters 到组装消息', () async {
      final provider = _CapturingProvider('新人格');
      final out = await reflectPersonaWithProvider(
        llm: provider,
        model: 'm1',
        currentPersonality: '温柔',
        charName: '艾莉亚',
        personaFacts: const ['她喜欢猫'],
        similarClusters: const ['喜欢猫；养了三只猫'],
      );
      expect(out, '新人格');
      expect(
        provider.lastMessages!.last.content,
        contains('以下事实语义相近，可能重复：\n- 喜欢猫；养了三只猫'),
      );
    });

    test('reflectPersonaWithProvider 缺省 → 无聚类段落', () async {
      final provider = _CapturingProvider('新人格');
      await reflectPersonaWithProvider(
        llm: provider,
        model: 'm1',
        currentPersonality: '温柔',
        charName: '艾莉亚',
        personaFacts: const ['她喜欢猫'],
      );
      expect(provider.lastMessages!.last.content, isNot(contains('以下事实语义相近')));
    });
  });
}

class _FakeEmbeddingService extends EmbeddingService {
  _FakeEmbeddingService({
    required MemoryRepository memory,
    required this.result,
    required this.calls,
  }) : super(
         memoryRepository: memory,
         resolveConfig: _neverConfig,
         clientFactory: _neverClient,
       );

  final List<List<MemoryEntry>> result;
  final List<int> calls;

  @override
  Future<List<List<MemoryEntry>>> buildClusterInput(int characterId) async {
    calls.add(characterId);
    return result;
  }

  static Future<EmbeddingEndpointConfig> _neverConfig() =>
      throw UnimplementedError();

  static EmbeddingClient _neverClient(EmbeddingEndpointConfig config) =>
      throw UnimplementedError();
}

class _CapturingProvider extends LLMProvider {
  _CapturingProvider(this.generated) : super(apiKey: 'test-key');

  final String generated;
  List<LlmMessage>? lastMessages;

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
    lastMessages = messages;
    return generated;
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
  }) {
    return const Stream<String>.empty();
  }
}
