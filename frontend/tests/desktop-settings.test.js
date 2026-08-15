import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
    hasDesktopBridge,
    getCloseAction,
    setCloseAction,
    ensureCloseActionChoice,
    initCloseActionSetting,
} from '../js/desktop-settings.js';
import { openModal } from '../js/components/modal.js';
import { showAlert } from '../js/components/confirm-dialog.js';

// D11 关闭行为偏好：桥检测 / 读写 / 首次弹窗 / 设置页分组。
// modal 与 showAlert 以 vi.mock 桩替（弹窗骨架已在 modal/confirm-dialog 各自测试覆盖）。

vi.mock('../js/components/modal.js', () => ({ openModal: vi.fn() }));
vi.mock('../js/components/confirm-dialog.js', () => ({ showAlert: vi.fn() }));

/** 造一个假 __TAURI_INTERNALS__ 桥（invoke 记录调用） */
function installBridge(value = null) {
    const invoke = vi.fn().mockResolvedValue(value);
    window.__TAURI_INTERNALS__ = { invoke };
    return invoke;
}

/** 造一个可捕获事件回调的假 overlay（模拟 openModal 的 onOpen 参数） */
function fakeOverlay() {
    const handlers = {};
    return {
        handlers,
        querySelector(sel) {
            const key = sel.replace('.', '');
            return { addEventListener: (ev, fn) => { handlers[key] = fn; } };
        },
    };
}

/** 拦截 openModal：同步执行 onOpen（close 直接透传结果给 onClose），返回捕获的 options 与假 overlay */
function captureModal() {
    let captured = null;
    const overlay = fakeOverlay();
    openModal.mockImplementation((opts) => {
        captured = opts;
        opts.onOpen?.(overlay, (result) => opts.onClose?.(result));
    });
    return { getOpts: () => captured, overlay };
}

const SETTINGS_GROUP_HTML = `
    <div class="settings-group" id="group-close-action" hidden>
        <input type="radio" name="close-action" value="tray">
        <input type="radio" name="close-action" value="quit">
    </div>
`;

describe('hasDesktopBridge', () => {
    it('Tauri 桥存在（invoke 为函数）→ true', () => {
        installBridge();
        expect(hasDesktopBridge()).toBe(true);
    });

    it('无桥（网页模式）→ false', () => {
        delete window.__TAURI_INTERNALS__;
        expect(hasDesktopBridge()).toBe(false);
    });

    it('桥存在但无 invoke（异常注入）→ false', () => {
        window.__TAURI_INTERNALS__ = {};
        expect(hasDesktopBridge()).toBe(false);
    });
});

describe('getCloseAction', () => {
    it('有桥 → 返回 invoke 结果（tray/quit/null）', async () => {
        const invoke = installBridge('quit');
        expect(await getCloseAction()).toBe('quit');
        expect(invoke).toHaveBeenCalledWith('get_close_action');
    });

    it('invoke 拒绝 → 返回 null（不抛错）', async () => {
        installBridge();
        window.__TAURI_INTERNALS__.invoke.mockRejectedValue(new Error('IPC 失败'));
        expect(await getCloseAction()).toBeNull();
    });

    it('无桥 → 直接 null 且不调用 invoke', async () => {
        delete window.__TAURI_INTERNALS__;
        expect(await getCloseAction()).toBeNull();
    });
});

describe('setCloseAction', () => {
    it('有桥 + 合法取值 → invoke 携带 action', async () => {
        const invoke = installBridge();
        await setCloseAction('tray');
        expect(invoke).toHaveBeenCalledWith('set_close_action', { action: 'tray' });
    });

    it('非法取值 → 忽略，不发命令', async () => {
        const invoke = installBridge();
        await setCloseAction('minimize');
        expect(invoke).not.toHaveBeenCalled();
    });

    it('无桥 → 忽略，不发命令', async () => {
        delete window.__TAURI_INTERNALS__;
        await setCloseAction('quit');
    });
});

