/// MemoryService 行为契约（AC-02/AC-03）：注入组装 + 指令解析落库。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/services/memory/memory_prompt.dart';
import 'package:conver_system_mobile/services/memory/memory_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late MemoryRepository repo;
  late MemoryService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MemoryRepository(db);
    service = MemoryService(repo);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedCharacter() async {
    final character = await db.into(db.characters).insertReturning(
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
      final reply =
          '好的。\n<persona:她叫艾莉亚>\n<add:她今天心情不好>\n<search:艾莉亚>';

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
}
