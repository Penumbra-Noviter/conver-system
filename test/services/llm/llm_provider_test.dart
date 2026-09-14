/// LLMProvider / LLMProviderFactory 抽象契约（工单 01b 验收）+ 基类默认错误
/// 分发链（工单 01 / C1 验收）。
///
/// 抽象契约经 FakeLLMProvider（test/helpers/fake_llm_provider.dart）验证：
/// 共享消息准备（system 提出 + chat 逐条重建）、testConnection 默认最小生成
/// （max_tokens=1，锚 `desktop/backend/app/services/llm/base.py`）、错误翻译
/// 骨架（runTranslated → translateError），及工厂抽象签名。C1 部分验证基类
/// 默认 [LLMProvider.translateError] 分发链（LLMError 直通 → DioException →
/// HttpStatusError → Provider 特有钩子 → SocketException → HttpException →
/// FormatException/TypeError → 兜底）与 Provider 特有钩子槽位。语义锚点：
/// `desktop/backend/app/services/llm/base.py`。
library;

import 'dart:io';

import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/llm/translate_helpers.dart';
import 'package:dio/dio.dart';
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
    double temperature = 0.7,
  }) =>
      throw UnimplementedError();

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) =>
      throw UnimplementedError();

  /// 经共享骨架执行并抛原始异常的调用（等价于 generate 内部形态）。
  Future<String> guarded() => runTranslated(() async => throw StateError('boom'));
}

/// 未分类异常原语（Provider 特有钩子的专属命中类型，基类链不识别的负样本）。
class _MarkerError implements Exception {
  _MarkerError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 只依赖基类默认 translateError 分发链的最小 provider（不覆写翻译方法）。
class _DefaultChainProvider extends LLMProvider {
  _DefaultChainProvider() : super(apiKey: 'k');

  @override
  String get providerName => 'Test';

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) =>
      throw UnimplementedError();

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) =>
      throw UnimplementedError();
}

/// 覆写 Provider 特有钩子的 provider：`_MarkerError` → 专属 LLM 族，其余返回
/// null 走基类默认链；记录每次钩子被咨询的运行时类型供槽位断言。
class _HookProvider extends _DefaultChainProvider {
  final List<Type> hookCalls = [];

  @override
  LLMError? translateProviderError(Object error) {
    hookCalls.add(error.runtimeType);
    if (error is _MarkerError) {
      return LLMError('Test 专属钩子命中: ${error.message}');
    }
    return null;
  }
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

  group('LLMProvider 默认 translateError 分发链（C1：基类默认实现，逐字对齐 '
      '原 claude/openai 内联链）', () {
    _DefaultChainProvider provider() => _DefaultChainProvider();

    test('LLMError 直通不二次翻译（same 恒等）', () {
      final original = LLMAuthError('Test');
      expect(provider().translateError(original), same(original));
    });

    test('相位叶子（Connect/Read）直通不二次翻译', () {
      final connect = ConnectPhaseInterruptedError(originalError: Exception('c'));
      final read = ReadPhaseInterruptedError(originalError: Exception('r'));
      expect(provider().translateError(connect), same(connect));
      expect(provider().translateError(read), same(read));
    });

    test('DioException 连接超时 → LLMTimeoutError', () {
      final e = provider().translateError(DioException(
        type: DioExceptionType.connectionTimeout,
        requestOptions: RequestOptions(path: '/x'),
      ));
      expect(e, isA<LLMTimeoutError>());
      expect(e.message, 'Test API 请求超时');
    });

    test('DioException 携带 401 响应 → LLMAuthError（error.message 提取）', () {
      final e = provider().translateError(DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 401,
          data: {'error': {'message': 'invalid key'}},
        ),
      ));
      expect(e, isA<LLMAuthError>());
      expect(e.message, 'Test API Key 无效或未配置');
    });

    test('DioException 无状态码无响应 → LLM 族兜底（不崩溃、不穿透）', () {
      final e = provider().translateError(DioException(
        requestOptions: RequestOptions(path: '/x'),
      ));
      expect(e, isA<LLMError>());
      expect(e.message, startsWith('Test API 调用失败:'));
    });

