/**
 * save-key-meta 契约锁（TD-67/68 单一来源 — 行为等价重构，基线绿）。
 *
 * 锁的内容：
 *   1. SAVE_KEY_META_RE 与既有四处字面量副本逐字等价（source 一致 + 无 flag —
 *      test() 判定无 lastIndex 状态）；
 *   2. escapeRegExp 转义结果与旧内联字面量 /[.*+?^${}()|[\]\\]/g 逐字节等价
 *      （含正则元字符全集特殊 id 转义后 new RegExp 可编译且语义为字面量匹配；
 *      countIdOccurrences 消费形态一致）；
 *   3. WG_SESSION_ONLY_IDS 恰含 wg_ 族两游戏（小马宝莉 / 高中生模拟器），
 *      无多余成员（双处硬编码语义合并后的集合契约）。
 *   4. saveKeyIsPattern — 正则模式判定（非字符串/空串 → false）
 *   5. saveKeyIsValidPattern — 模式可编译验证（精确键 → true；可编译 → true；
 *      不可编译 → false）
 *   6. saveKeyMatches — 白名单条目匹配键名（精确 === 或正则 ^…$ 锚定；防御
 *      非字符串/空串/不可编译/非字符串 keyName → false）
 *
 * 本测试文件是契约锁的锚点：产品代码（save-key-meta.js 之外）不得再出现
 * 正则元字符字面量 / wg_ 集合字面量（见工单 02 验收 grep 口径）。
 */
import { describe, it, expect } from 'vitest';
import { SAVE_KEY_META_RE, escapeRegExp, WG_SESSION_ONLY_IDS, saveKeyIsPattern, saveKeyIsValidPattern, saveKeyMatches, __all__ } from '../js/save-key-meta.js';

// 契约锁锚点：迁移前四处字面量副本的一致值（仅测试文件持有，产品代码不得复制）
const LEGACY_SAVE_KEY_META_RE = /[.*+?^${}()|[\]\\]/;

describe('save-key-meta 常量契约（TD-67/68 单一来源）', () => {
    it('SAVE_KEY_META_RE 与既有四处字面量副本逐字等价（source 一致且无 flag）', () => {
        expect(SAVE_KEY_META_RE.source).toBe(LEGACY_SAVE_KEY_META_RE.source);
        expect(SAVE_KEY_META_RE.flags).toBe('');
    });

    it('SAVE_KEY_META_RE test() 判定语义：正则元字符命中、普通键名不命中', () => {
        expect(SAVE_KEY_META_RE.test('a.b')).toBe(true);
        expect(SAVE_KEY_META_RE.test('a^b')).toBe(true);
        expect(SAVE_KEY_META_RE.test('plain_save')).toBe(false);
        expect(SAVE_KEY_META_RE.test('wg_xiaomabaoli_save')).toBe(false);
    });

    it('escapeRegExp 转义结果与旧内联字面量逐字节等价', () => {
        // 旧内联变体（simulator-manifest.test.js :48 迁移前形态）
        const legacy = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const samples = [
            'my-little-pony',
            'high-school-sim',
            'wg_xiaomabaoli_save',
            'a.b*c?d+e{f}g(h)i[j]k\\l^m$n|o',
            'id_123',
            'x[y]z',
            'a\\b',
            'endless_sea_cfg',
        ];
        for (const s of samples) {
            expect(escapeRegExp(s), `样本「${s}」逐字节等价`).toBe(legacy(s));
        }
    });

    it('正则元字符全集特殊 id 转义后 new RegExp 可编译且语义为字面量匹配', () => {
        const special = 'a.*+?^${}()|[]\\z'; // 全集元字符（. * + ? ^ $ { } ( ) | [ ] \）
        const escaped = escapeRegExp(special);
        const re = new RegExp(`id="${escaped}"`);
        expect(re.test(`id="${special}"`)).toBe(true); // 字面量匹配原串
        expect(re.test('id="axz"')).toBe(false); // 未被当作元字符解释
    });

    it('countIdOccurrences 消费形态：空 id / 普通 id 转义后全局匹配行为不变', () => {
        const countWith = (html, id) => {
            const m = html.match(new RegExp(`id="${escapeRegExp(id)}"`, 'g'));
            return m ? m.length : 0;
        };
        expect(countWith('id="a.b" x id="a.b" y id="plain"', 'a.b')).toBe(2);
        expect(countWith('id="a.b" x id="a.b" y id="plain"', 'plain')).toBe(1);
        expect(countWith('id="a.b" x', 'a.b')).toBe(1);
        expect(countWith('id="a.b" x', 'c.d')).toBe(0);
        // 空 id（Falsify）：转义后仍可编译，仅匹配字面空 id 属性
        expect(countWith('id=""', '')).toBe(1);
        expect(countWith('id="x"', '')).toBe(0);
    });

    it('escapeRegExp 非字符串输入按 String() 归一化（Falsify：不抛错）', () => {
        expect(escapeRegExp(123)).toBe('123');
        expect(escapeRegExp(null)).toBe('null');
        expect(escapeRegExp(undefined)).toBe('undefined');
        expect(escapeRegExp('')).toBe('');
    });

    it('WG_SESSION_ONLY_IDS 恰含 wg_ 族两游戏（小马宝莉 / 高中生模拟器），无多余成员', () => {
        expect(WG_SESSION_ONLY_IDS).toEqual(new Set(['my-little-pony', 'high-school-sim']));
        expect(WG_SESSION_ONLY_IDS.has('my-little-pony')).toBe(true);
        expect(WG_SESSION_ONLY_IDS.has('high-school-sim')).toBe(true);
        expect(WG_SESSION_ONLY_IDS.has('life-sim')).toBe(false);
        expect(WG_SESSION_ONLY_IDS.size).toBe(2);
    });
});

