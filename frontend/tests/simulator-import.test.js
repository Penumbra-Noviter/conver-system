/**
 * 模拟器导入模块测试（工单 04）。
 *
 * 覆盖（公共接口边界 — simulator-import.js 深模块协议表面 __all__：
 *   initSimulatorImport / openImportFlow / importFile / resetSimulatorImport /
 *   setFetch）：
 *   - initSimulatorImport：隐藏文件选择器（accept .html）创建 + 列表面板
 *     拖拽事件绑定（dragover 高亮 / dragleave 移除 / drop 入口）；无 container
 *     no-op 不抛错
 *   - openImportFlow（按钮路径）：安全警告确认弹窗（文案含「第三方游戏可
 *     读取本地数据并调用 API」）→ 确认后打开文件选择器；取消 → 不打开；
 *     未 init no-op
 *   - 文件选择器路径（change 事件）：选中 .html → 直接上传（确认已在选文件
 *     前完成，不重复弹窗）→ multipart FormData（字段 file）→ POST IMPORT_URL
 *   - importFile（拖拽路径）：非 .html → 明确提示不上传；确认取消 → 中止；
 *     确认 → 上传
 *   - 拖拽交互：drop 多文件 → 「一次只能导入一个」；导入中 drop 忽略；
 *     dragover/dragleave 高亮类迁移
 *   - 上传在途：按钮禁用 + 文案「正在导入…」；完成/失败复位可重试
 *   - 成功反馈：成功 toast（改名时含新文件名）→ onImported 钩子 → warnings
 *     警告弹窗（中文文案映射，不拦截）→ 未覆盖提示（同源 fetch 覆盖层 CSS
 *     文本 → simulator-adapt 分析 → 非空弹窗含引导文案；为空不弹；record 项
 *     过滤为导入预期状态；覆盖层 fetch 失败跳过不阻塞）
 *   - 错误路径：400/409 → 后端 detail 原样展示（409 含「已存在」）；非 JSON
 *     body → HTTP 状态兜底；网络失败 → 可读错误；上传超时 → 中文超时文案
 *   - Falsify：畸形响应体（ok:true 但无 game）/ warnings 非数组 / 文件无
 *     .text() 方法 / 非 File 对象（{name:'a.html'}）→ 均不炸
 *
 * 挂载模式：jsdom + vi.resetModules()（每用例全新模块状态）；showConfirm 以
 * vi.mock 桩替（弹窗骨架在 confirm-dialog 自身测试覆盖）；toast 断言经
 * utils 模块 spyOn（showSuccess/showError 薄封装 — utils.test.js 已覆盖
 * toast DOM 行为）；fetch 经 setFetch seam 注入（路由 IMPORT_URL 与覆盖层
 * CSS URL 两路）。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// showConfirm 桩替：弹窗骨架已在 confirm-dialog.js 自身测试覆盖，本文件只
// 断言「何时弹、弹什么参数、确认/取消后的流程走向」（desktop-settings 先例）
vi.mock('../js/components/confirm-dialog.js', () => ({ showConfirm: vi.fn() }));

/** 最小列表面板 DOM — 与 index.html 的 #simulator-list-panel 契约一致（只读契约） */
const PANEL_HTML = '<div id="simulator-list-panel"></div>';

/** 成功响应 JSON（契约：{ ok, game{id,file,name,type,config?}, renamed, warnings }） */
const OK_GAME = { id: 'imported-game', file: '新游戏.html', name: '新游戏', type: 'local' };

const mockJson = (data, status = 200) => Promise.resolve({
    ok: status < 400,
    status,
    json: async () => data,
});

/** 可路由 fetch mock：IMPORT_URL → importResult/importFail/pending；其余 → 覆盖层 CSS */
function makeFetch({ importResult = null, importFail = null, cssText = '', cssFail = false, pending = null } = {}) {
    return vi.fn((url, opts) => {
        if (pending) return pending.promise;
        if (String(url).includes('/api/simulators/import')) {
            if (importFail) return Promise.reject(importFail);
            return importResult;
        }
        if (cssFail) return Promise.reject(new Error('css 加载失败'));
        return Promise.resolve({ ok: true, status: 200, text: async () => cssText });
    });
}

