/// 迁移索引对账（F-130）：onUpgrade 手工 CREATE INDEX 清单 ⊆ tables.dart
/// @TableIndex 注解清单——防止「手工 SQL 与 drift 声明漂移」。
///
/// 方向性说明：onUpgrade 只补「版本新增」索引（M0 基座索引
/// idx_characters_name / idx_conversations_character_id /
/// idx_messages_conversation_id 随 CREATE TABLE 自带，不在 onUpgrade 重复
/// 补建），故断言为单方向包含；「注解新增忘补 onUpgrade」依赖 F-95 先例
/// 人工同步 + 本测试的反向漂移防护（onUpgrade 引用未声明索引名即红）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 提取 [source] 中 @TableIndex 注解的 name 参数（支持单行/跨行写法）。
Set<String> _tableIndexNames(String source) {
  final re = RegExp(r"@TableIndex\((?:.|\n)*?name: '([A-Za-z0-9_]+)'");
  return {for (final m in re.allMatches(source)) m.group(1)!};
}

/// 提取 [source] 中 onUpgrade 手工 CREATE [UNIQUE] INDEX 的索引名。
///
/// 源文件 SQL 字符串可能断行（`'CREATE UNIQUE INDEX IF NOT EXISTS '` +
/// `'idx_... '`），且注释也会出现「CREATE INDEX」字样（如
/// 「CREATE INDEX IF NOT EXISTS 幂等补建」）——本库 onUpgrade 全部索引 SQL
/// 均以 `IF NOT EXISTS` 为固定前缀，故将其设为**必需**（非可选），注释里的
/// 中文拼音后无合法标识符即整体失败，不会回溯把 `IF` 当索引名；捕获前只
/// 允许消耗引号与空白（断行字面量的行首引号）。
Set<String> _createIndexNames(String source) {
  final re = RegExp(
    r"""CREATE (?:UNIQUE )?INDEX IF NOT EXISTS ['\s]*([A-Za-z0-9_]+)""",
  );
  return {for (final m in re.allMatches(source)) m.group(1)!};
}

void main() {
  test('onUpgrade CREATE INDEX 清单 ⊆ tables.dart @TableIndex 注解（F-130 对账）', () {
    final tables = File('lib/data/database/tables.dart').readAsStringSync();
    final database = File('lib/data/database/app_database.dart')
        .readAsStringSync();

    final annotated = _tableIndexNames(tables);
    final handWritten = _createIndexNames(database);

    expect(annotated, isNotEmpty, reason: 'tables.dart 应含 @TableIndex 注解');
    expect(
      handWritten,
      isNotEmpty,
      reason: 'app_database.dart 应含 onUpgrade 索引 SQL',
    );
    expect(
      handWritten.difference(annotated),
      isEmpty,
      reason: 'onUpgrade 手工索引未在 tables.dart 声明（漂移）',
    );
  });
}
