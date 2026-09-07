/// saveKeyMetaRe / escapeRegExp 契约锁（对拍桌面 save-key-meta.test.js）。
///
/// 桌面锚点（只读，语义锚）：`desktop/frontend/tests/save-key-meta.test.js`
/// —— SAVE_KEY_META_RE 源串逐字等价、escapeRegExp 与旧内联字面量逐字节
/// 等价、正则元字符全集转义后可编译且为字面量匹配。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/save_key_meta.dart';

// 契约锁锚点：桌面 SAVE_KEY_META_RE 源串（`/[.*+?^${}()|[\]\\]/` 的 source）。
// 仅测试文件持有，产品代码不得复制为独立正则字面量（对拍桌面同款锁法）。
const String legacySaveKeyMetaReSource = r'[.*+?^${}()|[\]\\]';

void main() {
  group('saveKeyMetaRe · 常量契约（单一来源）', () {
    test('源串与桌面 SAVE_KEY_META_RE source 逐字等价', () {
      expect(saveKeyMetaRe.pattern, legacySaveKeyMetaReSource);
    });

    test('判定语义：正则元字符命中、普通键名不命中', () {
      expect(saveKeyMetaRe.hasMatch('a.b'), isTrue);
      expect(saveKeyMetaRe.hasMatch('a^b'), isTrue);
      expect(saveKeyMetaRe.hasMatch('plain_save'), isFalse);
      expect(saveKeyMetaRe.hasMatch('wg_xiaomabaoli_save'), isFalse);
    });
  });

  group('escapeRegExp · 转义与旧内联字面量逐字节等价', () {
    // 旧内联变体（桌面 simulator-manifest.test.js 迁移前形态）
    String legacy(String s) => s.replaceAllMapped(
          RegExp(r'[.*+?^${}()|[\]\\]'),
          (m) => '\\${m[0]}',
        );

    test('样本逐字节等价', () {
      const samples = [
        'my-little-pony',
        'high-school-sim',
        'wg_xiaomabaoli_save',
        r'a.b*c?d+e{f}g(h)i[j]k\l^m$n|o',
        'id_123',
        'x[y]z',
        r'a\b',
        'endless_sea_cfg',
      ];
      for (final s in samples) {
        expect(escapeRegExp(s), legacy(s), reason: '样本「$s」逐字节等价');
      }
    });

    test('字面量断言：元字符全部加反斜杠转义', () {
      expect(escapeRegExp('a.b'), r'a\.b');
      expect(escapeRegExp('x[y]z'), r'x\[y\]z');
      expect(escapeRegExp(r'a\b'), r'a\\b');
      expect(escapeRegExp('prefix_.*'), r'prefix_\.\*');
      expect(escapeRegExp('plain_save'), 'plain_save');
    });

    test('正则元字符全集特殊 id 转义后可编译且语义为字面量匹配', () {
      const special = r'a.*+?^${}()|[]\z'; // 全集元字符（. * + ? ^ $ { } ( ) | [ ] \）
      final escaped = escapeRegExp(special);
      final re = RegExp('id="$escaped"');
      expect(re.hasMatch('id="$special"'), isTrue); // 字面量匹配原串
      expect(re.hasMatch('id="axz"'), isFalse); // 未被当作元字符解释
    });

    test('countIdOccurrences 消费形态：空 id / 普通 id 转义后全局匹配行为不变', () {
      int countWith(String html, String id) {
        final m = RegExp('id="${escapeRegExp(id)}"').allMatches(html);
        return m.length;
      }

      expect(countWith('id="a.b" x id="a.b" y id="plain"', 'a.b'), 2);
      expect(countWith('id="a.b" x id="a.b" y id="plain"', 'plain'), 1);
      expect(countWith('id="a.b" x', 'a.b'), 1);
      expect(countWith('id="a.b" x', 'c.d'), 0);
      expect(countWith('id=""', ''), 1); // 空 id（Falsify）：转义后仍可编译
      expect(countWith('id="x"', ''), 0);
    });

    test('非字符串输入按 String() 归一化（Falsify：不抛错）', () {
      expect(escapeRegExp(123), '123');
      expect(escapeRegExp(null), 'null');
      expect(escapeRegExp(''), '');
    });
  });

  group('wgSessionOnlyIds · wg_ 族游戏 id 集（恰两成员）', () {
    test('恰含小马宝莉 / 高中生模拟器，无多余成员', () {
      expect(wgSessionOnlyIds, {'my-little-pony', 'high-school-sim'});
      expect(wgSessionOnlyIds.contains('my-little-pony'), isTrue);
      expect(wgSessionOnlyIds.contains('high-school-sim'), isTrue);
      expect(wgSessionOnlyIds.contains('life-sim'), isFalse);
      expect(wgSessionOnlyIds.length, 2);
    });
  });

  group('saveKeyIsPattern · 正则模式判定', () {
    test('非字符串 → false（Falsify）', () {
      expect(saveKeyIsPattern(123), isFalse);
      expect(saveKeyIsPattern(null), isFalse);
    });

    test('空串 → false（Falsify）', () {
      expect(saveKeyIsPattern(''), isFalse);
    });

    test('不含正则元字符的精确键名 → false', () {
      expect(saveKeyIsPattern('my_key'), isFalse);
      expect(saveKeyIsPattern('ls_autosave'), isFalse);
      expect(saveKeyIsPattern('god_save_1'), isFalse);
    });

    test('含正则元字符的字符串 → true', () {
      expect(saveKeyIsPattern(r'my_key_\d+'), isTrue);
      expect(saveKeyIsPattern('prefix_.*'), isTrue);
      expect(saveKeyIsPattern('slot_[0-9]+'), isTrue);
      expect(saveKeyIsPattern('a.b'), isTrue);
    });
  });

  group('saveKeyIsValidPattern · 模式可编译验证', () {
    test('非字符串 → false（Falsify）', () {
      expect(saveKeyIsValidPattern(123), isFalse);
      expect(saveKeyIsValidPattern(null), isFalse);
    });

    test('空串 → false（Falsify）', () {
      expect(saveKeyIsValidPattern(''), isFalse);
    });

    test('精确键名（不含正则元字符）→ true（无需编译）', () {
      expect(saveKeyIsValidPattern('my_key'), isTrue);
      expect(saveKeyIsValidPattern('ls_autosave'), isTrue);
      expect(saveKeyIsValidPattern('god_save_1'), isTrue);
    });

    test('含正则元字符 + 可编译 → true', () {
      expect(saveKeyIsValidPattern(r'my_key_\d+'), isTrue);
      expect(saveKeyIsValidPattern('prefix_.*'), isTrue);
      expect(saveKeyIsValidPattern('slot_[0-9]+'), isTrue);
      expect(saveKeyIsValidPattern('a.b'), isTrue);
    });

    test('不可编译 → false（Falsify）', () {
      expect(saveKeyIsValidPattern('[invalid'), isFalse);
      expect(saveKeyIsValidPattern('(unclosed'), isFalse);
      expect(saveKeyIsValidPattern('[a-'), isFalse);
    });
  });

  group('saveKeyMatches · 白名单条目匹配键名', () {
    test('精确键名 === 匹配 → true', () {
      expect(saveKeyMatches('my_key', 'my_key'), isTrue);
      expect(saveKeyMatches('ls_autosave', 'ls_autosave'), isTrue);
    });

    test(r'正则模式 ^…$ 锚定命中 → true', () {
      expect(saveKeyMatches(r'my_key_\d+', 'my_key_123'), isTrue);
      expect(saveKeyMatches('prefix_.*', 'prefix_anything'), isTrue);
      expect(saveKeyMatches(r'god_save_\d+', 'god_save_42'), isTrue);
      expect(saveKeyMatches('slot_[0-9]+', 'slot_7'), isTrue);
    });

    test('不命中 → false', () {
      expect(saveKeyMatches('my_key', 'other_key'), isFalse);
      expect(saveKeyMatches(r'my_key_\d+', 'my_key_abc'), isFalse);
      expect(saveKeyMatches(r'my_key_\d+', 'my_key_123x'), isFalse); // 锚定 ^…$ 尾缀不命中
    });

    test('非字符串 entry → false（Falsify）', () {
      expect(saveKeyMatches(123, 'key'), isFalse);
      expect(saveKeyMatches(null, 'key'), isFalse);
    });

    test('空串 entry → false（Falsify）', () {
      expect(saveKeyMatches('', 'key'), isFalse);
    });

    test('不可编译模式 → false（Falsify）', () {
      expect(saveKeyMatches('[invalid', 'key'), isFalse);
    });

    test('非字符串 keyName → false（Falsify）', () {
      expect(saveKeyMatches('key', 123), isFalse);
      expect(saveKeyMatches('key', null), isFalse);
    });
  });
}
