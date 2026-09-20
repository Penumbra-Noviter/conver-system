/// 分支服务（BR-01）— 分支快照构建 / 快照克隆 / 锚消息分支 + 快照文件导出。
///
/// 语义锚点（只读，逐字对齐）：
/// - `desktop/backend/app/services/conversation_export.py::build_branch_snapshot`
///   （截断锚含该消息；消息 id 升序 = 插入序稳定序；swipes 的 message_index
///   指向快照内数组下标；无候选消息不产出候选条目）
/// - `desktop/backend/app/services/conversation.py::clone_conversation`
///   （重建：消息按快照序 role/content/created_at 保真；候选与激活序号直接
///   落库；防御矩阵——非法角色 / message_index 越界 / 激活序号越界 /
///   content≠激活候选即拒）
/// - `desktop/backend/app/services/conversation.py::branch_from_message`
///   （编排：校验源 + 锚 → 截断快照 → clone → 记录 parent / branch_from_
///   message_id / branch_title）
///
/// 移动端有意偏差（BR-01 工单验收 6 驱动，concerns/18.md 记录）：
/// 世界书条目**复制为独立新行**（互不影响——改新会话条目不污染源行）；
/// 桌面共享角色模型不重插为「条目集合不变」，移动端以独立行断言锁定复制语义。
///
/// 快照文件导出复用既有文件 seam（M4）：本服务产出
/// [ConversationExportResult]（fileName + JSON content），平台写入/分享仍走
/// [ConversationExportFileExchange.exportFile]——`conversation_export_service`
/// 的对话导出已含候选集（MS-01，SR-29），本票按「最小扩展」不再改动其文件。
library;

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（构造语义由下方 docstring 说明；同
// conversation_export_service.dart 先例）。
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../data/database/app_database.dart'
    show
        AppDatabase,
        Conversation,
        ConversationsCompanion,
        LorebookEntry,
        Message,
        MessagesCompanion,
        MessageSwipesCompanion;
import '../../data/database/tables.dart';
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/lorebook_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../conversation_export_service.dart' show ConversationExportResult;
import '../file_name.dart' show safeFileName;
import '../llm/errors.dart';
import 'branch_snapshot.dart';

/// 分支服务 — [buildBranchSnapshot] / [cloneFromSnapshot] /
/// [branchFromMessage] 三法 + [exportSnapshot] 文件导出。
///
/// 服务层编排（消费四仓储只读面 + 数据库事务重建），不触碰 UI / 平台通道。
class BranchService {
  /// [database] 为消息/候选重建的事务落库面（cloneFromSnapshot 直接写行——
  /// 快照定义全部消息，不走 [MessageRepository.createMessage] 的自动命名 /
  /// 开场白副作用）；[now] 为时间戳来源注入点（测试确定性用）。
  BranchService({
    required AppDatabase database,
    required ConversationRepository conversationRepository,
    required CharacterRepository characterRepository,
    required MessageRepository messageRepository,
    required LorebookRepository lorebookRepository,
    DateTime Function()? now,
  }) : _database = database,
       _conversationRepository = conversationRepository,
       _characterRepository = characterRepository,
       _messageRepository = messageRepository,
       _lorebookRepository = lorebookRepository,
       _now = now ?? DateTime.now;

  final AppDatabase _database;
  final ConversationRepository _conversationRepository;
  final CharacterRepository _characterRepository;
  final MessageRepository _messageRepository;
  final LorebookRepository _lorebookRepository;
  final DateTime Function() _now;

