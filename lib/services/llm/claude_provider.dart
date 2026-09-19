/// ClaudeProvider — Anthropic Messages API 原生双栈 wire（T02）。
///
/// - 非流式 [generate] 走 dio；流式 [streamGenerate] 走 dart:io HttpClient 直连
///   （设计文档双栈裁定：`research/stack-confirm/findings.md` R2）。
/// - POST `{base}/v1/messages`；`x-api-key` + `anthropic-version: 2023-06-01`
///   头（官方必需）；system 作顶层参数；`content_block_delta` 的 `text_delta`
///   逐 token 产出；`message_stop` 为终态；`ping` 忽略；`error` 事件抛错终止。
/// - **temperature 接收但忽略**（U-2 更新 R8 定案：Anthropic 官方已弃用
///   temperature，Opus 4.6 后非 1.0 值 → HTTP 400），请求体不携带该键。
/// - 401/429/408/504 → Auth / RateLimit / Timeout；400 content_filter →
///   ContentFilter；连接失败 → LLM 族兜底；流中途断连（EOF 未到终态 / 连接重置）
///   → 可区分的 [LLMConnectionInterruptedError]（供 T03 断流处理）。
/// 锚：`desktop/backend/app/services/llm/claude.py` + `errors.dart::translateSdkError`。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'errors.dart';
import 'llm_provider.dart';
import 'sse.dart';
import 'stream_wire.dart';
import 'translate_helpers.dart';

/// Anthropic 官方版本头（必需；research R1-1：`anthropic-version: 2023-06-01`）。
const String kAnthropicVersion = '2023-06-01';

/// 规范化 Anthropic 端点根地址（F5：锚 `desktop/backend/app/services/llm/claude.py`
/// `_normalize_base_url` 语义修正）。
///
/// Claude 的 Messages 端点恒为 `{base}/v1/messages`，因此用户配置的面板地址若
/// 已含版本段（末尾 `v1` / `v1beta`），拼接前须剥去——否则拼出
/// `/v1/v1/messages`（404，观察级缺陷）；末尾多余斜杠一并去除；空值返回 null
/// （无覆盖 → 回退官方默认端点）。
String? normalizeClaudeBaseUrl(String? baseUrl) {
  if (baseUrl == null || baseUrl.trim().isEmpty) {
    return null;
  }
  var url = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final lastSegment = url.split('/').last;
  if (RegExp(r'^v\d+(beta)?$').hasMatch(lastSegment)) {
    url = url.substring(0, url.length - lastSegment.length - 1);
  }
  return url;
}

/// Anthropic Claude 实现。
class ClaudeProvider extends LLMProvider {
  ClaudeProvider({required super.apiKey, super.baseUrl});

  @override
  String get providerName => 'Claude';

  static const String _defaultModel = 'claude-sonnet-5';
  static const String _defaultEndpoint = 'https://api.anthropic.com';

  /// 非流式 REST 客户端（T02 双栈：dio 侧）。
  final Dio _dio = Dio();

  /// Claude 特有异常翻译钩子：只命中 Anthropic 流内 `error` 事件原语
  /// （[translateSdkError] 进 LLM 族），其余返回 null 走基类默认分发链——
  /// 对齐原完整覆写中 `_StreamApiError` 分支的逐字语义与槽位（HttpStatusError
  /// 后、SocketException 前）。
  @override
  LLMError? translateProviderError(Object error) {
    if (error is _StreamApiError) {
      return translateSdkError(providerName, message: error.message, cause: error);
    }
    return null;
  }

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) {
    // U-2：temperature 接收但忽略（Anthropic 已弃用该键，请求体不携带）。
    return runTranslated(() async {
      final body = _buildBody(messages, maxTokens: maxTokens, model: model);
      final response = await _dio.post(
        _messagesUri().toString(),
        data: body,
        options: _requestOptions(),
      );
      return _extractText(response.data);
    });
  }

  /// Anthropic 流式 wire 扩展点（protected 语义，基类默认 [LLMProvider.streamGenerate]
  /// 承载错误翻译骨架）：POST + SSE 消费，逐 token 产出（共享骨架 [streamSse]，
  /// 本方法只提供 Anthropic 差异面：端点 / 头 / 终态帧 / 帧提取 / 流错帧）。
  /// [temperature] 接收但忽略（U-2：Anthropic 已弃用该键，请求体不携带）。
  @override
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) async* {
    yield* streamSse(
      uri: _messagesUri(),
      body: jsonEncode(
        _buildBody(messages,
            maxTokens: maxTokens, model: model, streaming: true),
      ),
      headers: {
        'accept': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': kAnthropicVersion,
      },
      errorFrameException: (frame) => frame.event == 'error'
          ? _StreamApiError(_errorEventMessage(frame))
          : null,
      isTerminated: isAnthropicMessageStop,
      extractToken: extractAnthropicText,
    );
  }

  /// 组装 Messages API 请求体；temperature 接收但忽略（U-2），不携带该键。
  Map<String, dynamic> _buildBody(
    List<LlmMessage> messages, {
    required int maxTokens,
    String? model,
    bool streaming = false,
  }) {
    final prepared = prepareMessages(messages);
    return {
      'model': model ?? _defaultModel,
      'max_tokens': maxTokens,
      // 对齐锚 claude.py：system 缺省时传 []（顶层参数）。
      'system': (prepared.system == null || prepared.system!.isEmpty)
          ? const <Object>[]
          : prepared.system,
      'messages': [
        for (final m in prepared.chat) {'role': m.role, 'content': m.content},
      ],
      if (streaming) 'stream': true,
    };
  }

  /// 从 Messages API 非流式响应提取首个 text 块文本（锚 claude.py generate）。
  String _extractText(Object? data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('非标准响应结构（缺顶层对象）');
    }
    final content = data['content'];
    if (content is! List) {
      throw const FormatException('非标准响应结构（缺 content 列表）');
    }
    for (final block in content) {
      if (block is Map<String, dynamic> && block['type'] == 'text') {
        final text = block['text'];
        if (text is String) {
          return text;
        }
      }
    }
    return '';
  }

  Uri _messagesUri() {
    // F5：剥去 baseUrl 自带版本段（v1/v1beta），避免拼出 /v1/v1/messages。
    final base = normalizeClaudeBaseUrl(baseUrl) ?? _defaultEndpoint;
    return Uri.parse('$base/v1/messages');
  }

  Options _requestOptions() => Options(
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': kAnthropicVersion,
          'accept': 'application/json',
        },
        contentType: Headers.jsonContentType,
      );

  /// 提取 Anthropic error 事件负载中的 `error.message`（Claude 流内 error 事件独有）。
  String _errorEventMessage(SseFrame frame) {
    final decoded = decodeJson(frame.data);
    final error = decoded?['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    return frame.data;
  }
}

/// Anthropic 流内 `error` 事件原语（抛错终止，translateError 翻译进 LLM 族）。
class _StreamApiError implements Exception {
  _StreamApiError(this.message);

  final String message;
}
