import { describe, it, expect } from 'vitest';
import { highlightText, buildMessagesHtml, assistantAvatarHtml, userAvatarHtml, characterCardHtml, conversationItemHtml, searchResultItemHtml } from '../js/format.js';

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

// ══════════════════════════════════════════════════
// 视图渲染模板纯函数（ARC-6 从 app.js 迁移）
// ══════════════════════════════════════════════════

describe('characterCardHtml', () => {
    const char = {
        id: 1, name: '测试角色', description: '简介', first_mes: '你好',
        tags: ['甲', '乙'], temperature: 0.9, conversation_count: 3,
    };

    it('渲染卡片结构:头像/名称/简介/开场白/标签/元数据/4 操作按钮', () => {
        const html = characterCardHtml(char);
        expect(html).toContain('character-card" data-id="1"');
        expect(html).toContain('测试角色');
        expect(html).toContain('简介');
        expect(html).toContain('开场白:');
        expect(html).toContain('标签:');
        expect(html).toContain('data-icon="temperature"');
        expect(html).toContain('0.9');
        expect(html).toContain('data-icon="messages"');
        expect(html).toContain('3');
        expect(html).toContain('chat-with');
        expect(html).toContain('edit-char');
        expect(html).toContain('export-char');
        expect(html).toContain('delete-char');
    });

    it('转义用户内容:名称含 < 不注入 HTML', () => {
        const html = characterCardHtml({ id: 2, name: '<script>', description: 'x', first_mes: 'y', temperature: 0.7, conversation_count: 0 });
        expect(html).not.toContain('<script>');
        expect(html).toContain('&lt;script&gt;');
    });

    it('缺省字段安全:无开场白/标签/温度 → 不渲染对应区块,温度回退 0.7', () => {
        const html = characterCardHtml({ id: 3, name: '精简', temperature: undefined, conversation_count: undefined });
        expect(html).not.toContain('开场白');
        expect(html).not.toContain('标签');
        expect(html).toContain('data-icon="temperature"');
        expect(html).toContain('0.7');
        expect(html).toContain('data-icon="messages"');
        expect(html).toContain('0');
    });
});

describe('conversationItemHtml', () => {
    const conv = { id: 10, title: '对话A', message_count: 5, model_name: 'deepseek-v4-flash' };

    it('渲染标题/消息数/模型,activeId 匹配时高亮', () => {
        const html = conversationItemHtml(conv, { activeId: 10 });
        expect(html).toContain('conversation-item active"');
        expect(html).toContain('data-id="10"');
        expect(html).toContain('对话A');
        expect(html).toContain('5 条消息 · deepseek-v4-flash');
    });

    it('activeId 不匹配不高亮;model_name 缺省回退 provider', () => {
        expect(conversationItemHtml(conv, { activeId: 99 })).toContain('conversation-item "');
        expect(conversationItemHtml(conv, { activeId: 99 })).toContain('data-id="10"');
        expect(conversationItemHtml({ id: 1, title: 't', message_count: 0, model_provider: 'openai' })).toContain('0 条消息 · openai');
    });
});

describe('searchResultItemHtml', () => {
    it('user 消息角色标签使用 user 图标；assistant 使用 character 图标', () => {
        const userHtml = searchResultItemHtml({ role: 'user', character_name: 'X', conversation_id: 1, message_id: 1, content_preview: 'hello', conversation_title: 'C' }, '');
        expect(userHtml).toContain('data-icon="user"');
        expect(userHtml).toContain('你');
        const asstHtml = searchResultItemHtml({ role: 'assistant', character_name: 'AI', conversation_id: 1, message_id: 2, content_preview: 'hi', conversation_title: 'C' }, '');
        expect(asstHtml).toContain('data-icon="character"');
        expect(asstHtml).toContain('AI');
        expect(asstHtml).toContain('data-icon="messages"');
    });

    it('关键词高亮包 <mark>;对话标题缺省「未命名对话」', () => {
        const html = searchResultItemHtml({ role: 'user', conversation_id: 1, message_id: 1, content_preview: '找到关键词了', conversation_title: undefined }, '关键词');
        expect(html).toContain('<mark class="search-highlight">关键词</mark>');
        expect(html).toContain('未命名对话');
        expect(html).toContain('data-conversation-id="1"');
    });
});