// ══════════════════════════════════════════════════
// saveKeyIsPattern — 正则模式判定
// ══════════════════════════════════════════════════

describe('saveKeyIsPattern — 正则模式判定', () => {
    it('非字符串 → false（Falsify）', () => {
        expect(saveKeyIsPattern(123)).toBe(false);
        expect(saveKeyIsPattern(null)).toBe(false);
        expect(saveKeyIsPattern(undefined)).toBe(false);
    });

    it('空串 → false（Falsify）', () => {
        expect(saveKeyIsPattern('')).toBe(false);
    });

    it('不含正则元字符的精确键名 → false', () => {
        expect(saveKeyIsPattern('my_key')).toBe(false);
        expect(saveKeyIsPattern('ls_autosave')).toBe(false);
        expect(saveKeyIsPattern('god_save_1')).toBe(false);
    });

    it('含正则元字符的字符串 → true', () => {
        expect(saveKeyIsPattern('my_key_\\d+')).toBe(true);
        expect(saveKeyIsPattern('prefix_.*')).toBe(true);
        expect(saveKeyIsPattern('slot_[0-9]+')).toBe(true);
        expect(saveKeyIsPattern('a.b')).toBe(true);
    });
});

// ══════════════════════════════════════════════════
// saveKeyIsValidPattern — 模式可编译验证
// ══════════════════════════════════════════════════

describe('saveKeyIsValidPattern — 模式可编译验证', () => {
    it('非字符串 → false（Falsify）', () => {
        expect(saveKeyIsValidPattern(123)).toBe(false);
        expect(saveKeyIsValidPattern(null)).toBe(false);
    });

    it('空串 → false（Falsify）', () => {
        expect(saveKeyIsValidPattern('')).toBe(false);
    });

    it('精确键名（不含正则元字符）→ true（无需编译）', () => {
        expect(saveKeyIsValidPattern('my_key')).toBe(true);
        expect(saveKeyIsValidPattern('ls_autosave')).toBe(true);
        expect(saveKeyIsValidPattern('god_save_1')).toBe(true);
    });

    it('含正则元字符 + 可编译 → true', () => {
        expect(saveKeyIsValidPattern('my_key_\\d+')).toBe(true);
        expect(saveKeyIsValidPattern('prefix_.*')).toBe(true);
        expect(saveKeyIsValidPattern('slot_[0-9]+')).toBe(true);
        expect(saveKeyIsValidPattern('a.b')).toBe(true);
    });

    it('不可编译 → false（Falsify）', () => {
        expect(saveKeyIsValidPattern('[invalid')).toBe(false);
        expect(saveKeyIsValidPattern('(unclosed')).toBe(false);
        expect(saveKeyIsValidPattern('[a-')).toBe(false);
    });
});

// ══════════════════════════════════════════════════
// saveKeyMatches — 白名单条目匹配键名
// ══════════════════════════════════════════════════

describe('saveKeyMatches — 白名单条目匹配键名', () => {
    // ── happy path ──
    it('精确键名 === 匹配 → true', () => {
        expect(saveKeyMatches('my_key', 'my_key')).toBe(true);
        expect(saveKeyMatches('ls_autosave', 'ls_autosave')).toBe(true);
    });

    it('正则模式 ^…$ 锚定命中 → true', () => {
        expect(saveKeyMatches('my_key_\\d+', 'my_key_123')).toBe(true);
        expect(saveKeyMatches('prefix_.*', 'prefix_anything')).toBe(true);
        expect(saveKeyMatches('god_save_\\d+', 'god_save_42')).toBe(true);
        expect(saveKeyMatches('slot_[0-9]+', 'slot_7')).toBe(true);
    });

    it('不命中 → false', () => {
        expect(saveKeyMatches('my_key', 'other_key')).toBe(false);
        expect(saveKeyMatches('my_key_\\d+', 'my_key_abc')).toBe(false);
        expect(saveKeyMatches('my_key_\\d+', 'my_key_123x')).toBe(false); // 锚定 ^…$ 尾缀不命中
    });

    // ── Falsify 防御 ──
    it('非字符串 entry → false', () => {
        expect(saveKeyMatches(123, 'key')).toBe(false);
        expect(saveKeyMatches(null, 'key')).toBe(false);
        expect(saveKeyMatches(undefined, 'key')).toBe(false);
    });

    it('空串 entry → false', () => {
        expect(saveKeyMatches('', 'key')).toBe(false);
    });

    it('不可编译模式 → false', () => {
        expect(saveKeyMatches('[invalid', 'key')).toBe(false);
    });

    it('非字符串 keyName → false', () => {
        expect(saveKeyMatches('key', 123)).toBe(false);
        expect(saveKeyMatches('key', null)).toBe(false);
    });
});

// ══════════════════════════════════════════════════
// 协议表面 __all__ 更新
// ══════════════════════════════════════════════════

describe('save-key-meta __all__ 协议表面', () => {
    it('__all__ 包含新增的三个匹配语义函数', () => {
        expect(__all__).toContain('saveKeyIsPattern');
        expect(__all__).toContain('saveKeyIsValidPattern');
        expect(__all__).toContain('saveKeyMatches');
    });

    it('__all__ 仍包含既有常量与函数', () => {
        expect(__all__).toContain('SAVE_KEY_META_RE');
        expect(__all__).toContain('escapeRegExp');
        expect(__all__).toContain('WG_SESSION_ONLY_IDS');
    });
});
