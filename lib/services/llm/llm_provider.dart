/// LLM Provider 抽象 + 共享消息准备 / 错误翻译骨架 + LLMProviderFactory 抽象。
///
/// 本文件零传输依赖（dio / dart:io）；具体 wire 实现在 T02 装配层。
/// 桌面权威源（只读，语义锚点）：`desktop/backend/app/services/llm/base.py`（BaseLLM）。
library;

import 'errors.dart';

/// 单条 LLM 对话消息（角色 + 内容），不可变值对象。
class LlmMessage {
  const LlmMessage({required this.role, required this.content});

  final String role;
  final String content;

  @override
  bool operator ==(Object other) =>
      other is LlmMessage && other.role == role && other.content == content;

  @override
  int get hashCode => Object.hash(role, content);
}

/// 所有 LLM Provider 的统一抽象。
///
/// ChatService 与 UI 只依赖本抽象与 [LLMProviderFactory]，不触碰具体 Provider。
/// 共享骨架（Provider 不再各自实现）：[prepareMessages]（system 分离 + chat
/// 逐条重建）与 [runTranslated]（错误翻译骨架）；[testConnection] 默认 =
/// 最小生成请求（max_tokens=1）。[translateError] 为抽象契约，子类须将自身
/// wire 层异常统一映射为 LLM 错误族。
abstract class LLMProvider {
  LLMProvider({required this.apiKey, this.baseUrl});

  /// Provider API Key。
  final String apiKey;

  /// 自定义端点（空 → Provider 官方默认端点）。
  final String? baseUrl;

  /// 共享消息准备：从消息列表提出 system prompt，返回 `(system, chat_messages)`。
  ///
  /// 对齐 `base.py::_prepare_messages`：system 以纯文本返回（Claude 侧直接作
  /// 顶层 system 参数、OpenAI 侧调用处再包装回 `{"role": "system", ...}`），
  /// chat 消息逐条重建为新的 [LlmMessage]（不持有外部引用）；多个 system
  /// 消息时最后一个生效。
  ({String? system, List<LlmMessage> chat}) prepareMessages(List<LlmMessage> messages) {
    String? system;
    final chat = <LlmMessage>[];
    for (final msg in messages) {
      if (msg.role == 'system') {
        system = msg.content;
      } else {
        chat.add(LlmMessage(role: msg.role, content: msg.content));
      }
    }
    return (system: system, chat: chat);
  }

  /// 错误翻译抽象契约：将 wire 层任意异常映射为 LLM 错误族。
  ///
  /// 对齐 `base.py::_translate_error`：抽象方法强制子类实现，杜绝 wire 异常
  /// 以原始形态穿透到上层。generate / streamGenerate 的调用体经 [runTranslated]
  /// 捕获任何异常并交给本方法翻译后再上抛。
  LLMError translateError(Object error);

  /// 共享错误翻译骨架：块内抛出的任意异常统一经 [translateError] 映射为
  /// LLM 错误族上抛。对应 `base.py::_translated_call`（Dart 以回调替
  /// async context manager）。子类将各 SDK 调用体放入本方法执行。
  Future<T> runTranslated<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw translateError(e);
    }
  }

  /// 非流式生成完整回复。
  ///
  /// 注：R8 定案不透传 temperature（Claude 官方已弃用，非 1.0 值 → HTTP 400），
  /// 本抽象层据此不设 temperature 参数，T02 wire 层无需透传。
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  });

  /// 流式生成，逐 token 产出。
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  });

  /// 测试 API 连接是否可用（校验 Key 有效性与网络可达性）。
  ///
  /// 默认实现 = 最小生成请求（max_tokens=1），对齐 `base.py::test_connection`；
  /// 连接无效时抛出经 [translateError] 映射的 LLM 错误族。Provider 可覆写为
  /// 更便宜的专门校验（如 models 端点）。
  Future<void> testConnection({String? model}) async {
    await generate(
      messages: const [LlmMessage(role: 'user', content: 'ping')],
      maxTokens: 1,
      model: model,
    );
  }
}

/// LLM Provider 工厂抽象 —— ChatService 只依赖本抽象创建 Provider 实例。
abstract class LLMProviderFactory {
  /// 依据 [provider] 标识创建 [LLMProvider] 实例。
  ///
  /// 派生规则（锚：desktop `factory.py` / `resolver.py`）：`claude` → Claude、
  /// 其余经协议解析归 OpenAI / OpenAI 兼容端点；未知 → [ProviderNotSupportedError]。
  /// 具体派生归 T02 装配层实现。
  LLMProvider create({
    required String provider,
    required String apiKey,
    String? baseUrl,
  });
}