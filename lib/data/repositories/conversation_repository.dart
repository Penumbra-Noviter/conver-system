/// 对话仓储 — CRUD 语义与桌面 conversation 服务逐条对齐。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/conversation.py`
///
/// 对齐要点：
/// - 列表附带 `message_count`（outer join + group by），按 `updated_at` 倒序
///   （桌面 list_conversations 实况；spec 修订日志①裁定，勿用 created_at），
///   支持按 character_id 过滤；
/// - create_conversation 蓝本内建副作用：标题占位「与 {角色名} 的对话」、
///   provider/model 缺省回退 SettingsReader（config 兜底腿等价复刻为常量）、
///   预插角色开场白（`{{user}}/{{char}}` 替换经纯函数）；开场白消息直接经
///   drift 插入（消息仓储归工单 05，不重复此路径），副作用与桌面 message
///   服务 create 等价：消息时间戳本层赋值 + 对话 updated_at 随之前移；
/// - 部分更新仅写显式字段并前移 updated_at；删除返回受影响与否；
/// - delete_all_conversations：桌面为「先删消息再删对话」两步显式删除，
///   移动端单删对话由外键 CASCADE 达成同一可观察结果（spec 数据仓储节）；
/// - 时间戳全部由本层赋值。
library;

import 'package:drift/drift.dart';

import '../../services/template_vars.dart';
import '../database/app_database.dart';
import '../database/tables.dart';
import 'settings_reader.dart';

/// 角色 + 对话数聚合行（桌面 `ConversationResponse.message_count` 对应物）。
class ConversationWithCount {
  const ConversationWithCount({
    required this.conversation,
    required this.messageCount,
  });

  /// 对话行本体
  final Conversation conversation;

  /// 该对话内的消息数（无消息为 0）
  final int messageCount;
}

/// 对话占位默认标题「与 {角色名} 的对话」；角色缺失（或名称为空）用
/// 「与 角色 的对话」（桌面 `_default_title_for_character` 对应物）。
///
/// 顶层纯函数：工单 05 的 auto-title 判定（首条 user 消息占位替换）
/// 将复用此函数，标题生命周期判定不另写第二份规则。
String defaultConversationTitle(String? charName) {
  final effective = (charName == null || charName.isEmpty) ? '角色' : charName;
  return '与 $effective 的对话';
}

