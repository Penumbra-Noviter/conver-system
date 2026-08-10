import { describe, it, expect, vi, afterEach } from 'vitest';
import { characters, conversations, messages, request, requestBlob, setFetch } from '../js/api.js';
import { downloadBlob } from '../js/utils.js';

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

/**
 * 构造 Blob 响应 mock（满足 requestBlob 用到的 ok/status/headers/blob 字段）
 */
function mockBlobResponse({ ok = true, status = 200, contentDisposition = null, detail = '导出失败' } = {}) {
    return {
        ok,
        status,
        headers: {
            get: (name) => (name.toLowerCase() === 'content-disposition' ? contentDisposition : null),
        },
        json: async () => ({ detail }),
        text: async () => detail,
        blob: async () => new Blob(['mock-body']),
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

describe('requestBlob', () => {
    afterEach(() => {
        setFetch(null);
    });

    it('走 doFetch seam：GET /api/... 并返回 Blob', async () => {
        const fetchMock = vi.fn(async () =>
            mockBlobResponse({ contentDisposition: 'attachment; filename="fallback.json"' })
        );
        setFetch(fetchMock);

        const { blob } = await requestBlob('/characters/1/export');

        expect(fetchMock).toHaveBeenCalledTimes(1);
        expect(fetchMock).toHaveBeenCalledWith('/api/characters/1/export', expect.objectContaining({ method: 'GET' }));
        expect(blob).toBeInstanceOf(Blob);
    });

    it('文件名解析：filename*（RFC 5987 UTF-8）优先于 filename，中文正确解码', async () => {
        // 与后端 conversations 导出一致的格式：attachment; filename="ascii兜底"; filename*=UTF-8''<percent-encoded>
        const fetchMock = vi.fn(async () =>
            mockBlobResponse({
                contentDisposition:
                    'attachment; filename="conversation-1.json"; filename*=UTF-8\'\'conversation-1-%E5%B0%8F%E7%BA%A2.json',
            })
        );
        setFetch(fetchMock);

        const { filename } = await requestBlob('/conversations/1/export/json');

        expect(filename).toBe('conversation-1-小红.json');
    });

    it('文件名解析：无 filename* 回退 filename；无 Content-Disposition 返回 null', async () => {
        // markdown 导出只有 filename（后端 format：filename="conversation-1.md"）
        setFetch(vi.fn(async () => mockBlobResponse({ contentDisposition: 'attachment; filename="conversation-1.md"' })));
        expect((await requestBlob('/conversations/1/export/markdown')).filename).toBe('conversation-1.md');

        // 角色卡导出只有 filename*（UTF-8 编码）
        setFetch(vi.fn(async () => mockBlobResponse({ contentDisposition: "attachment; filename*=UTF-8''%E7%8E%A9%E5%AE%B6.json" })));
        expect((await requestBlob('/characters/1/export')).filename).toBe('玩家.json');

        // filename* 非法百分号序列（解码失败）→ 回退 filename
        setFetch(
            vi.fn(async () =>
                mockBlobResponse({ contentDisposition: 'attachment; filename="backup.json"; filename*=UTF-8\'\'%E4%E5' })
            )
        );
        expect((await requestBlob('/characters/1/export')).filename).toBe('backup.json');

        // 无 Content-Disposition → null
        setFetch(vi.fn(async () => mockBlobResponse({ contentDisposition: null })));
        expect((await requestBlob('/conversations/1/export/json')).filename).toBeNull();
    });

    it('非 2xx 抛领域错误：优先 JSON detail，回退纯文本，再回退状态码', async () => {
        // JSON detail（FastAPI 错误响应）
        setFetch(vi.fn(async () => mockBlobResponse({ ok: false, status: 404, detail: '对话不存在' })));
        await expect(requestBlob('/conversations/999/export/json')).rejects.toThrow('对话不存在');

        // 纯文本错误体（非 JSON）
        setFetch(
            vi.fn(async () => ({
                ok: false,
                status: 500,
                headers: { get: () => null },
                json: async () => {
                    throw new SyntaxError('not json');
                },
                text: async () => '服务器内部错误',
                blob: async () => new Blob(['']),
            }))
        );
        await expect(requestBlob('/characters/1/export')).rejects.toThrow('服务器内部错误');

        // 空错误体 → 状态码兜底
        setFetch(
            vi.fn(async () => ({
                ok: false,
                status: 503,
                headers: { get: () => null },
                json: async () => {
                    throw new SyntaxError('not json');
                },
                text: async () => {
                    throw new SyntaxError('body consumed');
                },
                blob: async () => new Blob(['']),
            }))
        );
        await expect(requestBlob('/characters/1/export')).rejects.toThrow('请求失败 (503)');
    });

    it('超时抛 AbortError 领域错误（signal.abort → 归一化为「请求超时」）', async () => {
        vi.useFakeTimers();
        try {
            // 模拟真实 fetch：signal 中止时以 AbortError 拒绝
            const fetchMock = vi.fn(
                (_url, options) =>
                    new Promise((_resolve, reject) => {
                        options.signal.addEventListener('abort', () => {
                            const err = new Error('This operation was aborted');
                            err.name = 'AbortError';
                            reject(err);
                        });
                    })
            );
            setFetch(fetchMock);

            const pending = requestBlob('/characters/1/export', { timeout: 100 });
            const assertion = expect(pending).rejects.toMatchObject({ name: 'AbortError', message: '请求超时' });

            await vi.advanceTimersByTimeAsync(100);
            await assertion;
        } finally {
            vi.useRealTimers();
        }
    });

    it('请求在超时前完成：不 abort、结果正常、超时点过后无副作用', async () => {
        vi.useFakeTimers();
        try {
            let capturedSignal = null;
            const fetchMock = vi.fn(async (_url, options) => {
                capturedSignal = options.signal;
                return mockBlobResponse({ contentDisposition: null });
            });
            setFetch(fetchMock);

            const { filename } = await requestBlob('/characters/1/export', { timeout: 100 });

            expect(filename).toBeNull();
            expect(capturedSignal.aborted).toBe(false);
            await vi.advanceTimersByTimeAsync(200);
            expect(capturedSignal.aborted).toBe(false);
        } finally {
            vi.useRealTimers();
        }
    });

    it('request() 同样支持 timeout：超时抛 AbortError', async () => {
        vi.useFakeTimers();
        try {
            const fetchMock = vi.fn(
                (_url, options) =>
                    new Promise((_resolve, reject) => {
                        options.signal.addEventListener('abort', () => {
                            const err = new Error('This operation was aborted');
                            err.name = 'AbortError';
                            reject(err);
                        });
                    })
            );
            setFetch(fetchMock);

            const pending = request('GET', '/characters', null, { timeout: 50 });
            const assertion = expect(pending).rejects.toMatchObject({ name: 'AbortError', message: '请求超时' });

        await vi.advanceTimersByTimeAsync(50);
        await assertion;
    } finally {
        vi.useRealTimers();
    }
});

describe('downloadBlob 薄包装', () => {
    afterEach(() => {
        setFetch(null);
    });

    it('委托 requestBlob 走 seam；服务端 filename* 优先于入参 filename', async () => {
        const fetchMock = vi.fn(async () =>
            mockBlobResponse({
                contentDisposition: 'attachment; filename="fallback.json"; filename*=UTF-8\'\'%E5%B0%8F%E7%BA%A2.json',
            })
        );
        setFetch(fetchMock);

        const createObjectURL = vi.fn(() => 'blob:mock');
        const revokeObjectURL = vi.fn();
        const originalCreate = URL.createObjectURL;
        const originalRevoke = URL.revokeObjectURL;
        URL.createObjectURL = createObjectURL;
        URL.revokeObjectURL = revokeObjectURL;
        const createElementSpy = vi.spyOn(document, 'createElement');
        try {
            await downloadBlob('/api/characters/1/export', '本地兜底.json');

            // 旧式 '/api' 前缀 URL 原样交给 seam（requestBlob 归一化后仍请求同一地址）
            expect(fetchMock).toHaveBeenCalledWith('/api/characters/1/export', expect.objectContaining({ method: 'GET' }));
            expect(createObjectURL).toHaveBeenCalledTimes(1);
            const anchor = createElementSpy.mock.results.map((r) => r.value).find((el) => el.tagName === 'A');
            expect(anchor.download).toBe('小红.json');
            expect(revokeObjectURL).toHaveBeenCalledWith('blob:mock');
        } finally {
            URL.createObjectURL = originalCreate;
            URL.revokeObjectURL = originalRevoke;
            createElementSpy.mockRestore();
        }
    });

    it('失败路径保持：非 2xx 时 showToast 提示而非抛错', async () => {
        const fetchMock = vi.fn(async () => mockBlobResponse({ ok: false, status: 404, detail: '对话不存在' }));
        setFetch(fetchMock);
        const toastSpy = vi.spyOn(document, 'createElement');
        try {
            await downloadBlob('/api/conversations/999/export/json', 'conv.json');
            const toast = toastSpy.mock.results.map((r) => r.value).find((el) => el.className?.startsWith('toast toast-error'));
            expect(toast).toBeTruthy();
            expect(toast.textContent).toBe('导出失败: 对话不存在');
        } finally {
            toastSpy.mockRestore();
        }
    });
});
});
