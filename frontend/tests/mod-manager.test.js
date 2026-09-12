/**
 * Mod 管理面板契约锁（MD-2 / 03，spec §MD-2）
 *
 * 覆盖：
 *   1. prompt 三区域 payload 序列化/解析（serializePromptPayload / parsePromptPayload）
 *   2. 表单校验（validateModForm：名称必填 / target_area 收口三值）
 *   3. 保存 payload 按区域切换形态（buildModPayload：prompt → JSON 字符串，memory/css → 自由文本）
 *   4. 导入导出信封（buildExportEnvelope 字面命中 version/mods 键；parseImportEnvelope 拒非法）
 *   5. 导入容错（importModsFromEnvelope：逐条 mods.create，单条失败不阻断其余，source 落 imported）
 *   6. 面板渲染与交互（showModManager：标题含角色名 / 列表 id 升序 / 新建 / 编辑 / 删除 / 导出）
 *
 * 挂载模式：jsdom + vi.mock(api.js)（面板与导入用假 mods；纯函数组不依赖 DOM）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { iconHtml } from '../js/icons.js';

// 面板/导入组 mock API 层（组件 import '../api.js' 解析到同一模块）
vi.mock('../js/api.js', () => ({
    mods: {
        list: vi.fn(), create: vi.fn(), update: vi.fn(), delete: vi.fn(),
        listCharacterMods: vi.fn(), bind: vi.fn(), setEnabled: vi.fn(),
        setSortOrder: vi.fn(), unbind: vi.fn(),
    },
}));

import { mods } from '../js/api.js';
import {
    showModManager,
    computeSortSwap,
    TARGET_AREAS,
    serializePromptPayload,
    parsePromptPayload,
    validateModForm,
    buildModPayload,
    buildExportEnvelope,
    parseImportEnvelope,
    importModsFromEnvelope,
    __all__,
} from '../js/components/mod-manager.js';

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
});

describe('5. 面板渲染与交互（mock api.js + DOM）', () => {
    beforeEach(() => {
        document.body.innerHTML = '';
        vi.resetAllMocks();
    });

    it('打开模态框：标题含角色名 + 关闭按钮 + Escape 关闭', async () => {
        mods.list.mockResolvedValue([]);

        showModManager({ characterName: '测试角色' });
        await flush();

        const overlay = document.querySelector('.mod-manager-modal');
        expect(overlay).not.toBeNull();
        expect(overlay.querySelector('.modal-header h3').textContent).toContain('测试角色');
        expect(overlay.querySelector('.modal-close')).not.toBeNull();

        overlay.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
        await flush();
        expect(document.querySelector('.mod-manager-modal')).toBeNull();
    });

    it('列表渲染 id 升序 + 每行显示名称/target_area/source', async () => {
        mods.list.mockResolvedValue([
            { id: 3, name: 'C', target_area: 'css', source: 'manual', payload: '' },
            { id: 1, name: 'A', target_area: 'prompt', source: 'imported', payload: '' },
            { id: 2, name: 'B', target_area: 'memory', source: 'manual', payload: '' },
        ]);

        showModManager({ characterName: 'R' });
        await flush();

        const rows = document.querySelectorAll('.mod-row');
        expect(rows.length).toBe(3);
        expect(rows[0].textContent).toContain('A');
        expect(rows[0].textContent).toContain('prompt');
        expect(rows[0].textContent).toContain('imported');
        expect(rows[1].textContent).toContain('B');
        expect(rows[2].textContent).toContain('C');
    });

    it('新建 Mod：填名称 + 选区域 + 填 payload → mods.create 且 payload 往返一致', async () => {
        mods.list.mockResolvedValue([]);
        mods.create.mockResolvedValue({ id: 9 });

        showModManager({ characterName: 'R' });
        await flush();
        document.querySelector('[data-mod-add]').click();
        await flush();

        document.querySelector('#mod-name').value = '新Mod';
        document.querySelector('#mod-world').value = '世界知识';
        document.querySelector('#mod-before-char').value = '角色前';
        document.querySelector('#mod-after-char').value = '角色后';
        document.querySelector('#mod-save').click();
        await flush();

        expect(mods.create).toHaveBeenCalledTimes(1);
        const arg = mods.create.mock.calls[0][0];
        expect(arg.name).toBe('新Mod');
        expect(arg.target_area).toBe('prompt');
        expect(JSON.parse(arg.payload)).toEqual({ world: '世界知识', before_char: '角色前', after_char: '角色后' });
    });

    it('新建校验失败（名称为空）→ 内联错误且不调 create', async () => {
        mods.list.mockResolvedValue([]);

        showModManager({ characterName: 'R' });
        await flush();
        document.querySelector('[data-mod-add]').click();
        await flush();

        document.querySelector('#mod-save').click();
        await flush();

        expect(document.querySelector('#mod-name-error').textContent).toContain('名称');
        expect(mods.create).not.toHaveBeenCalled();
    });

    it('编辑 Mod：预填现有字段 → 保存 mods.update（不携带不可变字段）', async () => {
        mods.list.mockResolvedValue([{ id: 1, name: '旧名', description: '旧描述', target_area: 'memory', payload: '旧内容', source: 'manual' }]);
        mods.update.mockResolvedValue({ id: 1 });

        showModManager({ characterName: 'R' });
        await flush();
        document.querySelector('[data-mod-edit]').click();
        await flush();

        expect(document.querySelector('#mod-name').value).toBe('旧名');
        expect(document.querySelector('#mod-area').value).toBe('memory');
        expect(document.querySelector('#mod-payload').value).toBe('旧内容');

        document.querySelector('#mod-name').value = '新名';
        document.querySelector('#mod-area').value = 'css';
        document.querySelector('#mod-payload').value = '新内容';
        document.querySelector('#mod-save').click();
        await flush();

        expect(mods.update).toHaveBeenCalledTimes(1);
        const [id, payload] = mods.update.mock.calls[0];
        expect(id).toBe(1);
        expect(payload.name).toBe('新名');
        expect(payload.target_area).toBe('css');
        expect(payload.payload).toBe('新内容');
        expect(payload).not.toHaveProperty('id');
        expect(payload).not.toHaveProperty('source');
    });

    it('prompt Mod 编辑：三区域预填往返一致', async () => {
        mods.list.mockResolvedValue([{ id: 1, name: 'P', description: '', target_area: 'prompt', payload: '{"world":"w","before_char":"b","after_char":"a"}', source: 'manual' }]);

        showModManager({ characterName: 'R' });
        await flush();
        document.querySelector('[data-mod-edit]').click();
        await flush();

        expect(document.querySelector('#mod-world').value).toBe('w');
        expect(document.querySelector('#mod-before-char').value).toBe('b');
        expect(document.querySelector('#mod-after-char').value).toBe('a');
    });

    it('删除 Mod：showConfirm 确认后 mods.delete 并从列表移除', async () => {
        mods.list.mockResolvedValue([{ id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' }]);
        mods.delete.mockResolvedValue(null);

        showModManager({ characterName: 'R' });
        await flush();
        document.querySelector('[data-mod-del]').click();
        await flush();

        expect(document.querySelector('.confirm-modal')).not.toBeNull();
        document.querySelector('.confirm-ok').click();
        await flush();

        expect(mods.delete).toHaveBeenCalledWith(1);
        expect(document.querySelectorAll('.mod-row').length).toBe(0);
    });

    it('导出：Blob 下载，JSON 字面命中 version 与 mods 键', async () => {
        mods.list.mockResolvedValue([
            { id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: 'x' },
            { id: 2, name: 'B', target_area: 'css', source: 'imported', payload: 'y' },
        ]);

        const createObjectURL = vi.fn(() => 'blob:mock');
        const revokeObjectURL = vi.fn();
        const origCreate = URL.createObjectURL;
        const origRevoke = URL.revokeObjectURL;
        URL.createObjectURL = createObjectURL;
        URL.revokeObjectURL = revokeObjectURL;
        try {
            showModManager({ characterName: 'R' });
            await flush();
            document.querySelector('[data-mod-export]').click();
            await flush();

            expect(createObjectURL).toHaveBeenCalledTimes(1);
            const blob = createObjectURL.mock.calls[0][0];
            expect(blob).toBeInstanceOf(Blob);
            // jsdom Blob 无 .text()：用 FileReader 读回内容断言信封
            const text = await new Promise((resolve, reject) => {
                const reader = new FileReader();
                reader.onload = () => resolve(reader.result);
                reader.onerror = () => reject(reader.error);
                reader.readAsText(blob);
            });
            const parsed = JSON.parse(text);
            expect(parsed.version).toBe(1);
            expect(Array.isArray(parsed.mods)).toBe(true);
            expect(parsed.mods.length).toBe(2);
            expect(revokeObjectURL).toHaveBeenCalledWith('blob:mock');
        } finally {
            URL.createObjectURL = origCreate;
            URL.revokeObjectURL = origRevoke;
        }
    });

    it('导入：非法信封报错不落库（mods.create 未调用）', async () => {
        const r = await importModsFromEnvelope('not-json');
        expect(r.ok).toBe(false);
        expect(mods.create).not.toHaveBeenCalled();
    });

    it('导入：文件输入读取合法信封 → 逐条 create 并刷新列表', async () => {
        mods.list.mockResolvedValue([]);
        mods.create.mockResolvedValue({ id: 1 });

        showModManager({ characterName: 'R' });
        await flush();

        const input = document.querySelector('[data-mod-import-file]');
        const file = new File(['{"version":1,"mods":[{"name":"A","target_area":"prompt","payload":"x"}]}'], 'mods.json', { type: 'application/json' });
        Object.defineProperty(input, 'files', { value: [file], configurable: true });
        input.dispatchEvent(new Event('change'));
        await flush();
        await flush();

        expect(mods.create).toHaveBeenCalledWith(expect.objectContaining({ name: 'A', source: 'imported' }));
        expect(mods.list).toHaveBeenCalledTimes(2); // 初始 + 导入后刷新
    });

    it('导入：文件输入读取非法信封 → 报错不落库', async () => {
        mods.list.mockResolvedValue([]);

        showModManager({ characterName: 'R' });
        await flush();

        const input = document.querySelector('[data-mod-import-file]');
        const file = new File(['{"version":2,"mods":[]}'], 'mods.json', { type: 'application/json' });
        Object.defineProperty(input, 'files', { value: [file], configurable: true });
        input.dispatchEvent(new Event('change'));
        await flush();
        await flush();

        expect(mods.create).not.toHaveBeenCalled();
    });

    it('编辑：target_area 切换 prompt ↔ memory 切换录入形态', async () => {
        mods.list.mockResolvedValue([]);

        showModManager({ characterName: 'R' });
        await flush();
        document.querySelector('[data-mod-add]').click();
        await flush();

        // 默认 prompt：三区域可见，自由文本隐藏
        expect(document.querySelector('[data-mod-prompt-fields]').hidden).toBe(false);
        expect(document.querySelector('[data-mod-free-fields]').hidden).toBe(true);

        // 切到 memory：自由文本可见，三区域隐藏
        const area = document.querySelector('#mod-area');
        area.value = 'memory';
        area.dispatchEvent(new Event('change'));
        await flush();

        expect(document.querySelector('[data-mod-prompt-fields]').hidden).toBe(true);
        expect(document.querySelector('[data-mod-free-fields]').hidden).toBe(false);
    });

    it('导入：合法信封逐条 create，单条失败不阻断其余（容错）', async () => {
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

    it('新建保存失败（API 抛错）→ 提示且不崩溃', async () => {
        mods.list.mockResolvedValue([]);
        mods.create.mockRejectedValue(new Error('网络错误'));

        showModManager({ characterName: 'R' });
        await flush();
        document.querySelector('[data-mod-add]').click();
        await flush();

        document.querySelector('#mod-name').value = '新Mod';
        document.querySelector('#mod-save').click();
        await flush();

        expect(mods.create).toHaveBeenCalledTimes(1);
        expect(document.querySelector('.mod-editor')).not.toBeNull(); // 仍停留编辑视图，未崩溃
    });

    it('导出：环境不支持 Blob 下载 → 提示降级不抛错', async () => {
        mods.list.mockResolvedValue([{ id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' }]);
        const origCreate = URL.createObjectURL;
        const origRevoke = URL.revokeObjectURL;
        URL.createObjectURL = undefined;
        URL.revokeObjectURL = undefined;
        try {
            showModManager({ characterName: 'R' });
            await flush();
            document.querySelector('[data-mod-export]').click();
            await flush();

            expect(document.querySelector('.confirm-modal')).not.toBeNull();
        } finally {
            URL.createObjectURL = origCreate;
            URL.revokeObjectURL = origRevoke;
        }
    });

    it('列表加载失败 → 错误提示（不抛）', async () => {
        mods.list.mockRejectedValue(new Error('加载失败'));

        showModManager({ characterName: 'R' });
        await flush();

        expect(document.querySelector('.mod-empty').textContent).toContain('加载 Mod 库失败');
    });
});

describe('6. 协议表面与图标 seam', () => {
    it('__all__ 覆盖全部公开导出', () => {
        for (const name of ['showModManager', 'computeSortSwap', 'TARGET_AREAS', 'serializePromptPayload',
            'parsePromptPayload', 'validateModForm', 'buildModPayload',
            'buildExportEnvelope', 'parseImportEnvelope', 'importModsFromEnvelope']) {
            expect(__all__).toContain(name);
        }
    });

    it('puzzle 图标走 iconHtml seam（MD-2 Mod 按钮）', () => {
        expect(iconHtml('puzzle')).toContain('data-icon="puzzle"');
    });
});

// ════════════════════════════════════════════════════════════════
// 挂载区块（MD-2/04）：当前角色已挂载 Mod 的管理
// ════════════════════════════════════════════════════════════════

describe('7. 挂载区块（MD-2/04）', () => {
    beforeEach(() => {
        document.body.innerHTML = '';
        vi.resetAllMocks();
    });
    afterEach(() => {
        vi.restoreAllMocks();
    });

    it('挂载区块列出已挂载 Mod（sort_order 升序，含名称/区域/序号/开关态）', async () => {
        mods.list.mockResolvedValue([
            { id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' },
            { id: 2, name: 'B', target_area: 'memory', source: 'manual', payload: '' },
        ]);
        mods.listCharacterMods.mockResolvedValue([
            { id: 12, character_id: 1, mod_id: 2, enabled: false, sort_order: 20 },
            { id: 11, character_id: 1, mod_id: 1, enabled: true, sort_order: 5 },
        ]);

        showModManager({ characterId: 1, characterName: 'R' });
        await flush();

        const rows = document.querySelectorAll('.mod-binding-row');
        expect(rows.length).toBe(2);
        // sort_order 升序：A(sort 5) 在 B(sort 20) 前
        expect(rows[0].querySelector('.mod-binding-name').textContent).toBe('A');
        expect(rows[0].dataset.sortOrder).toBe('5');
        expect(rows[0].querySelector('.mod-binding-meta').textContent).toContain('prompt');
        expect(rows[0].querySelector('[data-mod-binding-toggle]').innerHTML).toContain('data-icon="toggleOn"');
        expect(rows[1].querySelector('.mod-binding-name').textContent).toBe('B');
        expect(rows[1].dataset.sortOrder).toBe('20');
        expect(rows[1].querySelector('.mod-binding-meta').textContent).toContain('memory');
        expect(rows[1].querySelector('[data-mod-binding-toggle]').innerHTML).toContain('data-icon="toggleOff"');
    });

    it('挂载下拉只列未挂载 Mod（客户端去重）', async () => {
        mods.list.mockResolvedValue([
            { id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' },
            { id: 2, name: 'B', target_area: 'css', source: 'manual', payload: '' },
        ]);
        mods.listCharacterMods.mockResolvedValue([
            { id: 11, character_id: 1, mod_id: 1, enabled: true, sort_order: 0 },
        ]);

        showModManager({ characterId: 1, characterName: 'R' });
        await flush();

        const values = [...document.querySelectorAll('[data-mod-bind-select] option')].map((o) => o.value);
        expect(values).toEqual(['', '2']); // 已挂载的 A(id=1) 不出现在选项
    });

    it('未在库中命中的 mod_id（异常数据）→ 显示「未知 Mod」占位不崩', async () => {
        mods.list.mockResolvedValue([{ id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' }]);
        mods.listCharacterMods.mockResolvedValue([
            { id: 11, character_id: 1, mod_id: 1, enabled: true, sort_order: 0 },
            { id: 12, character_id: 1, mod_id: 999, enabled: false, sort_order: 10 }, // 库中不存在
        ]);

        showModManager({ characterId: 1, characterName: 'R' });
        await flush();

        const rows = document.querySelectorAll('.mod-binding-row');
        expect(rows.length).toBe(2);
        expect(rows[1].querySelector('.mod-binding-name').textContent).toBe('未知 Mod');
        expect(rows[1].querySelector('.mod-binding-meta').textContent).toContain('未知区域');
    });

    it('挂载新 Mod：选择未挂载 Mod → mods.bind 调用，列表新增该行', async () => {
        mods.list.mockResolvedValue([
            { id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' },
            { id: 2, name: 'B', target_area: 'css', source: 'manual', payload: '' },
        ]);
        mods.listCharacterMods
            .mockResolvedValueOnce([{ id: 11, character_id: 1, mod_id: 1, enabled: true, sort_order: 0 }])
            .mockResolvedValueOnce([
                { id: 11, character_id: 1, mod_id: 1, enabled: true, sort_order: 0 },
                { id: 12, character_id: 1, mod_id: 2, enabled: true, sort_order: 10 },
            ]);
        mods.bind.mockResolvedValue({ id: 12, character_id: 1, mod_id: 2, enabled: true, sort_order: 10 });

        showModManager({ characterId: 1, characterName: 'R' });
        await flush();

        const select = document.querySelector('[data-mod-bind-select]');
        select.value = '2';
        document.querySelector('[data-mod-bind-add]').click();
        await flush();

        expect(mods.bind).toHaveBeenCalledWith(1, { mod_id: 2 });
        const rows = document.querySelectorAll('.mod-binding-row');
        expect(rows.length).toBe(2);
        expect(rows[1].querySelector('.mod-binding-name').textContent).toBe('B');
    });

    it('未选择 Mod → showAlert 且不调 bind', async () => {
        mods.list.mockResolvedValue([]);
        mods.listCharacterMods.mockResolvedValue([]);
        const confirmModule = await import('../js/components/confirm-dialog.js');
        const alertSpy = vi.spyOn(confirmModule, 'showAlert').mockResolvedValue(undefined);

        showModManager({ characterId: 1, characterName: 'R' });
        await flush();

        document.querySelector('[data-mod-bind-add]').click();
        await flush();

        expect(alertSpy).toHaveBeenCalledWith('请先选择一个 Mod');
        expect(mods.bind).not.toHaveBeenCalled();
    });

    it('挂载失败（后端 400 兜底）→ showAlert 且列表重拉回滚', async () => {
        mods.list.mockResolvedValue([
            { id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' },
            { id: 2, name: 'B', target_area: 'css', source: 'manual', payload: '' },
        ]);
        mods.listCharacterMods.mockResolvedValue([]);
        mods.bind.mockRejectedValue(new Error('该 Mod 已挂载'));
        const confirmModule = await import('../js/components/confirm-dialog.js');
        const alertSpy = vi.spyOn(confirmModule, 'showAlert').mockResolvedValue(undefined);

        showModManager({ characterId: 1, characterName: 'R' });
        await flush();

        const select = document.querySelector('[data-mod-bind-select]');
        select.value = '2'; // 未挂载的 B
        document.querySelector('[data-mod-bind-add]').click();
        await flush();

        expect(mods.bind).toHaveBeenCalledWith(1, { mod_id: 2 });
        expect(alertSpy).toHaveBeenCalledWith('挂载失败: 该 Mod 已挂载');
        expect(mods.listCharacterMods).toHaveBeenCalledTimes(2); // 初始 + 失败重拉
    });

    it('开关切换 → mods.setEnabled 调用，行内开关态翻转', async () => {
        mods.list.mockResolvedValue([{ id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' }]);
        mods.listCharacterMods
            .mockResolvedValueOnce([{ id: 11, character_id: 1, mod_id: 1, enabled: true, sort_order: 0 }])
            .mockResolvedValueOnce([{ id: 11, character_id: 1, mod_id: 1, enabled: false, sort_order: 0 }]);
        mods.setEnabled.mockResolvedValue({});

        showModManager({ characterId: 1, characterName: 'R' });
        await flush();

        document.querySelector('[data-mod-binding-toggle]').click();
        await flush();

        expect(mods.setEnabled).toHaveBeenCalledWith(11, false);
        expect(document.querySelector('[data-mod-binding-toggle]').innerHTML).toContain('data-icon="toggleOff"');
    });

    it('解绑（showConfirm 确认后）→ mods.unbind 调用，列表移除该行', async () => {
        mods.list.mockResolvedValue([{ id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' }]);
        mods.listCharacterMods
            .mockResolvedValueOnce([{ id: 11, character_id: 1, mod_id: 1, enabled: true, sort_order: 0 }])
            .mockResolvedValueOnce([]);
        mods.unbind.mockResolvedValue(null);

        showModManager({ characterId: 1, characterName: 'R' });
        await flush();

        document.querySelector('[data-mod-binding-unbind]').click();
        await flush();
        expect(document.querySelector('.confirm-modal')).not.toBeNull();
        document.querySelector('.confirm-ok').click();
        await flush();

        expect(mods.unbind).toHaveBeenCalledWith(11);
        expect(document.querySelectorAll('.mod-binding-row').length).toBe(0);
    });

    it('上移 → mods.setSortOrder 两次交换相邻 sort_order 并持久化，重拉后顺序正确', async () => {
        mods.list.mockResolvedValue([
            { id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' },
            { id: 2, name: 'B', target_area: 'memory', source: 'manual', payload: '' },
        ]);
        mods.listCharacterMods
            .mockResolvedValueOnce([
                { id: 11, character_id: 1, mod_id: 1, enabled: true, sort_order: 0 },
                { id: 12, character_id: 1, mod_id: 2, enabled: true, sort_order: 10 },
            ])
            .mockResolvedValueOnce([
                { id: 12, character_id: 1, mod_id: 2, enabled: true, sort_order: 0 },
                { id: 11, character_id: 1, mod_id: 1, enabled: true, sort_order: 10 },
            ]);
        mods.setSortOrder.mockResolvedValue({});

        showModManager({ characterId: 1, characterName: 'R' });
        await flush();

        // 上移第二行（B，index 1）
        document.querySelectorAll('.mod-binding-row')[1].querySelector('[data-mod-binding-up]').click();
        await flush();

        expect(mods.setSortOrder).toHaveBeenCalledTimes(2);
        expect(mods.setSortOrder).toHaveBeenNthCalledWith(1, 12, 0);  // B 取 A 的 0
        expect(mods.setSortOrder).toHaveBeenNthCalledWith(2, 11, 10); // A 取 B 的 10
        // 重拉后顺序正确：B 在前
        const after = document.querySelectorAll('.mod-binding-row');
        expect(after[0].querySelector('.mod-binding-name').textContent).toBe('B');
        expect(after[0].dataset.sortOrder).toBe('0');
        expect(after[1].querySelector('.mod-binding-name').textContent).toBe('A');
        expect(after[1].dataset.sortOrder).toBe('10');
    });

    it('变更失败 → showAlert 提示且列表重拉回滚（listCharacterMods 再拉）', async () => {
        mods.list.mockResolvedValue([{ id: 1, name: 'A', target_area: 'prompt', source: 'manual', payload: '' }]);
        mods.listCharacterMods.mockResolvedValue([{ id: 11, character_id: 1, mod_id: 1, enabled: true, sort_order: 0 }]);
        mods.setEnabled.mockRejectedValue(new Error('网络错误'));
        const confirmModule = await import('../js/components/confirm-dialog.js');
        const alertSpy = vi.spyOn(confirmModule, 'showAlert').mockResolvedValue(undefined);

        showModManager({ characterId: 1, characterName: 'R' });
        await flush();

        document.querySelector('[data-mod-binding-toggle]').click();
        await flush();

        expect(alertSpy).toHaveBeenCalledWith('切换失败: 网络错误');
        // 重拉：初始 1 次 + 失败回滚再拉 1 次
        expect(mods.listCharacterMods).toHaveBeenCalledTimes(2);
    });
});

describe('8. computeSortSwap 纯函数', () => {
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
