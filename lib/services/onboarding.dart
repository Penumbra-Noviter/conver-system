/// 首启新手指引的纯逻辑服务（工单 05 / spec §U-4）。
///
/// 读写设置表单一键 `onboarding_completed`：非敏感数据，走 drift Settings
/// 表（经 [SettingsRepository]），不进 secure_storage、不引 shared_preferences。
/// 标记语义：键缺失或值为空 → 未完成；值非空 → 已完成。
///
/// 层级：`services/` 纯 Dart 业务逻辑，可单测；消费 [SettingsRepository]。
library;

import '../data/repositories/settings_repository.dart';

/// 首启指引完成标记的单一语义入口。
class OnboardingService {
  /// 构造服务；[settings] 为设置仓储（写入 `onboarding_completed` 键）。
  const OnboardingService({required this.settings});

  /// 设置表键名——落库契约键（`SettingsRepository.allowedKeys` 白名单成员）。
  static const String completedKey = 'onboarding_completed';

  /// 设置仓储（键值 CRUD 的单一来源）。
  final SettingsRepository settings;

  /// 是否已完成指引：读 `onboarding_completed`，缺失或空回退「未完成」。
  ///
  /// 镜像 [SettingsRepository.getValue] 的空串语义（空串视同缺失）。
  Future<bool> isCompleted() async {
    final value = await settings.getValue(completedKey);
    return value.isNotEmpty;
  }

  /// 落完成标记（写非空值 `'true'`）；幂等，重复写覆盖同键。
  Future<void> markCompleted() async {
    await settings.setMany({completedKey: 'true'});
  }
}
