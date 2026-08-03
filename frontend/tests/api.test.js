import { describe, it, expect, vi, afterEach } from 'vitest';
import { characters, conversations, messages, setFetch } from '../js/api.js';

/**
 * 构造 mock Response（满足 api.js 用到的 status/ok/json 字段）
 */
function mockResponse({ ok = true, status = 200, data = {} } = {}) {
    return {
        ok,
        status,
        json: async () => data,
    };
}

describe('api.js fetch seam', () => {
    afterEach(() => {
        setFetch(null);
    });

    it('characters.list() 请求 GET /api/characters 并解析返回数据', async () => {
        const fetchMock = vi.fn(async () => mockResponse({ data: [{ id: 1, name: 'A' }] }));
        setFetch(fetchMock);

        const data = await characters.list();

        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(fetchMock).toHaveBeenCalledWith('/api/characters', expect.objectContaining({ method: 'GET' }));
        expect(data).toEqual([{ id: 1, name: 'A' }]);
    });

    it('characters.create() 请求 POST 并携带 JSON body', async () => {
        const fetchMock = vi.fn(async () => mockResponse({ data: { id: 1, name: 'X' } }));
        setFetch(fetchMock);

        const data = await characters.create({ name: 'X' });

        const [url, options] = fetchMock.mock.calls[0];
        expect(url).toBe('/api/characters');
        expect(options.method).toBe('POST');
        expect(JSON.parse(options.body)).toEqual({ name: 'X' });
        expect(data).toEqual({ id: 1, name: 'X' });
    });

    it('messages.search() 编码 query 参数', async () => {
        const fetchMock = vi.fn(async () => mockResponse({ data: [] }));
        setFetch(fetchMock);

        await messages.search('你好 world', 20);

        expect(fetchMock).toHaveBeenCalledWith(
            '/api/messages/search?q=%E4%BD%A0%E5%A5%BD%20world&limit=20',
            expect.objectContaining({ method: 'GET' })
        );
    });

    it('非 2xx 响应抛出带 detail 的 Error', async () => {
        const fetchMock = vi.fn(async () =>
            mockResponse({ ok: false, status: 422, data: { detail: '导入失败：字段错误' } })
        );
        setFetch(fetchMock);

        await expect(characters.import({})).rejects.toThrow('导入失败：字段错误');
    });

    it('204 响应返回 null 且不解析 JSON', async () => {
        const fetchMock = vi.fn(async () => ({
            ok: true,
            status: 204,
            json: async () => {
                throw new Error('不应调用 json()');
            },
        }));
        setFetch(fetchMock);

        const data = await conversations.deleteAll();

        expect(data).toBeNull();
        expect(fetchMock).toHaveBeenCalledWith('/api/conversations', expect.objectContaining({ method: 'DELETE' }));
    });
});