/** 加载全新 simulator-import 模块（DOM 先就位；返回模块 + confirm 桩 + utils spy） */
async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = PANEL_HTML;
    const imp = await import('../js/simulator-import.js');
    const confirm = await import('../js/components/confirm-dialog.js');
    const utils = await import('../js/utils.js');
    // showError/showSuccess 挂 spy + 抑制真实 toast DOM 副作用（setTimeout 5s 泄漏；
    // toast 骨架已在 utils.test.js 覆盖 — save-manager 先例）
    vi.spyOn(utils, 'showError').mockImplementation(() => {});
    vi.spyOn(utils, 'showSuccess').mockImplementation(() => {});
    return { imp, confirm, utils, panel: document.querySelector('#simulator-list-panel') };
}

/** 模拟 simulators.js 渲染的「导入游戏」按钮（DOM 契约：.sim-import-btn） */
function renderImportBtn(panel) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'sim-import-btn';
    btn.textContent = '导入游戏';
    panel.appendChild(btn);
    return btn;
}

/** 派发带 dataTransfer 的拖拽事件（jsdom 无 DataTransfer 构造 — 自定义对象模拟） */
function dispatchDrop(panel, files) {
    const drop = new Event('drop', { bubbles: true, cancelable: true });
    drop.dataTransfer = { files };
    panel.dispatchEvent(drop);
    return drop;
}

/**
 * 造测试 HTML 文件：jsdom 的 File 缺 text()（Blob.text 是浏览器标准 API —
 * 模块消费属标准契约，jsdom 环境缺失），附加 text() 返回给定内容。
 */
function makeHtmlFile(name, content) {
    const file = new File([content], name, { type: 'text/html' });
    Object.defineProperty(file, 'text', { value: async () => content, configurable: true });
    return file;
}

describe('simulator-import — 协议表面 __all__', () => {
    it('__all__ 收口公开函数与 fetch seam', async () => {
        const { imp } = await loadModules();
        expect(imp.__all__.sort()).toEqual([
            'importFile',
            'initSimulatorImport',
            'openImportFlow',
            'resetSimulatorImport',
            'setFetch',
        ]);
    });
});

describe('initSimulatorImport — 文件选择器与拖拽绑定', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('init 后创建隐藏文件选择器（accept .html）', async () => {
        const { imp } = await loadModules();
        imp.initSimulatorImport({ container: document.querySelector('#simulator-list-panel') });

        const input = document.body.querySelector('input[type="file"]');
        expect(input).not.toBeNull();
        expect(input.hidden).toBe(true);
        expect(input.accept).toBe('.html');
    });

    it('Falsify:init 无 container → no-op 不抛错', async () => {
        const { imp } = await loadModules();
        expect(() => imp.initSimulatorImport({})).not.toThrow();
        expect(() => imp.initSimulatorImport()).not.toThrow();
    });
});

