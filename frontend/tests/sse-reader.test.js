import { describe, it, expect, vi } from 'vitest';
import { parseSSEStream } from '../js/utils/sse-reader.js';

/**
 * 构造一个模拟 ReadableStream reader，逐块产出字节。
 * @param {Array<Uint8Array|string>} chunks - 各块（string 会按 UTF-8 编码）
 */
function makeReader(chunks) {
    const bytes = chunks.map(c =>
        typeof c === 'string' ? new TextEncoder().encode(c) : c,
    );
    let i = 0;
    return {
        async read() {
            if (i < bytes.length) return { done: false, value: bytes[i++] };
            return { done: true, value: undefined };
        },
    };
}

describe('parseSSEStream', () => {
    it('解析 token / done 事件并回调', async () => {
        const onToken = vi.fn();
        const onDone = vi.fn();
        const reader = makeReader([
            'data: {"type":"token","content":"你"}\n',
            'data: {"type":"token","content":"好"}\n',
            'data: {"type":"done","message_id":42}\n\n',
        ]);
        const completed = await parseSSEStream(reader, { onToken, onDone });
        expect(completed).toBe(true);
        expect(onToken).toHaveBeenCalledTimes(2);
        expect(onToken).toHaveBeenNthCalledWith(1, '你');
        expect(onToken).toHaveBeenNthCalledWith(2, '好');
        expect(onDone).toHaveBeenCalledWith(42);
    });

    it('跨 chunk 边界拼接 buffer（分块到达的半行）', async () => {
        const onToken = vi.fn();
        const onDone = vi.fn();
        // 第一块：data 前缀 + JSON 一半；第二块：JSON 剩余（含闭合引号与大括号）
        const reader = makeReader([
            'data: {"type":"token","content":"',
            '半个"}\ndata: {"type":"done","message_id":7}\n\n',
        ]);
        const completed = await parseSSEStream(reader, { onToken, onDone });
        expect(completed).toBe(true);
        expect(onToken).toHaveBeenCalledWith('半个');
        expect(onDone).toHaveBeenCalledWith(7);
    });

    it('error 事件回调 onError，流中断（无 done）时回调 onDone(null)', async () => {
        const onError = vi.fn();
        const onDone = vi.fn();
        const reader = makeReader([
            'data: {"type":"error","message":"限流"}\n',
            'data: {"type":"token","content":"部分内容"}\n',
        ]);
        const completed = await parseSSEStream(reader, { onToken: () => {}, onDone, onError });
        expect(completed).toBe(false);
        expect(onError).toHaveBeenCalledWith(expect.any(Error));
        expect(onError.mock.calls[0][0].message).toBe('限流');
        // 流结束但未收到 done → onDone(null)（连接中断）
        expect(onDone).toHaveBeenCalledWith(null);
    });

    it('忽略非 data: 行与解析失败的行', async () => {
        const onToken = vi.fn();
        const onDone = vi.fn();
        const reader = makeReader([
            ': comment\n',
            'data: {"type":"token","content":"OK"}\n',
            'data: 这不是合法JSON\n',
            'event: done\n',
            'data: {"type":"done","message_id":1}\n\n',
        ]);
        const completed = await parseSSEStream(reader, { onToken, onDone });
        expect(completed).toBe(true);
        expect(onToken).toHaveBeenCalledTimes(1);
        expect(onToken).toHaveBeenCalledWith('OK');
        expect(onDone).toHaveBeenCalledWith(1);
    });
});
