/// 消息仓储 — CRUD + create 副作用 + 锚定截断，语义与桌面 message 服务逐条对齐。
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
library;

import 'package:drift/drift.dart';

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

/// 消息仓储 — 表面与桌面 message 服务对应
/// （get_messages / create_message / delete_messages_from；
/// build_message_list / search_messages 归 M2 / M3，不在此实现）。
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
}