describe('openImportFlow — 按钮路径（警告确认 → 文件选择器）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('点「导入游戏」→ 安全警告确认弹窗（文案含「第三方游戏可读取本地数据并调用 API」）', async () => {
        const { imp, confirm } = await loadModules();
        imp.initSimulatorImport({ container: document.querySelector('#simulator-list-panel') });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.openImportFlow();
        expect(confirm.showConfirm).toHaveBeenCalledTimes(1);
        const opts = confirm.showConfirm.mock.calls[0][0];
        expect(opts.message).toContain('第三方游戏可读取本地数据并调用 API');
        expect(opts.danger).toBe(true);
    });

    it('确认 → 打开文件选择器（触发 input.click）', async () => {
        const { imp, confirm } = await loadModules();
        imp.initSimulatorImport({ container: document.querySelector('#simulator-list-panel') });
        confirm.showConfirm.mockResolvedValue(true);
        const input = document.body.querySelector('input[type="file"]');
        const clickSpy = vi.spyOn(input, 'click');

        await imp.openImportFlow();
        expect(clickSpy).toHaveBeenCalledTimes(1);
    });

    it('取消确认 → 不打开文件选择器（导入中止）', async () => {
        const { imp, confirm } = await loadModules();
        imp.initSimulatorImport({ container: document.querySelector('#simulator-list-panel') });
        confirm.showConfirm.mockResolvedValue(false);
        const input = document.body.querySelector('input[type="file"]');
        const clickSpy = vi.spyOn(input, 'click');

        await imp.openImportFlow();
        expect(clickSpy).not.toHaveBeenCalled();
    });

    it('Falsify:未 init（无文件选择器）→ no-op 不抛错', async () => {
        const { imp, confirm } = await loadModules();
        confirm.showConfirm.mockResolvedValue(true);
        await expect(imp.openImportFlow()).resolves.toBeUndefined();
    });
});

describe('文件选择器路径 — change 事件直接上传（确认已前置，不重复弹窗）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('选中 .html → multipart 上传 IMPORT_URL（FormData 字段 file）+ 成功 toast + onImported', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        const fetchSpy = makeFetch({ importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }) });
        imp.setFetch(fetchSpy);
        const onImported = vi.fn(async () => {});
        imp.initSimulatorImport({ container: panel, onImported });
        confirm.showConfirm.mockResolvedValue(true);

        const file = makeHtmlFile('新游戏.html', '<html>ok</html>');
        const input = document.body.querySelector('input[type="file"]');
        Object.defineProperty(input, 'files', { value: [file], configurable: true });
        input.dispatchEvent(new Event('change'));
        await vi.waitFor(() => expect(onImported).toHaveBeenCalledTimes(1));

        // 上传契约：IMPORT_URL + POST + FormData（字段 file，浏览器自动 boundary，不设 Content-Type）
        const [url, opts] = fetchSpy.mock.calls[0];
        expect(url).toBe('/api/simulators/import');
        expect(opts.method).toBe('POST');
        expect(opts.body).toBeInstanceOf(FormData);
        expect(opts.body.get('file')).toBe(file);
        expect(opts.headers).toBeUndefined();
        // 确认弹窗只发生在 openImportFlow（change 路径不重复弹窗）
        expect(confirm.showConfirm).not.toHaveBeenCalled();
        // 成功 toast
        await vi.waitFor(() => expect(utils.showSuccess).toHaveBeenCalledWith('导入成功'));
    });

    it('文件选择器无选中（files 为空）→ no-op 不上传', async () => {
        const { imp } = await loadModules();
        const fetchSpy = makeFetch({ importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }) });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: document.querySelector('#simulator-list-panel') });

        const input = document.body.querySelector('input[type="file"]');
        Object.defineProperty(input, 'files', { value: [], configurable: true });
        input.dispatchEvent(new Event('change'));
        await new Promise((r) => setTimeout(r, 0));
        expect(fetchSpy).not.toHaveBeenCalled();
    });
});

describe('importFile — 拖拽路径（校验 → 警告确认 → 上传）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('非 .html 文件 → 明确提示，不上传不弹确认', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        const fetchSpy = makeFetch();
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        const file = new File(['x'], '游戏.txt', { type: 'text/plain' });
        await imp.importFile(file);
        expect(confirm.showConfirm).not.toHaveBeenCalled();
        expect(fetchSpy).not.toHaveBeenCalled();
        await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith(expect.stringContaining('.html')));
    });

    it('Falsify:非 File 对象（仅 name 字符串）→ 按名称校验放行（不依赖 instanceof）', async () => {
        const { imp, confirm, panel } = await loadModules();
        const fetchSpy = makeFetch({ importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }) });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.importFile({ name: 'a.html' });
        await vi.waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
    });

    it('确认取消 → 中止导入（不上传）', async () => {
        const { imp, confirm, panel } = await loadModules();
        const fetchSpy = makeFetch();
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(false);

        const file = makeHtmlFile('a.html', 'x');
        await imp.importFile(file);
        expect(fetchSpy).not.toHaveBeenCalled();
    });

    it('警告确认（含威胁模型文案）→ 确认后上传', async () => {
        const { imp, confirm, panel } = await loadModules();
        const fetchSpy = makeFetch({ importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }) });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        const file = makeHtmlFile('a.html', 'x');
        await imp.importFile(file);
        expect(confirm.showConfirm).toHaveBeenCalledTimes(1);
        await vi.waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(2)); // import + 覆盖层 CSS
        expect(fetchSpy.mock.calls[0][0]).toBe('/api/simulators/import');
    });
});

