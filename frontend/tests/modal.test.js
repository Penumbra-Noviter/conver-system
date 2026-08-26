/**
 * 通用模态框工厂测试（modal.js 深模块 — T4 快赢：焦点陷阱 + 关闭还原）
 *
 * 覆盖（公共接口边界 — __all__）：
 *   - openModal 骨架：打开（遮罩挂载 / 标题转义）/ 三条关闭路径
 *     （关闭按钮 / 点击遮罩 / Escape）
 *   - 焦点陷阱：框内 Tab 循环不跳出（末位 → 首位；Shift+Tab 首位 → 末位；
 *     焦点在框外 Tab → 落入首位）
 *   - 关闭还原：三条关闭路径后焦点回到打开前元素；打开前元素被移除 → 跳过还原
 *   - Falsify：框内无可聚焦元素 Tab 不抛错；close 幂等
 *
 * jsdom 焦点语义：天然可聚焦元素（button/input/a 等）focus() 会更新
 * document.activeElement；合成 keydown 不会触发默认 Tab 移焦，循环跳转由
 * 实现显式调用 focus() 完成 — 测试即以 document.activeElement 断言行为。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
// 静态值常量（纯字符串）— 经公共 seam FOCUSABLE_SELECTOR 引用，避免测试复制收集口径
import { FOCUSABLE_SELECTOR } from '../js/components/modal.js';

/** 加载全新 modal.js 模块（无模块级状态，resetModules 保证测试隔离） */
async function loadModal() {
    vi.resetModules();
    return await import('../js/components/modal.js');
}

/** 打开一个含若干可聚焦元素的模态框（fixture） */
function openFixture(mod, { body = '', actions = '' } = {}) {
    return mod.openModal({
        title: '测试弹窗',
        body: body || '<p>内容</p>',
        actions: actions || `
            <button type="button" id="m-cancel">取消</button>
            <button type="button" id="m-ok">确定</button>
        `,
    });
}

/** 触发 Tab / Shift+Tab 键盘事件 */
function dispatchTab(target, { shift = false } = {}) {
    target.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true, shiftKey: shift }));
}

/** 模态框内可聚焦元素数组（引用实现导出的收集口径常量 — 无复制） */
function focusablesOf(overlay) {
    return [...overlay.querySelectorAll(FOCUSABLE_SELECTOR)]
        .filter((el) => el.closest('[hidden]') === null);
}

describe('modal — 协议表面 __all__', () => {
    it('__all__ 收口 openModal 与 FOCUSABLE_SELECTOR', async () => {
        const mod = await loadModal();
        expect(mod.__all__.sort()).toEqual(['FOCUSABLE_SELECTOR', 'openModal']);
    });
});

describe('modal — 焦点陷阱（Tab 循环在框内）', () => {
    beforeEach(() => {
        document.body.innerHTML = '';
        // 焦点陷阱的默认焦点落点：body
        document.body.focus();
    });
    afterEach(() => {
        document.body.innerHTML = '';
    });

    it('Tab 在末位可聚焦元素 → 循环回首位', async () => {
        const mod = await loadModal();
        const overlay = openFixture(mod);
        const focusables = focusablesOf(overlay);
        expect(focusables.length).toBeGreaterThanOrEqual(3); // 关闭按钮 + 取消 + 确定

        const last = focusables[focusables.length - 1];
        last.focus();
        expect(document.activeElement).toBe(last);

        dispatchTab(last);
        expect(document.activeElement).toBe(focusables[0]); // 循环回首位
    });

    it('Shift+Tab 在首位可聚焦元素 → 循环回末位', async () => {
        const mod = await loadModal();
        const overlay = openFixture(mod);
        const focusables = focusablesOf(overlay);
        const first = focusables[0];
        first.focus();

        dispatchTab(first, { shift: true });
        expect(document.activeElement).toBe(focusables[focusables.length - 1]);
    });

    it('Tab 在中间元素 → 不循环（焦点保持前进语义）', async () => {
        const mod = await loadModal();
        const overlay = openFixture(mod);
        const focusables = focusablesOf(overlay);
        const mid = focusables[1];
        mid.focus();

        dispatchTab(mid);
        expect(document.activeElement).toBe(mid); // 中间位不触发循环
    });

    it('焦点在框外（body）时 Tab → 落入首位', async () => {
        const mod = await loadModal();
        const overlay = openFixture(mod);
        const focusables = focusablesOf(overlay);
        document.body.focus();

        dispatchTab(overlay);
        expect(document.activeElement).toBe(focusables[0]);
    });

    it('Falsify: 框内无可聚焦元素时 Tab 不抛错（阻止默认跳转）', async () => {
        const mod = await loadModal();
        const overlay = mod.openModal({ title: '空弹窗', body: '<p>无控件</p>' });
        // 移除唯一可聚焦的关闭按钮 → 触发 empty 守卫
        overlay.querySelector('.modal-close').remove();
        expect(focusablesOf(overlay).length).toBe(0);

        expect(() => dispatchTab(overlay)).not.toThrow();
        // 焦点仍不在框外任何元素（jsdom 中默认留在 body）
        expect(document.activeElement).toBe(document.body);
    });

    it('hidden 的可聚焦元素不参与循环（如隐藏文件输入）', async () => {
        const mod = await loadModal();
        const overlay = mod.openModal({
            title: 'H',
            body: '<input type="file" id="hidden-file" hidden><button type="button" id="b1">B1</button>',
        });
        const focusables = focusablesOf(overlay);
        expect(focusables.map((el) => el.id)).not.toContain('hidden-file');
        expect(focusables.map((el) => el.id)).toContain('b1');
    });
});

