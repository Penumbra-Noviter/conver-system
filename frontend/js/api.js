/**
 * Conver System — 统一 API 调用层
 *
 * 封装 fetch，统一处理：
 *   - 请求/响应 JSON 序列化
 *   - 错误处理
 *   - 请求头设置
 */

const API_BASE = '/api';

/**
 * 通用请求函数
 * @param {string} method - HTTP 方法
 * @param {string} path - API 路径（例如 /characters）
 * @param {object|null} body - 请求体（可选）
 * @returns {Promise<any>} 解析后的 JSON 响应
 */
async function request(method, path, body = null) {
    const url = `${API_BASE}${path}`;
    const options = {
        method,
        headers: { 'Content-Type': 'application/json' },
    };

    if (body !== null) {
        options.body = JSON.stringify(body);
    }

    const res = await fetch(url, options);

    // 204 No Content
    if (res.status === 204) {
        return null;
    }

    const data = await res.json();

    if (!res.ok) {
        const msg = data.detail || `请求失败 (${res.status})`;
        throw new Error(msg);
    }

    return data;
}

// ══════════════════════════════════════════════════
// 角色 API
// ══════════════════════════════════════════════════

export const characters = {
    list: () => request('GET', '/characters'),
    get: (id) => request('GET', `/characters/${id}`),
    create: (data) => request('POST', '/characters', data),
    update: (id, data) => request('PUT', `/characters/${id}`, data),
    delete: (id) => request('DELETE', `/characters/${id}`),
    /** 从 SillyTavern V2 角色卡 JSON 导入角色（V2 信封 / 裸 data / V1 旧卡均可） */
    import: (card) => request('POST', '/characters/import', card),
};

// ══════════════════════════════════════════════════
// 对话 API
// ══════════════════════════════════════════════════

export const conversations = {
    list: (characterId) => {
        const query = characterId ? `?character_id=${characterId}` : '';
        return request('GET', `/conversations${query}`);
    },
    get: (id) => request('GET', `/conversations/${id}`),
    create: (data) => request('POST', '/conversations', data),
    update: (id, data) => request('PUT', `/conversations/${id}`, data),
    delete: (id) => request('DELETE', `/conversations/${id}`),
    deleteAll: () => request('DELETE', '/conversations'),
};

// ══════════════════════════════════════════════════
// 消息 & 聊天 API
// ══════════════════════════════════════════════════

export const messages = {
    list: (conversationId) => request('GET', `/conversations/${conversationId}/messages`),
    chat: (data) => request('POST', '/chats', data),
    search: (q, limit = 50) => request('GET', `/messages/search?q=${encodeURIComponent(q)}&limit=${limit}`),
};

/**
 * 流式聊天 — 通过 fetch + ReadableStream 逐 token 消费
 *
 * 内部创建 AbortController，返回 { abort, done }：
 *   - abort(): 中止请求（客户端停止生成）→ fetch 以 AbortError 中断，后端感知断开并保存部分内容
 *   - done: Promise<void>，await 等待整条流消费完成
 *
 * @param {object} data - { conversation_id, content }
 * @param {object} callbacks
 * @param {function} callbacks.onToken - 每个 token 的回调 (token: string) => void
 * @param {function} callbacks.onDone - 完成回调 (messageId: number|null) => void
 * @param {function} callbacks.onError - 错误/中止回调 (error: Error) => void
 * @returns {{abort: () => void, done: Promise<void>}}
 */
export function chatStream(data, { onToken, onDone, onError }) {
    const controller = new AbortController();

    const done = (async () => {
        try {
            const res = await fetch(`${API_BASE}/chats/stream`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data),
                signal: controller.signal,
            });

            if (!res.ok) {
                const err = await res.json().catch(() => ({ detail: '流式请求失败' }));
                throw new Error(err.detail || `HTTP ${res.status}`);
            }

            const reader = res.body.getReader();
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
            if (!completed) {
                if (onDone) onDone(null);
            }
        } catch (err) {
            onError(err);
        }
    })();

    return { abort: () => controller.abort(), done };
}

// ══════════════════════════════════════════════════
// 模型 API
// ══════════════════════════════════════════════════

export const models = {
    list: () => request('GET', '/models'),
};

// ══════════════════════════════════════════════════
// 设置 API
// ══════════════════════════════════════════════════

export const settings = {
    get: () => request('GET', '/settings'),
    update: (data) => request('PUT', '/settings', data),
    /** 测试指定 Provider 的 API Key 连接（P4.3）；失败时后端返回 400 及原因 */
    testConnection: (data) => request('POST', '/settings/test-connection', data),
};
