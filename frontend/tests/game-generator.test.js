/**
 * 游戏生成器组件测试（game-generator.js 深模块）
 *
 * 覆盖（公共接口边界 — __all__）：
 *   - initGameGenerator：注册 onGenerated 钩子
 *   - openGenerateFlow：打开模态框（标题 / textarea / 提交按钮 / 上传按钮）
 *     缺标题/空描述提交 → 校验错误提示
 *   - resetGameGenerator：复位生成中状态
 *   - Falsify：未 init 不炸 / 重复 init 更新钩子
 *
 * 挂载模式：jsdom + vi.resetModules() + 真实 modal.js 工厂（与 character-modal
 *   测试同模式）；showError/showSuccess 由 utils spy 抑制 DOM 副作用。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

/** 成功响应 */
const mockJson = (data, status = 200) => Promise.resolve({
    ok: status < 400,
    status,
    json: async () => data,
    text: async () => JSON.stringify(data),
});

/** 加载全新 game-generator 模块（DOM 先就位；返回模块 + utils spy） */
async function loadModules() {
    vi.resetModules();
    document.body.innerHTML = '';
    const gen = await import('../js/components/game-generator.js');
    const utils = await import('../js/utils.js');
    vi.spyOn(utils, 'showError').mockImplementation(() => {});
    vi.spyOn(utils, 'showSuccess').mockImplementation(() => {});
    return { gen, utils };
}

describe('game-generator — 协议表面 __all__', () => {
    it('__all__ 收口公开函数与 fetch seam', async () => {
        const { gen } = await loadModules();
        expect(gen.__all__.sort()).toEqual([
            'initGameGenerator',
            'openGenerateFlow',
            'resetGameGenerator',
            'setFetch',
        ]);
    });
});

describe('initGameGenerator — 钩子注册', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('注册 onGenerated 钩子：模拟成功生成后钩子被调用，模态框关闭', async () => {
        const { gen } = await loadModules();
        const hook = vi.fn();
        gen.setFetch(() => mockJson({ ok: true, game: { id: 'g1', file: 'g1.html' } }));
        gen.initGameGenerator({ onGenerated: hook });
        gen.openGenerateFlow();

        const desc = document.querySelector('#gg-description');
        desc.value = '一个赛博朋克世界';
        document.querySelector('#gg-submit-btn').click();

        await vi.waitFor(() => expect(hook).toHaveBeenCalledTimes(1));
        // 成功路径关闭模态框
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('成功生成后 onGenerated 返回完整响应（game 落列表刷新数据源）', async () => {
        const { gen } = await loadModules();
        const hook = vi.fn();
        gen.setFetch(() => mockJson({ ok: true, game: { id: 'g1', file: 'g1.html', name: '赛博追迹' } }));
        gen.initGameGenerator({ onGenerated: hook });
        gen.openGenerateFlow();

        document.querySelector('#gg-description').value = '赛博朋克';
        document.querySelector('#gg-submit-btn').click();

        await vi.waitFor(() => expect(hook).toHaveBeenCalledTimes(1));
    });

    it('Falsify: 校验失败 422 → 错误区域展示 + 重试按钮存在，模态框不关闭', async () => {
        const { gen } = await loadModules();
        gen.setFetch(() => mockJson({
            detail: { ok: false, errors: [{ field: 'data', message: '场景数据无效' }], suggestion: '请修正' },
        }, 422));
        gen.initGameGenerator({ onGenerated: vi.fn() });
        gen.openGenerateFlow();

        document.querySelector('#gg-description').value = '测试描述';
        document.querySelector('#gg-submit-btn').click();

        await vi.waitFor(() => {
            const resultArea = document.querySelector('#gg-result-area');
            expect(resultArea.className).toBe('gg-error');
        });
        expect(document.querySelector('#gg-retry-btn')).not.toBeNull();
        expect(document.querySelector('.modal-overlay')).not.toBeNull(); // 失败不关闭
    });

    it('Falsify: 不传参数不抛错', async () => {
        const { gen } = await loadModules();
        expect(() => gen.initGameGenerator()).not.toThrow();
        expect(() => gen.initGameGenerator({})).not.toThrow();
    });
});

describe('openGenerateFlow — 模态框结构', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => {
        document.body.innerHTML = '';
        vi.restoreAllMocks();
    });

    it('打开模态框：标题「AI 生成游戏」+ 关键字段存在', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();

        const overlay = document.querySelector('.modal-overlay');
        expect(overlay).not.toBeNull();
        expect(overlay.querySelector('.modal.game-gen-modal')).not.toBeNull();
        expect(overlay.querySelector('.modal-header h3').textContent).toBe('AI 生成游戏');
        expect(overlay.querySelector('#gg-description')).not.toBeNull();
        expect(overlay.querySelector('#gg-title')).not.toBeNull();
        expect(overlay.querySelector('#gg-upload-btn')).not.toBeNull();
        expect(overlay.querySelector('#gg-submit-btn')).not.toBeNull();
    });

    it('提交按钮存在且文案正确', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();

        const submitBtn = document.querySelector('#gg-submit-btn');
        expect(submitBtn).not.toBeNull();
        expect(submitBtn.textContent).toContain('生成游戏');
    });

    it('取消按钮存在且点击关闭模态框', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();

        const cancelBtn = document.querySelector('.modal-cancel');
        expect(cancelBtn).not.toBeNull();
        cancelBtn.click();
        expect(document.querySelector('.modal-overlay')).toBeNull();
    });

    it('空描述提交 → 校验错误提示', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();

        const submitBtn = document.querySelector('#gg-submit-btn');
        const descError = document.querySelector('#gg-desc-error');
        expect(descError.hidden).toBe(true);

        // 提交空描述
        submitBtn.click();
        expect(descError.hidden).toBe(false);
        expect(descError.textContent).toContain('请输入世界观设定');
    });

    it('Falsify: 未 init 可调用 openGenerateFlow（创建模态框）', async () => {
        const { gen } = await loadModules();
        // 未调用 initGameGenerator 直接 open
        expect(() => gen.openGenerateFlow()).not.toThrow();
        expect(document.querySelector('.modal-overlay')).not.toBeNull();
    });

    it('Falsify: 重复调用 openGenerateFlow 创建新模态框（removeExisting 替换旧弹窗）', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();
        const firstOverlay = document.querySelector('.modal-overlay');

        gen.openGenerateFlow();
        // 旧弹窗已移除，新弹窗存在
        expect(document.querySelector('.modal-overlay')).not.toBeNull();
    });
});

