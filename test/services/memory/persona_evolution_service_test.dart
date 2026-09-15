/// PersonaEvolutionService 行为契约（AC-04）：LLM 反思 → 版本化快照 → 确认闸门。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/memory/persona_evolution_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
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

  PersonaEvolutionService buildService(Future<String> Function({
    required String currentPersonality,
    required String charName,
    required List<String> personaFacts,
  }) reflector) {
    return PersonaEvolutionService(
      characterRepository: characterRepo,
      memoryRepository: memoryRepo,
      reflector: reflector,
    );
  }

  group('proposeEvolution', () {
    test('反思产出新人格 → 落快照且不回写 personality', () async {
      final character = await seedCharacter();
      final service = buildService(({required currentPersonality, required charName, required personaFacts}) async {
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
      final service = buildService(({required currentPersonality, required charName, required personaFacts}) async {
        return '   ';
      });

      final revision = await service.proposeEvolution(character.id);
      expect(revision, isNull);
      expect(await memoryRepo.listRevisions(character.id), isEmpty);
    });

    test('反思产出与当前人格相同 → 返回 null 不落快照', () async {
      final character = await seedCharacter();
      final service = buildService(({required currentPersonality, required charName, required personaFacts}) async {
        return currentPersonality;
      });

      final revision = await service.proposeEvolution(character.id);
      expect(revision, isNull);
    });

    test('角色不存在 → 抛 CharacterNotFoundError', () async {
      final service = buildService(({required currentPersonality, required charName, required personaFacts}) async {
        return '新人格';
      });
      expect(
        () => service.proposeEvolution(99999),
        throwsA(isA<CharacterNotFoundError>()),
      );
    });
  });

  group('applyRevision / discardRevision', () {
    test('applyRevision 回写 personality；版本不存在返回 false', () async {
      final character = await seedCharacter();
      final service = buildService(({required currentPersonality, required charName, required personaFacts}) async {
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
      final service = buildService(({required currentPersonality, required charName, required personaFacts}) async {
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
}
