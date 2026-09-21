/// 消息仓储 — CRUD + create 副作用 + 锚定截断 + swipes 候选，语义与桌面
/// message 服务逐条对齐。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/message.py`
///
/// 对齐要点：
/// - create_message 蓝本内建副作用：消息落库同时前移所属对话 `updated_at`；
///   保存首条 user 消息时若标题仍为占位默认值则替换为规则截断标题；
/// - 判定时序复刻桌面（源码显式注释防 autoflush 把本条计入）：既有 user
///   消息查询与占位标题比对发生在本条插入**之前**；判定、标题替换、
///   时间戳前移与消息插入同事务原子完成（工单 05 指定顺序：
///   查 → 改标题 → 改 conv.updated_at → 插消息）；
/// - 占位标题比对复用 [defaultConversationTitle]（工单 03 标题策略单一实现，
///   不另写第二份规则）：按当前角色名计算占位值，角色缺失走
///   「与 角色 的对话」分支，与桌面 `default_conversation_title` 语义一致；
/// - 列表按 `created_at` 正序、同秒以 `id` 兜底（F-3 unix 秒精度假设，
///   spec Further Notes；桌面仅 `created_at asc`）；
/// - delete_messages_from：删除 `id >= target`（含）并返回条数，**不**前移
///   对话 `updated_at`（桌面注释「仅 create_message 会更新时间戳」）；
/// - 对话不存在时副作用全跳过（桌面 `if conv:` 守卫）；移动端 FK ON 下
///   消息插入将被外键约束拒绝——孤儿消息在移动端语义中不存在
///   （spec 级联节：依赖 M0 外键 CASCADE + `PRAGMA foreign_keys = ON`）；
/// - 时间戳全部由本层赋值（drift 列无 DB 默认）。
///
/// swipes 对齐要点（MS-01，chat-polish spec §4.2）：
/// - add_swipe 首次播种候选 0 = 消息当前 content（桌面 L378-381），新候选
///   index = max+1（L382：删中间留空档后不碰撞）；make_active=True 同步覆写
///   messages.content 与 active_swipe_index（L384-387）——`messages.content`
///   恒为「当前激活候选」，既有读面零改动取 active 内容；
/// - switch_swipe 越界抛 [SwipeIndexOutOfRangeError]（桌面 SwipeIndexError），
///   合法切换覆写 content + active（L495-496）；
/// - delete_swipe 删当前激活候选回落「小于被删 index 的最大现存，否则大于的
///   最小现存」（L536）+ content 跟随回落候选；**移动端有意偏差**：桌面候选 0
///   受保护拒删（L515-516），移动端允许删空候选集 → active 回落 0 锁定、
///   content 保留消息本体（工单验收 4/5，详见 concerns/01.md §3）；
/// - 消息/候选删除的级联由 FK CASCADE + PRAGMA foreign_keys=ON 承保。
library;

import 'package:drift/drift.dart';

import '../../services/llm/errors.dart';
import '../database/app_database.dart';
import '../database/tables.dart';
import 'conversation_repository.dart';

/// 规则截断对话标题（纯函数，桌面 `conversation.truncate_title` 对应物）。
///
/// 折叠所有空白为单空格并去首尾；[maxLen] 字内原样返回，否则取前 [maxLen]
/// 字加「…」。不剥离 Markdown（原样截断字符）。
///
/// 长度按 Unicode 码点计（桌面 Python `len` 语义），经 [String.runes]
/// 切分，避免 UTF-16 代理对在截断点被劈开（如 emoji）。
String truncateTitle(String text, {int maxLen = 20}) {
  final collapsed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.runes.length <= maxLen) {
    return collapsed;
  }
  return '${String.fromCharCodes(collapsed.runes.take(maxLen))}…';
}

/// 消息搜索命中行 — 消息 + 所属对话 + 角色三表 join 上下文
/// （桌面 `search_messages` 的 `(Message, Conversation, Character)` 行元组
/// 对应物；服务层经 [SearchService] 映射为 `SearchResult` 契约）。
class MessageSearchHit {
  const MessageSearchHit({
    required this.message,
    required this.conversation,
    required this.character,
  });

  /// 命中消息行（`content` 为全文）。
  final Message message;

  /// 所属对话行（`title` 为对话标题）。
  final Conversation conversation;

  /// 对话所属角色行（`name` / `avatar` 供结果展示）。
  final Character character;
}

