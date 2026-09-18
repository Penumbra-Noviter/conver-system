/// MemoryManagementController 行为契约（AC-05）：加载 / 增改删记忆条目 + 演化历史。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/services/memory/persona_evolution_service.dart';
import 'package:conver_system_mobile/views/characters/memory_management_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late MemoryRepository repo;
  late CharacterRepository characterRepo;
  late int characterId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = MemoryRepository(db);
    characterRepo = CharacterRepository(db);
    final character = await db.into(db.characters).insertReturning(
          CharactersCompanion.insert(
            name: '艾莉亚',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    characterId = character.id;
  });

  tearDown(() async {
    await db.close();
  });

  MemoryManagementController buildController({
    PersonaEvolutionService? evolutionService,
  }) =>
      MemoryManagementController(
        memoryRepository: repo,
        characterId: characterId,
        evolutionService: evolutionService ??
            PersonaEvolutionService(
              characterRepository: characterRepo,
              memoryRepository: repo,
              reflector: (
                {
                required characterId,
                required currentPersonality,
                required charName,
                required personaFacts,
              }) async =>
                  '温柔体贴且心思细腻',
            ),
        characterRepository: characterRepo,
      );

  /// 记录 reflector 调用次数并按其语义返回的 fake 构建器。
  MemoryManagementController buildControlledController({
    required Future<String> Function({
      required int characterId,
      required String currentPersonality,
      required String charName,
      required List<String> personaFacts,
    })
    reflector,
  }) =>
      MemoryManagementController(
        memoryRepository: repo,
        characterId: characterId,
        evolutionService: PersonaEvolutionService(
          characterRepository: characterRepo,
          memoryRepository: repo,
          reflector: reflector,
        ),
        characterRepository: characterRepo,
      );

  group('load', () {
    test('加载记忆条目与人设演化版本', () async {
      await repo.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '她叫艾莉亚',
      );
      await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: 'v1',
      );
      final controller = buildController();

      await controller.load();

      expect(controller.entries.map((e) => e.content), ['她叫艾莉亚']);
      expect(controller.revisions.map((r) => r.personalitySnapshot), ['v1']);
      expect(controller.loading, isFalse);
    });

    test('失败保留既有列表并置 notice', () async {
      final controller = buildController();
      await controller.load();
      expect(controller.entries, isEmpty);

      // 关闭底层库触发 load 失败。
      await db.close();
      await controller.load();
      expect(controller.notice, isNotNull);
      expect(controller.entries, isEmpty);
    });
  });

  group('增改删', () {
    test('createEntry 后条目可见；updateEntry 更新内容；deleteEntry 移除', () async {
      final controller = buildController();
      await controller.load();

      await controller.createEntry(MemoryKind.episodic, '今天聊了天气');
      expect(controller.entries.map((e) => e.content), ['今天聊了天气']);

      final entry = controller.entries.single;
      await controller.updateEntry(entry.id, content: '今天聊了天气，很开心');
      expect(controller.entries.single.content, '今天聊了天气，很开心');

      await controller.deleteEntry(entry.id);
      expect(controller.entries, isEmpty);
    });
  });

  group('dismissNotice', () {
    test('清除 notice', () async {
      final controller = buildController();
      await db.close();
      await controller.load();
      expect(controller.notice, isNotNull);

      controller.dismissNotice();
      expect(controller.notice, isNull);
    });
  });

  group('人设演化（确认闸门）', () {
    test('propose 非 null → 快照落库 + 消息「已提出演化，待确认」+ proposing 复位', () async {
      final controller = buildController();
      await controller.load();

      final future = controller.proposeEvolution();

      expect(controller.proposing, isTrue);
      await future;
      expect(controller.proposing, isFalse);
      expect(controller.snackMessage, '已提出演化，待确认');
      expect(controller.revisions.map((r) => r.personalitySnapshot),
          ['温柔体贴且心思细腻']);
    });

    test('propose null（产出与当前人格相同）→ 消息「人设无变化」不落快照', () async {
      final controller = buildControlledController(
        reflector:
            ({
              required characterId,
              required currentPersonality,
              required charName,
              required personaFacts,
            }) async =>
                currentPersonality,
      );
      await controller.load();

      await controller.proposeEvolution();

      expect(controller.snackMessage, '人设无变化');
      expect(controller.revisions, isEmpty);
    });

    test('propose 异常（reflector 抛错）→ notice 固定摘要不含异常原文（SR-16）', () async {
      final controller = buildControlledController(
        reflector:
            ({
              required characterId,
              required currentPersonality,
              required charName,
              required personaFacts,
            }) async =>
                throw StateError('sk-secret-wire-9432'),
      );
      await controller.load();

      await controller.proposeEvolution();

      expect(controller.proposing, isFalse);
      expect(controller.notice, isNotNull);
      expect(controller.notice, isNot(contains('sk-secret-wire-9432')));
      expect(controller.revisions, isEmpty);
    });

    test('proposing 期间重复调用被忽略（仅一次 reflector 调用）', () async {
      var calls = 0;
      final controller = buildControlledController(
        reflector:
            ({
              required characterId,
              required currentPersonality,
              required charName,
              required personaFacts,
            }) async {
              calls++;
              return '演化人格';
            },
      );
      await controller.load();

      final first = controller.proposeEvolution();
      // 同步调用第二次——guard 应直接返回，不产生第二次 reflector 调用。
      final second = controller.proposeEvolution();
      await Future.wait([first, second]);

      expect(calls, 1);
      expect(controller.revisions.map((r) => r.personalitySnapshot), ['演化人格']);
    });

    test('apply 端到端：propose → apply → personality 回写 + 已应用标记 + 消息', () async {
      final controller = buildController();
      await controller.load();
      await controller.proposeEvolution();
      final revisionId = controller.revisions.single.id;
      controller.consumeSnackMessage();

      await controller.applyRevision(revisionId);

      final updated = await characterRepo.getCharacter(characterId);
      expect(updated!.personality, '温柔体贴且心思细腻');
      expect(controller.appliedRevisionIds, {revisionId});
      expect(controller.snackMessage, '人设已更新');
    });

    test('apply false（版本不存在）→ 不抛且无消息', () async {
      final controller = buildController();
      await controller.load();

      await controller.applyRevision(99999);

      expect(controller.snackMessage, isNull);
      expect(controller.appliedRevisionIds, isEmpty);
    });

    test('discard 端到端：propose → discard → 快照删除', () async {
      final controller = buildController();
      await controller.load();
      await controller.proposeEvolution();
      final revisionId = controller.revisions.single.id;

      await controller.discardRevision(revisionId);

      expect(controller.revisions, isEmpty);
    });

    test('discard false（版本不存在）→ 不抛', () async {
      final controller = buildController();
      await controller.load();

      await controller.discardRevision(99999);

      expect(controller.revisions, isEmpty);
    });

    test('Q7 判定：load 后 appliedRevisionIds = 快照等于当前人格的版本', () async {
      final current = (await characterRepo.getCharacter(characterId))!.personality;
      final applied = await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: current,
      );
      final pending = await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: '另一版人格',
      );
      final controller = buildController();

      await controller.load();

      expect(controller.appliedRevisionIds, {applied.id});
      expect(controller.appliedRevisionIds, isNot(contains(pending.id)));
    });

    test('Q7 reapply 幂等：apply 后手动编辑 personality → 回待确认 → 再 apply 同一 revision', () async {
      // F-117。Q7 语义：appliedRevisionIds 由「快照 == 当前人格」启发式在 load
      // 时重算，非持久状态。同一快照可重复应用：只要当前人格 ≠ 快照即回到
      // 「待确认」，再次 apply 同一 revision 会幂等回写并重新标记已应用。
      final controller = buildController();
      await controller.load();
      await controller.proposeEvolution();
      final revisionId = controller.revisions.single.id;
      controller.consumeSnackMessage();

      // 第一次 apply：快照回写 personality → load 重算 → 已应用。
      await controller.applyRevision(revisionId);
      expect(controller.appliedRevisionIds, {revisionId});

      // 手动编辑 personality（模拟外部改动）→ load 后 Q7 重算：快照 ≠ 当前人格
      // → 回待确认。
      await characterRepo.updateCharacter(
        characterId,
        CharactersCompanion(personality: Value('手动编辑后的人格')),
      );
      await controller.load();
      expect(controller.appliedRevisionIds, isEmpty);

      // 同一 revision 再 apply（幂等重放）：快照再次回写并重新标记已应用。
      await controller.applyRevision(revisionId);
      expect(controller.appliedRevisionIds, {revisionId});
      final updated = await characterRepo.getCharacter(characterId);
      expect(updated!.personality, '温柔体贴且心思细腻');
    });

    test('apply 异常（服务抛错）→ 不抛到 UI、无消息、revisions 不变', () async {
      // F-118 异常吞并分支：与「版本不存在返回 false」是不同路径（false 走
      // 正常返回，这里服务直接抛错），catch(_) 吞掉且不刷新。
      final revision = await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: 'v1',
      );
      final controller = buildController(
        evolutionService: _ThrowingEvolutionService(
          characterRepository: characterRepo,
          memoryRepository: repo,
        ),
      );
      await controller.load();

      await controller.applyRevision(revision.id);

      expect(controller.snackMessage, isNull);
      expect(controller.appliedRevisionIds, isEmpty);
      expect(controller.revisions.map((r) => r.id), [revision.id]);
    });

    test('discard 异常（服务抛错）→ 不抛到 UI、无消息、revisions 不变', () async {
      // F-118 异常吞并分支：catch(_) 吞掉且保留既有列表。
      final revision = await repo.addRevision(
        characterId: characterId,
        personalitySnapshot: 'v1',
      );
      final controller = buildController(
        evolutionService: _ThrowingEvolutionService(
          characterRepository: characterRepo,
          memoryRepository: repo,
        ),
      );
      await controller.load();

      await controller.discardRevision(revision.id);

      expect(controller.snackMessage, isNull);
      expect(controller.appliedRevisionIds, isEmpty);
      expect(controller.revisions.map((r) => r.id), [revision.id]);
    });
  });
}

/// 异常注入 fake：apply/discard 直接抛错，验证 controller 的 catch(_) 吞并分支。
///
/// 与「版本不存在返回 false」是不同路径——false 走正常返回，本类走异常通道；
/// controller 应把两者都静默处理（不抛到 UI、不置 snackMessage、状态不变）。
class _ThrowingEvolutionService extends PersonaEvolutionService {
  _ThrowingEvolutionService({
    required super.characterRepository,
    required super.memoryRepository,
  }) : super(
         reflector:
             ({
               required characterId,
               required currentPersonality,
               required charName,
               required personaFacts,
             }) async =>
                 '',
       );

  @override
  Future<bool> applyRevision(int revisionId) async {
    throw StateError('apply 异常注入');
  }

  @override
  Future<bool> discardRevision(int revisionId) async {
    throw StateError('discard 异常注入');
  }
}
