/// `resolveCharTemperature` 值域表驱动（F-147 采样温度解析链单源）。
///
/// 覆盖原 ChatService / MemoryPalaceService 两套独占防御实现的全部面：
/// NaN / ±Infinity / 缺省等值 0.7 / null / 越界上下限 clamp / 合法覆盖 /
/// 边界恰等。常量自 [SettingsRepository] 静态导入（单源，不硬编码）。
library;

import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/llm/temperature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveCharTemperature 值域表驱动（F-147）', () {
    // 全局兜底值取 0.5：与缺省角色 0.7 可区分，确保「== default → 回退全局」
    // 分支被真实断言（而非两头同值恒真）。
    const global = 0.5;

    final cases = <({double? char, double expected, String label})>[
      (char: double.nan, expected: global, label: 'NaN → 回退全局'),
      (char: double.infinity, expected: global, label: '+Infinity → 回退全局'),
      (
        char: double.negativeInfinity,
        expected: global,
        label: '-Infinity → 回退全局',
      ),
      (char: null, expected: global, label: 'null（宽松缺省）→ 回退全局'),
      (
        char: SettingsRepository.defaultTemperature,
        expected: global,
        label: '== defaultTemperature(0.7) → 判定未覆盖 → 回退全局',
      ),
      (
        char: 9.9,
        expected: SettingsRepository.temperatureMax,
        label: '越界上界 9.9 → clamp 到 temperatureMax',
      ),
      (
        char: -1.5,
        expected: SettingsRepository.temperatureMin,
        label: '越界下界 -1.5 → clamp 到 temperatureMin',
      ),
      (char: 1.2, expected: 1.2, label: '合法覆盖值 1.2 → 原样'),
      (
        char: SettingsRepository.temperatureMax,
        expected: SettingsRepository.temperatureMax,
        label: '边界恰等上界 → 原样（clamp 不动）',
      ),
      (
        char: SettingsRepository.temperatureMin,
        expected: SettingsRepository.temperatureMin,
        label: '边界恰等下界 → 原样（clamp 不动）',
      ),
    ];

    test('全值域表：NaN / ±Inf / null / 缺省等值 → 全局；越界 clamp；合法原样', () {
      for (final c in cases) {
        expect(
          resolveCharTemperature(c.char, global),
          c.expected,
          reason: c.label,
        );
      }
    });

    test('全局透传逐值：char == default 时返回的正是传入的 global（非巧合）', () {
      expect(resolveCharTemperature(0.7, 0.9), 0.9);
      expect(resolveCharTemperature(null, 1.4), 1.4);
    });
  });
}