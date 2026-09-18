/// `lib/utils/utf16_truncate.dart` 契约测试（F-114/F-115 单源收敛）。
///
/// 覆盖：短文本原样 / 恰好上限不截 / BMP 超限截断 / 代理对边界不劈开
/// （F-114 票面：SR-22 `substring` 切在代理对中间 → 尾部 U+FFFD 的根因
/// 预防）。
library;

import 'package:conver_system_mobile/utils/utf16_truncate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('truncateUtf16', () {
    test('短文本（<= max）原样返回（不复制语义：identical）', () {
      const text = '你好';
      expect(truncateUtf16(text, 10), text);
      expect(identical(truncateUtf16(text, 10), text), isTrue);
    });

    test('恰好等于上限不截断', () {
      final text = 'a' * 2000;
      expect(truncateUtf16(text, 2000), text);
      expect(truncateUtf16(text, 2000).length, 2000);
    });

    test('BMP 字符超限按 Code Unit 截断', () {
      final text = 'a' * 2100;
      final cut = truncateUtf16(text, 2000);
      expect(cut, 'a' * 2000);
      expect(cut.length, 2000);
    });

    test('代理对不劈开：边界恰在代理对中间 → 多截 1 个 Code Unit', () {
      // U+1F600（😀）= 高代理 0xD83D + 低代理 0xDE00。
      final emoji = '\u{1F600}';
      // 1999 个 BMP 字符 + emoji（2 code units）= 2001；上限 2000 若
      // substring(0, 2000) 会切在 emoji 中间（末尾为高代理 0xD83D）。
      final text = 'a' * 1999 + emoji;
      final cut = truncateUtf16(text, 2000);
      expect(cut.length, 2000 - 1);
      expect(cut, 'a' * 1999);
      // 断言既非高代理结尾也非孤立代理残留（无 U+FFFD 输入面）。
      final last = cut.codeUnitAt(cut.length - 1);
      expect(last >= 0xD800 && last <= 0xDBFF, isFalse);
    });

    test('代理对恰好完整落在界内（上限落在低代理之后）不额外截断', () {
      final emoji = '\u{1F600}';
      // 1998 BMP + emoji = 2000 code units，完整保留。
      final text = 'a' * 1998 + emoji;
      final cut = truncateUtf16(text, 2000);
      expect(cut, text);
      expect(cut.length, 2000);
    });

    test('空串与零上限边界', () {
      expect(truncateUtf16('', 2000), '');
      expect(truncateUtf16('abc', 0), '');
    });
  });

  group('maxSnapshotLength 单源', () {
    test('常量值为 2000（与既有双源字面量一致，F-115）', () {
      expect(maxSnapshotLength, 2000);
    });
  });
}