/// OpenAIProvider — OpenAI Chat Completions 原生双栈 wire（T02）。
///
/// - 非流式 [generate] 走 dio；流式 [streamGenerate] 走 dart:io HttpClient 直连
///   （设计文档双栈裁定：`research/stack-confirm/findings.md` R2）。
/// - POST `{normalizedBase}/chat/completions`（[normalizeBaseUrl] 补 `/v1` 段）；
///   `Authorization: Bearer <key>` 头；temperature **照传**（U-2：由
///   generate/streamGenerate 的 `temperature` 参数驱动，缺省 0.7 逐字透传）；
///   `choices[0].delta.content` 逐 token 产出（null / 空 choices 跳过，锚
///   research R1-2）；`[DONE]` 终态。
/// - 401/429/408/504 → Auth / RateLimit / Timeout；400 content_filter →
///   ContentFilter；连接失败 → LLM 族兜底；流中途断连（[DONE] 前 EOF / 连接重置）
///   → 可区分的 [LLMConnectionInterruptedError]（与 Claude wire 共享，errors.dart
///   中定义，供 T03 断流处理统一捕获）。
/// 锚：`desktop/backend/app/services/llm/openai.py` + `errors.dart::translateSdkError`。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'errors.dart';
import 'llm_provider.dart';
import 'sse.dart';
import 'stream_wire.dart';

/// 规范化 OpenAI 兼容端点地址（锚 `desktop/backend/app/services/llm/openai.py`
/// `_normalize_base_url`）。
///
/// 用户常只填面板根地址（如 `https://api.example.com`），补 `/v1` 版本段；
/// 末尾段已含版本段（`v1` / `v1beta` 等形式：`v\d+(beta)?`）则原样返回；
/// 空值返回 null（由 provider 回退官方默认端点）。
String? normalizeBaseUrl(String? baseUrl) {
  if (baseUrl == null || baseUrl.trim().isEmpty) {
    return null;
  }
  final url = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final lastSegment = url.split('/').last;
  if (RegExp(r'^v\d+(beta)?$').hasMatch(lastSegment)) {
    return url;
  }
  return '$url/v1';
}

/// OpenAI / OpenAI 兼容端点实现。
class OpenAIProvider extends LLMProvider {
  OpenAIProvider({
    required super.apiKey,
    super.baseUrl,
  });

  @override
  String get providerName => 'OpenAI';

  static const String _defaultModel = 'gpt-4o';
  static const String _defaultNormalizedBase = 'https://api.openai.com/v1';

  /// 非流式 REST 客户端（T02 双栈：dio 侧）。
  final Dio _dio = Dio();

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) {
    return runTranslated(() async {
      final body = _buildBody(messages,
          maxTokens: maxTokens, model: model, temperature: temperature);
      final response = await _dio.post(
        _chatCompletionsUri().toString(),
        data: body,
        options: _requestOptions(),
      );
      return _extractText(response.data);
    });
  }

  /// OpenAI 流式 wire 扩展点（protected 语义，基类默认 [LLMProvider.streamGenerate]
  /// 承载错误翻译骨架）：POST + SSE 消费，逐 token 产出（共享骨架 [streamSse]，
  /// 本方法只提供 OpenAI 差异面：端点 / 头 / 终态帧 / 帧提取；无流内错误帧
  /// 语义 → [streamSse.errorFrameException] 缺省 null）。[temperature] 照传。
  @override
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) async* {
    yield* streamSse(
      uri: _chatCompletionsUri(),
      body: jsonEncode(
        _buildBody(messages,
            maxTokens: maxTokens,
            model: model,
            temperature: temperature,
            streaming: true),
      ),
      headers: {'authorization': 'Bearer $apiKey'},
      isTerminated: isOpenAiDone,
      extractToken: extractOpenAiText,
    );
  }

  /// 组装 Chat Completions 请求体；temperature 照传（U-2：取传入参数，缺省 0.7）。
  Map<String, dynamic> _buildBody(
    List<LlmMessage> messages, {
    required int maxTokens,
    String? model,
    double temperature = 0.7,
    bool streaming = false,
  }) {
    final prepared = prepareMessages(messages);
    final chat = <Map<String, dynamic>>[
      for (final m in prepared.chat) {'role': m.role, 'content': m.content},
    ];
    // 对齐锚 openai.py：system 包裹回 {"role":"system"} 并插到最前。
    if (prepared.system != null && prepared.system!.isNotEmpty) {
      chat.insert(0, {'role': 'system', 'content': prepared.system});
    }
    return {
      'model': model ?? _defaultModel,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'messages': chat,
      if (streaming) 'stream': true,
    };
  }

  /// 从 Chat Completions 非流式响应提取 `choices[0].message.content`。
  /// 结构异常抛 [FormatException]（→ responseParse LLM 族）；内容缺失返回空串。
  String _extractText(Object? data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('非标准响应结构（缺顶层对象）');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('非标准响应结构（缺 choices 列表）');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const FormatException('非标准响应结构（choices 条目非对象）');
    }
    final message = first['message'];
    if (message is Map<String, dynamic>) {
      final content = message['content'];
      if (content is String) {
        return content;
      }
    }
    return '';
  }

  Uri _chatCompletionsUri() {
    final normalized = normalizeBaseUrl(baseUrl) ?? _defaultNormalizedBase;
    return Uri.parse('$normalized/chat/completions');
  }

  Options _requestOptions() => Options(
        headers: {
          'authorization': 'Bearer $apiKey',
          'accept': 'application/json',
        },
        contentType: Headers.jsonContentType,
      );
}