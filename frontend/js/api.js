/**
 * Conver System — 统一 API 调用层
 *
 * 封装 fetch，统一处理：
 *   - 请求/响应 JSON 序列化
 *   - 错误处理
 *   - 请求头设置
 */

const API_BASE = '/api';

import { parseSSEStream } from './utils/sse-reader.js';

// ── fetch seam ──
// 允许测试注入自定义 fetch 实现；浏览器环境默认使用全局 fetch。
let fetchImpl = null;

/**
 * 注入自定义 fetch 实现（测试用，避免真实网络）。传 null/非函数恢复默认全局 fetch。
 * @param {Function|null} fn - fetch 兼容函数 (url, options) => Promise<Response>
 */
export function setFetch(fn) {
    fetchImpl = typeof fn === 'function' ? fn : null;
}

function doFetch(...args) {
    return (fetchImpl ?? globalThis.fetch)(...args);
}

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

    const res = await doFetch(url, options);

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
    /** 使用 LLM 从文档中提取角色卡字段 */
    parseDocument: (data) => request('POST', '/characters/parse-document', data),
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
            const res = await doFetch(`${API_BASE}/chats/stream`, {
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

            await parseSSEStream(reader, { onToken, onDone, onError });
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