describe('resetGameGenerator — 复位', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('复位不抛错', async () => {
        const { gen } = await loadModules();
        expect(() => gen.resetGameGenerator()).not.toThrow();
    });

    it('打开模态框后复位（生成中状态清理）', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();
        expect(() => gen.resetGameGenerator()).not.toThrow();
    });
});

describe('game-generator — 上传/校验/错误分支（覆盖率收口）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('上传 .txt 文件 → 填入 textarea + 自动生成标题', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();
        const fileInput = document.querySelector('#gg-file-input');
        const file = new File(['霓虹都市'], '赛博追迹.txt', { type: 'text/plain' });
        Object.defineProperty(fileInput, 'files', { value: [file], configurable: true });

        fileInput.dispatchEvent(new Event('change'));

        await vi.waitFor(() => {
            expect(document.querySelector('#gg-description').value).toBe('霓虹都市');
        });
        expect(document.querySelector('#gg-title').value).toBe('赛博追迹'); // 文件名去扩展名
    });

    it('上传非文本文件 → 错误提示「仅支持 .txt、.md、.text 文件」', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();
        const fileInput = document.querySelector('#gg-file-input');
        Object.defineProperty(fileInput, 'files', { value: [new File(['x'], 'game.html', { type: 'text/html' })], configurable: true });

        fileInput.dispatchEvent(new Event('change'));

        const descError = document.querySelector('#gg-desc-error');
        await vi.waitFor(() => expect(descError.hidden).toBe(false));
        expect(descError.textContent).toBe('仅支持 .txt、.md、.text 文件');
    });

    it('上传无文件（files 为空）→ no-op 不抛错', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();
        const fileInput = document.querySelector('#gg-file-input');
        Object.defineProperty(fileInput, 'files', { value: [], configurable: true });
        expect(() => fileInput.dispatchEvent(new Event('change'))).not.toThrow();
    });

    it('描述超长（> 10000 字）→ 错误提示', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();
        document.querySelector('#gg-description').value = 'x'.repeat(10001);
        document.querySelector('#gg-submit-btn').click();

        const descError = document.querySelector('#gg-desc-error');
        expect(descError.hidden).toBe(false);
        expect(descError.textContent).toContain('不能超过 10000 字');
    });

    it('输入时清除错误提示（input 事件）', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();
        const descError = document.querySelector('#gg-desc-error');
        // 先触发空描述错误
        document.querySelector('#gg-submit-btn').click();
        expect(descError.hidden).toBe(false);
        // 输入 → 清除
        document.querySelector('#gg-description').value = '有内容';
        document.querySelector('#gg-description').dispatchEvent(new Event('input'));
        expect(descError.hidden).toBe(true);
    });

    it('其他 HTTP 错误（500 + 字符串 detail）→ 「生成失败」错误消息 + 重试按钮，不关闭', async () => {
        const { gen } = await loadModules();
        gen.setFetch(() => mockJson({ detail: '服务器繁忙' }, 500));
        gen.initGameGenerator({ onGenerated: vi.fn() });
        gen.openGenerateFlow();
        document.querySelector('#gg-description').value = '测试';
        document.querySelector('#gg-submit-btn').click();

        await vi.waitFor(() => {
            expect(document.querySelector('#gg-result-area').className).toBe('gg-error');
        });
        expect(document.querySelector('#gg-result-area').textContent).toContain('生成失败');
        expect(document.querySelector('#gg-result-area').textContent).toContain('服务器繁忙');
        expect(document.querySelector('#gg-retry-btn')).not.toBeNull();
        expect(document.querySelector('.modal-overlay')).not.toBeNull();
    });

    it('网络错误（fetch 拒绝）→ 「请求失败」错误消息', async () => {
        const { gen } = await loadModules();
        gen.setFetch(() => { throw new Error('网络中断'); });
        gen.initGameGenerator({ onGenerated: vi.fn() });
        gen.openGenerateFlow();
        document.querySelector('#gg-description').value = '测试';
        document.querySelector('#gg-submit-btn').click();

        await vi.waitFor(() => {
            expect(document.querySelector('#gg-result-area').className).toBe('gg-error');
        });
        expect(document.querySelector('#gg-result-area').textContent).toContain('请求失败');
        expect(document.querySelector('#gg-result-area').textContent).toContain('网络中断');
    });

    it('重试按钮点击 → 重新发起生成请求', async () => {
        const { gen } = await loadModules();
        const fetchMock = vi.fn()
            .mockImplementationOnce(() => mockJson({ detail: { ok: false, errors: [{ field: 'data', message: '无效' }] } }, 422))
            .mockImplementationOnce(() => mockJson({ ok: true, game: { id: 'g2', file: 'g2.html' } }));
        gen.setFetch(fetchMock);
        const hook = vi.fn();
        gen.initGameGenerator({ onGenerated: hook });
        gen.openGenerateFlow();
        document.querySelector('#gg-description').value = '测试';
        document.querySelector('#gg-submit-btn').click();

        await vi.waitFor(() => {
            expect(document.querySelector('#gg-retry-btn')).not.toBeNull();
        });
        document.querySelector('#gg-retry-btn').click();
        await vi.waitFor(() => expect(hook).toHaveBeenCalledTimes(1));
        expect(fetchMock).toHaveBeenCalledTimes(2); // 首次 + 重试
        expect(document.querySelector('.modal-overlay')).toBeNull(); // 重试成功关闭
    });

    it('上传按钮点击 → 触发隐藏文件输入选择器（fileInput.click）', async () => {
        const { gen } = await loadModules();
        gen.openGenerateFlow();
        const fileInput = document.querySelector('#gg-file-input');
        const clickSpy = vi.spyOn(fileInput, 'click').mockImplementation(() => {});
        document.querySelector('#gg-upload-btn').click();
        expect(clickSpy).toHaveBeenCalledTimes(1);
    });
});