describe('拖拽交互 — drop / dragover / dragleave', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('dragover → preventDefault + 高亮类；dragleave → 移除高亮', async () => {
        const { imp, panel } = await loadModules();
        imp.initSimulatorImport({ container: panel });

        const over = new Event('dragover', { bubbles: true, cancelable: true });
        panel.dispatchEvent(over);
        expect(over.defaultPrevented).toBe(true);
        expect(panel.classList.contains('sim-drop-active')).toBe(true);

        panel.dispatchEvent(new Event('dragleave'));
        expect(panel.classList.contains('sim-drop-active')).toBe(false);
    });

    it('drop 单 .html → 警告确认 → 上传', async () => {
        const { imp, confirm, panel } = await loadModules();
        const fetchSpy = makeFetch({ importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }) });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        dispatchDrop(panel, [makeHtmlFile('a.html', 'x')]);
        await vi.waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(2)); // import + 覆盖层 CSS
        expect(fetchSpy.mock.calls[0][0]).toBe('/api/simulators/import');
        expect(panel.classList.contains('sim-drop-active')).toBe(false); // drop 后移除高亮
    });

    it('drop 多文件 → 明确提示「一次只能导入一个文件」，不上传', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        const fetchSpy = makeFetch();
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        dispatchDrop(panel, [
            makeHtmlFile('a.html', 'x'),
            makeHtmlFile('b.html', 'y'),
        ]);
        await new Promise((r) => setTimeout(r, 0));
        expect(confirm.showConfirm).not.toHaveBeenCalled();
        expect(fetchSpy).not.toHaveBeenCalled();
        await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith('一次只能导入一个文件'));
    });

    it('导入在途时 drop → 忽略（不上传，按钮保持导入中）', async () => {
        const { imp, confirm, panel } = await loadModules();
        const pending = { resolve: null, promise: null };
        pending.promise = new Promise((r) => { pending.resolve = r; });
        const fetchSpy = makeFetch({ pending });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);
        const btn = renderImportBtn(panel);

        const file = makeHtmlFile('a.html', 'x');
        const first = imp.importFile(file); // 上传挂起
        await vi.waitFor(() => expect(btn.disabled).toBe(true));

        dispatchDrop(panel, [makeHtmlFile('b.html', 'y')]);
        await new Promise((r) => setTimeout(r, 0));
        expect(fetchSpy).toHaveBeenCalledTimes(1); // 未发起第二次上传

        pending.resolve(mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }));
        await first;
        expect(btn.disabled).toBe(false);
        expect(btn.textContent).toBe('导入游戏');
    });
});

