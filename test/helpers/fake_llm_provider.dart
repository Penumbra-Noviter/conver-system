/// 共享 FakeLLMProvider — M2 服务层测试替身（T01b 抽象契约 + T02 / T03 复用）。
///
/// 可播放 canned token 序列（streamGenerate 逐条产出、generate 拼接返回）、
/// 抛出配置的错误（LLM 族或任意对象，原样抛出，fake 不做翻译）、零 token 流
/// （缺省空序列）。记录每次调用入参（messages / maxTokens / model 与调用计数）
/// 供断言。
library;

import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';

/// 恒返回同一 [LLMProvider] 实例的工厂 fake（ChatController / ChatView 测试
/// 经真实 ChatService 注入；派生入参不校验）。
class FixedLLMProviderFactory implements LLMProviderFactory {
  FixedLLMProviderFactory(this.provider);

  /// 每次 [create] 返回的 provider 实例。
  final LLMProvider provider;

  @override
  LLMProvider create({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) =>
      this.provider;
}

/// 经 [LLMProvider] 抽象播放既定行为的假实现。
class FakeLLMProvider extends LLMProvider {
  FakeLLMProvider({
    super.apiKey = 'test-key',
    super.baseUrl,
    List<String> tokens = const [],
    this.error,
    this.generateDelay,
  }) : _tokens = List<String>.unmodifiable(tokens);

  final List<String> _tokens;

  /// 非 null 时 generate / streamGenerate 立即抛出（原样，不翻译）。
  final Object? error;

  /// generate 的产物等待时长（观测「重生成进行中」禁用态等慢路径用）；
  /// null → 立即产出。
  final Duration? generateDelay;

  // 调用记录（T02 / T03 断言用）。
  int generateCallCount = 0;
  int streamGenerateCallCount = 0;
  int testConnectionCallCount = 0;
  List<LlmMessage>? lastMessages;
  int? lastMaxTokens;
  String? lastModel;

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  }) async {
    generateCallCount++;
    lastMessages = messages;
    lastMaxTokens = maxTokens;
    lastModel = model;
    final delay = generateDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    final e = error;
    if (e != null) {
      throw e;
    }
    return _tokens.join();
  }

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  }) async* {
    streamGenerateCallCount++;
    lastMessages = messages;
    lastMaxTokens = maxTokens;
    lastModel = model;
    final e = error;
    if (e != null) {
      throw e;
    }
    for (final token in _tokens) {
      yield token;
    }
  }

  @override
  Future<void> testConnection({String? model}) async {
    testConnectionCallCount++;
    await super.testConnection(model: model);
  }
}

/// 逐 token 延时的流式 provider（打字机 / 停止 / 断流 widget 测试共用）。
///
/// [streamGenerate] 先按 [delay] 间隔逐个产出 [tokens]，产出完后若
/// [errorAfter] 非空则以**未经翻译的原样异常**上抛——模拟 T02 wire 层经
/// `translateError` 翻译后的 LLM 族异常（如 [LLMConnectionInterruptedError]
/// 断流信号）。停止语义（widget 层取消订阅）靠真实异步 `yield` 延迟表达。
///
/// 调用记录（断言复用）：`generateCallCount` / `streamGenerateCallCount` /
/// `lastMessages` / `lastModel`。
class TickingFakeLLMProvider extends LLMProvider {
  TickingFakeLLMProvider({
    super.apiKey = 'test-key',
    List<String> tokens = const [],
    this.errorAfter,
    this.delay = const Duration(milliseconds: 5),
  }) : _tokens = List<String>.unmodifiable(tokens);

  /// 逐个产出的 token 序列。
  final List<String> _tokens;

  /// 全部 token 产出完毕后的异常（原样上抛，不翻译）；null → 正常完成。
  final Object? errorAfter;

  /// 相邻 token 的产出间隔（真实异步延迟）。
  final Duration delay;

  int generateCallCount = 0;
  int streamGenerateCallCount = 0;
  List<LlmMessage>? lastMessages;
  int? lastMaxTokens;
  String? lastModel;

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  }) async {
    generateCallCount++;
    lastMessages = messages;
    lastMaxTokens = maxTokens;
    lastModel = model;
    final e = errorAfter;
    if (e != null) {
      throw e;
    }
    return _tokens.join();
  }

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  }) async* {
    streamGenerateCallCount++;
    lastMessages = messages;
    lastMaxTokens = maxTokens;
    lastModel = model;
    for (final token in _tokens) {
      await Future<void>.delayed(delay);
      yield token;
    }
    final e = errorAfter;
    if (e != null) {
      throw e;
    }
  }

  @override
  Future<void> testConnection({String? model}) async {}
}