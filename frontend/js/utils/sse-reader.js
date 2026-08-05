/**
 * Conver System — SSE 流解析器
 *
 * 纯函数：从 ReadableStream 读取字节 → 逐行解析 SSE data: 帧 → 回调。
 * 与 API 调用解耦，可独立于 fetch 进行测试。
 *
 * 协议表面（__all__）：parseSSEStream
 */

/**
 * 从 ReadableStream reader 中逐块读取并解析 SSE data: 帧
 *
 * SSE 格式预期：
 *   data: {"type": "token", "content": "..."}
 *   data: {"type": "done", "message_id": 123}
 *   data: {"type": "error", "message": "..."}
 *
 * @param {ReadableStreamDefaultReader} reader - fetch Response.body.getReader()
 * @param {object} callbacks
 * @param {function} callbacks.onToken - 每个 token 回调 (token: string) => void
 * @param {function} callbacks.onDone - 完成回调 (messageId: number|null) => void
 * @param {function} [callbacks.onError] - 错误回调 (error: Error) => void
 * @returns {Promise<boolean>} 是否收到 done 事件（true=正常完成，false=流中断）
 */
export async function parseSSEStream(reader, { onToken, onDone, onError }) {
    const decoder = new TextDecoder();
    let buffer = '';
    let completed = false;

    while (true) {
        const { done: streamDone, value } = await reader.read();
        if (streamDone) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed.startsWith('data: ')) continue;

            try {
                const parsed = JSON.parse(trimmed.slice(6));
                if (parsed.type === 'token') {
                    onToken(parsed.content);
                } else if (parsed.type === 'done') {
                    completed = true;
                    onDone(parsed.message_id);
                } else if (parsed.type === 'error') {
                    if (onError) onError(new Error(parsed.message));
                }
            } catch {
                // 跳过解析失败的行
            }
        }
    }

    // 流结束但未收到 done 事件（连接中断/异常关闭）
    if (!completed && onDone) {
        onDone(null);
    }

    return completed;
}