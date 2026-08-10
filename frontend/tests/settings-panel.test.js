import { describe, it, expect } from 'vitest';
import { resolveCredentialTarget } from '../js/components/settings-panel.js';

// 语义对齐后端 backend/app/services/setting.py::_slot_value：
// 同协议槽位优先 → 跨协议兜底（任一槽位有值即可全局使用）。
describe('resolveCredentialTarget', () => {
    // 同协议优先：deepseek(id=openai) 两槽都填 → 取 openai 槽位
    it('同协议优先：多协议槽位都有值时取同协议槽位', () => {
        const form = {
            provider: { key: 'deepseek', id: 'openai' },
            claude_api_key: 'sk-claude',
            claude_base_url: 'https://api.anthropic.com',
            openai_api_key: 'sk-openai',
            openai_base_url: 'https://api.openai.com/v1',
        };
        expect(resolveCredentialTarget(form)).toEqual({
            providerKey: 'deepseek',
            key: 'sk-openai',
            baseUrl: 'https://api.openai.com/v1',
        });
    });

    // 跨协议兜底：同协议槽位为空 → 回退另一协议槽位
    it('跨协议兜底：同协议槽位为空时回退另一协议槽位', () => {
        const form = {
            provider: { key: 'deepseek', id: 'openai' },
            claude_api_key: 'sk-claude',
            claude_base_url: 'https://api.anthropic.com',
            openai_api_key: '',
            openai_base_url: '',
        };
        expect(resolveCredentialTarget(form)).toEqual({
            providerKey: 'deepseek',
            key: 'sk-claude',
            baseUrl: 'https://api.anthropic.com',
        });
    });

    // 未填回退：两槽都空 → key/baseUrl 为空串，providerKey 保留（调用方据此跳过测试）
    it('未填回退：两槽都空时 key/baseUrl 为空串', () => {
        const form = {
            provider: { key: 'claude', id: 'claude' },
            claude_api_key: '',
            claude_base_url: '',
            openai_api_key: '',
            openai_base_url: '',
        };
        expect(resolveCredentialTarget(form)).toEqual({
            providerKey: 'claude',
            key: '',
            baseUrl: '',
        });
    });

    // 表单字段缺失：键不存在（undefined）与空串等价，不抛错
    it('表单字段缺失：字段键缺失时按空处理并兜底，不抛错', () => {
        const form = {
            provider: { key: 'openai', id: 'openai' },
            // claude_api_key / claude_base_url 键完全缺失
            openai_api_key: undefined,
        };
        expect(resolveCredentialTarget(form)).toEqual({
            providerKey: 'openai',
            key: '',
            baseUrl: '',
        });
    });

    // URL 原样透传：不带 /v1 后缀的 base_url 不做任何规范化
    it('URL 不带 /v1 时原样透传，不做规范化', () => {
        const form = {
            provider: { key: 'claude', id: 'claude' },
            claude_api_key: 'sk-claude',
            claude_base_url: 'https://example.com/api',
            openai_api_key: '',
            openai_base_url: '',
        };
        expect(resolveCredentialTarget(form)).toEqual({
            providerKey: 'claude',
            key: 'sk-claude',
            baseUrl: 'https://example.com/api',
        });
    });
});
