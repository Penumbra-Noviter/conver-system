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
// 世界书 API（WL-4：条目 CRUD，挂在角色下）
// ══════════════════════════════════════════════════

export const lorebook = {
    /** 角色世界书条目列表（order 升序） */
    list: (characterId) => request('GET', `/characters/${characterId}/lorebook`),
    /** 创建条目 */
    create: (characterId, data) => request('POST', `/characters/${characterId}/lorebook`, data),
    /** 部分更新条目 */
    update: (entryId, data) => request('PUT', `/lorebook/${entryId}`, data),
    /** 删除条目 */
    delete: (entryId) => request('DELETE', `/lorebook/${entryId}`),
};

// ══════════════════════════════════════════════════
// Mod API（MD-2/03：库 CRUD + 角色挂载 CRUD）
// ══════════════════════════════════════════════════

export const mods = {
    /** 全局 Mod 库列表（id 升序） */
    list: () => request('GET', '/mods'),
    /** 创建 Mod */
    create: (data) => request('POST', '/mods', data),
    /** 部分更新 Mod */
    update: (modId, data) => request('PUT', `/mods/${modId}`, data),
    /** 删除 Mod */
    delete: (modId) => request('DELETE', `/mods/${modId}`),
    /** 角色挂载列表（sort_order 升序） */
    listCharacterMods: (characterId) => request('GET', `/characters/${characterId}/mods`),
    /** 挂载 Mod 到角色（body {mod_id, enabled?, sort_order?}） */
    bind: (characterId, data) => request('POST', `/characters/${characterId}/mods`, data),
    /** 切换挂载开关（body {enabled}） */
    setEnabled: (bindingId, enabled) => request('PUT', `/mod-bindings/${bindingId}`, { enabled }),
    /**
     * 原子批量重排角色挂载顺序（F-102：body = [binding_id...] 按新序；工单 04 消费）
     * @param {number|string} characterId - 角色 id
     * @param {Array<number>} orderedIds - 移动后的完整 binding_id 顺序数组
     * @returns {Promise<Array>} 重排后的挂载列表（sort_order 升序）
     */
    reorder: (characterId, orderedIds) => request('PUT', `/characters/${characterId}/mods/order`, orderedIds),
    /** 解绑 */
    unbind: (bindingId) => request('DELETE', `/mod-bindings/${bindingId}`),
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
    /**
     * 重生成对话中目标 AI 回复（缺省末条 assistant — T6 MVP 非流式）
     *
     * POST /api/conversations/{id}/regenerate；响应与既有非流式 ChatResponse 同构
     * `{ reply, message_id, conversation_id }`，其中 message_id 为服务端**新消息**
     * 的 id —— 调用方写 tab 缓存 / 结算时必须用该 id 替换占位条目（W2 增量审核）。
     * 客户端错误处理与 `messages.chat` 同走 `request` 错误通道（catch 后由聊天域
     * 统一渲染错误条，不各自为政）。
     *
     * @param {number|string} id - 会话 id
     * @param {object} [opts]
     * @param {number|string|null} [opts.message_id] - 目标 assistant 消息 id（缺省 =
     *   末条 AI 回复；不传时后端按 None 处理，请求体不携带）
     * @returns {Promise<{reply: string, message_id: number, conversation_id: number}>}
     */
    regenerate: (id, { message_id } = {}) => request(
        'POST',
        `/conversations/${id}/regenerate`,
        message_id != null ? { message_id } : null,
    ),
    /**
     * 续写末条 AI 回复（MS-3 append 续写：不追加 user，原消息扩展为「原内容 + 续写片段」）
     *
     * POST /api/conversations/{id}/continue；无请求体（续写目标恒为末条 assistant）。
     * 响应与既有非流式 ChatResponse 同构 `{ reply, message_id, conversation_id }`，
     * 其中 message_id = **被续写的消息**（消息 id 不变，内容扩展）——调用方经
     * settleTurn 重载服务端列表获得扩展内容。
     *
     * @param {number|string} id - 会话 id
     * @returns {Promise<{reply: string, message_id: number, conversation_id: number}>}
     */
    continue: (id) => request('POST', `/conversations/${id}/continue`, null),
    /**
     * 从锚消息派生分支会话（F-100 能力 1：POST /api/conversations/{id}/branch）
     *
     * 以源会话的锚消息（message_id）为快照末条派生一条新分支会话（BR-2 消费）。
     * 响应为 201 ConversationResponse（含新会话 `id`/`character_id`/`title`）——调用方
     * 据此「刷新会话列表 + 激活新分支会话」（创建即打开，对齐 startChatWithCharacter）。
     * 客户端错误处理与 messages.chat / regenerate / continue 同走 `request` 错误通道
     * （catch 后由聊天域统一渲染错误条，不各自为政）。
     *
     * @param {number|string} id - 源会话 id
     * @param {object} [opts]
     * @param {number|string} opts.message_id - 分叉锚消息 id（末条 assistant id）
     * @param {string} [opts.title] - 分支显示名（缺省 = 源会话标题；不传时不携带）
     * @returns {Promise<{id: number, character_id: number, title: string}>}
     */
    branch: (id, { message_id, title } = {}) => request(
        'POST',
        `/conversations/${id}/branch`,
        { message_id, ...(title != null ? { title } : {}) },
    ),
    /**
     * 读取最终组装后的 prompt 分段（只读调试，PD-4）。
     * GET /conversations/{id}/prompt-debug；响应含 conversation_id/character_name/
     * model/prompt_mode/segments（{role, content, source}）。
     * @param {number|string} id - 会话 id
     * @returns {Promise<object>} prompt-debug 响应
     */
    promptDebug: (id) => request('GET', `/conversations/${id}/prompt-debug`),
};

