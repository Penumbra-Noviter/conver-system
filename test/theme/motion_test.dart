/// ConverDurations 动效时长 token（M6-07）——三档对齐桌面 `--transition-*`
/// + tab 切换专用档。
///
/// 验收语义（工单 07 验收 1 + spec §4.1 + 共识 §2 面1 1.3）：
/// - `fast=140ms`（桌面 `--transition-fast:0.14s`）/ `mid=220ms`
///   （`--transition:0.22s`）/ `slow=300ms`（`--transition-slow:0.3s`）；
/// - `tabFade=160ms`（共识 TP-1 ① tab 切换 Fade 160ms，独立命名档——
///   不改变三档与桌面的逐字对齐）。
library;

import 'package:conver_system_mobile/theme/motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConverDurations token 值（验收 1）', () {
    test('fast / mid / slow 逐字对齐桌面 --transition-*', () {
      expect(ConverDurations.fast, const Duration(milliseconds: 140));
      expect(ConverDurations.mid, const Duration(milliseconds: 220));
      expect(ConverDurations.slow, const Duration(milliseconds: 300));
    });

    test('tabFade 独立档 160ms（共识 TP-1 ①，不冲淡三档桌面锚）', () {
      expect(ConverDurations.tabFade, const Duration(milliseconds: 160));
    });

    test('三档严格递增', () {
      expect(ConverDurations.fast < ConverDurations.mid, isTrue);
      expect(ConverDurations.mid < ConverDurations.slow, isTrue);
    });
  });
}