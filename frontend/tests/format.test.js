import { describe, it, expect } from 'vitest';
import { highlightText, buildMessagesHtml, messageBubbleHtml, assistantAvatarHtml, userAvatarHtml, characterCardHtml, conversationItemHtml, searchResultItemHtml, avatarImgHtml } from '../js/format.js';

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

describe('messageBubbleHtml — 参数化气泡工厂（F1 三路径统一）', () => {
    it('user 变体：用户头像 + 转义内容 + 复制按钮', () => {
        const html = messageBubbleHtml('user', '<script>x</script>');
        expect(html).toContain('<div class="message user">');
        expect(html).toContain('msg-avatar user-avatar');
        expect(html).toContain('&lt;script&gt;');
        expect(html).not.toContain('<script>');
        expect(html).toContain('btn-copy-message');
        // FE-1：复制内容不进 HTML 属性（数据通道单一化 — 由调用方经 dataset 赋值）
        expect(html).not.toContain('data-content');
    });

    it('assistant 变体：角色头像 + Markdown 渲染 + 复制按钮', () => {
        const html = messageBubbleHtml('assistant', 'Hello **world**', {
            characters: [{ id: 1, name: '测试角色' }], currentCharacterId: 1,
        });
        expect(html).toContain('<div class="message assistant">');
        expect(html).toContain('avatar-placeholder-xs');
        expect(html).toContain('<strong>world</strong>');
        expect(html).toContain('btn-copy-message');
    });

    it('system 变体：无头像 + 无复制按钮（产品微调 F1 — 与其他 system 形态一致）', () => {
        const html = messageBubbleHtml('system', '发送失败: x');
        expect(html).toContain('<div class="message system">');
        expect(html).not.toContain('msg-avatar');
        expect(html).not.toContain('btn-copy-message');
        expect(html).toContain('发送失败: x');
    });

    it('streaming 变体：data-streaming-live 标记（onToken 复用定位）', () => {
        const html = messageBubbleHtml('assistant', '部分', { streaming: true });
        expect(html).toContain('data-streaming-live="1"');
    });

    it('非 streaming 变体无 data-streaming-live', () => {
        expect(messageBubbleHtml('assistant', 'x')).not.toContain('data-streaming-live');
    });

    it('stopped 变体：追加「（已停止）」标记（用户主动停止语义）', () => {
        const html = messageBubbleHtml('assistant', '内容', { stopped: true });
        expect(html).toContain('message-stop-tag');
        expect(html).toContain('（已停止）');
    });

    it('error 变体：追加 message-error 类', () => {
        const html = messageBubbleHtml('assistant', '[错误] x', { error: true });
        expect(html).toContain('class="message assistant message-error"');
    });

    it('复制按钮不含 data-content 属性（复制内容由调用方经 dataset.content 补写 — FE-1）', () => {
        const html = messageBubbleHtml('user', 'a & b');
        expect(html).toContain('btn-copy-message');
        expect(html).not.toContain('data-content');
    });

    // ── FE-1 复制数据通道单一化（防复发回归断言）──
    // 旧实现：escapeHtml 基于 textContent→innerHTML，文本节点双引号不实体化，
    // 嵌入 data-content="…" 属性后解析即在首个引号处截断（复制数据损坏）。
    // 修复：气泡 HTML 不再携带复制内容（由调用方经 btn.dataset.content 赋值）。
    it('FE-1 复制内容不再嵌入 HTML 属性：内容含双引号解析后 data-content 不存在（不截断）', () => {
        const container = document.createElement('div');
        container.innerHTML = messageBubbleHtml('user', '他说 "你好" 和 "再见"');
        const btn = container.querySelector('.btn-copy-message');
        expect(btn.getAttribute('data-content')).toBeNull();
        // 无对应属性时 dataset.content 为 undefined（attachCopyButton 读时以 ?? '' 兜底）
        expect(btn.dataset.content).toBeUndefined();
    });

    it('FE-1 属性注入面关闭：内容含 hi" onclick="alert(2) 不产生 onclick 属性', () => {
        const container = document.createElement('div');
        container.innerHTML = messageBubbleHtml('user', 'hi" onclick="alert(2)');
        const btn = container.querySelector('.btn-copy-message');
        expect(btn.hasAttribute('onclick')).toBe(false);
    });

    // ── T2 搜索定位：data-message-id 渲染 ──

    it('messageId 选项 → 外层 div 含 data-message-id 属性', () => {
        const html = messageBubbleHtml('user', 'hello', { messageId: 42 });
        expect(html).toContain('data-message-id="42"');
    });

    it('messageId 未提供 → 外层 div 无 data-message-id', () => {
        const html = messageBubbleHtml('user', 'hello');
        expect(html).not.toContain('data-message-id');
    });

    it('messageId=0 → data-message-id="0"（0 为有效 id）', () => {
        const html = messageBubbleHtml('user', 'hello', { messageId: 0 });
        expect(html).toContain('data-message-id="0"');
    });
});

