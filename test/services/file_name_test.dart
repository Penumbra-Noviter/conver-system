/// safeFileName 顶层纯函数测试（验收 6；2026-09-07 架构深化自平台 seam 迁出
/// 至 `file_name.dart`——纯函数归纯处，平台薄层不再夹带）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/file_name.dart';
import 'package:conver_system_mobile/services/simulator/save_contract.dart';

/// 双锚对照矩阵（C3 参数化合并逐字符保契）：同一批边界输入分别经导出锚
/// [safeFileName] 与存档锚 [sanitizeFilename] 断言，golden 值 = 合并前
/// 现状行为逐字符冻结（`(输入, 导出锚 golden, 存档锚 golden)`）。
final List<(String, String, String)> _dualAnchorMatrix = [
  // —— 字符集分叉：导出锚字符集不含 % 与 0x7f（保留），存档锚替换 ——
  ('a%b', 'a%b', 'a_b'),
  ('a\x7fb', 'a\x7fb', 'a_b'),
  ('a\x00b\x7fc', 'a_b\x7fc', 'a_b_c'),
  // —— 控制字符（两锚均替换）——
  ('a\x00b\x1fc', 'a_b_c', 'a_b_c'),
  // —— 首尾点分叉：导出锚两侧剔除，存档锚仅尾部 ——
  ('.abc.', 'abc', '.abc'),
  ('..abc..', 'abc', '..abc'),
  ('.', 'character', 'game'),
  ('..', 'character', 'game'),
  ('...', 'character', 'game'),
  // —— 空白分叉：导出锚 Unicode 空白两侧修剪，存档锚仅尾部空格 ——
  ('   ', 'character', 'game'),
  ('   name   ', 'name', '   name'),
  ('  .hidden', 'hidden', '  .hidden'),
  // 导出锚现状怪癖：截断后二次修剪的剔点操作会遗留尾部空格（'a '）；
  // 存档锚单次整段剔尾（'a'）。逐字符冻结，不得「修」成一致。
  ('a . .', 'a ', 'a'),
  // —— 空串 / 中文 / 内部空格 ——
  ('', 'character', 'game'),
  ('中文名', '中文名', '中文名'),
  ('a b', 'a b', 'a b'),
  // —— 超长名：导出锚截断 100，存档锚不截断 ——
  ('n' * 150, 'n' * 100, 'n' * 150),
  // —— 混合非法字符（% 保留 vs 替换；路径分隔符替换为 _）——
  ('a"b\\c/d\x01e%f', 'a_b_c_d_e%f', 'a_b_c_d_e_f'),
  ('///', '___', '___'),
  ('../etc/passwd', '_etc_passwd', '.._etc_passwd'),
  ('trail. ', 'trail', 'trail'),
  ('life-sim.', 'life-sim', 'life-sim'),
  (r'a\b\c', 'a_b_c', 'a_b_c'),
];

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

  group('双锚对照矩阵 · C3 参数化合并逐字符保契（合并前 golden 冻结）', () {
    test('同一批边界输入经 safeFileName（导出锚）→ 逐字符一致', () {
      for (final (input, exportGolden, _) in _dualAnchorMatrix) {
        expect(safeFileName(input), exportGolden, reason: '导出锚「$input」');
      }
    });

    test('同一批边界输入经 sanitizeFilename（存档锚）→ 逐字符一致', () {
      for (final (input, _, saveGolden) in _dualAnchorMatrix) {
        expect(sanitizeFilename(input), saveGolden, reason: '存档锚「$input」');
      }
    });
  });

  group('safeFileName · 导出锚负样本（C3 边界加固）', () {
    test('% 与 0x7f 保留（导出锚字符集不含此二字符——与存档锚分叉）', () {
      expect(safeFileName('a%b'), 'a%b');
      expect(safeFileName('a\x7fb'), 'a\x7fb');
    });

    test('前导点剔除（防 `..` 段穿越 / 隐藏文件形态）', () {
      expect(safeFileName('..abc'), 'abc');
      expect(safeFileName('.hidden'), 'hidden');
    });

    test('超长截断 100 + 截断后二次修剪（截断露出的空白被二次剔除）', () {
      expect(safeFileName('${'n' * 98}  .  ${'名' * 10}'), 'n' * 98);
    });

    test('纯非法字符替换后仍非空 → 不回退（仍是安全文件名）', () {
      expect(safeFileName('///'), '___');
      expect(safeFileName('a?b*c'), 'a_b_c');
    });

    test('空 / 纯空白 / 纯点 → 回退 character', () {
      expect(safeFileName(''), 'character');
      expect(safeFileName('   '), 'character');
      expect(safeFileName('...'), 'character');
    });
  });

  group('safeFileNameCore · 核心行为矩阵（C3 参数化单核心）', () {
    // 独立声明两锚配置（与薄包装内部声明同构，但独立于实现——golden 来自
    // 合并前现状行为，不依赖包装内配置文字）。
    const FileNameSanitizerConfig exportConfig = FileNameSanitizerConfig(
      edgeTrim: FileNameEdgeTrim.whitespaceAndDotsBothEdges,
      maxLength: 100,
      trimAfterTruncate: true,
      fallback: 'character',
    );
    const FileNameSanitizerConfig saveConfig = FileNameSanitizerConfig(
      extraChars: '\x7f%',
      edgeTrim: FileNameEdgeTrim.trailingDotsAndSpaces,
      fallback: 'game',
    );

    test('导出锚配置 + 核心 == 导出锚 golden（逐字符）', () {
      for (final (input, exportGolden, _) in _dualAnchorMatrix) {
        expect(
          safeFileNameCore(input, config: exportConfig),
          exportGolden,
          reason: '导出锚配置「$input」',
        );
      }
    });

    test('存档锚配置 + 核心 == 存档锚 golden（逐字符）', () {
      for (final (input, _, saveGolden) in _dualAnchorMatrix) {
        expect(
          safeFileNameCore(input, config: saveConfig),
          saveGolden,
          reason: '存档锚配置「$input」',
        );
      }
    });

    test('两薄包装行为与核心同配置逐字符一致（薄包装确为委托）', () {
      for (final (input, exportGolden, saveGolden) in _dualAnchorMatrix) {
        expect(safeFileNameCore(input, config: exportConfig), safeFileName(input),
            reason: '导出锚委托「$input」');
        expect(
            safeFileNameCore(input, config: saveConfig), sanitizeFilename(input),
            reason: '存档锚委托「$input」');
        expect(safeFileNameCore(input, config: exportConfig), exportGolden,
            reason: '导出锚一致性「$input」');
        expect(safeFileNameCore(input, config: saveConfig), saveGolden,
            reason: '存档锚一致性「$input」');
      }
    });

    test('空串经核心（两配置）→ 各自兜底（golden 冻结）', () {
      expect(safeFileNameCore('', config: exportConfig), 'character');
      expect(safeFileNameCore('', config: saveConfig), 'game');
    });
  });

  group('safeFileNameCore · 配置互不串扰（Falsify：两路径边界锁定）', () {
    test('导出配置不含存档特有字符处理（% 与 0x7f 保留）', () {
      expect(safeFileName('a%b'), 'a%b');
      expect(safeFileName('a\x7fb'), 'a\x7fb');
      expect(safeFileName('a\x00b\x7fc'), 'a_b\x7fc');
    });

    test('存档配置不含导出特有行为（前导修剪 / 截断 / 二次修剪）', () {
      expect(sanitizeFilename('  .hidden'), '  .hidden');
      expect(sanitizeFilename('.abc.'), '.abc');
      expect(sanitizeFilename('n' * 150), 'n' * 150);
      expect(sanitizeFilename('a . .'), 'a');
    });
  });

  group('safeFileNameCore · Falsify（配置误用防御）', () {
    const FileNameSanitizerConfig exportConfig = FileNameSanitizerConfig(
      edgeTrim: FileNameEdgeTrim.whitespaceAndDotsBothEdges,
      maxLength: 100,
      trimAfterTruncate: true,
      fallback: 'character',
    );
    const FileNameSanitizerConfig saveConfig = FileNameSanitizerConfig(
      extraChars: '\x7f%',
      edgeTrim: FileNameEdgeTrim.trailingDotsAndSpaces,
      fallback: 'game',
    );

    test('非 String 输入 → 直接回退 fallback（不做任何替换/修剪）', () {
      expect(safeFileNameCore(null, config: saveConfig), 'game');
      expect(safeFileNameCore(42, config: saveConfig), 'game');
      expect(safeFileNameCore(3.14, config: saveConfig), 'game');
      // 导出锚签名收窄为 String 不可达；核心仍防御 → 回退导出兜底。
      expect(safeFileNameCore(null, config: exportConfig), 'character');
    });

    test('空配置（无修剪/无截断/无附加字符）→ 仅替换基础非法字符', () {
      const FileNameSanitizerConfig none = FileNameSanitizerConfig(fallback: 'x');
      expect(safeFileNameCore('..a/b', config: none), '..a_b');
      expect(safeFileNameCore('...', config: none), '...'); // 无修剪 → 保留
      expect(safeFileNameCore('', config: none), 'x');
    });

    test('超长 extraChars → 逐字面替换不崩溃', () {
      final FileNameSanitizerConfig cfg = FileNameSanitizerConfig(
        extraChars: '\x7f%junk0123456789' * 20,
        edgeTrim: FileNameEdgeTrim.trailingDotsAndSpaces,
        fallback: 'game',
      );
      expect(safeFileNameCore('a%b\x7f#c', config: cfg), 'a_b_#c');
      expect(safeFileNameCore('a/b', config: cfg), 'a_b'); // 基础字符集仍生效
    });

    test('退化的 fallback（空串）→ 原样返回空串，不崩溃', () {
      const FileNameSanitizerConfig cfg = FileNameSanitizerConfig(fallback: '');
      expect(safeFileNameCore('', config: cfg), '');
      expect(safeFileNameCore(null, config: cfg), '');
      expect(safeFileNameCore('abc', config: cfg), 'abc');
    });

    test('空 edgeTrim + 非空输入 → 原样返回（修剪规则显式声明为 none）', () {
      const FileNameSanitizerConfig none = FileNameSanitizerConfig(
        edgeTrim: FileNameEdgeTrim.none,
        fallback: 'x',
      );
      expect(safeFileNameCore('  ..a..  ', config: none), '  ..a..  ');
    });
  });
}