describe('modal — 关闭后焦点还原', () => {
    beforeEach(() => {
        document.body.innerHTML = '';
    });
    afterEach(() => {
        document.body.innerHTML = '';
    });

    /** 准备：外部按钮持焦 + 打开模态框 + 焦点移入框内（还原须把焦点带回外部） */
    async function setupModalWithExternalFocus() {
        const mod = await loadModal();
        const externalBtn = document.createElement('button');
        externalBtn.id = 'external-btn';
        externalBtn.textContent = '外部按钮';
        document.body.appendChild(externalBtn);
        externalBtn.focus();
        expect(document.activeElement).toBe(externalBtn);
        const overlay = openFixture(mod);
        // 焦点移入框内（模拟用户 Tab 进弹窗后关闭）— 还原须把焦点带回外部按钮
        overlay.querySelector('.modal-close').focus();
        expect(document.activeElement).toBe(overlay.querySelector('.modal-close'));
        return { overlay, externalBtn };
    }

    it('关闭按钮关闭 → 焦点还原到打开前元素', async () => {
        const { overlay, externalBtn } = await setupModalWithExternalFocus();
        overlay.querySelector('.modal-close').click();
        expect(document.querySelector('.modal-overlay')).toBeNull();
        expect(document.activeElement).toBe(externalBtn);
    });

    it('Escape 关闭 → 焦点还原到打开前元素', async () => {
        const { overlay, externalBtn } = await setupModalWithExternalFocus();
        overlay.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
        expect(document.querySelector('.modal-overlay')).toBeNull();
        expect(document.activeElement).toBe(externalBtn);
    });

    it('点击遮罩关闭 → 焦点还原到打开前元素', async () => {
        const { overlay, externalBtn } = await setupModalWithExternalFocus();
        overlay.click(); // target === overlay → 遮罩关闭路径
        expect(document.querySelector('.modal-overlay')).toBeNull();
        expect(document.activeElement).toBe(externalBtn);
    });

    it('Falsify: 打开前元素已被移除（removeExisting 场景）→ 还原跳过不抛错', async () => {
        const mod = await loadModal();
        // 旧弹窗内含一个将被聚焦的元素
        const first = mod.openModal({ title: '旧', body: '<button id="inner1">内</button>' });
        first.querySelector('#inner1').focus();
        expect(document.activeElement).toBe(first.querySelector('#inner1'));

        // 第二个 openModal 用 removeExisting 移除旧弹窗（inner1 随之脱离 DOM）—
        // 打开时记录的 previouslyFocused = inner1（isConnected=false）→ 关闭还原跳过
        const second = mod.openModal({ title: '新', body: '<p>x</p>', removeExisting: '.modal-overlay' });
        expect(() => second.querySelector('.modal-close').click()).not.toThrow();
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });
});

describe('modal — 三条关闭路径回归（零回归）', () => {
    beforeEach(() => {
        document.body.innerHTML = '';
    });
    afterEach(() => {
        document.body.innerHTML = '';
    });

    it('关闭按钮 → overlay 移除 + onClose 收到 cancelResult', async () => {
        const mod = await loadModal();
        const onClose = vi.fn();
        const overlay = mod.openModal({ title: 'T', onClose });
        overlay.querySelector('.modal-close').click();
        expect(document.querySelector('.modal-overlay')).toBeNull();
        expect(onClose).toHaveBeenCalledWith(undefined);
    });

    it('点击遮罩 → 关闭（closeOnBackdrop 默认 true；点框内不关闭）', async () => {
        const mod = await loadModal();
        const overlay = mod.openModal({ title: 'T', actions: '<button id="inner">内</button>' });
        document.querySelector('#inner').click();
        expect(document.querySelector('.modal-overlay')).not.toBeNull(); // 点框内不关
        overlay.click();
        expect(document.querySelector('.modal-overlay')).toBeNull(); // 点遮罩关
    });

    it('Escape → 关闭：closeOnEscape=true 关闭；false 不关闭', async () => {
        const mod = await loadModal();
        const overlay = mod.openModal({ title: 'T' });
        overlay.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
        expect(document.querySelector('.modal-overlay')).toBeNull();

        const overlay2 = mod.openModal({ title: 'T', closeOnEscape: false });
        overlay2.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
        expect(document.querySelector('.modal-overlay')).not.toBeNull();
    });

    it('close()（onOpen 回调提供）关闭 → overlay 移除 + 焦点还原', async () => {
        const mod = await loadModal();
        const externalBtn = document.createElement('button');
        externalBtn.id = 'ext2';
        document.body.appendChild(externalBtn);
        externalBtn.focus();

        let closeFn = null;
        mod.openModal({ title: 'T', onOpen: (el, close) => { closeFn = close; } });
        closeFn('result');
        expect(document.querySelector('.modal-overlay')).toBeNull();
        expect(document.activeElement).toBe(externalBtn);
    });
});