describe('上传在途与复位 — 不确定态「正在导入…」', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('上传挂起 → 按钮禁用 + 文案「正在导入…」；完成 → 复位', async () => {
        const { imp, confirm, panel } = await loadModules();
        const pending = { resolve: null, promise: null };
        pending.promise = new Promise((r) => { pending.resolve = r; });
        const fetchSpy = makeFetch({ pending });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);
        const btn = renderImportBtn(panel);

        const file = makeHtmlFile('a.html', 'x');
        const p = imp.importFile(file);
        await vi.waitFor(() => {
            expect(btn.disabled).toBe(true);
            expect(btn.textContent).toBe('正在导入…');
        });
        pending.resolve(mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }));
        await p;
        await vi.waitFor(() => {
            expect(btn.disabled).toBe(false);
            expect(btn.textContent).toBe('导入游戏');
        });
    });

    it('Falsify:容器内无导入按钮 → 导入中状态操作 no-op 不抛错', async () => {
        const { imp, confirm, panel } = await loadModules();
        const pending = { resolve: null, promise: null };
        pending.promise = new Promise((r) => { pending.resolve = r; });
        const fetchSpy = makeFetch({ pending });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        const p = imp.importFile(makeHtmlFile('a.html', 'x'));
        pending.resolve(mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }));
        await expect(p).resolves.toBeUndefined();
    });
});

