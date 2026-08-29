/// 具体工厂派生（工单 02 验收：锚 `desktop/backend/app/services/llm/factory.py`）。
///
/// 派生规则：`claude` → ClaudeProvider；`resolveApiProvider(key) == openai`
/// （model_catalog 协议解析，覆盖 openai 及全部 OpenAI 兼容第三方）→
/// OpenAIProvider；其余 → ProviderNotSupportedError「不支持的 Provider: {provider}」。
library;

import 'package:conver_system_mobile/services/llm/claude_provider.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/factory.dart';
import 'package:conver_system_mobile/services/llm/openai_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const factory = LLMFactory();

  group('派生规则（锚 factory.py register_builtin_providers）', () {
    test('claude → ClaudeProvider', () {
      final provider = factory.create(provider: 'claude', apiKey: 'k');
      expect(provider, isA<ClaudeProvider>());
      expect(provider.apiKey, 'k');
    });

    test('openai（自身）→ OpenAIProvider', () {
      expect(
        factory.create(provider: 'openai', apiKey: 'k'),
        isA<OpenAIProvider>(),
      );
    });

    test('OpenAI 兼容第三方（协议解析归 openai）→ OpenAIProvider', () {
      for (final key in [
        'deepseek',
        'qwen',
        'kimi',
        'glm',
        'minimax',
        'step',
      ]) {
        expect(
          factory.create(provider: key, apiKey: 'k'),
          isA<OpenAIProvider>(),
          reason: 'provider=$key 协议应为 openai',
        );
      }
    });

    test('未知 provider → ProviderNotSupportedError（文案含 provider 名）', () {
      expect(
        () => factory.create(provider: 'unknown-x', apiKey: 'k'),
        throwsA(isA<ProviderNotSupportedError>().having(
          (e) => e.message,
          'message',
          '不支持的 Provider: unknown-x',
        )),
      );
    });

    test('空字符串 provider 视作未知 → ProviderNotSupportedError', () {
      expect(
        () => factory.create(provider: '', apiKey: 'k'),
        throwsA(isA<ProviderNotSupportedError>()),
      );
    });

    test('apiKey / baseUrl 透传到实例', () {
      final claude = factory.create(
          provider: 'claude', apiKey: 'ck', baseUrl: 'https://c.example');
      expect(claude.apiKey, 'ck');
      expect(claude.baseUrl, 'https://c.example');

      final openAi = factory.create(
          provider: 'openai', apiKey: 'ok', baseUrl: 'https://o.example/v1');
      expect(openAi.apiKey, 'ok');
      expect(openAi.baseUrl, 'https://o.example/v1');
    });
  });
}