/// 角色仓储 — CRUD 语义与桌面 character 服务逐条对齐。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/character.py`
///
/// 对齐要点：
/// - 列表附带 `conversation_count`（outer join + group by，桌面
///   `_base_character_query` 对应物），按 `updated_at` 倒序；
/// - 部分更新仅写显式提供的字段（桌面 `exclude_unset` 语义，drift 由
///   companion 的 `Value.absent()` 表达），且 `updated_at` 由本层随写前移
///   （桌面 ORM `onupdate` 对应物）；
/// - 删除返回受影响与否；删除角色引发的对话/消息消失依赖 M0 外键 CASCADE
///   + `PRAGMA foreign_keys = ON`（本层零显式级联代码，测试实证）；
/// - created_at / updated_at 全部由本层赋值（drift 列无 DB 默认，tables.dart
///   头注释的 M1 职责）。
library;

import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// 角色 + 对话数聚合行（桌面 `CharacterResponse.conversation_count` 对应物）。
class CharacterWithCount {
  const CharacterWithCount({
    required this.character,
    required this.conversationCount,
  });

  /// 角色行本体
  final Character character;

  /// 该角色名下的对话数（无对话为 0）
  final int conversationCount;
}

/// 角色仓储 — 表面与桌面 character 服务一一对应。
class CharacterRepository {
  /// [now] 为时间戳来源注入点（测试确定性用），缺省 [DateTime.now]。
  CharacterRepository(this._db, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  /// 所有角色 + 对话数，按 `updated_at` 倒序（桌面 list_characters）。
  Future<List<CharacterWithCount>> listCharacters() async {
    final (query, countExp) = _baseCharacterQuery();
    query.orderBy([OrderingTerm.desc(_db.characters.updatedAt)]);
    final rows = await query.get();
    return [
      for (final row in rows)
        CharacterWithCount(
          character: row.readTable(_db.characters),
          conversationCount: row.read(countExp) ?? 0,
        ),
    ];
  }

  /// 单个角色（不带对话数，供内部使用；桌面 get_character）。
  Future<Character?> getCharacter(int characterId) {
    return (_db.select(_db.characters)
          ..where(($CharactersTable t) => t.id.equals(characterId)))
        .getSingleOrNull();
  }

  /// 单个角色 + 对话数，不存在返回 null（桌面 get_character_with_count）。
  Future<CharacterWithCount?> getCharacterWithCount(int characterId) async {
    final (query, countExp) = _baseCharacterQuery();
    query.where(_db.characters.id.equals(characterId));
    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }
    return CharacterWithCount(
      character: row.readTable(_db.characters),
      conversationCount: row.read(countExp) ?? 0,
    );
  }

  /// 创建角色；created_at / updated_at 由本层赋值（显式传入的时间戳被覆盖）。
  Future<Character> createCharacter(CharactersCompanion data) {
    final now = _now();
    return _db.into(_db.characters).insertReturning(
          data.copyWith(createdAt: Value(now), updatedAt: Value(now)),
        );
  }

  /// 部分更新：仅写 [data] 中显式提供的字段，并前移 updated_at。
  ///
  /// 角色不存在返回 null；[data] 无任何显式字段时不产生 UPDATE 语句
  /// （桌面 ORM 零变更提交即 no-op、updated_at 不动的语义）。
  Future<Character?> updateCharacter(
    int characterId,
    CharactersCompanion data,
  ) async {
    final existing = await getCharacter(characterId);
    if (existing == null) {
      return null;
    }
    if (data.toColumns(false).isEmpty) {
      return existing;
    }
    await (_db.update(_db.characters)
          ..where(($CharactersTable t) => t.id.equals(characterId)))
        .write(data.copyWith(updatedAt: Value(_now())));
    return getCharacter(characterId);
  }

  /// 删除角色；返回是否确有角色被删（不存在 → false 且零副作用）。
  ///
  /// 其对话与消息由外键 CASCADE 随之消失（无显式级联代码）。
  Future<bool> deleteCharacter(int characterId) async {
    final affected = await (_db.delete(_db.characters)
          ..where(($CharactersTable t) => t.id.equals(characterId)))
        .go();
    return affected > 0;
  }

  /// 预置 conversation_count 聚合列的共享查询基座
  /// （桌面 `_base_character_query` 对应物）。
  ///
  /// 计数用 `COUNT(conversations.id)` 而非 `COUNT(*)`：outer join 无匹配时
  /// 桌面 `func.count(Conversation.id)` 记 0，`COUNT(*)` 会把空匹配行误记 1。
  ///
  /// drift `select(...).join(...)` 返回未参数化的 `JoinedSelectStatement`
  /// （行读取经 `readTable`/`read` 仍带完整类型），故此处按其原样标注。
  (JoinedSelectStatement, Expression<int>) _baseCharacterQuery() {
    final countExp = _db.conversations.id.count();
    final query = _db.select(_db.characters).join([
      leftOuterJoin(
        _db.conversations,
        _db.conversations.characterId.equalsExp(_db.characters.id),
      ),
    ])
      ..addColumns([countExp])
      ..groupBy([_db.characters.id]);
    return (query, countExp);
  }
}
