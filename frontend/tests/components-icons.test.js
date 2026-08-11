import { afterEach, describe, expect, it } from 'vitest';
import { openModal } from '../js/components/modal.js';
import { showConfirm } from '../js/components/confirm-dialog.js';
import { showExportDialog } from '../js/components/export-dialog.js';
import { showCharacterWizard } from '../js/components/character-wizard.js';

afterEach(() => {
    document.body.innerHTML = '';
});

describe('动态组件图标语义', () => {
    it('通用模态框使用可访问名称与 x 图标关闭', () => {
        const overlay = openModal({ title: '测试弹窗' });
        const close = overlay.querySelector('.modal-close');

        expect(close.title).toBe('关闭');
        expect(close.querySelector('[data-icon="x"]')).not.toBeNull();
    });

    it('确认框按危险级别输出 warning 或 info 图标', async () => {
        const dangerResult = showConfirm({ message: '删除数据', danger: true });
        expect(document.querySelector('.confirm-icon [data-icon="warning"]')).not.toBeNull();
        document.querySelector('.confirm-cancel').click();
        await expect(dangerResult).resolves.toBe(false);

        const infoResult = showConfirm({ message: '继续操作' });
        expect(document.querySelector('.confirm-icon [data-icon="info"]')).not.toBeNull();
        document.querySelector('.confirm-cancel').click();
        await expect(infoResult).resolves.toBe(false);
    });

    it('导出选项使用文件类型图标并保留格式文字', () => {
        showExportDialog(7);
        const overlay = document.querySelector('#export-dialog-overlay');

        expect(overlay.querySelector('[data-icon="fileText"]')).not.toBeNull();
        expect(overlay.querySelector('[data-icon="fileJson"]')).not.toBeNull();
        expect(overlay.textContent).toContain('Markdown (.md)');
        expect(overlay.textContent).toContain('JSON (.json)');
    });

    it('角色向导入口只输出 SVG 图标，用户后续输入不受过滤', () => {
        showCharacterWizard();
        const overlay = document.querySelector('.wizard-modal');

        expect(overlay.querySelector('.modal-close [data-icon="x"]')).not.toBeNull();
        expect(overlay.querySelector('.wizard-mode-card[data-mode="import"] [data-icon="fileText"]')).not.toBeNull();
        expect(overlay.querySelector('.wizard-mode-card[data-mode="template"] [data-icon="character"]')).not.toBeNull();
        expect(overlay.querySelector('.wizard-mode-card[data-mode="manual"] [data-icon="edit"]')).not.toBeNull();

        overlay.querySelector('.wizard-mode-card[data-mode="manual"]').click();
        const nameInput = overlay.querySelector('#wiz-name');
        nameInput.value = '角色🙂';
        nameInput.dispatchEvent(new Event('input', { bubbles: true }));
        expect(nameInput.value).toBe('角色🙂');
    });
});
