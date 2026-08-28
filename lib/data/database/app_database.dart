/// 应用数据库 — drift 数据库入口（schemaVersion=1，M0 冻结）。
///
/// - 表注册：characters / conversations / messages / settings
///   （定义见 `tables.dart`，权威源为桌面端 ORM）
/// - 执行器构造注入：测试 seam，测试用 `AppDatabase(NativeDatabase.memory())`
///   在内存中打开真实 schema，不依赖设备
/// - 运行态连接经 [AppDatabase.open]（drift_flutter 惰性打开，内部即
///   LazyDatabase 包装，M0 不调用、不做任何真实查询；M1 起使用）
/// - 打开时启用 `PRAGMA foreign_keys = ON`，对齐桌面端 CASCADE 语义
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Conver System 移动端数据库。
@DriftDatabase(tables: [
  Characters,
  Conversations,
  Messages,
  Settings,
])
class AppDatabase extends _$AppDatabase {
  /// 执行器注入构造（测试 seam / 自定义执行器）。
  AppDatabase(super.e);

  /// 运行态构造：drift_flutter 惰性打开（LazyDatabase），M0 不调用。
  factory AppDatabase.open() {
    return AppDatabase(driftDatabase(name: 'conver_system'));
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          // 对齐桌面端 CASCADE 删除语义（SQLite 默认关闭外键约束）。
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
