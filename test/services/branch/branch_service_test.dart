/// BR-01：BranchService 三法 — buildBranchSnapshot / cloneFromSnapshot /
/// branchFromMessage + exportSnapshot + 删源置空级联语义。
///
/// 测试 seam（公共接口边界）：[BranchService] 公开 API + [BranchSnapshot]
/// 模型。通过内存 drift + 四真实仓储 + [FakeSettingsReader] 驱动（服务层不
/// mock 内部）；契约锚为桌面 `conversation.py::clone_conversation /
/// branch_from_message` 与 `conversation_export.py::build_branch_snapshot`
/// 逐字语义 + 移动端工单 BR-01 验收 3~7（截断含锚 / 往返一致 / 世界书复制
/// 互不影响 / 删源置空锁定）。
library;

import 'dart:convert';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/lorebook_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/services/branch/branch_service.dart';
import 'package:conver_system_mobile/services/branch/branch_snapshot.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_env.dart' show FakeSettingsReader;

void main() {
  late AppDatabase db;
  late CharacterRepository charRepo;
  late ConversationRepository convRepo;
  late MessageRepository msgRepo;
  late LorebookRepository lorebookRepo;
  late BranchService branchService;

  // 可变时刻：消息/候选/世界书/会话种子经 `now:` 注入逐条控制。
  late DateTime fakeNow;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    fakeNow = DateTime(2023, 11, 14, 22, 13, 20);
    charRepo = CharacterRepository(db, now: () => fakeNow);
    convRepo = ConversationRepository(
      db,
      const FakeSettingsReader(),
      now: () => fakeNow,
    );
    msgRepo = MessageRepository(db, now: () => fakeNow);
    lorebookRepo = LorebookRepository(db, now: () => fakeNow);
    branchService = BranchService(
      database: db,
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: msgRepo,
      lorebookRepository: lorebookRepo,
      now: () => fakeNow,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<Character> seedCharacter({String name = '艾莉亚'}) {
    return charRepo.createCharacter(
      CharactersCompanion.insert(
        name: name,
        createdAt: fakeNow,
        updatedAt: fakeNow,
      ),
    );
  }

  Future<Conversation> seedConversation(int characterId, {String? title}) =>
      convRepo.createConversation(characterId: characterId, title: title);

  Future<Message> seedMessage({
    required int conversationId,
    required Role role,
    required String content,
  }) {
    return msgRepo.createMessage(
      conversationId: conversationId,
      role: role,
      content: content,
    );
  }

  /// 种子源会话：角色 + 两条世界书条目 + 四消息（U1/A1/U2/A2），A2 带候选
  /// （原始回复 + 「重写答」激活）。返回 (对话, 消息 id 列表)。
  Future<(Conversation, List<int>)> seedSourceWith(
    int characterId, {
    int lorebookCount = 0,
  }) async {
    for (var i = 0; i < lorebookCount; i++) {
      await lorebookRepo.createEntry(
        characterId,
        LorebookEntryDraft(
          title: '条目$i',
          keys: ['键$i'],
          content: '内容$i',
          constant: i == 0,
          order: 10 + i,
        ),
      );
    }
    final conv = await seedConversation(characterId, title: '源对话');
    final ids = <int>[];
    for (final (role, content) in [
      (Role.user, '第一轮问'),
      (Role.assistant, '第一轮答'),
      (Role.user, '第二轮问'),
      (Role.assistant, '第二轮答'),
    ]) {
      final message = await seedMessage(
        conversationId: conv.id,
        role: role,
        content: content,
      );
      ids.add(message.id);
    }
    await msgRepo.addSwipe(ids[3], '重写答');
    return (conv, ids);
  }

  Future<List<Message>> messagesOf(int conversationId) =>
      msgRepo.getMessages(conversationId);

  group('buildBranchSnapshot · 截断锚正确性（验收 3）', () {
    test('全量：含全部消息（id 升序）+ 世界书条目 + 候选（message_index/active）', () async {
      final char = await seedCharacter();
      final (conv, ids) = await seedSourceWith(char.id, lorebookCount: 2);

      final snapshot = await branchService.buildBranchSnapshot(conv.id);

      expect(snapshot.version, snapshotVersion);
      expect(snapshot.characterId, char.id);
      expect(snapshot.modelProvider, 'claude');
      expect(snapshot.modelName, 'claude-sonnet-5');
      expect(snapshot.title, '源对话');

      // 消息 id 升序全量 + role/content 逐条。
      expect(snapshot.messages.map((m) => m.role).toList(), [
        'user',
        'assistant',
        'user',
        'assistant',
      ]);
      expect(snapshot.messages.map((m) => m.content).toList(), [
        '第一轮问',
        '第一轮答',
        '第二轮问',
        '重写答',
      ]);
      expect(snapshot.messages.map((m) => m.createdAt).toList(), [
        for (final _ in ids) fakeNow,
      ]);

      // 世界书条目快照字段一一对应。
      expect(snapshot.lorebookEntries, hasLength(2));
      expect(snapshot.lorebookEntries[0].title, '条目0');
      expect(snapshot.lorebookEntries[0].keys, ['键0']);
      expect(snapshot.lorebookEntries[0].constant, true);
      expect(snapshot.lorebookEntries[0].order, 10);

      // 候选：仅含候选的消息；message_index = 快照数组下标（与源消息 id 无关）。
      expect(snapshot.swipes, hasLength(1));
      expect(snapshot.swipes.single.messageIndex, 3);
      expect(snapshot.swipes.single.swipes, ['第二轮答', '重写答']);
      expect(snapshot.swipes.single.activeSwipeIndex, 1);
    });

    test('截断锚含该消息、不含锚后消息（uptoMessageId=第二轮答）', () async {
      final char = await seedCharacter();
      final (conv, ids) = await seedSourceWith(char.id);

      final snapshot = await branchService.buildBranchSnapshot(
        conv.id,
        uptoMessageId: ids[2],
      );

      expect(snapshot.messages.map((m) => m.content).toList(), [
        '第一轮问',
        '第一轮答',
        '第二轮问',
      ]);
      // 锚后的 A2（带候选）被截掉 → 快照无候选。
      expect(snapshot.swipes, isEmpty);
    });

    test('截断锚含该消息、不含锚后消息；锚消息候选映射为截断后数组下标', () async {
      final char = await seedCharacter();
      // 首条 assistant 带候选：截断到 A1 时 A1 仍为截断数组末位（下标 1）。
      final conv = await seedConversation(char.id, title: '源对话');
      await seedMessage(conversationId: conv.id, role: Role.user, content: '问');
      final a1 = await seedMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '答',
      );
      await msgRepo.addSwipe(a1.id, '重写答');
      final u2 = await seedMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '又问',
      );

      final snapshot = await branchService.buildBranchSnapshot(
        conv.id,
        uptoMessageId: u2.id,
      );

      // 快照消息 content 恒为激活候选（addSwipe 激活后 = 重写答），桌面
      // 「content 跟随激活候选」不变量。
      expect(snapshot.messages.map((m) => m.content).toList(), [
        '问',
        '重写答',
        '又问',
      ]);
      expect(snapshot.swipes.single.messageIndex, 1);
      expect(snapshot.swipes.single.swipes, ['答', '重写答']);
      expect(snapshot.swipes.single.activeSwipeIndex, 1);
    });

    test('序号锚定与源消息 id 无关：删前两条后重编号', () async {
      final char = await seedCharacter();
      final (conv, ids) = await seedSourceWith(char.id);
      // 删除 U1 / A1（单删，候选级联），A2 源 id 仍为原始大 id。
      await msgRepo.deleteMessage(ids[0]);
      await msgRepo.deleteMessage(ids[1]);

      final snapshot = await branchService.buildBranchSnapshot(conv.id);

      expect(snapshot.messages.map((m) => m.content).toList(), ['第二轮问', '重写答']);
      expect(
        snapshot.swipes.single.messageIndex,
        1,
        reason: 'message_index 为快照数组下标（0/1 重编号），非源消息 id',
      );
    });

    test('锚消息不存在 → MessageNotFoundError（禁止静默空快照）', () async {
      final char = await seedCharacter();
      final (conv, _) = await seedSourceWith(char.id);

      await expectLater(
        branchService.buildBranchSnapshot(conv.id, uptoMessageId: 999999),
        throwsA(isA<MessageNotFoundError>()),
      );
    });

    test('锚消息属于其他对话 → MessageNotFoundError（不得跨会话截断）', () async {
      final char = await seedCharacter();
      final (convA, idsA) = await seedSourceWith(char.id);
      final (convB, _) = await seedSourceWith(char.id);

      await expectLater(
        branchService.buildBranchSnapshot(convB.id, uptoMessageId: idsA[0]),
        throwsA(isA<MessageNotFoundError>()),
      );
      expect(convA.id, isNot(convB.id));
    });

    test('对话不存在 → ConversationNotFoundError', () async {
      await expectLater(
        branchService.buildBranchSnapshot(999999),
        throwsA(isA<ConversationNotFoundError>()),
      );
    });

    test('空对话快照：消息/候选为空，世界书条目仍随快照', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id, title: '空对话');
      await lorebookRepo.createEntry(
        char.id,
        LorebookEntryDraft(title: '雪色', content: '雪夜'),
      );

      final snapshot = await branchService.buildBranchSnapshot(conv.id);

      expect(snapshot.messages, isEmpty);
      expect(snapshot.swipes, isEmpty);
      expect(snapshot.lorebookEntries, hasLength(1));
      expect(snapshot.title, '空对话');
    });
  });

  group('cloneFromSnapshot · 快照重建往返（验收 4/6）', () {
    test('往返：新会话消息/候选/激活逐条一致，created_at 保真', () async {
      final char = await seedCharacter();
      final (conv, _) = await seedSourceWith(char.id, lorebookCount: 1);
      final snapshot = await branchService.buildBranchSnapshot(conv.id);

      final clone = await branchService.cloneFromSnapshot(snapshot);

      expect(clone.id, isNot(conv.id));
      expect(clone.characterId, char.id);
      expect(clone.title, '源对话');
      expect(clone.modelProvider, 'claude');
      expect(clone.modelName, 'claude-sonnet-5');

      final cloneMessages = await messagesOf(clone.id);
      expect(cloneMessages.map((m) => m.role.value).toList(), [
        'user',
        'assistant',
        'user',
        'assistant',
      ]);
      expect(cloneMessages.map((m) => m.content).toList(), [
        '第一轮问',
        '第一轮答',
        '第二轮问',
        '重写答',
      ]);
      expect(cloneMessages.map((m) => m.createdAt).toList(), [
        for (final _ in const [1, 2, 3, 4]) fakeNow,
      ]);

      // 无候选消息 active=0（BR-01 关注：移动端候选清空退化态 + 无候选零影响）。
      expect(cloneMessages.first.activeSwipeIndex, 0);

      // 候选重建：候选 0 = 原始内容，激活 = 重写答。
      final last = cloneMessages.last;
      expect(last.activeSwipeIndex, 1);
      final swipes = await msgRepo.listSwipes(last.id);
      expect(swipes.map((s) => s.content).toList(), ['第二轮答', '重写答']);
    });

    test('title：显式覆盖快照标题；缺省 → 快照标题', () async {
      final char = await seedCharacter();
      final (conv, _) = await seedSourceWith(char.id);
      final snapshot = await branchService.buildBranchSnapshot(conv.id);

      final withTitle = await branchService.cloneFromSnapshot(
        snapshot,
        title: '我的分支',
      );
      expect(withTitle.title, '我的分支');

      final withoutTitle = await branchService.cloneFromSnapshot(snapshot);
      expect(withoutTitle.title, '源对话');
    });

    test('快照角色不存在 → CharacterNotFoundError', () async {
      final snapshot = BranchSnapshot(characterId: 999999);

      await expectLater(
        branchService.cloneFromSnapshot(snapshot),
        throwsA(isA<CharacterNotFoundError>()),
      );
    });

    test('空消息快照 → 新会话无消息（合法；无候选）', () async {
      final char = await seedCharacter();
      final snapshot = BranchSnapshot(characterId: char.id);

      final clone = await branchService.cloneFromSnapshot(snapshot);

      expect(await messagesOf(clone.id), isEmpty);
    });

    test('防御矩阵：非法消息角色 → InvalidBranchSnapshotError', () async {
      final char = await seedCharacter();
      final snapshot = BranchSnapshot(
        characterId: char.id,
        messages: const [BranchSnapshotMessage(role: 'npc', content: '非法角色')],
      );

      await expectLater(
        branchService.cloneFromSnapshot(snapshot),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('防御矩阵：message_index 越界 → InvalidBranchSnapshotError', () async {
      final char = await seedCharacter();
      final snapshot = BranchSnapshot(
        characterId: char.id,
        messages: const [
          BranchSnapshotMessage(role: 'assistant', content: '答'),
        ],
        swipes: const [
          BranchSnapshotSwipe(messageIndex: 5, swipes: ['答']),
        ],
      );

      await expectLater(
        branchService.cloneFromSnapshot(snapshot),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('防御矩阵：激活序号越界 → InvalidBranchSnapshotError', () async {
      final char = await seedCharacter();
      final snapshot = BranchSnapshot(
        characterId: char.id,
        messages: const [
          BranchSnapshotMessage(role: 'assistant', content: '答'),
        ],
        swipes: const [
          BranchSnapshotSwipe(
            messageIndex: 0,
            swipes: ['答', '重写'],
            activeSwipeIndex: 5,
          ),
        ],
      );

      await expectLater(
        branchService.cloneFromSnapshot(snapshot),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('防御矩阵：content ≠ 激活候选（不变量）→ InvalidBranchSnapshotError', () async {
      final char = await seedCharacter();
      final snapshot = BranchSnapshot(
        characterId: char.id,
        messages: const [
          BranchSnapshotMessage(role: 'assistant', content: '内容A'),
        ],
        swipes: const [
          BranchSnapshotSwipe(
            messageIndex: 0,
            swipes: ['原始', '候选B'],
            activeSwipeIndex: 1,
          ),
        ],
      );

      await expectLater(
        branchService.cloneFromSnapshot(snapshot),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('世界书条目被复制且互不影响（验收 6：独立行断言）', () async {
      final char = await seedCharacter();
      final (conv, _) = await seedSourceWith(char.id, lorebookCount: 2);
      final before = await lorebookRepo.listEntries(char.id);
      expect(before, hasLength(2));
      final maxIdBefore = before
          .map((e) => e.id)
          .reduce((a, b) => a > b ? a : b);
      final snapshot = await branchService.buildBranchSnapshot(conv.id);

      await branchService.cloneFromSnapshot(snapshot);

      // 复制：角色条目集合翻倍（快照条目被写为独立新行）。
      final after = await lorebookRepo.listEntries(char.id);
      expect(after, hasLength(4));
      final copies = [
        for (final e in after)
          if (e.id > maxIdBefore) e,
      ];
      expect(copies, hasLength(2));
      expect(copies.map((e) => e.title).toList(), containsAll(['条目0', '条目1']));
      expect(copies.map((e) => e.order).toList(), containsAll([10, 11]));

      // 互不影响：改新会话复制行 → 源行原样。
      final sourceRow = before.first;
      final copyRow = copies.first;
      expect(copyRow.title, sourceRow.title);
      await lorebookRepo.updateEntry(
        copyRow.id,
        LorebookEntriesCompanion(content: const Value('改过的复制')),
      );
      final refreshedSource = await lorebookRepo
          .listEntries(char.id)
          .then((rows) => rows.firstWhere((e) => e.id == sourceRow.id));
      expect(refreshedSource.content, '内容0', reason: '改新会话复制行不污染源行（独立行断言）');
    });
  });

  group('branchFromMessage · 锚消息分支（验收 5）', () {
    test('新会话消息序列 = 源截断含锚；源会话零改动；父/锚记录', () async {
      final char = await seedCharacter();
      final (conv, ids) = await seedSourceWith(char.id);
      final anchorId = ids[1]; // 第一轮答

      final branch = await branchService.branchFromMessage(
        conv.id,
        anchorId,
        title: '雪夜分叉',
      );

      // 新会话消息序列与源（截断含锚后）逐条一致。
      expect(branch.id, isNot(conv.id));
      expect(branch.characterId, char.id);
      final branchMessages = await messagesOf(branch.id);
      expect(branchMessages.map((m) => m.content).toList(), ['第一轮问', '第一轮答']);
      expect(branchMessages.map((m) => m.role.value).toList(), [
        'user',
        'assistant',
      ]);

      // 父/锚/分支名记录。
      expect(branch.parentConversationId, conv.id);
      expect(branch.branchFromMessageId, anchorId);
      expect(branch.branchTitle, '雪夜分叉');

      // 源会话零改动（消息数与内容断言 + 候选原样）。
      final sourceAfter = await messagesOf(conv.id);
      expect(sourceAfter.map((m) => m.content).toList(), [
        '第一轮问',
        '第一轮答',
        '第二轮问',
        '重写答',
      ]);
      expect(
        sourceAfter.map((m) => m.id).toList(),
        ids,
        reason: '源消息无新增/删除/替换',
      );
      expect(
        (await msgRepo.listSwipes(ids[3])).map((s) => s.content).toList(),
        ['第二轮答', '重写答'],
        reason: '源候选原样',
      );
      // 源对话三引用列仍为空（分支元数据只写在新会话）。
      final sourceReload = await convRepo.getConversation(conv.id);
      expect(sourceReload!.parentConversationId, isNull);
      expect(sourceReload.branchFromMessageId, isNull);
    });

    test('未传 title → branchTitle 为 null，新会话标题 = 快照标题', () async {
      final char = await seedCharacter();
      final (conv, ids) = await seedSourceWith(char.id);

      final branch = await branchService.branchFromMessage(conv.id, ids[1]);

      expect(branch.branchTitle, isNull);
      expect(branch.title, '源对话');
      expect(branch.parentConversationId, conv.id);
    });

    test('分支路径世界书条目复制互不影响（cloneFromSnapshot 组合继承）', () async {
      final char = await seedCharacter();
      final (conv, ids) = await seedSourceWith(char.id, lorebookCount: 2);
      final before = await lorebookRepo.listEntries(char.id);

      await branchService.branchFromMessage(conv.id, ids[1], title: '雪夜分叉');

      final after = await lorebookRepo.listEntries(char.id);
      expect(after, hasLength(4), reason: '分支快照含世界书条目 → 复制为独立行（互不影响）');
      // 源条目内容未被改写。
      expect(after.firstWhere((e) => e.id == before.first.id).content, '内容0');
    });

    test('锚消息不存在 → MessageNotFoundError', () async {
      final char = await seedCharacter();
      final (conv, _) = await seedSourceWith(char.id);

      await expectLater(
        branchService.branchFromMessage(conv.id, 999999),
        throwsA(isA<MessageNotFoundError>()),
      );
    });

    test('锚消息属于其他对话 → MessageNotFoundError（不得跨会话分支）', () async {
      final char = await seedCharacter();
      final (convA, idsA) = await seedSourceWith(char.id);
      final (convB, _) = await seedSourceWith(char.id);

      await expectLater(
        branchService.branchFromMessage(convB.id, idsA[0]),
        throwsA(isA<MessageNotFoundError>()),
      );
      expect(convA.id, isNot(convB.id));
    });

    test('源会话不存在 → ConversationNotFoundError', () async {
      await expectLater(
        branchService.branchFromMessage(999999, 1),
        throwsA(isA<ConversationNotFoundError>()),
      );
    });
  });

  group('删源会话 · 置空策略锁定（验收 7）', () {
    test('删源会话不连坐已派生分支：parent/锚置空、branchTitle 保留、分支消息完好', () async {
      final char = await seedCharacter();
      final (conv, ids) = await seedSourceWith(char.id);
      final child = await branchService.branchFromMessage(
        conv.id,
        ids[1],
        title: '雪夜分叉',
      );

      final deleted = await convRepo.deleteConversation(conv.id);
      expect(deleted, isTrue);

      // 分支存活，引用置空（明示策略：parent/锚 → NULL；branch_title 保留）。
      final childReload = await convRepo.getConversation(child.id);
      expect(childReload, isNotNull);
      expect(childReload!.parentConversationId, isNull);
      expect(childReload.branchFromMessageId, isNull);
      expect(childReload.branchTitle, '雪夜分叉');
      expect((await messagesOf(child.id)).map((m) => m.content).toList(), [
        '第一轮问',
        '第一轮答',
      ]);
    });

    test('普通会话删除零副作用：无派生分支时 NULL 置空语句为空操作', () async {
      final char = await seedCharacter();
      final (conv, _) = await seedSourceWith(char.id);

      expect(await convRepo.deleteConversation(conv.id), isTrue);
      expect(await convRepo.getConversation(conv.id), isNull);
    });
  });

  group('exportSnapshot · 快照文件导出产物（BR-02 文件 seam 消费面）', () {
    test('导出 JSON 载荷含版本/消息/世界书/候选 + 文件名 {title}-branch.json', () async {
      final char = await seedCharacter(name: '艾莉亚');
      final (conv, _) = await seedSourceWith(char.id, lorebookCount: 1);

      final result = await branchService.exportSnapshot(conv.id);

      expect(result!.fileName, '源对话-branch.json');
      final decoded = BranchSnapshot.fromJson(jsonDecode(result.content));
      expect(decoded.version, snapshotVersion);
      expect(decoded.title, '源对话');
      expect(decoded.lorebookEntries, hasLength(1));
      expect(decoded.swipes.single.swipes, ['第二轮答', '重写答']);
    });

    test('导出截断形态：uptoMessageId 含锚、不含锚后', () async {
      final char = await seedCharacter();
      final (conv, ids) = await seedSourceWith(char.id);

      final result = await branchService.exportSnapshot(
        conv.id,
        uptoMessageId: ids[1],
      );

      final decoded = BranchSnapshot.fromJson(jsonDecode(result!.content));
      expect(decoded.messages.map((m) => m.content).toList(), ['第一轮问', '第一轮答']);
    });

    test('对话不存在 → null（零副作用）', () async {
      expect(await branchService.exportSnapshot(999999), isNull);
    });
  });
}