describe('ensureCloseActionChoice（首次运行引导）', () => {
    beforeEach(() => {
        vi.clearAllMocks();
        document.body.innerHTML = SETTINGS_GROUP_HTML;
    });

    afterEach(() => {
        delete window.__TAURI_INTERNALS__;
    });

    it('无桥 → no-op（不弹窗、不读偏好）', async () => {
        delete window.__TAURI_INTERNALS__;
        await ensureCloseActionChoice();
        expect(openModal).not.toHaveBeenCalled();
    });

    it('偏好已设置（tray/quit）→ 不弹窗', async () => {
        installBridge('tray');
        await ensureCloseActionChoice();
        expect(openModal).not.toHaveBeenCalled();
    });

    it('偏好未设置（null）→ 弹窗且两按钮必选其一，选择后持久化并同步表单', async () => {
        const invoke = installBridge(null);
        const { getOpts, overlay } = captureModal();
        const promise = ensureCloseActionChoice();

        // 等待 getCloseAction 微任务链结算、openModal 被调用
        await vi.waitFor(() => expect(getOpts()).not.toBeNull());
        const opts = getOpts();
        expect(opts.cancelResult).toBe('tray');
        // 选择「直接退出程序」
        overlay.handlers['close-action-quit']();
        await promise;

        expect(invoke).toHaveBeenCalledWith('set_close_action', { action: 'quit' });
        // 表单同步：quit 单选选中
        const radios = [...document.querySelectorAll('input[name="close-action"]')];
        expect(radios.find((r) => r.value === 'quit').checked).toBe(true);
        expect(radios.find((r) => r.value === 'tray').checked).toBe(false);
    });

    it('保存失败 → 不抛错（console.error），关闭语义保持默认', async () => {
        installBridge(null);
        window.__TAURI_INTERNALS__.invoke.mockResolvedValueOnce(null);
        window.__TAURI_INTERNALS__.invoke.mockRejectedValueOnce(new Error('写盘失败'));
        const { getOpts, overlay } = captureModal();
        const promise = ensureCloseActionChoice();
        await vi.waitFor(() => expect(getOpts()).not.toBeNull());
        overlay.handlers['close-action-tray']();
        await expect(promise).resolves.toBeUndefined();
    });
});

describe('initCloseActionSetting（设置页分组）', () => {
    beforeEach(() => {
        vi.clearAllMocks();
        document.body.innerHTML = SETTINGS_GROUP_HTML;
    });

    afterEach(() => {
        delete window.__TAURI_INTERNALS__;
    });

    it('无桥 → 分组保持隐藏', async () => {
        delete window.__TAURI_INTERNALS__;
        await initCloseActionSetting();
        expect(document.querySelector('#group-close-action').hidden).toBe(true);
    });

    it('有桥 → 分组显示并回填当前偏好', async () => {
        installBridge('quit');
        await initCloseActionSetting();
        const group = document.querySelector('#group-close-action');
        expect(group.hidden).toBe(false);
        const radios = [...group.querySelectorAll('input[name="close-action"]')];
        expect(radios.find((r) => r.value === 'quit').checked).toBe(true);
    });

    it('未设置（null）→ 分组显示且无选中', async () => {
        installBridge(null);
        await initCloseActionSetting();
        const group = document.querySelector('#group-close-action');
        expect(group.hidden).toBe(false);
        expect([...group.querySelectorAll('input[name="close-action"]')].some((r) => r.checked)).toBe(false);
    });

    it('切换单选 → 即时保存 + 提示', async () => {
        const invoke = installBridge('tray');
        await initCloseActionSetting();
        const quitRadio = document.querySelector('input[name="close-action"][value="quit"]');
        quitRadio.checked = true;
        quitRadio.dispatchEvent(new Event('change'));
        // 等待异步保存完成（invoke 调用是同步发生的，showAlert 在其后微任务——合并断言轮询到两者齐备）
        await vi.waitFor(() => {
            expect(invoke).toHaveBeenCalledWith('set_close_action', { action: 'quit' });
            expect(showAlert).toHaveBeenCalled();
        });
    });

    it('保存失败 → 提示失败且不抛错', async () => {
        installBridge('tray');
        window.__TAURI_INTERNALS__.invoke
            .mockResolvedValueOnce('tray')
            .mockRejectedValueOnce(new Error('写盘失败'));
        await initCloseActionSetting();
        const quitRadio = document.querySelector('input[name="close-action"][value="quit"]');
        quitRadio.checked = true;
        quitRadio.dispatchEvent(new Event('change'));
        await vi.waitFor(() => expect(showAlert).toHaveBeenCalledWith(expect.stringContaining('保存失败')));
    });

    it('分组元素缺失 → no-op 不抛错', async () => {
        document.body.innerHTML = '';
        installBridge('tray');
        await expect(initCloseActionSetting()).resolves.toBeUndefined();
    });
});
