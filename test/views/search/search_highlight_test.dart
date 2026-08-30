/// `highlightFirst` 顶层纯函数行为契约（M3-04b 预览高亮第一处）。
///
/// 语义锚点：桌面 `desktop/frontend/js/format.js::highlightText`
/// （`indexOf` 首个命中、不区分大小写、仅高亮第一处）；`search-view.js`
/// 传入的 keyword 已 trim，故本函数不做 trim（遵循桌面语义，调用方保证）。
library;

import 'package:conver_system_mobile/views/search/search_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('highlightFirst · 不区分大小写，仅高亮第一处（验收 4）', () {
    test('多命中 → 仅第一处命中区间', () {
      final r = highlightFirst('aXbXc', 'x');
      expect(r.text, 'aXbXc', reason: 'text 恒为原样文本');
      expect(r.start, 1);
      expect(r.end, 2);
    });

    test('跨大小写 → 命中首处（大小写不敏感）', () {
      final r = highlightFirst('Hello World hello', 'hello');
      expect(r.start, 0);
      expect(r.end, 5);
    });

    test('命中在末尾', () {
      final r = highlightFirst('abX', 'x');
      expect(r.start, 2);
      expect(r.end, 3);
    });

    test('命中在开头', () {
      final r = highlightFirst('Xab', 'x');
      expect(r.start, 0);
      expect(r.end, 1);
    });

    test('空 query → 原样文本、无命中区间', () {
      final r = highlightFirst('abc', '');
      expect(r.text, 'abc');
      expect(r.start, isNull);
      expect(r.end, isNull);
    });

    test('无命中 → 原样文本、无命中区间', () {
      final r = highlightFirst('abc', 'zzz');
      expect(r.text, 'abc');
      expect(r.start, isNull);
      expect(r.end, isNull);
    });

    test('空 content → 空文本、无命中区间', () {
      final r = highlightFirst('', 'x');
      expect(r.text, '');
      expect(r.start, isNull);
    });

    test('大小写折叠展开（İ→i̇）不越界：clamp 至原串安全区间或回落无命中', () {
      // lower 后 content 长度膨胀（'İ'.toLowerCase() 展开为两个 code unit），
      // 原串切分必须不抛 RangeError。
      final r = highlightFirst('İx', 'i̇x');
      expect(r.text, 'İx', reason: 'text 恒为原样，不抛错');
      // 或 clamp 后 start/end 合法：不外抛，绝不越界
      final r2 = highlightFirst('İstanbul', 'İ');
      expect(r2.text, 'İstanbul');
    });
  });
}