// ══════════════════════════════════════════════════
// 消息 & 聊天 API
// ══════════════════════════════════════════════════

export const messages = {
    list: (conversationId) => request('GET', `/conversations/${conversationId}/messages`),
    chat: (data) => request('POST', '/chats', data),
    search: (q, limit = 50) => request('GET', `/messages/search?q=${encodeURIComponent(q)}&limit=${limit}`),
    /** 切换消息激活候选（MS-2：body {index}；越界 → 400） */
    switchSwipe: (messageId, index) => request('POST', `/messages/${messageId}/switch-swipe`, { index }),
    /**
     * 编辑重发（仅 user 消息级操作）：就地替换 content + 物理截断后续 + 重新生成回复。
     * PUT /api/messages/{id} body {content}；响应与非流式 ChatResponse 同构。
     * @param {number|string} messageId - 目标 user 消息 id
     * @param {string} content - 编辑后的新内容
     * @returns {Promise<{reply: string, message_id: number, conversation_id: number}>}
     */
    edit: (messageId, content) => request('PUT', `/messages/${messageId}`, { content }),
    /**
     * 删除单条消息（user/assistant）：角色感知截断。DELETE /api/messages/{id}；
     * 204 → null（无响应体）。
     * @param {number|string} messageId - 目标消息 id
     * @returns {Promise<null>}
     */
    delete: (messageId) => request('DELETE', `/messages/${messageId}`),
};

// ══════════════════════════════════════════════════
// 图片出图 & CG 回顾 API（CG-3）
// ══════════════════════════════════════════════════

export const images = {
    /**
     * 提交图片生成任务（对话内出图）——POST /api/images/tasks
     * @param {object} data - { conversation_id, prompt, negative_prompt?, width?, height?, provider?, message_id? }
     * @returns {Promise<{id: number, conversation_id: number, status: string, ...}>}
     */
    submitTask: (data) => request('POST', '/images/tasks', data),
    /**
     * 轮询任务状态——GET /api/images/tasks/{id}
     * @returns {Promise<{id, status: 'pending'|'running'|'succeeded'|'failed', result_url?, error?}>}
     */
    getTask: (id) => request('GET', `/images/tasks/${id}`),
    /**
     * 剧情回顾时间线——GET /api/characters/{id}/cg-timeline
     * @returns {Promise<Array<{cg_id, url, group_name, message_content, message_created_at}>>}
     */
    cgTimeline: (characterId) => request('GET', `/characters/${characterId}/cg-timeline`),
    /**
     * 角色全量 CG 列表（T2/T5：画廊网格数据通道，id 降序、全量含未解锁）
     * @param {number|string} characterId - 角色 id
     * @returns {Promise<Array<{id, character_id, url, group_name, weight, unlock_hint, is_special, unlocked, created_at}>>}
     */
    list: (characterId) => request('GET', `/characters/${characterId}/cg`),
    /**
     * 手工录入 CG（T2/T5：画廊「录入 CG」表单数据通道）——POST /api/characters/{id}/cg
     * 初始默认锁定：不收 unlocked 字段，服务层默认恒 unlocked=False。
     * @param {number|string} characterId - 角色 id
     * @param {object} data - { url, group_name?, weight?, unlock_hint?, is_special? }
     * @returns {Promise<{id, character_id, url, group_name, weight, unlock_hint, is_special, unlocked, created_at}>}
     */
    create: (characterId, data) => request('POST', `/characters/${characterId}/cg`, data),
    /**
     * 解锁 CG（T2/T5：画廊锁定态点击数据通道，幂等复用）——POST /api/cg/{id}/unlock
     * @param {number|string} cgId - CG id
     * @returns {Promise<{id, character_id, url, group_name, weight, unlock_hint, is_special, unlocked, created_at}>}
     */
    unlock: (cgId) => request('POST', `/cg/${cgId}/unlock`),
    /**
     * 生图能力门控（MD-3）——GET /api/images/available
     * @returns {Promise<{available: boolean}>}
     */
    available: () => request('GET', '/images/available'),
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

// ══════════════════════════════════════════════════
// 协议表面收口
// ══════════════════════════════════════════════════

export const __all__ = [
    'setFetch',
    'request',
    'requestBlob',
    'characters',
    'conversations',
    'lorebook',
    'mods',
    'messages',
    'chatStream',
    'models',
    'settings',
    'images',
];
