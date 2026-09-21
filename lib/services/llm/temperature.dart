/// 采样温度解析链单源（F-147，波 3 C2）。
///
/// 「角色为主 / 全局兜底 + NaN/Infinity 回退 + 越界 clamp」同一链路在
/// ChatService 与 MemoryPalaceService 各存一份逐字实现的债面收敛于此。
/// 常量（[SettingsRepository.defaultTemperature] /
/// [SettingsRepository.temperatureMin] / [SettingsRepository.temperatureMax]）
/// 自设置仓储静态导入（单源）。
library;

import '../../data/repositories/settings_repository.dart';

/// 解析采样温度：角色 [charTemperature] 为主、全局 [globalTemperature] 兜底。
///
/// 返回规则（与两服务旧实现逐值一致，F-76 防线单源化）：
/// - [charTemperature] 为 **null**（宽松缺省分支）、**NaN**、**±Infinity**
///   或 **== [SettingsRepository.defaultTemperature]**（0.7，DB 默认，判定
///   「未显式覆盖」）→ 返回 [globalTemperature]；
/// - **越界值** clamp 到 [SettingsRepository.temperatureMin, temperatureMax]
///   后返回（DB 层无 CHECK 约束，非法值不透明给 wire）；
/// - 其余合法值原样返回。
double resolveCharTemperature(
  double? charTemperature,
  double globalTemperature,
) {
  final temperature = charTemperature;
  if (temperature == null ||
      temperature.isNaN ||
      temperature.isInfinite ||
      temperature == SettingsRepository.defaultTemperature) {
    return globalTemperature;
  }
  return temperature
      .clamp(
        SettingsRepository.temperatureMin,
        SettingsRepository.temperatureMax,
      )
      .toDouble();
}