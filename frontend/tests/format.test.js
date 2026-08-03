import { describe, it, expect } from 'vitest';
import { highlightText, buildMessagesHtml, assistantAvatarHtml, userAvatarHtml } from '../js/format.js';

describe('highlightText', () => {
    it('无关键词时原样返回', () => {
        expect(highlightText('hello world', '')).toBe('hello world');
        expect(highlightText('hello world', null)).toBe('hello world');
    });

    it('关键词命中时包 <mark>', () => {
        expect(highlightText('hello world', 'lo w')).toBe(
            'hel<mark class="search-highlight">lo w</mark>orld'
        );
    });

    it('不区分大小写', () => {
        expect(highlightText('Hello WORLD', 'world')).toBe(
            'Hello <mark class="search-highlight">WORLD</mark>'
        );
    });

    it('未命中时原样返回', () => {
        expect(highlightText('hello', 'xyz')).toBe('hello');
    });

    it('空文本返回空', () => {
        expect(highlightText('', 'x')).toBe('');
    });
});

describe('buildMessagesHtml', () => {
    it('空数组返回 empty-state', () => {
        expect(buildMessagesHtml([])).toContain('empty-state');
    });

    it('非数组返回 empty-state', () => {
        expect(buildMessagesHtml(null)).toContain('empty-state');
    });

    it('用户消息内容被转义', () => {
        const html = buildMessagesHtml([{ role: 'user', content: '<script>x</script>' }]);
        expect(html).toContain('<div class="message user">');
        expect(html).not.toContain('<script>');
        expect(html).toContain('&lt;script&gt;');
        expect(html).toContain('class="msg-avatar user-avatar"');
    });

    it('助手消息渲染 Markdown 并带头像', () => {
        const html = buildMessagesHtml(
            [{ role: 'assistant', content: 'Hello **world**' }],
            { characters: [{ id: 1, name: '测试角色' }], currentCharacterId: 1 }
        );
        expect(html).toContain('<div class="message assistant">');
        expect(html).toContain('<strong>world</strong>');
        expect(html).toContain('avatar-placeholder-xs');
    });

    it('助手消息带角色头像 img', () => {
        const html = buildMessagesHtml(
            [{ role: 'assistant', content: 'hi' }],
            { characters: [{ id: 1, name: 'A', avatar: 'http://x/a.png' }], currentCharacterId: 1 }
        );
        expect(html).toContain('<img src="http://x/a.png"');
    });

    it('复制按钮 data-content 转义', () => {
        const html = buildMessagesHtml([{ role: 'user', content: 'a & b' }]);
        expect(html).toContain('data-content="a &amp; b"');
    });
});

describe('assistantAvatarHtml', () => {
    it('有头像时输出 img', () => {
        const html = assistantAvatarHtml([{ id: 1, name: 'A', avatar: 'http://x/y.png' }], 1);
        expect(html).toContain('<img src="http://x/y.png"');
    });

    it('无头像时输出占位符', () => {
        const html = assistantAvatarHtml([{ id: 1, name: 'Alice' }], 1);
        expect(html).toContain('avatar-placeholder-xs');
        expect(html).toContain('AL');
    });

    it('无匹配角色时回退 AI', () => {
        const html = assistantAvatarHtml([], 99);
        expect(html).toContain('avatar-placeholder-xs');
        expect(html).toContain('AI');
    });
});

describe('userAvatarHtml', () => {
    it('输出用户头像 div', () => {
        expect(userAvatarHtml()).toContain('msg-avatar user-avatar');
    });
});