  /// 构建分支快照（版本化导出；BR-1，spec §4.7）。
  ///
  /// 载荷：`{version, character_id, model_provider, model_name, title,
  /// messages, lorebook_entries, swipes}`——世界书条目随存档走（角色级
  /// 全量），候选与激活序号随消息走。消息按 **id 升序**（id=插入序；
  /// created_at 为秒精度、同秒多条时排序不可靠，快照/重建的稳定序以 id
  /// 为准，桌面 ORDER BY Message.id.asc() 逐字）；swipes 的 message_index
  /// 指向截断后 messages 数组下标（新会话重建后 id 变化，以序号锚定）。
  ///
  /// [uptoMessageId] 截断锚消息 id（**含**；快照末条）；None → 全量。锚
  /// 不存在或不属于该对话 → [MessageNotFoundError]（禁止静默空快照）；
  /// 对话不存在 → [ConversationNotFoundError]。
  Future<BranchSnapshot> buildBranchSnapshot(
    int conversationId, {
    int? uptoMessageId,
  }) async {
    final conversation = await _conversationRepository.getConversation(
      conversationId,
    );
    if (conversation == null) {
      throw ConversationNotFoundError();
    }
    if (uptoMessageId != null) {
      final anchor = await _messageRepository.messageById(
        conversationId,
        uptoMessageId,
      );
      if (anchor == null) {
        throw MessageNotFoundError();
      }
    }

    final messages = await _messageRepository.getMessages(conversationId);
    messages.sort((a, b) => a.id.compareTo(b.id));
    final truncated = uptoMessageId == null
        ? messages
        : [
            for (final message in messages)
              if (message.id <= uptoMessageId) message,
          ];

    final swipes = <BranchSnapshotSwipe>[];
    for (var index = 0; index < truncated.length; index++) {
      final candidates = await _messageRepository.listSwipes(
        truncated[index].id,
      );
      if (candidates.isEmpty) {
        continue; // 无候选消息不产出候选条目（重建回落 active=0）。
      }
      swipes.add(
        BranchSnapshotSwipe(
          messageIndex: index,
          swipes: [for (final candidate in candidates) candidate.content],
          activeSwipeIndex: truncated[index].activeSwipeIndex,
        ),
      );
    }

    final entries = await _lorebookRepository.listEntries(
      conversation.characterId,
    );

    return BranchSnapshot(
      version: snapshotVersion,
      characterId: conversation.characterId,
      modelProvider: conversation.modelProvider,
      modelName: conversation.modelName,
      title: conversation.title,
      messages: [
        for (final message in truncated)
          BranchSnapshotMessage(
            role: message.role.value,
            content: message.content,
            createdAt: message.createdAt,
          ),
      ],
      lorebookEntries: [for (final entry in entries) _entryToSnapshot(entry)],
      swipes: swipes,
    );
  }

  /// 从分支快照重建会话（BR-2：导入 / 分支共用）。
  ///
  /// 新会话：character_id 复用快照角色；[title] 显式优先、否则快照标题
  /// （再缺省角色占位标题）；model_provider / model_name 走快照值（缺省
  /// 由 ConversationRepository 回退设置/常量）；消息按快照序重建（role /
  /// content / created_at 往返保真——候选 0 = 原始内容，content 恒等于激活
  /// 候选）；世界书条目**复制为独立新行**（互不影响，验收 6）。
  ///
  /// 防御校验（契约锁锁定，手写快照破坏不变量即拒，桌面 clone 防御矩阵
  /// 对应物）：快照角色必须存在（[CharacterNotFoundError]）；消息角色合法
  /// （[InvalidBranchSnapshotError]）；message_index < 消息数、激活序号在
  /// 候选范围内、content == 激活候选（快照不变量）。
  Future<Conversation> cloneFromSnapshot(
    BranchSnapshot snapshot, {
    String? title,
  }) {
    return _database.transaction(() async {
      final character = await _characterRepository.getCharacter(
        snapshot.characterId,
      );
      if (character == null) {
        throw CharacterNotFoundError(snapshot.characterId);
      }

      final conversation = await _conversationRepository.createConversation(
        characterId: snapshot.characterId,
        title: title ?? snapshot.title,
        modelProvider: snapshot.modelProvider,
        modelName: snapshot.modelName,
        // 快照定义全部消息，禁用开场白预插（显式空串三态）。
        greeting: '',
      );

      final rebuilt = <Message>[];
      for (final item in snapshot.messages) {
        final role = _roleOf(item.role);
        final message = await _database
            .into(_database.messages)
            .insertReturning(
              MessagesCompanion.insert(
                conversationId: conversation.id,
                role: role,
                content: item.content,
                createdAt: item.createdAt ?? _now(),
              ),
            );
        rebuilt.add(message);
      }

      // 候选与激活序号直接落库（不走 addSwipe：播种语义假设 content 即
      // 候选 0，桌面 clone L313 逐字）。
      for (final entry in snapshot.swipes) {
        if (entry.messageIndex >= rebuilt.length) {
          throw InvalidBranchSnapshotError(
            '快照候选 message_index 越界: ${entry.messageIndex}',
          );
        }
        final target = rebuilt[entry.messageIndex];
        if (entry.swipes.isEmpty) {
          continue; // 空候选条目无操作（重建回落 active=0，候选清空退化态）。
        }
        if (entry.activeSwipeIndex >= entry.swipes.length) {
          throw InvalidBranchSnapshotError(
            '快照激活序号越界: ${entry.activeSwipeIndex}'
            '（候选仅 ${entry.swipes.length} 条）',
          );
        }
        if (target.content != entry.swipes[entry.activeSwipeIndex]) {
          throw InvalidBranchSnapshotError('快照消息内容与激活候选不一致（content 须跟随激活候选）');
        }
        final now = _now();
        for (var index = 0; index < entry.swipes.length; index++) {
          await _database
              .into(_database.messageSwipes)
              .insert(
                MessageSwipesCompanion.insert(
                  messageId: target.id,
                  index: index,
                  content: entry.swipes[index],
                  createdAt: now,
                ),
              );
        }
        await (_database.update(
          _database.messages,
        )..where((t) => t.id.equals(target.id))).write(
          MessagesCompanion(
            content: Value(entry.swipes[entry.activeSwipeIndex]),
            activeSwipeIndex: Value(entry.activeSwipeIndex),
          ),
        );
      }

      // 世界书条目复制互不影响（BR-01 验收 6，独立行断言）：快照条目写为
      // 目标角色下的新行——改新会话复制行不污染源行。
      for (final entry in snapshot.lorebookEntries) {
        await _lorebookRepository.createEntry(
          snapshot.characterId,
          _snapshotToDraft(entry),
        );
      }

      return conversation;
    });
  }

