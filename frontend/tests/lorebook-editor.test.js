/**
 * 世界书编辑器契约锁（WL-4，spec §WL-4）
 *
 * 覆盖：
 *   1. 关键词 chips 录入/去重/删除（addKeyChip / removeKeyChip）
 *   2. 表单校验：内容超限/关键词为空/数值越界 → 阻止提交 + 内联错误（validateLorebookEntry）
 *   3. 泛词告警触发条件（isGenericKey：单字符或高频泛词）
 *   4. 保存 payload 字段与后端 schemas/lorebook.py LorebookEntryBase 逐字段一致
 *      （buildLorebookPayload 字段名集合单一来源）
 *   5. 列表渲染：开关状态、常驻标记、搜索过滤（showLorebookEditor + mock API）
 *
 * 挂载模式：jsdom + vi.mock(api.js)（列表渲染用假数据；纯函数组不依赖 DOM）。
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

// 列表渲染组 mock API 层（组件 import '../api.js' 解析到同一模块）
vi.mock('../js/api.js', () => ({
    lorebook: { list: vi.fn(), create: vi.fn(), update: vi.fn(), delete: vi.fn() },
}));

// ── 纯函数组（不 mock，直接导入）──
import {
    addKeyChip,
    removeKeyChip,
    isGenericKey,
    validateLorebookEntry,
    buildLorebookPayload,
    CONTENT_MAX_LENGTH,
    __all__,
} from '../js/components/lorebook-editor.js';

const flush = () => new Promise((r) => setTimeout(r, 0));

describe('1. 关键词 chips 录入/去重/删除', () => {
    it('录入：裁剪空白并追加', () => {
        expect(addKeyChip([], ' 酒馆 ')).toEqual(['酒馆']);
        expect(addKeyChip(['酒馆'], '龙')).toEqual(['酒馆', '龙']);
    });

    it('去重：重复关键词返回原列表；空输入返回原列表', () => {
        const keys = ['酒馆'];
        expect(addKeyChip(keys, '酒馆')).toBe(keys);
        expect(addKeyChip(keys, '   ')).toBe(keys);
        expect(addKeyChip(keys, '')).toBe(keys);
    });

    it('删除：精确移除指定关键词', () => {
        expect(removeKeyChip(['酒馆', '龙', '龙'], '龙')).toEqual(['酒馆']);
        expect(removeKeyChip(['酒馆'], '不存在')).toEqual(['酒馆']);
    });
});

describe('2. 表单校验：阻止提交 + 内联错误', () => {
    const base = {
        title: '', keys: ['酒馆'], content: '', constant: false,
        order: 100, probability: 100, group_name: '', group_weight: 100,
        match_mode: 'or', position: 'world', depth: 20, enabled: true,
    };

    it('合法条目通过（ok=true，无错误）', () => {
        const r = validateLorebookEntry(base);
        expect(r.ok).toBe(true);
        expect(r.errors).toEqual({});
    });

    it('内容超限 → 阻止 + content 错误', () => {
        const r = validateLorebookEntry({ ...base, content: 'x'.repeat(CONTENT_MAX_LENGTH + 1) });
        expect(r.ok).toBe(false);
        expect(r.errors.content).toContain('内容过长');
    });

    it('关键词为空且非常驻 → 阻止 + keys 错误（常驻时豁免）', () => {
        expect(validateLorebookEntry({ ...base, keys: [] }).errors.keys).toContain('至少填写一个触发关键词');
        expect(validateLorebookEntry({ ...base, keys: [], constant: true }).ok).toBe(true);
    });

    it('数值越界（order/probability/depth/group_weight）→ 阻止 + 字段级错误', () => {
        const r = validateLorebookEntry({ ...base, order: -1, probability: 200, depth: 99, group_weight: 0 });
        expect(r.ok).toBe(false);
        expect(r.errors.order).toContain('0-9999');
        expect(r.errors.probability).toContain('1-100');
        expect(r.errors.depth).toContain('0-20');
        expect(r.errors.group_weight).toContain('1-100');
    });
});

describe('3. 泛词告警触发条件', () => {
    it('单字符 → 泛词；多字符有信息量词 → 非泛词', () => {
        expect(isGenericKey('你')).toBe(true);
        expect(isGenericKey('。')).toBe(true);
        expect(isGenericKey('酒馆')).toBe(false);
        expect(isGenericKey('莉莉')).toBe(false);
    });

    it('高频虚词 → 泛词；单字符任何词 → 泛词（spec：keys 含 1 字符即告警）', () => {
        expect(isGenericKey('的')).toBe(true);
        expect(isGenericKey(' ')).toBe(true);
        expect(isGenericKey('龙')).toBe(true); // 单字符（即使有信息量）→ 泛词
        expect(isGenericKey('莉莉')).toBe(false); // 多字符非虚词 → 非泛词
    });
});

describe('4. 保存 payload 与后端 schema 逐字段一致（单一来源映射）', () => {
    const BACKEND_FIELDS = [
        'title', 'keys', 'content', 'constant', 'order', 'probability',
        'group_name', 'group_weight', 'match_mode', 'position', 'depth', 'enabled',
    ];

    it('payload 字段名集合与后端 LorebookEntryBase 完全一致', () => {
        const payload = buildLorebookPayload({
            title: '酒馆', keys: ['酒馆'], content: '内容', constant: false,
            order: '50', probability: '80', group_name: '', group_weight: '30',
            match_mode: 'or', position: 'world', depth: '10', enabled: true,
        });
        expect(Object.keys(payload).sort()).toEqual([...BACKEND_FIELDS].sort());
    });

    it('类型化：数值字符串 → Number；布尔 → Boolean', () => {
        const payload = buildLorebookPayload({
            title: '', keys: [], content: '', constant: true,
            order: '50', probability: '80', group_name: '', group_weight: '30',
            match_mode: 'and', position: 'before_char', depth: '10', enabled: false,
        });
        expect(payload.order).toBe(50);
        expect(payload.probability).toBe(80);
        expect(payload.constant).toBe(true);
        expect(payload.enabled).toBe(false);
        expect(payload.match_mode).toBe('and');
        expect(payload.position).toBe('before_char');
    });
});

describe('5. 列表渲染：开关状态/常驻标记/搜索过滤', () => {
    beforeEach(() => {
        document.body.innerHTML = '';
        vi.resetModules();
    });

    it('渲染条目行：常驻标记、启用开关状态、关键词预览', async () => {
        const { lorebook } = await import('../js/api.js');
        const { showLorebookEditor } = await import('../js/components/lorebook-editor.js');
        lorebook.list.mockResolvedValue([
            { id: 1, title: '酒馆', keys: ['酒馆', 'tavern', '龙', '皇宫'], enabled: true, order: 10, constant: false },
            { id: 2, title: '常驻指引', keys: [], enabled: false, order: 20, constant: true },
        ]);

        showLorebookEditor({ characterId: 1, characterName: '测试角色' });
        await flush();

        const rows = document.querySelectorAll('.lorebook-row');
        expect(rows.length).toBe(2);
        expect(rows[0].textContent).toContain('酒馆');
        expect(rows[0].textContent).toContain('+1'); // 关键词前 3 + 计数
        expect(rows[0].querySelector('[data-lorebook-toggle]').dataset.lorebookToggle).toBe('1');
        expect(rows[1].textContent).toContain('常驻'); // 常驻标记
        expect(rows[1].classList.contains('is-constant')).toBe(true);
    });

    it('搜索过滤：按标题/关键词缩小列表', async () => {
        const { lorebook } = await import('../js/api.js');
        const { showLorebookEditor } = await import('../js/components/lorebook-editor.js');
        lorebook.list.mockResolvedValue([
            { id: 1, title: '酒馆', keys: ['酒馆'], enabled: true, order: 10, constant: false },
            { id: 2, title: '皇宫', keys: ['龙'], enabled: true, order: 20, constant: false },
        ]);

        showLorebookEditor({ characterId: 1, characterName: '测试角色' });
        await flush();

        const search = document.querySelector('[data-lorebook-search]');
        search.value = '龙';
        search.dispatchEvent(new Event('input'));
        await flush();

        const rows = document.querySelectorAll('.lorebook-row');
        expect(rows.length).toBe(1);
        expect(rows[0].textContent).toContain('皇宫');
    });

    it('空世界书 → 空态提示', async () => {
        const { lorebook } = await import('../js/api.js');
        const { showLorebookEditor } = await import('../js/components/lorebook-editor.js');
        lorebook.list.mockResolvedValue([]);

        showLorebookEditor({ characterId: 1, characterName: '测试角色' });
        await flush();

        expect(document.querySelector('.lorebook-empty').textContent).toContain('还没有世界书条目');
    });

    it('协议表面：__all__ 覆盖全部公开导出', () => {
        for (const name of ['showLorebookEditor', 'isGenericKey', 'validateLorebookEntry',
            'buildLorebookPayload', 'addKeyChip', 'removeKeyChip']) {
            expect(__all__).toContain(name);
        }
    });
});