describe('成功反馈 — toast / renamed / onImported / 弹窗顺序', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('改名导入 → toast 含新文件名', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        confirm.showConfirm.mockResolvedValue(true);
        const fetchSpy = makeFetch({
            importResult: mockJson({
                ok: true,
                game: { id: 'imported-game', file: '游戏-2.html', name: '游戏', type: 'local' },
                renamed: true,
                warnings: [],
            }),
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        await imp.importFile(makeHtmlFile('游戏.html', 'x'));
        await vi.waitFor(() => expect(utils.showSuccess).toHaveBeenCalledWith('导入成功（文件已重命名为 游戏-2.html）'));
    });

    it('warnings 非空 → 警告弹窗列出中文映射（不拦截，导入已成功）', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        const fetchSpy = makeFetch({
            importResult: mockJson({
                ok: true,
                game: OK_GAME,
                renamed: false,
                warnings: ['eval', 'document.cookie'],
            }),
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.importFile(makeHtmlFile('a.html', 'eval(x); document.cookie'));
        await vi.waitFor(() => expect(utils.showSuccess).toHaveBeenCalled());
        // 两次确认：导入前警告 + 导入后 warnings 警告（不拦截）
        expect(confirm.showConfirm).toHaveBeenCalledTimes(2);
        const warnOpts = confirm.showConfirm.mock.calls[1][0];
        expect(warnOpts.detail).toContain('eval');
        expect(warnOpts.detail).toContain('使用 eval() 动态执行任意代码');
        expect(warnOpts.detail).toContain('读取 document.cookie');
        expect(warnOpts.title).toContain('警告');
    });

    it('warnings 含未知键 → 兜底展示原始键名（后端新增未联动不炸）', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        const fetchSpy = makeFetch({
            importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: ['future-key'] }),
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(confirm.showConfirm).toHaveBeenCalledTimes(2));
        expect(confirm.showConfirm.mock.calls[1][0].detail).toContain('future-key');
    });

    it('Falsify:warnings 非数组（畸形响应）→ 不炸，跳过警告弹窗', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        const fetchSpy = makeFetch({
            importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: 'eval' }),
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showSuccess).toHaveBeenCalled());
        expect(confirm.showConfirm).toHaveBeenCalledTimes(1); // 仅导入前确认
    });

    it('未覆盖清单非空 → 适配提示弹窗（列表 + 引导文案 <game-id>.css）', async () => {
        const { imp, confirm, panel } = await loadModules();
        // 覆盖层 CSS：仅覆盖 .msg；导入游戏 HTML 使用 .log-entry → class 未覆盖
        const cssText = '# sim-pc:\n内置 | classes=msg\n.msg { color: red; }';
        const fetchSpy = makeFetch({
            importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }),
            cssText,
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.importFile(makeHtmlFile('a.html', '<div class="log-entry">x</div>'));
        await vi.waitFor(() => expect(confirm.showConfirm).toHaveBeenCalledTimes(2));
        const hintOpts = confirm.showConfirm.mock.calls[1][0];
        expect(hintOpts.title).toContain('覆盖层');
        expect(hintOpts.detail).toContain('类名 log-entry');
        expect(hintOpts.detail).toContain(`${OK_GAME.id}.css`); // 引导：<game-id>.css 放入数据目录
        expect(hintOpts.detail).toContain('数据目录');
    });

    it('未覆盖清单为空（含 record 项过滤 — 导入游戏无映射记录是预期状态）→ 不弹适配提示', async () => {
        const { imp, confirm, panel } = await loadModules();
        // 游戏三面全被覆盖层覆盖（仅 record 项）→ 过滤后为空 → 不弹
        const cssText = '# sim-pc:\n内置 | classes=log-entry\n.log-entry { color: red; }';
        const fetchSpy = makeFetch({
            importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }),
            cssText,
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.importFile(makeHtmlFile('a.html', '<div class="log-entry">x</div>'));
        await new Promise((r) => setTimeout(r, 20));
        expect(confirm.showConfirm).toHaveBeenCalledTimes(1); // 仅导入前确认
    });

    it('覆盖层 CSS fetch 失败（404/网络错误）→ 跳过适配提示，不阻塞导入反馈', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        const fetchSpy = makeFetch({
            importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }),
            cssFail: true,
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.importFile(makeHtmlFile('a.html', '<div class="log-entry">x</div>'));
        await vi.waitFor(() => expect(utils.showSuccess).toHaveBeenCalled());
        expect(confirm.showConfirm).toHaveBeenCalledTimes(1); // 无适配提示
    });

    it('覆盖层 CSS 非 2xx（ok:false）→ 跳过适配提示（空串语义）', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        const fetchSpy = vi.fn((url) => {
            if (String(url).includes('/api/simulators/import')) {
                return mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] });
            }
            return Promise.resolve({ ok: false, status: 404, text: async () => 'Not Found' });
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.importFile(makeHtmlFile('a.html', '<div class="log-entry">x</div>'));
        await vi.waitFor(() => expect(utils.showSuccess).toHaveBeenCalled());
        expect(confirm.showConfirm).toHaveBeenCalledTimes(1); // 无适配提示
    });

    it('onImported 未注入 → 成功流程 no-op 不炸', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        const fetchSpy = makeFetch({ importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }) });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showSuccess).toHaveBeenCalled());
    });

    it('onImported 抛错 → 不阻塞 warnings / 适配提示（刷新失败不吞反馈）', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        const fetchSpy = makeFetch({
            importResult: mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: ['eval'] }),
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel, onImported: async () => { throw new Error('刷新失败'); } });
        confirm.showConfirm.mockResolvedValue(true);

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(confirm.showConfirm).toHaveBeenCalledTimes(2)); // 导入前确认 + warnings 警告
        expect(utils.showSuccess).toHaveBeenCalled();
    });

    it('Falsify:成功响应体畸形（ok:true 但无 game）→ 错误提示不炸', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        confirm.showConfirm.mockResolvedValue(true);
        const fetchSpy = makeFetch({ importResult: mockJson({ ok: true }) });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith('导入响应无效，请重试'));
    });

    it('Falsify:成功响应 body 非 JSON（json() 抛错）→ 错误提示不炸', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        confirm.showConfirm.mockResolvedValue(true);
        const fetchSpy = makeFetch({
            importResult: Promise.resolve({ ok: true, status: 200, json: async () => { throw new Error('bad json'); } }),
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith('导入响应无效，请重试'));
    });
});

