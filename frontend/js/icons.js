/**
 * Conver System — 本地 SVG 图标工厂
 *
 * 图形优先复用项目既有的 currentColor 线框图标；补充图形按
 * Lucide Icons 风格（https://lucide.dev，ISC License）绘制。
 */

const ICON_PATHS = {
    chat: '<path d="M3 4.5A1.5 1.5 0 014.5 3h7A1.5 1.5 0 0113 4.5v4A1.5 1.5 0 0111.5 10H8l-3 2v-2H4.5A1.5 1.5 0 013 8.5v-4z"/><path d="M6 6.5h4"/>',
    user: '<circle cx="8" cy="5.5" r="3"/><path d="M2.5 14c0-3 2.5-5 5.5-5s5.5 2 5.5 5"/>',
    character: '<path d="M5 3.5h6v9H5z"/><path d="M6.5 6h3M6.5 8.5h3M7 12h2"/><path d="M4 5H2.5v9H10"/>',
    search: '<circle cx="7" cy="7" r="4.5"/><path d="M11 11l3.5 3.5"/>',
    settings: '<circle cx="8" cy="8" r="2.5"/><path d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M3.4 12.6l1.4-1.4M11.2 4.8l1.4-1.4"/>',
    send: '<path d="M2 8L14 2l-4 12-3-5-5-1Z" fill="currentColor"/><path d="M7 9 14 2"/>',
    stop: '<rect x="4" y="4" width="8" height="8" rx="1" fill="currentColor"/>',
    clipboard: '<rect x="4" y="3" width="8" height="10" rx="1"/><path d="M6 3V2.5A1.5 1.5 0 017.5 1h1A1.5 1.5 0 0110 2.5V3"/>',
    check: '<path d="m3 8 3 3 7-7"/>',
    x: '<path d="m3 3 10 10M13 3 3 13"/>',
    edit: '<path d="M11.4 2.6a1.7 1.7 0 012.4 2.4L7.5 11.3 4 12l.7-3.5 6.7-5.9z"/>',
    export: '<path d="M13.5 10v3.5a1 1 0 01-1 1h-9a1 1 0 01-1-1V10"/><path d="M8 9.5v-7M5.5 5 8 2.5 10.5 5"/>',
    download: '<path d="M8 2v8M5 7l3 3 3-3M2.5 12v1h11v-1"/>',
    trash: '<path d="M2.5 4.5h11M12.7 4.5v9.3a1.3 1.3 0 01-1.3 1.3H4.6a1.3 1.3 0 01-1.3-1.3V4.5M6.6 4.5V3.4a.9.9 0 01.9-.9h1a.9.9 0 01.9.9v1.1M6.6 7.5v4M9.4 7.5v4"/>',
    temperature: '<path d="M7 3v6.2a2.5 2.5 0 102 0V3a1 1 0 10-2 0Z"/><path d="M8 6v4"/>',
    messages: '<path d="M3 4a2 2 0 012-2h8a2 2 0 012 2v6a2 2 0 01-2 2H7l-4 3V4Z"/><path d="M6 6h6M6 8.5h4"/>',
    menu: '<path d="M2 4h12M2 8h12M2 12h12"/>',
    chevronLeft: '<path d="m9.5 3-4 5 4 5"/>',
    chevronRight: '<path d="m6.5 3 4 5-4 5"/>',
    sun: '<circle cx="8" cy="8" r="3"/><path d="M8 1v2M8 13v2M1 8h2M13 8h2M3 3l1.5 1.5M11.5 11.5 13 13M3 13l1.5-1.5M11.5 4.5 13 3"/>',
    moon: '<path d="M12.5 10.5A5.5 5.5 0 015.5 3a5.5 5.5 0 107 7.5Z"/>',
    fileText: '<path d="M4 2h6l3 3v9H4z"/><path d="M10 2v3h3M6 8h4M6 10.5h4"/>',
    fileJson: '<path d="M6 3H4.5A1.5 1.5 0 003 4.5v7A1.5 1.5 0 004.5 13H6M10 3h1.5A1.5 1.5 0 0113 4.5v7a1.5 1.5 0 01-1.5 1.5H10M7 5.5 5.5 8 7 10.5M9 5.5 10.5 8 9 10.5"/>',
    warning: '<path d="M8 2 14 13H2L8 2Z"/><path d="M8 6v3M8 11.25v.01"/>',
    info: '<circle cx="8" cy="8" r="6"/><path d="M8 7v4M8 4.75v.01"/>',
    sparkles: '<path d="m8 1 .8 3.2L12 5l-3.2.8L8 9l-.8-3.2L4 5l3.2-.8L8 1ZM12.5 10l.4 1.6 1.6.4-1.6.4-.4 1.6-.4-1.6-1.6-.4 1.6-.4.4-1.6ZM3 10l.5 2 .5-2 2-.5-2-.5-.5-2-.5 2-2 .5 2 .5Z"/>',
    gamepad: '<rect x="1.5" y="5" width="13" height="6" rx="2.5"/><path d="M5 6.75v2.5M3.75 8h2.5"/><path d="M10.5 7.25v.01M10.5 9v.01"/>',
};

/**
 * 构造本地、装饰性的 SVG 图标 HTML。
 *
 * @param {string} name - 已注册的图标名称。
 * @param {{size?: number, className?: string}} [options={}] - 尺寸与附加 CSS 类。
 * @returns {string} 含 data-icon 和 aria-hidden 的 SVG HTML。
 * @throws {Error} 图标名称未注册时抛出明确错误。
 */
export function iconHtml(name, options = {}) {
    if (!Object.hasOwn(ICON_PATHS, name)) throw new Error(`未知图标: ${name}`);
    if (options === null || typeof options !== 'object' || Array.isArray(options)) {
        throw new Error('图标选项必须是对象');
    }

    const { size = 16, className = '' } = options;
    if (typeof size !== 'number' || !Number.isFinite(size) || size < 1 || size > 128) {
        throw new Error('图标尺寸必须是 1 到 128 的有限数字');
    }
    if (typeof className !== 'string' || !/^[-_a-zA-Z0-9 ]*$/.test(className)) {
        throw new Error('图标类名只能包含 CSS 标识符');
    }

    const classes = className ? ` class="${className}"` : '';
    return `<svg${classes} width="${size}" height="${size}" viewBox="0 0 16 16" fill="none" aria-hidden="true" data-icon="${name}" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${ICON_PATHS[name]}</svg>`;
}

export const __all__ = ['iconHtml'];
