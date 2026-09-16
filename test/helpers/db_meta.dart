/// SQLite 元数据查询测试辅助 — `sqlite_master` 名称枚举。
///
/// 收敛 `app_database_test`（原实例方法形态）与 `stage2_migration_test`
/// （原顶层函数形态）的双份定义；后续工单（如 FD-05 迁移索引锚）统一经
/// 此 helper 引用。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:drift/drift.dart';

/// 枚举 `sqlite_master` 中指定类型的对象名（表 / 索引），可选按所属表过滤。
///
/// [type] 取 `sqlite_master.type` 的取值（如 `table` / `index`）；[table]
/// 非空时追加 `AND tbl_name = ?` 条件。返回按查询行序排列的名称列表。
Future<List<String>> sqliteMasterNames(
  AppDatabase db,
  String type, {
  String? table,
}) async {
  final rows = await db.customSelect(
    "SELECT name FROM sqlite_master WHERE type = ?"
    '${table != null ? ' AND tbl_name = ?' : ''}',
    variables: [
      Variable.withString(type),
      if (table != null) Variable.withString(table),
    ],
  ).get();
  return rows.map((row) => row.data['name'] as String).toList();
}