    test('嵌套 DioException（响应体 data 为 DioException）→ 兜底不崩溃', () {
      final inner = DioException(
        requestOptions: RequestOptions(path: '/x'),
        message: 'boom',
      );
      final outer = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 401,
          data: inner,
        ),
      );
      // 响应体非 Map/String → responseText 返回 ''，仍按状态码 401 归属 Auth。
      final e = provider().translateError(outer);
      expect(e, isA<LLMAuthError>());
      expect(e.message, 'Test API Key 无效或未配置');
    });

    test('HttpStatusError 401 → LLMAuthError', () {
      final e = provider().translateError(HttpStatusError(401, 'x'));
      expect(e, isA<LLMAuthError>());
      expect(e.message, 'Test API Key 无效或未配置');
    });

    test('HttpStatusError 429 → LLMRateLimitError', () {
      final e = provider().translateError(HttpStatusError(429, 'rate limited'));
      expect(e, isA<LLMRateLimitError>());
      expect(e.message, 'Test API 请求频率超限');
    });

    test('HttpStatusError 504 → LLMTimeoutError（网关超时特判）', () {
      final e = provider().translateError(HttpStatusError(504, ''));
      expect(e, isA<LLMTimeoutError>());
      expect(e.message, 'Test API 请求超时');
    });

    test('HttpStatusError 408 → LLMTimeoutError', () {
      expect(
          provider().translateError(HttpStatusError(408, '')), isA<LLMTimeoutError>());
    });

    test('HttpStatusError 400 content_filter → LLMContentFilterError', () {
      final e = provider()
          .translateError(HttpStatusError(400, 'Content filtered by content_filter'));
      expect(e, isA<LLMContentFilterError>());
      expect(e.message, '内容被 Test 内容过滤器拦截');
    });

    test('SocketException → LLM 族兜底（message 带原始文本）', () {
      final e =
          provider().translateError(const SocketException('Connection refused'));
      expect(e, isA<LLMError>());
      expect(e.message, 'Test API 调用失败: Connection refused');
    });

    test('HttpException → LLM 族兜底', () {
      final e = provider().translateError(HttpException('Connection reset'));
      expect(e, isA<LLMError>());
      expect(e.message, 'Test API 调用失败: Connection reset');
    });

    test('FormatException → LLMResponseParseFailedError（responseParse 语义）', () {
      final e = provider().translateError(const FormatException('bad json'));
      expect(e, isA<LLMResponseParseFailedError>());
      expect(e.message, startsWith('Test API 返回格式异常：'));
      expect(e.message, contains('兼容 Test'));
    });

    test('TypeError → LLMResponseParseFailedError', () {
      expect(provider().translateError(TypeError()), isA<LLMResponseParseFailedError>());
    });

    test('未知异常（StateError）→ 兜底，文案含 provider 名', () {
      final e = provider().translateError(StateError('boom'));
      expect(e, isA<LLMError>());
      expect(e.message, 'Test API 调用失败: Bad state: boom');
    });

    test('providerName 缺省 getter 生效（兜底文案依赖）', () {
      expect(provider().providerName, 'Test');
    });
  });

  group('Provider 特有钩子槽位（C1：HttpStatusError 后、SocketException 前被咨询）', () {
    _HookProvider provider() => _HookProvider();

    test('未分类专属异常 → 钩子命中返回专属 LLM 族', () {
      final e = provider().translateError(_MarkerError('boom'));
      expect(e.message, 'Test 专属钩子命中: boom');
    });

    test('钩子返回 null → 走基类 SocketException 分支（不吞错误）', () {
      final p = provider();
      final e = p.translateError(const SocketException('refused'));
      expect(e, isA<LLMError>());
      expect(e.message, 'Test API 调用失败: refused');
      // 槽位锚：钩子在 SocketException 分支之前被咨询（先问钩子，null 再续链）。
      expect(p.hookCalls, [SocketException]);
    });

    test('钩子返回 null → 走基类 responseParse 分支（FormatException）', () {
      final p = provider();
      final e = p.translateError(const FormatException('x'));
      expect(e, isA<LLMResponseParseFailedError>());
      // FormatException 位于钩子之后，链上先咨询钩子（null）再落 responseParse。
      expect(p.hookCalls, [FormatException]);
    });

    test('LLMError 早退：钩子不被咨询', () {
      final p = provider();
      p.translateError(LLMAuthError('Test'));
      expect(p.hookCalls, isEmpty);
    });

    test('DioException 早退：钩子不被咨询', () {
      final p = provider();
      p.translateError(DioException(requestOptions: RequestOptions(path: '/x')));
      expect(p.hookCalls, isEmpty);
    });

    test('HttpStatusError 早退：钩子不被咨询', () {
      final p = provider();
      p.translateError(HttpStatusError(401, 'x'));
      expect(p.hookCalls, isEmpty);
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