describe('openGenerateFlow — 凭证预检（T4）', () => {
    beforeEach(() => { vi.restoreAllMocks(); });
    afterEach(() => { document.body.innerHTML = ''; vi.restoreAllMocks(); });

    it('openai 态 → 无顶部提示（#gg-cred-warning 保持隐藏）', async () => {
        const { gen } = await loadModules();
        gen.initGameGenerator({
            getCredentials: vi.fn(async () => ({ key: 'sk-x', endpoint: 'e', model: 'm', protocol: 'openai' })),
        });
        gen.openGenerateFlow();

        await vi.waitFor(() => {
            expect(document.querySelector('#gg-cred-warning')).not.toBeNull();
        });
        expect(document.querySelector('#gg-cred-warning').hidden).toBe(true);
        expect(document.querySelector('#gg-cred-warning').textContent).not.toContain('需先配置');
    });

    it('none 态 → 顶部提示「需先配置 OpenAI 兼容 Key」+ 设置链接（复用 key-injector 常量），点击跳转', async () => {
        const navigate = vi.fn();
        const { gen } = await loadModules();
        gen.initGameGenerator({
            getCredentials: vi.fn(async () => ({ key: '', endpoint: '', model: '', protocol: 'none' })),
            onNavigateSettings: navigate,
        });
        gen.openGenerateFlow();

        await vi.waitFor(() => {
            expect(document.querySelector('#gg-cred-warning').hidden).toBe(false);
        });
        const warning = document.querySelector('#gg-cred-warning');
        expect(warning.textContent).toContain('需先配置 OpenAI 兼容 Key');
        const link = warning.querySelector('.sim-key-nav-settings');
        expect(link).not.toBeNull();
        expect(link.textContent).toBe('前往设置页配置'); // 复用 key-injector LINK_NAV_SETTINGS

        link.click();
        expect(navigate).toHaveBeenCalledTimes(1); // 点击 → switchView('settings')
        link.click();
        expect(navigate).toHaveBeenCalledTimes(2);
    });

    it('claude 态 → 同样顶部提示 + 设置链接', async () => {
        const navigate = vi.fn();
        const { gen } = await loadModules();
        gen.initGameGenerator({
            getCredentials: vi.fn(async () => ({ key: '', endpoint: '', model: '', protocol: 'claude' })),
            onNavigateSettings: navigate,
        });
        gen.openGenerateFlow();

        await vi.waitFor(() => {
            expect(document.querySelector('#gg-cred-warning').hidden).toBe(false);
        });
        const warning = document.querySelector('#gg-cred-warning');
        expect(warning.textContent).toContain('需先配置 OpenAI 兼容 Key');
        warning.querySelector('.sim-key-nav-settings').click();
        expect(navigate).toHaveBeenCalledTimes(1);
    });

    it('Falsify: 凭证请求失败 → 不阻塞打开（模态框已打开、无提示）', async () => {
        const { gen } = await loadModules();
        gen.initGameGenerator({
            getCredentials: vi.fn(async () => { throw new Error('网络错误'); }),
        });
        expect(() => gen.openGenerateFlow()).not.toThrow();
        // 模态框立即打开（凭证检查非阻塞）
        expect(document.querySelector('.modal-overlay')).not.toBeNull();

        await vi.waitFor(() => {
            // 请求失败降级：无提示（warning 保持隐藏）
            expect(document.querySelector('#gg-cred-warning').hidden).toBe(true);
        });
        expect(document.querySelector('.modal-overlay')).not.toBeNull(); // 仍打开
    });

    it('Falsify: 未注入 getCredentials → 打开不报错、无提示', async () => {
        const { gen } = await loadModules();
        expect(() => gen.openGenerateFlow()).not.toThrow();
        expect(document.querySelector('.modal-overlay')).not.toBeNull();
        await vi.waitFor(() => {
            expect(document.querySelector('#gg-cred-warning').hidden).toBe(true);
        });
    });

    it('竞态守卫: 提交生成后迟到的凭证预检响应不注入提示（生成中状态不被覆盖）', async () => {
        const { gen } = await loadModules();

        // 凭证预检与生成请求均挂起可手动放行：先生成进行中（generating=true），
        // 再让凭证预检响应迟到到达（none 态，本应注入顶部提示）
        let resolveCreds;
        const credsPromise = new Promise((r) => { resolveCreds = r; });
        let resolveGenerate;
        const generatePromise = new Promise((r) => { resolveGenerate = r; });

        gen.setFetch(() => generatePromise);
        gen.initGameGenerator({
            getCredentials: vi.fn(() => credsPromise),
        });
        gen.openGenerateFlow();

        // 提交生成 → generating 置 true（executeGenerate 首条语句，同步生效）
        document.querySelector('#gg-description').value = '赛博朋克';
        document.querySelector('#gg-submit-btn').click();

        // 凭证预检响应此刻到达（none 态）
        resolveCreds({ key: '', endpoint: '', model: '', protocol: 'none' });

        // 提示必须保持隐藏：生成中状态不被「需配置」提示覆盖
        await vi.waitFor(() => {
            expect(document.querySelector('#gg-cred-warning').hidden).toBe(true);
        });
        expect(document.querySelector('#gg-cred-warning').textContent).not.toContain('需先配置');
        // 生成仍进行中：模态框未关闭、结果区无错误
        expect(document.querySelector('.modal-overlay')).not.toBeNull();
        expect(document.querySelector('#gg-result-area').className).not.toBe('gg-error');

        // 收尾：放行生成请求（避免挂起），成功关闭模态框
        resolveGenerate(mockJson({ ok: true, game: { id: 'g1', file: 'g1.html' } }));
        await vi.waitFor(() => expect(document.querySelector('.modal-overlay')).toBeNull());
    });

    it('竞态守卫: 模态框关闭后到达的凭证预检响应被丢弃（不注入提示）', async () => {
        const { gen } = await loadModules();

        let resolveCreds;
        const credsPromise = new Promise((r) => { resolveCreds = r; });
        gen.initGameGenerator({
            getCredentials: vi.fn(() => credsPromise),
        });
        gen.openGenerateFlow();

        // 关闭模态框（el.isConnected 变 false）后凭证预检响应才到达
        document.querySelector('.modal-overlay .modal-close').click();
        expect(document.querySelector('.modal-overlay')).toBeNull();

        resolveCreds({ key: '', endpoint: '', model: '', protocol: 'none' });
        // 迟到响应被丢弃：不抛错、不复活模态框、无提示注入
        await new Promise((r) => setTimeout(r, 0));
        expect(document.querySelector('.modal-overlay')).toBeNull();
        const stale = document.querySelector('#gg-cred-warning');
        expect(stale).toBeNull(); // 模态框 DOM 已整体移除
    });
});