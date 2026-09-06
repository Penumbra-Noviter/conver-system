/// safeFileName 顶层纯函数测试（验收 6；2026-09-07 架构深化自平台 seam 迁出
/// 至 `file_name.dart`——纯函数归纯处，平台薄层不再夹带）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/file_name.dart';

void main() {
  group('safeFileName · 顶层纯函数（验收 6，自平台 seam 迁出）', () {
    test('Windows 非法字符与控制字符替换为 _', () {
      expect(safeFileName(r'a/b\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
      expect(safeFileName('a\x00b\x1fc'), 'a_b_c');
    });

    test('路径分隔符替换为 _ 且首尾点剔除（不残留分隔符，杜绝穿越）', () {
      // 验收 6：/ 与 \ 同为非法文件名字符 → 替换为 _；输出不含任何分隔符，
      // 无法构成子路径（目录穿越免疫）；前导 `..` 形态随首尾点剔除收敛。
      expect(safeFileName('../etc/passwd'), '_etc_passwd');
      expect(safeFileName(r'a\b\c'), 'a_b_c');
      expect(safeFileName('../etc/passwd'), isNot(contains('/')));
      expect(safeFileName(r'a\b\c'), isNot(contains('\\')));
    });

    test('首尾空格剔除', () {
      expect(safeFileName('  name  '), 'name');
    });

    test('空 / 纯空白 → 回退 character', () {
      expect(safeFileName(''), 'character');
      expect(safeFileName('   '), 'character');
      // 纯非法字符替换后仍非空（`___`），按字面语义不回退（仍是安全文件名）。
      expect(safeFileName('///'), '___');
    });

    test('`.` 与 `..` → 首尾点剔除后回退 character（防穿越 / 隐藏文件）', () {
      expect(safeFileName('..'), 'character');
      expect(safeFileName('.'), 'character');
      expect(safeFileName('..角色..'), '角色');
      expect(safeFileName('....'), 'character');
    });

    test('超长截断至 100 字符', () {
      expect(safeFileName('名' * 150), '名' * 100);
    });
  });
}
