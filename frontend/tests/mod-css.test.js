/**
 * mod-css.js 契约锁（spec T4 — css 区 Mod 前端注入 seam）
 *
 * 覆盖：
 *   1. 注入：enabled css Mod payload → <style id="mod-css-active"> 挂 document.head
 *   2. 关联：binding（不嵌套 Mod）+ Mod 库两段式按 mod_id 客户端关联；
 *      过滤 enabled && target_area==='css'；按 binding sort_order 升序以 '\n' 拼接
 *   3. 幂等：重复 apply 至多一个节点；remove 后不存在；无节点 remove 为 no-op
 *   4. 零注入：无绑定 / 无 css Mod / 空 payload / 全禁用 → 不产生节点
 *   5. 失败：取数 reject → 不注入、不向调用方抛出（静默降级）
 *   6. Falsify：payload 含 '</style>' 不撑破 DOM 结构（textContent 赋值）；
 *      remove 使在途 apply 失效（竞态：后到的旧 apply 不得注入）
 *
 * 挂载模式：jsdom + fetch-seam（api.js setFetch）— 对齐 mod-manager.test.js 的
 * fetch mock 模式，走真实 api.js mods 方法。
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { setFetch } from '../js/api.js';
import { applyCharacterCss, removeCharacterCss, __all__ } from '../js/mod-css.js';

const STYLE_ID = 'mod-css-active';

const mockJson = (data, status = 200) =>
    Promise.resolve({ ok: status < 400, status, json: async () => data });

/** Mod 库条目工厂（ModResponse 形状的最小集） */
const mod = (id, targetArea, payload) => ({ id, name: `M${id}`, target_area: targetArea, payload });

/** binding 工厂（ModBindingResponse 形状 —— 不嵌套 Mod 详情） */
const binding = (id, modId, { enabled = true, sortOrder = 0 } = {}) => ({
    id, character_id: 7, mod_id: modId, enabled, sort_order: sortOrder,
});

/**
 * fetch mock 路由：GET /api/mods → Mod 库；GET /api/characters/{id}/mods → bindings。
 * @param {object} deps
 * @param {Array} deps.library - Mod 库列表
 * @param {Array} deps.bindings - 角色挂载列表
 * @param {{resolve?: (value: unknown) => void}} [deps.gate] - 挂起闸（构造时先挂起，
 *   手动 resolve 后 fetch 才返回 —— 竞态用例用）
 */
function makeModsFetch({ library = [], bindings = [], gate = null } = {}) {
    let calls = 0;
    return vi.fn(async (url) => {
        // gate 只挂起首次调用（apply 走 Promise.all 两个请求，全挂起会互相等死）
        const shouldGate = gate != null && calls === 0;
        calls += 1;
        if (shouldGate) await new Promise((resolve) => { gate.resolve = resolve; });
        const path = String(url).replace(/^.*\/api/, '/api');
        if (path === '/api/mods') return mockJson(library);
        const m = path.match(/^\/api\/characters\/(\d+)\/mods$/);
        if (m) return mockJson(bindings);
        throw new Error(`未 mock 的请求: ${path}`);
    });
}

const activeStyle = () => document.getElementById(STYLE_ID);
const headStyleCount = () => document.head.querySelectorAll('style').length;

beforeEach(() => {
    document.head.innerHTML = '';
});
afterEach(() => {
    removeCharacterCss();
    vi.restoreAllMocks();
});

describe('1. 注入（enabled css Mod payload → style 节点）', () => {
    it('单个 enabled css Mod：head 存在 #mod-css-active 且文本含 payload', async () => {
        setFetch(makeModsFetch({
            library: [mod(1, 'css', '.chat { color: red; }')],
            bindings: [binding(10, 1, { sortOrder: 0 })],
        }));

        await applyCharacterCss(7);

        const style = activeStyle();
        expect(style).not.toBeNull();
        expect(style.textContent).toContain('.chat { color: red; }');
    });

    it('多 Mod 按 binding sort_order 升序以 \\n 拼接；disabled 与 prompt/memory 区不出现', async () => {
        setFetch(makeModsFetch({
            // 库 id 乱序（关联按 mod_id，与库序无关）
            library: [
                mod(3, 'css', '/* c3 */'),
                mod(1, 'css', '/* c1 */'),
                mod(2, 'prompt', '{"world":"x"}'),
                mod(4, 'memory', '归纳口径'),
                mod(5, 'css', '/* c5 */'),
            ],
            // bindings 故意乱序（sort_order 2,0,1）→ 断言按 sort_order 升序拼接
            bindings: [
                binding(13, 3, { sortOrder: 2 }),
                binding(11, 1, { sortOrder: 0 }),
                binding(12, 2, { sortOrder: 3 }),  // prompt 区 → 排除
                binding(14, 4, { sortOrder: 4 }),  // memory 区 → 排除
                binding(15, 5, { enabled: false, sortOrder: 5 }), // disabled → 排除
            ],
        }));

        await applyCharacterCss(7);

        const style = activeStyle();
        expect(style).not.toBeNull();
        expect(style.textContent).toBe('/* c1 */\n/* c3 */');
    });
});

describe('2. 幂等与移除', () => {
    it('重复 apply → 至多一个 #mod-css-active（内容为最新一次）', async () => {
        setFetch(makeModsFetch({
            library: [mod(1, 'css', '.a{}'), mod(2, 'css', '.b{}')],
            bindings: [binding(10, 1)],
        }));

        await applyCharacterCss(7);
        // 换角色（bindings/mods 数据随 mock 切换）
        setFetch(makeModsFetch({
            library: [mod(2, 'css', '.b{}')],
            bindings: [binding(20, 2)],
        }));
        await applyCharacterCss(8);

        expect(headStyleCount()).toBe(1);
        expect(activeStyle().textContent).toBe('.b{}');
    });

    it('remove 后节点不存在；无节点时 remove 为 no-op（不抛错）', async () => {
        setFetch(makeModsFetch({
            library: [mod(1, 'css', '.a{}')],
            bindings: [binding(10, 1)],
        }));

        await applyCharacterCss(7);
        expect(activeStyle()).not.toBeNull();

        removeCharacterCss();
        expect(activeStyle()).toBeNull();

        expect(() => removeCharacterCss()).not.toThrow();
        expect(activeStyle()).toBeNull();
    });
});