  /// 从源会话的锚消息处派生分支会话（BR-2，spec §BR-2）。
  ///
  /// 编排：校验源会话 + 锚消息（存在 / 属于该会话，否则明确异常）→ 截断快照
  /// （含锚）→ clone（消息/候选重建 + 世界书条目复制互不影响）→ 记录
  /// parent_conversation_id / branch_from_message_id / branch_title（分支
  /// 显示名）→ 返回新会话。源会话零改动（仅读 + 新会话落库）。
  ///
  /// [title] 分支显示名（进入 branch_title 与新会话标题；None → branch_title
  /// 为 null、标题走快照标题）。
  Future<Conversation> branchFromMessage(
    int conversationId,
    int messageId, {
    String? title,
  }) async {
    final conversation = await _conversationRepository.getConversation(
      conversationId,
    );
    if (conversation == null) {
      throw ConversationNotFoundError();
    }
    final anchor = await _messageRepository.messageById(
      conversationId,
      messageId,
    );
    if (anchor == null) {
      throw MessageNotFoundError();
    }

    final snapshot = await buildBranchSnapshot(
      conversationId,
      uptoMessageId: messageId,
    );
    final branch = await cloneFromSnapshot(snapshot, title: title);

    final updated = await _conversationRepository.updateConversation(
      branch.id,
      ConversationsCompanion(
        parentConversationId: Value(conversationId),
        branchFromMessageId: Value(messageId),
        branchTitle: Value(title),
      ),
    );
    if (updated == null) {
      throw StateError('分支会话 ${branch.id} 在同一事务路径中消失');
    }
    return updated;
  }

  /// 导出分支快照为文件 JSON（复用既有文件 seam——[ConversationExportResult]
  /// 值对象 + [ConversationExportFileExchange.exportFile] 平台写入/分享）。
  ///
  /// 文件名 `{safeFileName(title)}-branch.json`（BR-02 入口契约）；对话不存在
  /// → null（零副作用）；[uptoMessageId] 语义与 [buildBranchSnapshot] 一致。
  Future<ConversationExportResult?> exportSnapshot(
    int conversationId, {
    int? uptoMessageId,
  }) async {
    final conversation = await _conversationRepository.getConversation(
      conversationId,
    );
    if (conversation == null) {
      return null;
    }
    final snapshot = await buildBranchSnapshot(
      conversationId,
      uptoMessageId: uptoMessageId,
    );
    return ConversationExportResult(
      fileName: '${safeFileName(conversation.title)}-branch.json',
      content: jsonEncode(snapshot.toJson()),
    );
  }

  // ── 内部 ──

  /// 快照角色字符串 → [Role]（非法 → [InvalidBranchSnapshotError]，桌面
  /// clone L298-301 逐字——解析层与重建层双道防线）。
  Role _roleOf(String role) {
    for (final candidate in Role.values) {
      if (candidate.value == role) {
        return candidate;
      }
    }
    throw InvalidBranchSnapshotError('快照消息角色无效: $role');
  }

  /// 世界书条目行 → 快照条目（重建用全部内容字段）。
  BranchSnapshotLorebookEntry _entryToSnapshot(LorebookEntry entry) {
    return BranchSnapshotLorebookEntry(
      title: entry.title,
      keys: entry.keys,
      content: entry.content,
      constant: entry.constant,
      order: entry.order,
      probability: entry.probability,
      groupName: entry.groupName,
      groupWeight: entry.groupWeight,
      matchMode: entry.matchMode,
      position: entry.position,
      depth: entry.depth,
      source: entry.source,
      enabled: entry.enabled,
    );
  }

  /// 快照条目 → 落库草案（字段一一对应，character_id 由调用方设置）。
  LorebookEntryDraft _snapshotToDraft(BranchSnapshotLorebookEntry entry) {
    return LorebookEntryDraft(
      title: entry.title,
      keys: entry.keys,
      content: entry.content,
      constant: entry.constant,
      order: entry.order,
      probability: entry.probability,
      groupName: entry.groupName,
      groupWeight: entry.groupWeight,
      matchMode: entry.matchMode,
      position: entry.position,
      depth: entry.depth,
      source: entry.source,
      enabled: entry.enabled,
    );
  }
}
