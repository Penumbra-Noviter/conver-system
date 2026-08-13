import { describe, it, expect } from 'vitest';
import { providerDisplayName } from '../js/utils/model-utils.js';

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
