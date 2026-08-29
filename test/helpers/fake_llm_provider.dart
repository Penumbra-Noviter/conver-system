/// 共享 FakeLLMProvider — M2 服务层测试替身（T01b 抽象契约 + T02 / T03 复用）。
///
/// 可播放 canned token 序列（streamGenerate 逐条产出、generate 拼接返回）、
/// 抛出配置的错误（LLM 族或任意对象，原样抛出，fake 不做翻译）、零 token 流
/// （缺省空序列）。记录每次调用入参（messages / maxTokens / model 与调用计数）
/// 供断言。
library;

import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';

/// 经 [LLMProvider] 抽象播放既定行为的假实现。
class FakeLLMProvider extends LLMProvider {
  FakeLLMProvider({
    super.apiKey = 'test-key',
    super.baseUrl,
    List<String> tokens = const [],
    this.error,
  }) : _tokens = List<String>.unmodifiable(tokens);

  final List<String> _tokens;

  /// 非 null 时 generate / streamGenerate 立即抛出（原样，不翻译）。
  final Object? error;

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