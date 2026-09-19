/// LLM Provider 抽象 + 共享消息准备 / 错误翻译骨架 + LLMProviderFactory 抽象。
///
/// 本文件引入 dio / dart:io 传输异常类型（既有长期依赖）——仅用于基类默认
/// 错误分发链的分类，不含任何 wire 调用；具体 wire 实现在 T02 装配层。
/// `errors.dart` 保持零 dio / dart:io 依赖（传输异常以 [translateSdkError]
/// 原语入参），`translate_helpers.dart` 承载分类原语（只读共享）。
/// 桌面权威源（只读，语义锚点）：`desktop/backend/app/services/llm/base.py`（BaseLLM）。
library;

import 'dart:io';

import 'package:dio/dio.dart';

import 'errors.dart';
import 'translate_helpers.dart';

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
/// 逐条重建）、[runTranslated]（错误翻译骨架）与 [translateError]（通用错误
/// 分发链默认实现）；[testConnection] 默认 = 最小生成请求（max_tokens=1）。
/// 分发链顺序：LLMError 直通 → DioException → HttpStatusError → Provider 特有
/// 钩子 [translateProviderError] → SocketException → HttpException →
/// FormatException/TypeError → 兜底；文案统一以 [providerName] 命名 provider。
abstract class LLMProvider {
  LLMProvider({required this.apiKey, this.baseUrl});

  /// Provider API Key。
  final String apiKey;

  /// 自定义端点（空 → Provider 官方默认端点）。
  final String? baseUrl;

  /// Provider 名（错误文案逐字依赖，如「{name} API 调用失败: …」）。
  ///
  /// 具体 Provider 覆写返回既有 'Claude' / 'OpenAI' 字面量；未覆写时用中性
  /// 缺省 'LLM'（测试夹具零改动编译）。
  String get providerName => 'LLM';

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

  /// 错误翻译契约（默认实现）：将 wire 层任意异常映射为 LLM 错误族。
  ///
  /// 对齐 `base.py::_translate_error`。分发链按序：
  /// [LLMError] 直通（含 [LLMConnectionInterruptedError] 两相位叶子，不二次
  /// 翻译）→ [DioException]（[translateDioError]，timeout / 状态码 / 兜底）→
  /// [HttpStatusError]（[translateStatusError]，408/504 归 Timeout）→ Provider
  /// 特有钩子 [translateProviderError]（默认返回 null）→ [SocketException] /
  /// [HttpException]（LLM 族兜底）→ [FormatException] / [TypeError]
  /// （[LlmTransportFailure.responseParse]）→ 未知异常兜底（文案含
  /// [providerName]）。generate / streamGenerate 的调用体经 [runTranslated]
  /// 捕获任何异常并交给本方法翻译后再上抛。
  LLMError translateError(Object error) {
    // 已映射为 LLM 族的错误（含连接中断类）直通，不二次翻译。
    if (error is LLMError) {
      return error;
    }
    if (error is DioException) {
      return translateDioError(providerName, error);
    }
    if (error is HttpStatusError) {
      return translateStatusError(
        providerName,
        error.statusCode,
        error.body,
        cause: error,
      );
    }
    // Provider 特有异常钩子：Claude 只命中其流内 error 事件原语，其余返回
    // null 继续通用链；OpenAI 无特有异常，直接继承本默认（返回 null）。
    final providerSpecific = translateProviderError(error);
    if (providerSpecific != null) {
      return providerSpecific;
    }
    if (error is SocketException) {
      // 连接阶段网络失败（拒绝 / DNS / 重置）→ LLM 族兜底，不穿透原始异常。
      return translateSdkError(
        providerName,
        message: error.message,
        cause: error,
      );
    }
    if (error is HttpException) {
      return translateSdkError(
        providerName,
        message: error.message,
        cause: error,
      );
    }
    if (error is FormatException || error is TypeError) {
      return translateSdkError(
        providerName,
        failure: LlmTransportFailure.responseParse,
        message: '$error',
        cause: error,
      );
    }
    return translateSdkError(providerName, message: '$error', cause: error);
  }

  /// Provider 特有异常翻译钩子（protected 语义的扩展点）。
  ///
  /// 在 [translateError] 默认链中固定于 [HttpStatusError] 之后、[SocketException]
  /// 之前被咨询：返回非 null 的 LLM 族错误则直接采用，否则继续通用链。
  /// 缺省实现恒返回 null（无特有异常）。子类覆写只对**自身私有异常原语**
  /// 返回非 null——如 Claude 的流内 `error` 事件原语；对其他类型一律返回
  /// null，保证通用链归属与顺序不变更。
  LLMError? translateProviderError(Object error) => null;

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
  /// [temperature] 采样温度，缺省 0.7（对齐桌面 `BaseLLM.generate` 签名，
  /// U-2 更新：原 R8「不透传 temperature」定案仅对 Claude 成立）。OpenAI 透传
  /// 进请求体；Claude 接收但忽略（Anthropic 已弃用该键）。
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  });

  /// 流式生成，逐 token 产出（基类默认实现 = 模板方法，承载错误翻译骨架）。
  ///
  /// 消费 [streamRequest] 内层流逐 token 透传；内层流抛出的任意异常经
  /// [translateError] 映射为 LLM 错误族后上抛（子类差异面只写端点 / 头 /
  /// 终态帧 / 帧提取，不再各自复制本骨架）。[temperature] 语义同 [generate]
  /// （OpenAI 透传、Claude 忽略）。
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) async* {
    try {
      // 注意不用 yield*：Dart 语义下 yield* 将内层流错误直接转发到外层流，
      // 不经外层 try/catch；await for 则将错误在其语句处抛出、可被捕获翻译。
      await for (final token in streamRequest(
        messages: messages,
        maxTokens: maxTokens,
        model: model,
        temperature: temperature,
      )) {
        yield token;
      }
    } catch (e) {
      throw translateError(e);
    }
  }

  /// Provider 特有流式 wire 扩展点（protected 语义）。
  ///
  /// 子类只实现本方法：端点 / 头 / 终态帧 / 帧提取（可复用 [streamSse] 共享
  /// 低级骨架），错误翻译收尾由基类默认 [streamGenerate] 单点承载。参数面与
  /// [streamGenerate] 同构（messages / maxTokens / model / temperature）。
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
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