describe('3. 零注入（无绑定 / 无 css Mod / 空 payload / 全禁用）', () => {
    it.each([
        ['无任何绑定', { library: [mod(1, 'css', '.a{}')], bindings: [] }],
        ['绑定指向的 Mod 不在库中（悬空 mod_id）', { library: [], bindings: [binding(10, 99)] }],
        ['无 css 区 Mod（prompt/memory）', {
            library: [mod(1, 'prompt', 'x'), mod(2, 'memory', 'y')],
            bindings: [binding(10, 1), binding(11, 2)],
        }],
        ['payload 为空串', { library: [mod(1, 'css', '')], bindings: [binding(10, 1)] }],
        ['payload 为纯空白', { library: [mod(1, 'css', '  \n\t ')], bindings: [binding(10, 1)] }],
        ['绑定全禁用', { library: [mod(1, 'css', '.a{}')], bindings: [binding(10, 1, { enabled: false })] }],
    ])('%s → apply 后不产生 style 节点', async (_name, deps) => {
        setFetch(makeModsFetch(deps));

        await applyCharacterCss(7);

        expect(activeStyle()).toBeNull();
        expect(headStyleCount()).toBe(0);
    });
});

describe('4. 取数失败（静默降级）', () => {
    it('fetch reject → apply 不抛出、不注入节点，console 记录', async () => {
        const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
        setFetch(vi.fn(async () => { throw new Error('network down'); }));

        await expect(applyCharacterCss(7)).resolves.not.toThrow();
        expect(activeStyle()).toBeNull();
        expect(errSpy).toHaveBeenCalled();
    });

    it('响应非 2xx（错误通道）→ 同样不注入、不抛出', async () => {
        vi.spyOn(console, 'error').mockImplementation(() => {});
        setFetch(vi.fn(async () => mockJson({ detail: 'boom' }, 500)));

        await expect(applyCharacterCss(7)).resolves.not.toThrow();
        expect(activeStyle()).toBeNull();
    });
});

describe('5. Falsify（对抗性）', () => {
    it('payload 含 </style> 闭合攻击 → DOM 结构不破（仍单个 style 节点，textContent 完整保留）', async () => {
        const evil = '.x{} </style><script>alert(1)</script><style> .y{}';
        setFetch(makeModsFetch({
            library: [mod(1, 'css', evil)],
            bindings: [binding(10, 1)],
        }));

        await applyCharacterCss(7);

        expect(headStyleCount()).toBe(1);
        expect(activeStyle().textContent).toBe(evil);
        // 无逃逸元素：payload 未在 style 之外产生节点
        expect(document.head.querySelectorAll('script')).toHaveLength(0);
    });

    it('超长 payload（~1MB）→ 单节点注入、textContent 完整（注入通道不被 payload 体量破坏）', async () => {
        const big = `.rule-${'x'.repeat(1024 * 1024)} { color: red; }`;
        setFetch(makeModsFetch({
            library: [mod(1, 'css', big)],
            bindings: [binding(10, 1)],
        }));

        await applyCharacterCss(7);

        expect(headStyleCount()).toBe(1);
        expect(activeStyle().textContent.length).toBe(big.length);
        expect(activeStyle().textContent.startsWith('.rule-xxx')).toBe(true);
    });

    it('竞态：apply 取数挂起期间 remove → 在途 apply 失效，最终无节点', async () => {
        const gate = {};
        setFetch(makeModsFetch({
            library: [mod(1, 'css', '.stale{}')],
            bindings: [binding(10, 1)],
            gate,
        }));

        const pending = applyCharacterCss(7);
        // 取数挂起期间用户切走 → remove
        removeCharacterCss();
        gate.resolve(); // 放行挂起的 fetch
        await pending;

        expect(activeStyle()).toBeNull();
    });

    it('竞态：旧角色 apply 晚于新角色 apply 完成 → 旧结果被丢弃（活动角色样式不被覆盖）', async () => {
        // 第一次取数挂起（旧角色 7），第二次立即返回（新角色 8）
        const gate = {};
        let call = 0;
        setFetch(vi.fn(async (url) => {
            const path = String(url).replace(/^.*\/api/, '/api');
            if (path === '/api/mods') {
                const isFirst = call === 0;
                call += 1;
                if (isFirst) { await new Promise((r) => { gate.resolve = r; }); }
                return mockJson([mod(1, 'css', '.old{}'), mod(2, 'css', '.new{}')]);
            }
            if (path === '/api/characters/7/mods') return mockJson([binding(10, 1)]);
            if (path === '/api/characters/8/mods') return mockJson([binding(20, 2)]);
            throw new Error(`未 mock 的请求: ${path}`);
        }));

        const stale = applyCharacterCss(7);
        await applyCharacterCss(8);
        expect(activeStyle().textContent).toBe('.new{}');

        gate.resolve();
        await stale;
        // 旧角色的迟到 apply 不得覆盖新角色样式
        expect(activeStyle().textContent).toBe('.new{}');
    });
});

describe('6. 协议表面', () => {
    it('__all__ 收口（applyCharacterCss / removeCharacterCss）', () => {
        expect(__all__).toEqual(['applyCharacterCss', 'removeCharacterCss']);
    });
});
