/**
 * Mod codec 深模块契约锁（F-103 — 行为等价迁移，基线绿）。
 *
 * 覆盖（8 个 codec 纯函数 + 目标区域常量，从 mod-manager.js 原样迁入，
 * 断言与迁移前 mod-manager.test.js 第 1~4、5（导入容错两条）、8 节逐字一致）：
 *   1. prompt 三区域 payload 序列化/解析（serializePromptPayload / parsePromptPayload）
 *   2. 表单校验（validateModForm：名称必填 / target_area 收口三值）
 *   3. 保存 payload 按区域切换形态（buildModPayload：prompt → JSON 字符串，memory/css → 自由文本）
 *   4. 导入导出信封（buildExportEnvelope 字面命中 version/mods 键；parseImportEnvelope 拒非法）
 *   5. 导入容错（importModsFromEnvelope：逐条 mods.create，单条失败不阻断其余，source 落 imported）
 *   6. 排序交换（computeSortSwap：相邻交换 sort_order，边界越界 no-op）
 *   7. __all__ 协议表面（TARGET_AREAS + 8 函数全覆盖）
 *
 * 挂载模式：jsdom + vi.mock(api.js)（导入容错用假 mods；其余纯函数不依赖 DOM）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// 导入落库组 mock API 层（mod-codec.js import './api.js' 解析到同一模块）
vi.mock('../js/api.js', () => ({
    mods: {
        list: vi.fn(), create: vi.fn(), update: vi.fn(), delete: vi.fn(),
        listCharacterMods: vi.fn(), bind: vi.fn(), setEnabled: vi.fn(),
        setSortOrder: vi.fn(), unbind: vi.fn(),
    },
}));

import { mods } from '../js/api.js';
import {
    TARGET_AREAS,
    serializePromptPayload,
    parsePromptPayload,
    validateModForm,
    buildModPayload,
    computeSortSwap,
    buildExportEnvelope,
    parseImportEnvelope,
    importModsFromEnvelope,
    __all__,
} from '../js/mod-codec.js';

const flush = () => new Promise((r) => setTimeout(r, 0));

describe('1. prompt 三区域 payload 序列化/解析', () => {
    it('TARGET_AREAS 收口三值', () => {
        expect(TARGET_AREAS).toEqual(['prompt', 'memory', 'css']);
    });

    it('serializePromptPayload 输出 {world,before_char,after_char} JSON 字符串', () => {
        expect(JSON.parse(serializePromptPayload('w', 'b', 'a'))).toEqual({ world: 'w', before_char: 'b', after_char: 'a' });
        expect(JSON.parse(serializePromptPayload())).toEqual({ world: '', before_char: '', after_char: '' });
    });

    it('parsePromptPayload：合法 JSON 提取三区域；非法回退全空', () => {
        expect(parsePromptPayload('{"world":"w","before_char":"b","after_char":"a"}')).toEqual({ world: 'w', before_char: 'b', after_char: 'a' });
        expect(parsePromptPayload('not-json')).toEqual({ world: '', before_char: '', after_char: '' });
        expect(parsePromptPayload('42')).toEqual({ world: '', before_char: '', after_char: '' });
        expect(parsePromptPayload(null)).toEqual({ world: '', before_char: '', after_char: '' });
        expect(parsePromptPayload('')).toEqual({ world: '', before_char: '', after_char: '' });
    });
});

describe('2. 表单校验 validateModForm', () => {
    it('名称空 → 阻止 + name 错误', () => {
        const r = validateModForm({ name: '  ', target_area: 'prompt' });
        expect(r.ok).toBe(false);
        expect(r.errors.name).toContain('名称');
    });

    it('非法 target_area → 阻止 + target_area 错误', () => {
        const r = validateModForm({ name: 'A', target_area: 'bogus' });
        expect(r.ok).toBe(false);
        expect(r.errors.target_area).toBeTruthy();
    });

    it('合法（名称 + 有效区域）→ ok', () => {
        expect(validateModForm({ name: 'A', target_area: 'memory' }).ok).toBe(true);
    });
});

describe('3. buildModPayload 按区域切换 payload 形态', () => {
    it('prompt 区：payload 序列化为三区域 JSON 字符串', () => {
        const p = buildModPayload({ name: 'M', description: 'd', target_area: 'prompt', world: 'w', before_char: 'b', after_char: 'a' });
        expect(p.name).toBe('M');
        expect(p.target_area).toBe('prompt');
        expect(JSON.parse(p.payload)).toEqual({ world: 'w', before_char: 'b', after_char: 'a' });
    });

    it('memory/css 区：payload 为自由文本', () => {
        expect(buildModPayload({ name: 'M', target_area: 'memory', payload: 'raw' }).payload).toBe('raw');
        expect(buildModPayload({ name: 'M', target_area: 'css', payload: 'p { color: red }' }).payload).toBe('p { color: red }');
    });

    it('name 裁剪空白；非法 target_area 回退 prompt', () => {
        const p = buildModPayload({ name: '  X  ', target_area: 'bogus', world: '', before_char: '', after_char: '' });
        expect(p.name).toBe('X');
        expect(p.target_area).toBe('prompt');
    });
});

describe('4. 导入导出信封', () => {
    it('buildExportEnvelope 字面命中 version 与 mods 键', () => {
        const e = buildExportEnvelope([{ id: 1 }, { id: 2 }]);
        expect(e.version).toBe(1);
        expect(e.mods).toEqual([{ id: 1 }, { id: 2 }]);
    });

    it('parseImportEnvelope：非法 JSON / version 不符 / mods 非数组 → 报错', () => {
        expect(parseImportEnvelope('not-json').ok).toBe(false);
        expect(parseImportEnvelope('{"version":2,"mods":[]}').ok).toBe(false);
        expect(parseImportEnvelope('{"version":1,"mods":{}}').ok).toBe(false);
        expect(parseImportEnvelope('').ok).toBe(false);
    });

    it('parseImportEnvelope：合法信封通过', () => {
        const r = parseImportEnvelope('{"version":1,"mods":[{"name":"A"}]}');
        expect(r.ok).toBe(true);
        expect(r.mods).toEqual([{ name: 'A' }]);
    });

    it('parseImportEnvelope：JSON null/数组/标量（非对象信封）→ 信封格式错误（Falsify）', () => {
        expect(parseImportEnvelope('null').error).toBe('信封格式错误');
        expect(parseImportEnvelope('[]').error).toBe('信封格式错误');
        expect(parseImportEnvelope('42').error).toBe('信封格式错误');
        expect(parseImportEnvelope('"str"').error).toBe('信封格式错误');
    });
});

describe('5. 导入落库容错 importModsFromEnvelope（mock api.js）', () => {
    beforeEach(() => {
        vi.resetAllMocks();
    });
    afterEach(() => {
        vi.restoreAllMocks();
    });

    it('非法信封报错不落库（mods.create 未调用）', async () => {
        const r = await importModsFromEnvelope('not-json');
        expect(r.ok).toBe(false);
        expect(mods.create).not.toHaveBeenCalled();
    });

    it('合法信封逐条 create，单条失败不阻断其余（容错）', async () => {
        mods.create.mockRejectedValueOnce(new Error('重复'));
        mods.create.mockResolvedValue({ id: 1 });

        const r = await importModsFromEnvelope('{"version":1,"mods":[{"name":"A","target_area":"prompt","payload":"x"},{"name":"B","target_area":"css","payload":"y"},{"name":"C","target_area":"memory","payload":"z"}]}');

        expect(mods.create).toHaveBeenCalledTimes(3);
        expect(r.ok).toBe(true);
        expect(r.imported).toBe(2);
        expect(r.failed).toBe(1);
        expect(mods.create.mock.calls[0][0].source).toBe('imported');
        expect(mods.create.mock.calls[1][0].target_area).toBe('css');
    });

    it('非对象条目（null / 标量）→ 逐条跳过 failed 计数，不落库（Falsify）', async () => {
        mods.create.mockResolvedValue({ id: 1 });

        const r = await importModsFromEnvelope('{"version":1,"mods":[null,42,{"name":"A","target_area":"prompt","payload":"x"}]}');

        expect(mods.create).toHaveBeenCalledTimes(1);
        expect(r.ok).toBe(true);
        expect(r.imported).toBe(1);
        expect(r.failed).toBe(2);
    });

    it('数组条目（[] / [{name:"A"}]）→ 拒绝 failed 计数，不落库；合法对象条目照常导入（F-106）', async () => {
        mods.create.mockResolvedValue({ id: 1 });

        const r = await importModsFromEnvelope('{"version":1,"mods":[[],[{"name":"A"}],{"name":"B","target_area":"prompt","payload":"x"}]}');

        expect(mods.create).toHaveBeenCalledTimes(1);
        expect(r.ok).toBe(true);
        expect(r.imported).toBe(1);
        expect(r.failed).toBe(2);
        // 唯一一次 create 是合法对象条目 B，且 source 强制 imported
        expect(mods.create.mock.calls[0][0].name).toBe('B');
        expect(mods.create.mock.calls[0][0].source).toBe('imported');
    });
});

describe('6. computeSortSwap 纯函数', () => {
    const bindings = [
        { id: 11, sort_order: 0 },
        { id: 12, sort_order: 10 },
        { id: 13, sort_order: 20 },
    ];

    it('up：与前一交换 sort_order', () => {
        expect(computeSortSwap(bindings, 1, 'up')).toEqual([
            { id: 12, sortOrder: 0 },
            { id: 11, sortOrder: 10 },
        ]);
    });

    it('down：与后一交换 sort_order', () => {
        expect(computeSortSwap(bindings, 1, 'down')).toEqual([
            { id: 12, sortOrder: 20 },
            { id: 13, sortOrder: 10 },
        ]);
    });

    it('边界越界 → 空数组（no-op）', () => {
        expect(computeSortSwap(bindings, 0, 'up')).toEqual([]);
        expect(computeSortSwap(bindings, 2, 'down')).toEqual([]);
    });
});

// ════════════════════════════════════════════════════════════════
// 协议表面 __all__（深模块：外部只通过这些符号与 mod-codec.js 交互）
// ════════════════════════════════════════════════════════════════

describe('7. __all__ 协议表面', () => {
    it('__all__ 覆盖全部公开导出（TARGET_AREAS + 8 codec 函数）', () => {
        for (const name of ['TARGET_AREAS', 'serializePromptPayload', 'parsePromptPayload',
            'validateModForm', 'buildModPayload', 'computeSortSwap',
            'buildExportEnvelope', 'parseImportEnvelope', 'importModsFromEnvelope']) {
            expect(__all__).toContain(name);
        }
    });
});