/// 消息仓储 — 表面与桌面 message 服务对应
/// （get_messages / create_message / delete_messages_from / search_messages；
/// build_message_list 归 M2，不在此实现）。
class MessageRepository {
  /// [now] 为时间戳来源注入点（测试确定性用），缺省 [DateTime.now]。
  MessageRepository(this._db, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  /// 对话的全部消息，按 `created_at` 正序、同秒以 `id` 兜底
  /// （桌面 get_messages + F-3 同秒兜底）。
  Future<List<Message>> getMessages(int conversationId) {
    return (_db.select(_db.messages)
          ..where(($MessagesTable t) => t.conversationId.equals(conversationId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  /// 该角色全部对话（conversations 按 [characterId] 过滤）中消息 `createdAt`
  /// 的全局最大值（判定⑨「最近消息」口径：角色最近活跃时间）。
  ///
  /// 单条 join 查询（messages ↔ conversations）完成，非逐对话循环；该角色
  /// 无任何消息时返回 null。伴侣域活跃时间判定（RelationshipService /
  /// ProactiveMessageService）统一经本方法取口径单源（F-81）。
  ///
  /// 索引加速（F-95，schemaVersion=4）：`idx_messages_created_at` 服务本条
  /// `ORDER BY created_at DESC LIMIT 1`，SQL 形态与结果语义不变。
  /// 秒精度为 F-3 既定契约（drift INTEGER 秒存储，亚秒截断）：索引加速
  /// 不改变精度语义，窗口/天粒度判定不受影响。
  Future<DateTime?> latestMessageAt(int characterId) async {
    final rows = await (_db.select(_db.messages).join([
          innerJoin(
            _db.conversations,
            _db.conversations.id.equalsExp(_db.messages.conversationId),
          ),
        ])
          ..where(_db.conversations.characterId.equals(characterId))
          ..orderBy([OrderingTerm.desc(_db.messages.createdAt)])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first.readTable(_db.messages).createdAt;
  }

  /// 跨全部对话的消息 content 模糊检索（桌面 `search_messages` 对应物）。
  ///
  /// - **仅匹配 `messages.content` 子串**（不搜角色名 / 对话标题 / 开场白，
  ///   对齐桌面 `Message.content.ilike` 契约）；
  /// - 空串 / 纯空白查询 → 空列表（不抛错、零查询短路）；
  /// - SQLite LIKE 对 ASCII 大小写不敏感、对中文按字节子串匹配——与桌面
  ///   ILIKE 可观察等价；
  /// - 三表 join（messages + conversations + characters）携带对话标题 /
  ///   角色上下文；排序 `created_at` 倒序、同秒以 `id` 倒序兜底；[limit]
  ///   截断（缺省 50）。
  Future<List<MessageSearchHit>> searchMessages(
    String query, {
    int limit = 50,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final pattern = '%$trimmed%';
    final stmt = _db.select(_db.messages).join([
      innerJoin(
        _db.conversations,
        _db.conversations.id.equalsExp(_db.messages.conversationId),
      ),
      innerJoin(
        _db.characters,
        _db.characters.id.equalsExp(_db.conversations.characterId),
      ),
    ])
      ..where(_db.messages.content.like(pattern))
      ..orderBy([
        OrderingTerm.desc(_db.messages.createdAt),
        OrderingTerm.desc(_db.messages.id),
      ])
      ..limit(limit);
    final rows = await stmt.get();
    return [
      for (final row in rows)
        MessageSearchHit(
          message: row.readTable(_db.messages),
          conversation: row.readTable(_db.conversations),
          character: row.readTable(_db.characters),
        ),
    ];
  }

  /// 保存单条消息（桌面 create_message 蓝本内建副作用）：
  ///
  /// - 消息时间戳由本层赋值（[now] 注入）；
  /// - 所属对话存在时前移其 `updated_at`；
  /// - [role] 为 [Role.user] 且 [content] 非空时，在插入本条**之前**判定
  ///   自动命名：此前无任何 user 消息且标题仍等于占位默认值
  ///   （按当前角色名经 [defaultConversationTitle] 计算）→ 以
  ///   [truncateTitle] 截断 [content] 替换标题；否则不动
  ///   （不覆盖非首条之后已定的标题，不覆盖显式命名的标题）。
  ///
  /// 判定、标题替换、时间戳前移与消息插入同事务原子完成。
  Future<Message> createMessage({
    required int conversationId,
    required Role role,
    required String content,
  }) {
    return _db.transaction(() async {
      final conv = await (_db.select(_db.conversations)
            ..where(($ConversationsTable t) => t.id.equals(conversationId)))
          .getSingleOrNull();
      final at = _now();

      if (conv != null) {
        // 桌面判定时序：先查既有 user 消息与占位标题（在本条插入之前），
        // 防止把本条计入已有消息（桌面源码 autoflush 注释）。
        if (role == Role.user && content.isNotEmpty) {
          final existingUser = await (_db.select(_db.messages)
                ..where(($MessagesTable t) =>
                    t.conversationId.equals(conversationId))
                ..where(($MessagesTable t) => t.role.equalsValue(Role.user))
                ..limit(1))
              .getSingleOrNull();
          if (existingUser == null) {
            final character = await (_db.select(_db.characters)
                  ..where(
                      ($CharactersTable t) => t.id.equals(conv.characterId)))
                .getSingleOrNull();
            if (conv.title == defaultConversationTitle(character?.name)) {
              await (_db.update(_db.conversations)
                    ..where(($ConversationsTable t) =>
                        t.id.equals(conversationId)))
                  .write(ConversationsCompanion(
                      title: Value(truncateTitle(content))));
            }
          }
        }

        // 桌面 create_message 副作用：消息落库同时前移对话 updated_at。
        await (_db.update(_db.conversations)
              ..where(($ConversationsTable t) => t.id.equals(conversationId)))
            .write(ConversationsCompanion(updatedAt: Value(at)));
      }

      final message = await _db.into(_db.messages).insertReturning(
            MessagesCompanion.insert(
              conversationId: conversationId,
              role: role,
              content: content,
              createdAt: at,
            ),
          );
      return message;
    });
  }

  /// 锚定截断（桌面 delete_messages_from）：删除 [conversationId] 内
  /// `id >= targetId` 的全部消息（含 target），返回删除条数。
  ///
  /// [toId] 非空时删除上界收敛为 `id <= toId`（F1 有界删除：重生成网络期间
  /// 并发写入的新消息 id 大于快照上界，必须保留，防静默数据丢失）。
  /// **不**前移对话 `updated_at`；越界 target（无消息满足）返回 0 且零副作用；
  /// 其他对话的消息不受影响。单条 DELETE 语句自身原子，无需显式事务
  /// （桌面为不提交变体、由调用方收尾，M1 无事务级调用方）。
  Future<int> deleteMessagesFrom(int conversationId, int targetId, {int? toId}) {
    final query = _db.delete(_db.messages)
      ..where(($MessagesTable t) => t.conversationId.equals(conversationId))
      ..where(($MessagesTable t) => t.id.isBiggerOrEqualValue(targetId));
    if (toId != null) {
      query.where(($MessagesTable t) => t.id.isSmallerOrEqualValue(toId));
    }
    return query.go();
  }

  /// 对话内当前最大消息 id；无消息返回 0（F1 快照语义辅助：重生成开始时捕获，
  /// 供有界删除上界）。
  Future<int> maxMessageId(int conversationId) async {
    final rows = await (_db.select(_db.messages)
          ..where(($MessagesTable t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .get();
    return rows.isEmpty ? 0 : rows.first.id;
  }

  /// 对话内末条 assistant 消息（缺省重生成目标，对齐桌面
  /// `_resolve_regenerate_target` 的 no-messageId 分支）。
  ///
  /// 单值读 `ORDER BY created_at DESC, id DESC LIMIT 1`——与「全量正序 +
  /// reversed 遍历取首个 assistant」逐位等价（含同秒 id 兜底，F-106 先例）；
  /// 无匹配（无消息 / 无 assistant）返回 null。
  Future<Message?> lastAssistantMessage(int conversationId) async {
    final rows = await (_db.select(_db.messages)
          ..where(($MessagesTable t) =>
              t.conversationId.equals(conversationId))
          ..where(($MessagesTable t) => t.role.equalsValue(Role.assistant))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// 对话内 [beforeId] 之前最近的一条 user 消息（重生成触发源，对齐桌面
  /// `_last_user_before`）。
  ///
  /// 判定语义与既有 `_lastUserBefore` 逐位等价：`role == user` 且 `id <
  /// beforeId` 的正序序列末条 = 倒序序列首条，故单值读
  /// `WHERE role='user' AND id < beforeId ORDER BY created_at DESC, id DESC
  /// LIMIT 1`（id 为自增主键，`id < beforeId` 即「该行之前」；同秒 id 兜底）。
  /// 无匹配返回 null。
  Future<Message?> lastUserMessageBefore(
    int conversationId,
    int beforeId,
  ) async {
    final rows = await (_db.select(_db.messages)
          ..where(($MessagesTable t) =>
              t.conversationId.equals(conversationId))
          ..where(($MessagesTable t) => t.role.equalsValue(Role.user))
          ..where(($MessagesTable t) => t.id.isSmallerThanValue(beforeId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// 对话内 [beforeId] 之前的全部消息，`ORDER BY created_at ASC, id ASC`
  /// 正序序列（与 [getMessages] 同序，buildMessages 滑窗依赖保持）。
  ///
  /// [beforeId] 为开区间上界（`id < beforeId`，不含目标行及其后）；无匹配
  /// 返回空列表。不下推滑窗——maxRounds 为「轮」语义非条数，保持服务层 →
  /// buildMessages 纯函数边界（S6 共识）。
  Future<List<Message>> messagesBefore(
    int conversationId,
    int beforeId,
  ) {
    return (_db.select(_db.messages)
          ..where(($MessagesTable t) =>
              t.conversationId.equals(conversationId))
          ..where(($MessagesTable t) => t.id.isSmallerThanValue(beforeId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  /// 显式 id 定位 + 对话归属校验（重生成显式 messageId 分支）。
  ///
  /// 仅当 [messageId] 属于 [conversationId] 时返回该行；id 不存在或属于
  /// 其他对话（跨对话同 id）一律返回 null——归属校验不抛错、不外泄他对话
  /// 行。查询异常上抛（仓库不吞错）。
  Future<Message?> messageById(int conversationId, int messageId) {
    return (_db.select(_db.messages)
          ..where(($MessagesTable t) => t.conversationId.equals(conversationId))
          ..where(($MessagesTable t) => t.id.equals(messageId)))
        .getSingleOrNull();
  }

  /// 对话内末条消息（chat_round 末条读下推）。
  ///
  /// 单值读 `ORDER BY created_at DESC, id DESC LIMIT 1`（同秒 id 兜底，
  /// F-106 先例）；无消息返回 null。调用方保留查询异常吞并语义（尽力而为
  /// 标记判定），仓库不吞错。
  Future<Message?> lastMessage(int conversationId) async {
    final rows = await (_db.select(_db.messages)
          ..where(($MessagesTable t) => t.conversationId.equals(conversationId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  // ── swipes 候选（MS-01；桌面 message.py add_swipe/switch_swipe/delete_swipe
  //    逐字对齐，有意偏差见文件头 docstring）──

  /// 为消息追加候选（桌面 `add_swipe` 对应物，L346-390 逐字）。
  ///
  /// - 首次追加（候选集为空）先播种候选 0 = 消息当前 `content`（原始回复，
  ///   L378-381），新候选从 index 1 起递增；此后 index = max+1（L382：删中间
  ///   候选留空档后不碰撞）；
  /// - [makeActive] 缺省 true：同步覆写 `messages.content` 与
  ///   `active_swipe_index`（L384-387）——content 恒为当前激活候选；
  /// - 消息不存在抛 [MessageNotFoundError]（桌面 `_require_message`）。
  ///
  /// 返回新候选 index（首次追加返回 1）。
  Future<int> addSwipe(
    int messageId,
    String content, {
    bool makeActive = true,
  }) {
    return _db.transaction(() async {
      final msg = await _requireMessage(messageId);
      final maxRow = await (_db.select(_db.messageSwipes)
            ..where(($MessageSwipesTable t) => t.messageId.equals(messageId))
            ..orderBy([(t) => OrderingTerm.desc(t.index)])
            ..limit(1))
          .get();
      final maxIndex = maxRow.isEmpty ? null : maxRow.first.index;
      if (maxIndex == null) {
        await _db.into(_db.messageSwipes).insert(
              MessageSwipesCompanion.insert(
                messageId: messageId,
                index: 0,
                content: msg.content,
                createdAt: _now(),
              ),
            );
      }
      final nextIndex = (maxIndex ?? 0) + 1;
      await _db.into(_db.messageSwipes).insert(
            MessageSwipesCompanion.insert(
              messageId: messageId,
              index: nextIndex,
              content: content,
              createdAt: _now(),
            ),
          );
      if (makeActive) {
        await _writeActive(messageId, content: content, index: nextIndex);
      }
      return nextIndex;
    });
  }

  /// 消息候选列表（index 升序；无候选返回空列表——既有消息零回归）。
  Future<List<MessageSwipe>> listSwipes(int messageId) {
    return (_db.select(_db.messageSwipes)
          ..where(($MessageSwipesTable t) => t.messageId.equals(messageId))
          ..orderBy([(t) => OrderingTerm.asc(t.index)]))
        .get();
  }

  /// 批量候选拉取（F-142：drift `isIn` 单次查询，消 branch/export 逐消息 N+1）。
  ///
  /// - 一次查询覆盖 [messageIds] 全部候选行（无新 join、无 schema 变更），
  ///   每 messageId 子列表按 `index` 升序（与 [listSwipes] 同查询面同序）；
  /// - 消息无候选不在返回 map（消费方以 `?? const []` 兜底）；
  /// - 空输入短路返回 `const {}`（零查询，不触达 DB）。
  /// - 输入规模 bound：单条 SQL 变量数受引擎 `SQLITE_MAX_VARIABLE_NUMBER`
  ///   约束（SQLite ≥3.32 默认 32766，编译期可调低，本仓打包引擎按默认计）；
  ///   [messageIds] 长度须 ≤ 该上限——超限 drift 抛「too many SQL variables」
  ///   硬失败（区别于旧逐条 [listSwipes] 的慢不失败）；调用方负责保证规模
  ///   （branch/export 消费方输入均受单对话消息数约束，远低于上限）；
  ///   将来超规模由调用方自行分块，本方法不承担 chunking。
  Future<Map<int, List<MessageSwipe>>> listSwipesBatch(
      Iterable<int> messageIds) async {
    final ids = messageIds.toList();
    if (ids.isEmpty) {
      return const {};
    }
    final rows = await (_db.select(_db.messageSwipes)
          ..where(($MessageSwipesTable t) => t.messageId.isIn(ids))
          ..orderBy([(t) => OrderingTerm.asc(t.index)]))
        .get();
    final batch = <int, List<MessageSwipe>>{};
    for (final row in rows) {
      (batch[row.messageId] ??= []).add(row);
    }
    return batch;
  }

  /// 切换激活候选（桌面 `switch_swipe` 对应物，L471-499 逐字）。
  ///
  /// [index] 必须存在于该消息候选集，否则抛 [SwipeIndexOutOfRangeError]；
  /// 合法切换后 `messages.content` 覆写为选中候选内容、
  /// `active_swipe_index` 更新（L495-496）；消息不存在抛
  /// [MessageNotFoundError]。返回切换后的 [Message]。
  Future<Message> switchSwipe(int messageId, int index) async {
    await _requireMessage(messageId); // 存在性校验（不存在抛 MessageNotFoundError）
    final swipe = await _swipeOrNull(messageId, index);
    if (swipe == null) {
      throw SwipeIndexOutOfRangeError(index);
    }
    // 桌面 switch_swipe L495-496：content 覆写为选中候选 + index 更新。
    await _writeActive(messageId, content: swipe.content, index: index);
    return _requireMessage(messageId);
  }

  /// 删除候选（桌面 `delete_swipe` 对应物，L502-545；有意偏差见 docstring）。
  ///
  /// - [index] 不存在抛 [SwipeIndexOutOfRangeError]；消息不存在抛
  ///   [MessageNotFoundError]；
  /// - 删当前激活候选：回落到「小于被删 index 的最大现存，否则大于的最小
  ///   现存」（桌面 L536）+ content 同步跟随回落候选（L538-542）；
  /// - **移动端有意偏差**：桌面候选 0 受保护拒删（L515-516），本实现允许删
  ///   任意候选（含 0）；删空候选集后 active 回落 0 锁定、`messages.content`
  ///   保留消息本体（工单验收 4/5「候选清空回落 0」，concerns/01.md §3）；
  /// - 删非激活候选：active/content 不变。
  ///
  /// 返回删除后的 [Message]。
  Future<Message> deleteSwipe(int messageId, int index) {
    return _db.transaction(() async {
      final msg = await _requireMessage(messageId);
      final swipe = await _swipeOrNull(messageId, index);
      if (swipe == null) {
        throw SwipeIndexOutOfRangeError(index);
      }
      await (_db.delete(_db.messageSwipes)
            ..where(($MessageSwipesTable t) =>
                t.messageId.equals(messageId) & t.index.equals(index)))
          .go();

      if (msg.activeSwipeIndex != index) {
        return _requireMessage(messageId);
      }
      final remaining = await listSwipes(messageId);
      if (remaining.isEmpty) {
        // 候选清空退化态：active 回落 0 锁定，content 保留消息本体。
        await (_db.update(_db.messages)
              ..where(($MessagesTable t) => t.id.equals(messageId)))
            .write(const MessagesCompanion(activeSwipeIndex: Value(0)));
      } else {
        final lower = [
          for (final s in remaining)
            if (s.index < index) s,
        ];
        final fallback = lower.isNotEmpty ? lower.last : remaining.first;
        await _writeActive(messageId,
            content: fallback.content, index: fallback.index);
      }
      return _requireMessage(messageId);
    });
  }

  /// 单删一条消息（桌面 delete_message 的「删 assistant 单删该条」分支）。
  ///
  /// 返回是否真实删除（0 行 → false，零副作用）；候选随 FK CASCADE 级联删除
  /// （beforeOpen `PRAGMA foreign_keys = ON` 承保，测试锚 FK CASCADE 断言）。
  Future<bool> deleteMessage(int messageId) async {
    final count = await (_db.delete(_db.messages)
          ..where(($MessagesTable t) => t.id.equals(messageId)))
        .go();
    return count > 0;
  }

  /// 编辑重发数据原语（MS-03；桌面 `update_message` + 截断的组合对应物）：
  /// 就地替换 [messageId] 的 content，并物理删除同一对话内 `id > messageId`
  /// 的全部后续消息（候选随 FK CASCADE 级联删），单事务原子。
  ///
  /// [messageId] 必须属于 [conversationId] 且存在，否则抛
  /// [MessageNotFoundError]（强校验，零副作用——服务层编辑目标解析的
  /// 第二道归属防线）。替换只触碰 content（role / createdAt /
  /// activeSwipeIndex 不变）；编辑目标是 user 消息（无候选），故不处理候选行。
  ///
  /// 返回截断删除条数（被编辑 user 保留，仅删其后的消息）。
  Future<int> replaceAndTruncateFollowing({
    required int conversationId,
    required int messageId,
    required String content,
  }) {
    return _db.transaction(() async {
      final target = await (_db.select(_db.messages)
            ..where(($MessagesTable t) =>
                t.id.equals(messageId) &
                t.conversationId.equals(conversationId)))
          .getSingleOrNull();
      if (target == null) {
        throw MessageNotFoundError();
      }
      await (_db.update(_db.messages)
            ..where(($MessagesTable t) => t.id.equals(messageId)))
          .write(MessagesCompanion(content: Value(content)));
      return (_db.delete(_db.messages)
            ..where(($MessagesTable t) =>
                t.conversationId.equals(conversationId))
            ..where(($MessagesTable t) => t.id.isBiggerThanValue(messageId)))
          .go();
    });
  }

  /// 消息行定位（swipes 写操作前置校验，桌面 `_require_message`）。
  ///
  /// 消息不存在抛 [MessageNotFoundError]——swipes 写面是强校验操作（区别于
  /// [messageById] 查询面返回 null 的容错契约）。
  Future<Message> _requireMessage(int messageId) async {
    final message = await (_db.select(_db.messages)
          ..where(($MessagesTable t) => t.id.equals(messageId)))
        .getSingleOrNull();
    if (message == null) {
      throw MessageNotFoundError();
    }
    return message;
  }

  /// 候选行定位（(message_id, index) 精确匹配；不存在返回 null）。
  Future<MessageSwipe?> _swipeOrNull(int messageId, int index) {
    return (_db.select(_db.messageSwipes)
          ..where(($MessageSwipesTable t) =>
              t.messageId.equals(messageId) & t.index.equals(index)))
        .getSingleOrNull();
  }

  /// 覆写消息激活状态（content 跟随激活候选 + active_swipe_index）。
  Future<void> _writeActive(
    int messageId, {
    required String content,
    required int index,
  }) {
    return (_db.update(_db.messages)
          ..where(($MessagesTable t) => t.id.equals(messageId)))
        .write(
          MessagesCompanion(
            content: Value(content),
            activeSwipeIndex: Value(index),
          ),
        );
  }
}