/// 对话仓储 — 表面与桌面 conversation 服务一一对应。
class ConversationRepository {
  /// [now] 为时间戳来源注入点（测试确定性用），缺省 [DateTime.now]。
  ConversationRepository(this._db, this._settings, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final SettingsReader _settings;
  final DateTime Function() _now;

  /// 桌面 config 兜底腿（引用 [SettingsDefaults] 单一归属——F-24 收敛，
  /// 原为本地复制字面量、与实现方填充值「碰巧相等」）。
  static const _fallbackProvider = SettingsDefaults.provider;
  static const _fallbackModel = SettingsDefaults.model;

  /// `{{user}}` 的兜底昵称（桌面 create_conversation 内联 `or 'User'`）。
  static const _fallbackUserName = SettingsDefaults.userName;

  /// 对话列表 + 消息数，按 `updated_at` 倒序；
  /// [characterId] 非空时仅含该角色的对话（桌面 list_conversations）。
  Future<List<ConversationWithCount>> listConversations({int? characterId}) async {
    final (query, countExp) = _baseConversationQuery();
    if (characterId != null) {
      query.where(_db.conversations.characterId.equals(characterId));
    }
    query.orderBy([OrderingTerm.desc(_db.conversations.updatedAt)]);
    final rows = await query.get();
    return [
      for (final row in rows)
        ConversationWithCount(
          conversation: row.readTable(_db.conversations),
          messageCount: row.read(countExp) ?? 0,
        ),
    ];
  }

  /// 单个对话，不存在返回 null（桌面 get_conversation）。
  Future<Conversation?> getConversation(int conversationId) {
    return (_db.select(_db.conversations)
          ..where(($ConversationsTable t) => t.id.equals(conversationId)))
        .getSingleOrNull();
  }

  /// 创建对话（桌面 create_conversation 蓝本内建副作用）：
  ///
  /// - [title] 为空或未传 → 占位「与 {角色名} 的对话」；
  /// - [modelProvider] / [modelName] 非空显式值优先，否则回退
  ///   [SettingsReader] 的设置值，再回退常量 `claude` / `claude-sonnet-5`；
  /// - [greeting]（NPD-03）开场白三态，锚桌面 `create_conversation` 的
  ///   `model_fields_set` 判定（Python `if "greeting" in ...` 语义的 Dart
  ///   镜像——Dart 无 model_fields_set，三态由「显式传入」调用点保证：
  ///   - null（未传 / 显式传 null，Dart 无法区分）→ 沿用现状：角色
  ///     `first_mes` 非空则预插首条 assistant 开场白（模板变量替换后），
  ///     first_mes 空则零预插（验收 1/2 零回归）；
  ///   - 非空字符串 → 预插**该内容**（模板变量替换后），与 first_mes 原值
  ///     无关（即使 first_mes 为空也预插）；
  ///   - 显式空串 → **不预插**（消息表为空，即使角色有 first_mes）。
  ///   纯空白字符串按 truthy 处理（`isNotEmpty`）→ 预插，与桌面 `if
  ///   greeting_text:` 的 Python truthiness 对齐；非 String 显式值属契约外
  ///   （调用点保证三态），防御性回退 first_mes 路径。
  /// - [presetDialogue]（NPD-02）：预设对话快照文本，创建时固化到
  ///   `conversations.preset_dialogue` 列；None/空串 → null（不落伪值，桌面
  ///   `data.preset_dialogue or None` 语义）。快照语义 = 创建时固化——改角色
  ///   卡 presetDialogues 实时值不影响已建会话注入源（验收 5 契约锁）。
  ///
  /// 角色不存在时经外键约束拒绝（与桌面 FK 语义一致，不做预检兜底）。
  Future<Conversation> createConversation({
    required int characterId,
    String? title,
    String? modelProvider,
    String? modelName,
    Object? greeting,
    String? presetDialogue,
  }) async {
    final character = await (_db.select(_db.characters)
          ..where(($CharactersTable t) => t.id.equals(characterId)))
        .getSingleOrNull();

    final provider = _resolveValue(
      explicit: modelProvider,
      fromSettings: await _settings.defaultProvider,
      fallback: _fallbackProvider,
    );
    final model = _resolveValue(
      explicit: modelName,
      fromSettings: await _settings.defaultModel,
      fallback: _fallbackModel,
    );
    final effectiveTitle = _resolveValue(
      explicit: title,
      fromSettings: '',
      fallback: defaultConversationTitle(character?.name),
    );
    // 快照归一：None/空串 → null 不落伪值（桌面 `data.preset_dialogue or None`；
    // 纯空白 truthy 原样固化，注入门控由 buildMessages 的 trim 检查承载）。
    final presetSnapshot =
        (presetDialogue == null || presetDialogue.isEmpty) ? null : presetDialogue;

    final now = _now();
    var conversation = await _db.into(_db.conversations).insertReturning(
          ConversationsCompanion.insert(
            characterId: characterId,
            title: Value(effectiveTitle),
            modelProvider: Value(provider),
            modelName: Value(model),
            presetDialogue: Value(presetSnapshot),
            createdAt: now,
            updatedAt: now,
          ),
        );

    // 预插开场白三态（桌面 `if "greeting" in model_fields_set` 语义镜像）：
    //   greeting 为 String 时以其值为准（空串 no-op；非空模板替换后预插）；
    //   greeting 非 String（含 null）时回退角色 first_mes（既有语义）。
    // 纯空白 truthy 走预插（与桌面 Python truthiness 一致，不 trim 判定）。
    final greetingText =
        (greeting is String) ? greeting : (character?.firstMes ?? '');
    if (character != null && greetingText.isNotEmpty) {
      final userName = _resolveValue(
        fromSettings: await _settings.userName,
        fallback: _fallbackUserName,
      );
      final extraVars = await _settings.templateVars;
      final resolved = applyTemplateVars(
        greetingText,
        userName: userName,
        charName: character.name,
        extraVars: extraVars,
      );
      final greetingAt = _now();
      await _db.into(_db.messages).insert(
            MessagesCompanion.insert(
              conversationId: conversation.id,
              role: Role.assistant,
              content: resolved,
              createdAt: greetingAt,
            ),
          );
      // 桌面 message 服务 create 副作用：消息落库前移对话 updated_at。
      // drift 存储为 unix 秒，重新读取以保证返回行反映前移后的时间戳。
      await (_db.update(_db.conversations)
            ..where(($ConversationsTable t) => t.id.equals(conversation.id)))
          .write(ConversationsCompanion(updatedAt: Value(greetingAt)));
      conversation = await _getConversationStrict(conversation.id);
    }
    return conversation;
  }

  /// 部分更新：仅写 [data] 中显式提供的字段，并前移 updated_at。
  ///
  /// 对话不存在返回 null；[data] 无任何显式字段时不产生 UPDATE 语句。
  Future<Conversation?> updateConversation(
    int conversationId,
    ConversationsCompanion data,
  ) async {
    final existing = await getConversation(conversationId);
    if (existing == null) {
      return null;
    }
    if (data.toColumns(false).isEmpty) {
      return existing;
    }
    await (_db.update(_db.conversations)
          ..where(($ConversationsTable t) => t.id.equals(conversationId)))
        .write(data.copyWith(updatedAt: Value(_now())));
    return getConversation(conversationId);
  }

  /// 删除单条对话；返回是否确有对话被删（不存在 → false 且零副作用）。
  ///
  /// 其消息由外键 CASCADE 随之消失（无显式级联代码）。
  Future<bool> deleteConversation(int conversationId) async {
    final affected = await (_db.delete(_db.conversations)
          ..where(($ConversationsTable t) => t.id.equals(conversationId)))
        .go();
    return affected > 0;
  }

  /// 清空全部对话及消息（桌面 delete_all_conversations 对应物）。
  ///
  /// 消息经外键 CASCADE 一并消失，可观察结果与桌面两步显式删除一致。
  Future<void> deleteAllConversations() async {
    await _db.delete(_db.conversations).go();
  }

  /// 预置 message_count 聚合列的共享查询基座（桌面 list_conversations
  /// 的 outerjoin/group_by 对应物；`COUNT(messages.id)` 对空对话记 0）。
  ///
  /// drift `select(...).join(...)` 返回未参数化的 `JoinedSelectStatement`
  /// （行读取经 `readTable`/`read` 仍带完整类型），故此处按其原样标注。
  (JoinedSelectStatement, Expression<int>) _baseConversationQuery() {
    final countExp = _db.messages.id.count();
    final query = _db.select(_db.conversations).join([
      leftOuterJoin(
        _db.messages,
        _db.messages.conversationId.equalsExp(_db.conversations.id),
      ),
    ])
      ..addColumns([countExp])
      ..groupBy([_db.conversations.id]);
    return (query, countExp);
  }

  Future<Conversation> _getConversationStrict(int conversationId) async {
    final conversation = await getConversation(conversationId);
    if (conversation == null) {
      throw StateError('对话 $conversationId 在同一事务路径中消失');
    }
    return conversation;
  }

  /// 消费方回退链：显式非空值优先 → 设置值非空优先 → 常量兜底。
  ///
  /// 显式空串视同未提供（工单验收 A4「显式值（非空）优先」）；设置空串语义
  /// 与桌面 get_value 一致（SettingsReader 契约）。
  static String _resolveValue({
    String? explicit,
    String fromSettings = '',
    required String fallback,
  }) {
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    if (fromSettings.isNotEmpty) {
      return fromSettings;
    }
    return fallback;
  }
}