describe('错误路径 — 409 / 400 / 500 / 网络失败 / 超时', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

    it('409 重复 → 后端 detail 原样展示（含「已存在」）', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        confirm.showConfirm.mockResolvedValue(true);
        const fetchSpy = makeFetch({ importResult: mockJson({ detail: '文件已存在：游戏已导入过（SHA-256 相同）' }, 409) });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith(expect.stringContaining('已存在')));
    });

    it('400 校验失败 → 后端 detail 原样展示', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        confirm.showConfirm.mockResolvedValue(true);
        const fetchSpy = makeFetch({ importResult: mockJson({ detail: '仅支持 .html 文件（超 5MB / 空文件同理拒绝）' }, 400) });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith('仅支持 .html 文件（超 5MB / 空文件同理拒绝）'));
    });

    it('后端 500 非 JSON body → HTTP 状态兜底文案', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        confirm.showConfirm.mockResolvedValue(true);
        const fetchSpy = makeFetch({
            importResult: Promise.resolve({ ok: false, status: 500, json: async () => { throw new Error('not json'); } }),
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith('导入失败（HTTP 500）'));
    });

    it('Falsify:响应无 json 方法（形状异常）→ HTTP 状态兜底不炸', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        confirm.showConfirm.mockResolvedValue(true);
        const fetchSpy = makeFetch({
            importResult: Promise.resolve({ ok: false, status: 400 }),
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith('导入失败（HTTP 400）'));
    });

    it('网络失败 → 可读错误「导入失败：<原因>」', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        confirm.showConfirm.mockResolvedValue(true);
        const fetchSpy = makeFetch({ importFail: new Error('网络连接中断') });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith('导入失败：网络连接中断'));
    });

    it('上传超时（30s 无响应，abort 通知真实 fetch）→ 「导入超时，请重试」', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        confirm.showConfirm.mockResolvedValue(true);
        // mock fetch：挂起直到收到 abort signal（与真实 fetch 断开语义一致）
        const fetchSpy = vi.fn((url, opts) => new Promise((_, reject) => {
            opts.signal.addEventListener('abort', () => {
                reject(new DOMException('The operation was aborted.', 'AbortError'));
            });
        }));
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });

        vi.useFakeTimers();
        try {
            const p = imp.importFile(makeHtmlFile('a.html', 'x'));
            await vi.advanceTimersByTimeAsync(30000);
            await p;
            await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith('导入超时，请重试'));
        } finally {
            vi.useRealTimers();
        }
    });

    it('失败后复位可重试：先失败后成功', async () => {
        const { imp, confirm, utils, panel } = await loadModules();
        let calls = 0;
        const fetchSpy = vi.fn((url) => {
            calls += 1;
            if (calls === 1) return Promise.reject(new Error('网络错误'));
            return mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] });
        });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);
        const btn = renderImportBtn(panel);

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showError).toHaveBeenCalledWith('导入失败：网络错误'));
        expect(btn.disabled).toBe(false); // 失败复位

        await imp.importFile(makeHtmlFile('a.html', 'x'));
        await vi.waitFor(() => expect(utils.showSuccess).toHaveBeenCalled());
        expect(fetchSpy).toHaveBeenCalledTimes(3); // 失败(1) + 成功 import(1) + 覆盖层 CSS(1)
    });
});

describe('resetSimulatorImport — 切走视图复位', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { vi.restoreAllMocks(); });

    it('复位：移除拖拽高亮 + 导入中状态复位（按钮恢复可用）', async () => {
        const { imp, confirm, panel } = await loadModules();
        const pending = { resolve: null, promise: null };
        pending.promise = new Promise((r) => { pending.resolve = r; });
        const fetchSpy = makeFetch({ pending });
        imp.setFetch(fetchSpy);
        imp.initSimulatorImport({ container: panel });
        confirm.showConfirm.mockResolvedValue(true);
        const btn = renderImportBtn(panel);
        panel.classList.add('sim-drop-active');

        const p = imp.importFile(makeHtmlFile('a.html', 'x')); // 挂起
        await vi.waitFor(() => expect(btn.disabled).toBe(true));
        imp.resetSimulatorImport(); // 切走视图 → 复位
        expect(btn.disabled).toBe(false);
        expect(panel.classList.contains('sim-drop-active')).toBe(false);

        pending.resolve(mockJson({ ok: true, game: OK_GAME, renamed: false, warnings: [] }));
        await p;
    });

    it('Falsify:未 init 调 reset → no-op 不抛错', async () => {
        const { imp } = await loadModules();
        expect(() => imp.resetSimulatorImport()).not.toThrow();
    });
});
