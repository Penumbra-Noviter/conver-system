import { describe, it, expect } from 'vitest';
import { escapeHtml, getInitials, formatTags, providerDisplayName } from '../js/utils.js';

describe('escapeHtml', () => {
    it('转义 < > &', () => {
        expect(escapeHtml('<script>x</script>')).toBe('&lt;script&gt;x&lt;/script&gt;');
        expect(escapeHtml('a & b')).toBe('a &amp; b');
    });

    it('非字符串返回空串', () => {
        expect(escapeHtml(null)).toBe('');
        expect(escapeHtml(undefined)).toBe('');
        expect(escapeHtml(123)).toBe('');
    });

    it('普通文本不变', () => {
        expect(escapeHtml('plain text')).toBe('plain text');
    });
});

describe('getInitials', () => {
    it('中文名取前两字', () => {
        expect(getInitials('测试角色')).toBe('测试');
    });

    it('英文名取前两字母大写', () => {
        expect(getInitials('alice')).toBe('AL');
        expect(getInitials('Bob')).toBe('BO');
    });

    it('空值返回 ?', () => {
        expect(getInitials('')).toBe('?');
        expect(getInitials(null)).toBe('?');
    });
});

describe('formatTags', () => {
    it('取前三个标签', () => {
        expect(formatTags(['冒险', '奇幻', '可爱', '多余'])).toBe('冒险, 奇幻, 可爱');
    });

    it('空数组/非数组返回空串', () => {
        expect(formatTags([])).toBe('');
        expect(formatTags(null)).toBe('');
        expect(formatTags('not-array')).toBe('');
    });
});

describe('providerDisplayName', () => {
    const modelData = {
        providers: [
            { key: 'claude', name: 'Claude (Anthropic)' },
            { key: 'openai', name: 'OpenAI' },
            { key: 'deepseek', name: 'DeepSeek' },
            { key: 'qwen', name: '通义千问 (Qwen)' },
        ],
    };

    it('按 key 解析为展示名', () => {
        expect(providerDisplayName(modelData, 'deepseek')).toBe('DeepSeek');
        expect(providerDisplayName(modelData, 'claude')).toBe('Claude (Anthropic)');
        expect(providerDisplayName(modelData, 'qwen')).toBe('通义千问 (Qwen)');
    });

    it('未匹配时回退为原始 key（不硬编码成 Claude）', () => {
        expect(providerDisplayName(modelData, 'kimi')).toBe('kimi');
        expect(providerDisplayName(modelData, 'unknown-provider')).toBe('unknown-provider');
    });

    it('接受裸 providers 数组', () => {
        expect(providerDisplayName(modelData.providers, 'openai')).toBe('OpenAI');
    });

    it('空 providerKey 返回空串', () => {
        expect(providerDisplayName(modelData, null)).toBe('');
        expect(providerDisplayName(modelData, '')).toBe('');
    });

    it('模型数据缺失时不抛错', () => {
        expect(providerDisplayName(null, 'deepseek')).toBe('deepseek');
        expect(providerDisplayName(undefined, 'deepseek')).toBe('deepseek');
        expect(providerDisplayName({}, 'deepseek')).toBe('deepseek');
    });
});