describe('buildMessagesHtml', () => {
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

    it('复制按钮不含 data-content 属性（FE-1 数据通道单一化）', () => {
        const html = buildMessagesHtml([{ role: 'user', content: 'a & b' }]);
        expect(html).toContain('btn-copy-message');
        expect(html).not.toContain('data-content');
    });

    // ── T2 搜索定位：buildMessagesHtml 透传 m.id → data-message-id ──

    it('消息对象有 id → 对应气泡含 data-message-id', () => {
        const html = buildMessagesHtml([
            { id: 101, role: 'user', content: 'a' },
            { id: 202, role: 'assistant', content: 'b' },
        ]);
        expect(html).toContain('class="message user" data-message-id="101"');
        expect(html).toContain('data-message-id="202"');
    });

    it('消息对象无 id → 气泡无 data-message-id 属性', () => {
        const html = buildMessagesHtml([{ role: 'user', content: 'a' }]);
        expect(html).not.toContain('data-message-id');
    });

    it('零值 id（0）→ data-message-id="0" 保留（0 为有效 id）', () => {
        const html = buildMessagesHtml([{ id: 0, role: 'user', content: 'a' }]);
        expect(html).toContain('data-message-id="0"');
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

describe('avatarImgHtml — onerror 回退参数化（ARC-10 C7）', () => {
    it('产出带 onerror 回退的 img（src/alt HTML 转义）', () => {
        const html = avatarImgHtml('http://x/a.png', '角色<A>', "<span class='avatar-placeholder'>图片加载失败</span>");
        expect(html).toContain('<img src="http://x/a.png"');
        expect(html).toContain('alt="角色&lt;A&gt;"');
        expect(html).toContain('onerror=');
    });

    it('onerror 内嵌单引号按 \\\' 转义形态生成', () => {
        const fallback = "<div class='avatar-placeholder-xs'>AL</div>";
        const html = avatarImgHtml('http://x/broken.png', 'Alice', fallback);
        expect(html).toContain("this.parentElement.innerHTML='<div class=\\'avatar-placeholder-xs\\'>AL</div>'");
    });

    it('onerror 触发 → 父元素 innerHTML 替换为 fallback（行为等价）', () => {
        const container = document.createElement('div');
        container.innerHTML = avatarImgHtml('http://x/broken.png', 'Alice', "<div class='avatar-placeholder-xs'>AL</div>");
        container.querySelector('img').dispatchEvent(new Event('error'));
        expect(container.querySelector('.avatar-placeholder-xs')).not.toBeNull();
        expect(container.textContent).toBe('AL');
    });

    it('fallback 含双引号 → 属性安全转义（&quot;），不破坏 img 属性', () => {
        const html = avatarImgHtml('u', 'a', '<div class="x">y</div>');
        expect(html).not.toContain('alt="a" onerror="this.parentElement.innerHTML=\'<div class="x"'); // 属性未中断
        expect(html).toContain('&quot;');
    });

    it('assistantAvatarHtml 有头像时走 initials 回退（avatar-placeholder-xs）', () => {
        const html = assistantAvatarHtml([{ id: 1, name: 'Alice', avatar: 'http://x/a.png' }], 1);
        expect(html).toContain('onerror=');
        expect(html).toContain("avatar-placeholder-xs");
    });

    it('characterCardHtml 有头像时走 initials 回退（avatar-placeholder-sm）', () => {
        const html = characterCardHtml({ id: 1, name: '角色A', avatar: 'http://x/a.png' });
        expect(html).toContain('onerror=');
        expect(html).toContain("avatar-placeholder-sm");
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

describe('messageBubbleHtml — T6 重生成操作按钮', () => {
    it('assistant + regenerate:true → 渲染 .btn-regenerate 按钮（refresh 图标）', () => {
        const html = messageBubbleHtml('assistant', '回复', { regenerate: true });
        expect(html).toContain('btn-regenerate');
        expect(html).toContain('data-icon="refresh"');
    });

    it('user + regenerate:true → 不渲染重生成按钮（仅 assistant 角色）', () => {
        const html = messageBubbleHtml('user', 'hi', { regenerate: true });
        expect(html).not.toContain('btn-regenerate');
    });

    it('缺省 regenerate:false → 不渲染重生成按钮', () => {
        const html = messageBubbleHtml('assistant', '回复');
        expect(html).not.toContain('btn-regenerate');
    });
});

describe('buildMessagesHtml — T6 末条 assistant 重生成操作（聊天域开关）', () => {
    it('canRegenerate:true → 仅末条 assistant 气泡渲染重生成按钮', () => {
        const html = buildMessagesHtml([
            { id: 1, role: 'user', content: 'a' },
            { id: 2, role: 'assistant', content: 'b' },
            { id: 3, role: 'user', content: 'c' },
            { id: 4, role: 'assistant', content: 'd' },
        ], { canRegenerate: true });
        // 末条 assistant(id4) 含按钮；前面 assistant(id2) 不含 — 按钮出现在 id4 气泡段之后
        const btnCount = html.split('btn-regenerate').length - 1;
        expect(btnCount).toBe(1);
        expect(html.indexOf('data-message-id="4"')).toBeLessThan(html.indexOf('btn-regenerate'));
    });

    it('canRegenerate 缺省（聊天域未开启）→ 无重生成按钮', () => {
        const html = buildMessagesHtml([{ role: 'assistant', content: 'x' }]);
        expect(html).not.toContain('btn-regenerate');
    });

    it('末条非 assistant（末条为 user）→ 无重生成按钮', () => {
        const html = buildMessagesHtml(
            [
                { role: 'user', content: 'a' },
                { role: 'assistant', content: 'b' },
                { role: 'user', content: 'c' },
            ],
            { canRegenerate: true }
        );
        expect(html).not.toContain('btn-regenerate');
    });

    it('末条 assistant 为 streaming（生成中）→ 无重生成按钮', () => {
        const html = buildMessagesHtml(
            [
                { role: 'user', content: 'a' },
                { role: 'assistant', content: '部分', streaming: true },
            ],
            { canRegenerate: true }
        );
        expect(html).not.toContain('btn-regenerate');
    });
});
