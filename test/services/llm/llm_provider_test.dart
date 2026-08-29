/// LLMProvider / LLMProviderFactory 抽象契约（工单 01b 验收）。
///
/// 抽象契约经 FakeLLMProvider（test/helpers/fake_llm_provider.dart）验证：
/// 共享消息准备（system 提出 + chat 逐条重建）、testConnection 默认最小生成
/// （max_tokens=1，锚 `desktop/backend/app/services/llm/base.py`）、错误翻译
/// 骨架（runTranslated → translateError），及工厂抽象签名。语义锚点：
/// `desktop/backend/app/services/llm/base.py`。
library;

import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_llm_provider.dart';

/// 最小 provider：仅用于验证 runTranslated 骨架（生成方法不被调用）。
class _ThrowingProvider extends LLMProvider {
  _ThrowingProvider() : super(apiKey: 'k');

  /// 把未分类异常映射为 Generic 兜底（LLM 族错误）。
  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('k API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  }) =>
      throw UnimplementedError();

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  }) =>
      throw UnimplementedError();

  /// 经共享骨架执行并抛原始异常的调用（等价于 generate 内部形态）。
  Future<String> guarded() => runTranslated(() async => throw StateError('boom'));
}

/// 最小工厂：create → FakeLLMProvider（字段透传）。
class _EchoFactory implements LLMProviderFactory {
  @override
  LLMProvider create({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) {
    return FakeLLMProvider(apiKey: apiKey, baseUrl: baseUrl);
  }
}

void main() {
  group('LLMProvider.prepareMessages 共享骨架（锚 base.py._prepare_messages）', () {
    late FakeLLMProvider fake;

    setUp(() => fake = FakeLLMProvider());

    test('system 提出：system 不入 chat，chat 逐条重建', () {
      const messages = [
        LlmMessage(role: 'system', content: 'sys'),
        LlmMessage(role: 'user', content: 'u'),
        LlmMessage(role: 'assistant', content: 'a'),
      ];
      final result = fake.prepareMessages(messages);
      expect(result.system, 'sys');
      expect(result.chat, hasLength(2));
      expect(result.chat[0].role, 'user');
      expect(result.chat[0].content, 'u');
      expect(result.chat[1].role, 'assistant');
      expect(result.chat[1].content, 'a');
    });

    test('多 system 消息：最后一条生效，system 全部不入 chat', () {
      final result = fake.prepareMessages(const [
        LlmMessage(role: 'system', content: 'first'),
        LlmMessage(role: 'system', content: 'second'),
        LlmMessage(role: 'user', content: 'u'),
      ]);
      expect(result.system, 'second');
      expect(result.chat, [const LlmMessage(role: 'user', content: 'u')]);
    });

    test('无 system：system 为 null，chat 含全部消息', () {
      final result = fake.prepareMessages(const [
        LlmMessage(role: 'user', content: 'u'),
        LlmMessage(role: 'assistant', content: 'a'),
      ]);
      expect(result.system, isNull);
      expect(result.chat, hasLength(2));
    });

    test('chat 消息为新建实例（不持有外部引用）', () {
      const original = LlmMessage(role: 'user', content: 'u');
      final result = fake.prepareMessages([original]);
      expect(identical(result.chat.single, original), isFalse);
      expect(result.chat.single, original);
    });
  });

  group('LlmMessage 值语义', () {
    test('相等消息内容相等且 hashCode 一致（value object 契约）', () {
      const a = LlmMessage(role: 'user', content: 'u');
      const b = LlmMessage(role: 'user', content: 'u');
      const c = LlmMessage(role: 'assistant', content: 'u');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('LLMProvider.testConnection 默认最小生成（锚 base.py）', () {
    test('默认 = generate([user ping], max_tokens=1)', () async {
      final fake = FakeLLMProvider();
      await fake.testConnection();
      expect(fake.testConnectionCallCount, 1);
      expect(fake.generateCallCount, 1);
      expect(fake.lastMessages, [const LlmMessage(role: 'user', content: 'ping')]);
      expect(fake.lastMaxTokens, 1);
    });

    test('透传 model、max_tokens 保持 1', () async {
      final fake = FakeLLMProvider();
      await fake.testConnection(model: 'claude-sonnet-5');
      expect(fake.lastModel, 'claude-sonnet-5');
      expect(fake.lastMaxTokens, 1);
    });

    test('配置错误时 testConnection 上抛（经 generate）', () async {
      final fake = FakeLLMProvider(error: LLMAuthError('Claude'));
      await expectLater(fake.testConnection(), throwsA(isA<LLMAuthError>()));
      expect(fake.generateCallCount, 1);
    });
  });

  group('LLMProvider.runTranslated 错误翻译骨架', () {
    test('块内原始异常经 translateError 映射为 LLMError', () async {
      await expectLater(
        _ThrowingProvider().guarded(),
        throwsA(
          isA<LLMError>()
              .having((e) => e.message, 'message', 'k API 调用失败: Bad state: boom'),
        ),
      );
    });

    test('translateError 对已 LLMError 原样返回', () {
      final e = LLMAuthError('Claude');
      expect(_ThrowingProvider().translateError(e), same(e));
    });
  });

  group('LLMProviderFactory 抽象（create → LLMProvider）', () {
    test('create(provider, apiKey, baseUrl) 字段透传', () {
      final provider = _EchoFactory()
          .create(provider: 'claude', apiKey: 'k', baseUrl: 'https://x');
      expect(provider, isA<LLMProvider>());
      expect(provider.apiKey, 'k');
      expect(provider.baseUrl, 'https://x');
    });

    test('baseUrl 可空', () {
      final provider = _EchoFactory().create(provider: 'openai', apiKey: 'k');
      expect(provider.baseUrl, isNull);
    });
  });

  group('FakeLLMProvider 行为契约（T02/T03 复用）', () {
    test('streamGenerate 播放 canned token 序列', () async {
      final fake = FakeLLMProvider(tokens: ['Hello', ', ', 'world']);
      final collected = <String>[];
      await for (final token in fake.streamGenerate(messages: const [])) {
        collected.add(token);
      }
      expect(collected, ['Hello', ', ', 'world']);
    });

    test('generate 拼接 canned token 序列', () async {
      final fake = FakeLLMProvider(tokens: ['Hello', ', ', 'world']);
      expect(await fake.generate(messages: const []), 'Hello, world');
    });

    test('零 token 流：streamGenerate 空、generate 空串', () async {
      final fake = FakeLLMProvider();
      expect(await fake.generate(messages: const []), '');
      await expectLater(
        fake.streamGenerate(messages: const []).toList(),
        completion(isEmpty),
      );
    });

    test('配置 LLM 族错误时 generate / streamGenerate 抛出', () async {
      final fake = FakeLLMProvider(error: LLMAuthError('Claude'));
      await expectLater(fake.generate(messages: const []), throwsA(isA<LLMAuthError>()));
      await expectLater(
        fake.streamGenerate(messages: const []).toList(),
        throwsA(isA<LLMAuthError>()),
      );
    });

    test('配置任意原始异常原样抛出（fake 不翻译）', () async {
      final fake = FakeLLMProvider(error: StateError('boom'));
      await expectLater(
        fake.generate(messages: const []),
        throwsA(isA<StateError>()),
      );
    });

    test('generate 记录入参（messages/maxTokens/model）', () async {
      final fake = FakeLLMProvider();
      const messages = [LlmMessage(role: 'user', content: 'hi')];
      await fake.generate(messages: messages, maxTokens: 42, model: 'm1');
      expect(fake.lastMessages, same(messages));
      expect(fake.lastMaxTokens, 42);
      expect(fake.lastModel, 'm1');
    });
  });
}