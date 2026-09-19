/// CompanionTimeWindows 单源契约测试（F-91 窗口常量 + F-129 日历日口径）。
library;

import 'package:conver_system_mobile/services/companion/companion_time_windows.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompanionTimeWindows（F-91/F-129 单源）', () {
    test('activeWindow 恰为 7 天（判定⑨窗口长度锚）', () {
      expect(CompanionTimeWindows.activeWindow, const Duration(days: 7));
    });

    test('localDayOf 截断时间部分（F-129 日历日身份）', () {
      final t = DateTime(2026, 9, 18, 23, 59, 59, 999);
      expect(CompanionTimeWindows.localDayOf(t), DateTime(2026, 9, 18));
    });

    test('isSameLocalDay：同日 true / 跨日 false（午夜边界）', () {
      expect(
        CompanionTimeWindows.isSameLocalDay(
          DateTime(2026, 9, 18, 0, 0, 0),
          DateTime(2026, 9, 18, 23, 59, 59),
        ),
        isTrue,
      );
      expect(
        CompanionTimeWindows.isSameLocalDay(
          DateTime(2026, 9, 18, 23, 59, 59),
          DateTime(2026, 9, 19, 0, 0, 0),
        ),
        isFalse,
      );
    });
  });
}
