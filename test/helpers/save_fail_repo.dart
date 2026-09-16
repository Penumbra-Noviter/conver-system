/// 设置仓储「写失败」替身 — 单源。
///
/// 收敛 `conversation_settings_widget_test` 与
/// `conversation_settings_page_stage2_test` 的双份私有定义；公共命名
/// `SaveFailRepo` 供两个测试文件引用。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';

import 'in_memory_secret_store.dart';

/// 保存失败的仓储替身：`setMany` 抛错 → 覆盖设置子页 `_save` catch 分支。
class SaveFailRepo extends SettingsRepository {
  SaveFailRepo(AppDatabase db)
      : super(database: db, secretStore: InMemorySecretStore());

  @override
  Future<void> setMany(Map<String, String> data) async =>
      throw StateError('save fail');
}
