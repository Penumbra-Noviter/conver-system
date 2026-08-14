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
 *
 * 本测试文件是契约锁的锚点：产品代码（save-key-meta.js 之外）不得再出现
 * 正则元字符字面量 / wg_ 集合字面量（见工单 02 验收 grep 口径）。
 */
import { describe, it, expect } from 'vitest';
import { SAVE_KEY_META_RE, escapeRegExp, WG_SESSION_ONLY_IDS } from '../js/save-key-meta.js';

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
