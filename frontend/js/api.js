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
import { doFetch } from './fetch-seam.js';

// ── fetch seam（单一来源 js/fetch-seam.js — TD-51/55/60）──
// 允许测试注入自定义 fetch 实现；浏览器环境默认使用全局 fetch。
// 注入/回落契约见 fetch-seam.js（setFetch 与 simulators.js 共享同一注入点）。
export { setFetch } from './fetch-seam.js';

// ── URL 策略（唯一来源：API_BASE + 路径拼接）──
// 兼容调用方传入的旧式 '/api' 前缀（downloadBlob 既有调用点），自动归一化。

/**
 * 拼接 API 完整 URL
 * @param {string} path - API 路径（如 /characters；兼容旧式 '/api' 前缀）
 * @returns {string}
 */
function buildApiUrl(path) {
    const normalized = path.startsWith('/api') ? path.slice('/api'.length) : path;
    return `${API_BASE}${normalized}`;
}

// ── 超时控制（request / requestBlob 共用）──

/**
 * 创建超时控制器（AbortController + setTimeout）；timeout 为空或非正数返回 null（无超时）。
 * 超时触发 → controller.abort() → fetch 以 AbortError 中断。
 * @param {number|undefined} timeout - 超时毫秒数
 * @returns {{controller: AbortController, timer: ReturnType<typeof setTimeout>}|null}
 */
function createTimeoutController(timeout) {
    if (!timeout || timeout <= 0) return null;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    return { controller, timer };
}

/**
 * 归一化超时错误：超时 abort 引发的任何拒绝（含 fetch 原生的 AbortError）统一收敛为
 * 领域 AbortError（name='AbortError'，message='请求超时'）。非超时错误原样返回。
 * @param {unknown} err - 捕获到的错误
 * @param {{controller: AbortController}|null} timeoutCtl - 超时控制器（无超时为 null）
 * @returns {Error}
 */
function normalizeTimeoutError(err, timeoutCtl) {
    if (timeoutCtl?.controller.signal.aborted) {
        const timeoutError = new Error('请求超时');
        timeoutError.name = 'AbortError';
        return timeoutError;
    }
    return err;
}

/**
 * 通用请求函数
 * @param {string} method - HTTP 方法
 * @param {string} path - API 路径（例如 /characters）
 * @param {object|null} body - 请求体（可选）
 * @param {{timeout?: number}} [options] - timeout: 超时毫秒数（默认无超时）
 * @returns {Promise<any>} 解析后的 JSON 响应
 */
export async function request(method, path, body = null, { timeout } = {}) {
    const timeoutCtl = createTimeoutController(timeout);
    try {
        const url = buildApiUrl(path);
        const options = {
            method,
            headers: { 'Content-Type': 'application/json' },
        };

        if (body !== null) {
            options.body = JSON.stringify(body);
        }
        if (timeoutCtl) {
            options.signal = timeoutCtl.controller.signal;
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
    } catch (err) {
        throw normalizeTimeoutError(err, timeoutCtl);
    } finally {
        if (timeoutCtl) clearTimeout(timeoutCtl.timer);
    }
}

/**
 * 从错误响应提取可读错误消息：优先 JSON detail，回退纯文本，再回退状态码。
 * @param {Response} res - 非 2xx 的响应对象
 * @returns {Promise<string>}
 */
async function extractErrorMessage(res) {
    try {
        const data = await res.json();
        if (data && typeof data.detail === 'string') return data.detail;
    } catch {
        // body 非 JSON（如纯文本错误页）
    }
    try {
        const text = await res.text();
        if (text) return text;
    } catch {
        // body 已消费或不可读
    }
    return `请求失败 (${res.status})`;
}

/**
 * 解析 Content-Disposition 文件名（RFC 6266 / RFC 5987）
 *
 * 优先 filename*（UTF-8 百分号编码 — 中文等非 ASCII 文件名走此通道，与后端
 * conversations/characters 导出一致），回退 filename；两者均无返回 null。
 *
 * @param {{get: (name: string) => string|null}|null} headers - 响应头（无 headers 时返回 null）
 * @returns {string|null}
 */
function parseContentDispositionFilename(headers) {
    if (!headers) return null;
    const value = headers.get('content-disposition');
    if (!value) return null;

    // RFC 5987: filename*=UTF-8''<percent-encoded>
    const starMatch = value.match(/filename\*\s*=\s*UTF-8''([^;]+)/i);
    if (starMatch) {
        try {
            return decodeURIComponent(starMatch[1].trim());
        } catch {
            // 非法百分号序列 → 回退 filename
        }
    }

    // RFC 6266: filename="..." 或 filename=...
    const plainMatch = value.match(/filename\s*=\s*"?([^";]*)"?/i);
    return plainMatch ? plainMatch[1].trim() : null;
}

/**
 * Blob 下载请求 — 走 doFetch seam
 *
 * 用于导出类端点（下载 JSON/Markdown）。返回 blob 及服务端 Content-Disposition
 * 文件名；文件名均无则返回 null（由调用方回退本地文件名）。
 *
 * @param {string} path - API 路径（如 /characters/1/export；兼容旧式 '/api' 前缀）
 * @param {{timeout?: number}} [options] - timeout: 超时毫秒数（默认无超时）
 * @returns {Promise<{blob: Blob, filename: string|null}>}
 */
export async function requestBlob(path, { timeout } = {}) {
    const timeoutCtl = createTimeoutController(timeout);
    try {
        const options = { method: 'GET' };
        if (timeoutCtl) {
            options.signal = timeoutCtl.controller.signal;
        }

        const res = await doFetch(buildApiUrl(path), options);

        if (!res.ok) {
            throw new Error(await extractErrorMessage(res));
        }

        const blob = await res.blob();
        return { blob, filename: parseContentDispositionFilename(res.headers) };
    } catch (err) {
        throw normalizeTimeoutError(err, timeoutCtl);
    } finally {
        if (timeoutCtl) clearTimeout(timeoutCtl.timer);
    }
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
    /** 主应用可用的 OpenAI 兼容凭证（只读，U8-T2 运行视图注入用）：
     *  返回 {key, endpoint, model, protocol} — protocol ∈ openai | claude | none */
    credentials: () => request('GET', '/settings/credentials'),
};
