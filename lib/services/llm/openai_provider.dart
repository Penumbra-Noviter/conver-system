/// OpenAIProvider — OpenAI Chat Completions 原生双栈 wire（T02）。
///
/// - 非流式 [generate] 走 dio；流式 [streamGenerate] 走 dart:io HttpClient 直连
///   （设计文档双栈裁定：`research/stack-confirm/findings.md` R2）。
/// - POST `{normalizedBase}/chat/completions`（[normalizeBaseUrl] 补 `/v1` 段）；
///   `Authorization: Bearer <key>` 头；temperature **照传**（R8 定案：与 Claude
///   相反，OpenAI 端点接受 temperature，默认 0.7 逐字透传）；
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
import 'dart:io';

import 'package:dio/dio.dart';

import 'errors.dart';
import 'llm_provider.dart';
import 'sse.dart';
import 'translate_helpers.dart';

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
    this.temperature = 0.7,
  });

  static const String _providerName = 'OpenAI';
  static const String _defaultModel = 'gpt-4o';
  static const String _defaultNormalizedBase = 'https://api.openai.com/v1';

  /// 采样温度（R8：OpenAI 侧照传）。默认 0.7 对齐桌面 openai.py generate 参数。
  final double temperature;

  /// 非流式 REST 客户端（T02 双栈：dio 侧）。
  final Dio _dio = Dio();

  @override
  LLMError translateError(Object error) {
    // 已映射为 LLM 族的错误（含连接中断类）直通，不二次翻译。
    if (error is LLMError) {
      return error;
    }
    if (error is DioException) {
      return translateDioError(_providerName, error);
    }
    if (error is HttpStatusError) {
      return translateStatusError(
        _providerName,
        error.statusCode,
        error.body,
        cause: error,
      );
    }
    if (error is SocketException) {
      return translateSdkError(
        _providerName,
        message: error.message,
        cause: error,
      );
    }
    if (error is HttpException) {
      return translateSdkError(
        _providerName,
        message: error.message,
        cause: error,
      );
    }
    if (error is FormatException || error is TypeError) {
      return translateSdkError(
        _providerName,
        failure: LlmTransportFailure.responseParse,
        message: '$error',
        cause: error,
      );
    }
    return translateSdkError(_providerName, message: '$error', cause: error);
  }

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  }) {
    return runTranslated(() async {
      final body = _buildBody(messages, maxTokens: maxTokens, model: model);
      final response = await _dio.post(
        _chatCompletionsUri().toString(),
        data: body,
        options: _requestOptions(),
      );
      return _extractText(response.data);
    });
  }

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  }) async* {
    try {
      // 注意不用 yield*：Dart 语义下 yield* 将内层流错误直接转发到外层流，
      // 不经外层 try/catch；await for 则将错误在其语句处抛出、可被捕获翻译。
      await for (final token in _streamRequest(messages,
          maxTokens: maxTokens, model: model)) {
        yield token;
      }
    } catch (e) {
      throw translateError(e);
    }
  }

  /// 流式请求体：POST + SSE 消费，逐 token 产出。
  Stream<String> _streamRequest(
    List<LlmMessage> messages, {
    required int maxTokens,
    String? model,
  }) async* {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final body = jsonEncode(
        _buildBody(messages, maxTokens: maxTokens, model: model, streaming: true),
      );
      final request = await client.postUrl(_chatCompletionsUri());
      request.headers.contentType = ContentType.json;
      request.headers.set('authorization', 'Bearer $apiKey');
      request.write(body);

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        // 非 SSE 错误体（HTTP 状态码 + 原文），交状态码翻译。
        final errorBody = await utf8.decoder.bind(response).join();
        throw HttpStatusError(response.statusCode, errorBody);
      }

      var reachedDone = false;
      final parser = SseParser();
      try {
        await for (final line
            in const LineSplitter().bind(utf8.decoder.bind(response))) {
          for (final frame in parser.feed(line)) {
            if (isOpenAiDone(frame)) {
              reachedDone = true;
            }
            final token = extractOpenAiText(frame);
            if (token != null) {
              yield token;
            }
          }
        }
      } on SocketException catch (e) {
        throw LLMConnectionInterruptedError(originalError: e);
      } on HttpException catch (e) {
        throw LLMConnectionInterruptedError(originalError: e);
      }
      // 流结束但未收到 [DONE]：可区分「连接中断」而非正常完成。
      if (!reachedDone) {
        throw LLMConnectionInterruptedError();
      }
    } finally {
      // 无论正常 / 异常 / 消费方取消，都强制关闭连接避免泄漏。
      client.close(force: true);
    }
  }

  /// 组装 Chat Completions 请求体；temperature 照传（默认 0.7）。
  Map<String, dynamic> _buildBody(
    List<LlmMessage> messages, {
    required int maxTokens,
    String? model,
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