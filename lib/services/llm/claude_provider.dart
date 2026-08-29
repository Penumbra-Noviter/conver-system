/// ClaudeProvider — Anthropic Messages API 原生双栈 wire（T02）。
///
/// - 非流式 [generate] 走 dio；流式 [streamGenerate] 走 dart:io HttpClient 直连
///   （设计文档双栈裁定：`research/stack-confirm/findings.md` R2）。
/// - POST `{base}/v1/messages`；`x-api-key` + `anthropic-version: 2023-06-01`
///   头（官方必需）；system 作顶层参数；`content_block_delta` 的 `text_delta`
///   逐 token 产出；`message_stop` 为终态；`ping` 忽略；`error` 事件抛错终止。
/// - **temperature 不透传**（R8 定案：Anthropic 官方已弃用 temperature，
///   Opus 4.6 后非 1.0 值 → HTTP 400），请求体不携带该键。
/// - 401/429/408/504 → Auth / RateLimit / Timeout；400 content_filter →
///   ContentFilter；连接失败 → LLM 族兜底；流中途断连（EOF 未到终态 / 连接重置）
///   → 可区分的 [LLMConnectionInterruptedError]（供 T03 断流处理）。
/// 锚：`desktop/backend/app/services/llm/claude.py` + `errors.dart::translateSdkError`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'errors.dart';
import 'llm_provider.dart';
import 'sse.dart';

/// 流在终态前中断（EOF 未到 message_stop / 连接重置）的可区分连接异常。
///
/// 继承 LLM 错误族（[LLMError]），translateError 直通不二次翻译；T03 断流处理
/// 以 `on LLMConnectionInterruptedError` 捕获并走「回复已中断」分支，区别于
/// 正常完成与鉴权 / 限流 / 超时等错误。
class LLMConnectionInterruptedError extends LLMError {
  LLMConnectionInterruptedError({super.originalError})
      : super('连接中断，回复未完成');
}

/// Anthropic 官方版本头（必需；research R1-1：`anthropic-version: 2023-06-01`）。
const String kAnthropicVersion = '2023-06-01';

/// Anthropic Claude 实现。
class ClaudeProvider extends LLMProvider {
  ClaudeProvider({required super.apiKey, super.baseUrl});

  static const String _providerName = 'Claude';
  static const String _defaultModel = 'claude-sonnet-5';
  static const String _defaultEndpoint = 'https://api.anthropic.com';

  /// 非流式 REST 客户端（T02 双栈：dio 侧）。
  final Dio _dio = Dio();

  @override
  LLMError translateError(Object error) {
    // 已映射为 LLM 族的错误（含连接中断类）直通，不二次翻译。
    if (error is LLMError) {
      return error;
    }
    if (error is DioException) {
      return _translateDio(error);
    }
    if (error is _HttpStatusError) {
      return _translateStatus(error.statusCode, error.body, cause: error);
    }
    if (error is _StreamApiError) {
      return translateSdkError(_providerName, message: error.message, cause: error);
    }
    if (error is SocketException) {
      // 连接阶段网络失败（拒绝 / DNS / 重置）→ LLM 族兜底，不穿透原始异常。
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
        _messagesUri().toString(),
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
      final request = await client.postUrl(_messagesUri());
      request.headers.contentType = ContentType.json;
      request.headers.set('accept', 'application/json');
      request.headers.set('x-api-key', apiKey);
      request.headers.set('anthropic-version', kAnthropicVersion);
      request.write(body);

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        // 非 SSE 错误体（HTTP 状态码 + 原文），交状态码翻译。
        final errorBody = await utf8.decoder.bind(response).join();
        throw _HttpStatusError(response.statusCode, errorBody);
      }

      var reachedMessageStop = false;
      final parser = SseParser();
      try {
        await for (final line
            in const LineSplitter().bind(utf8.decoder.bind(response))) {
          for (final frame in parser.feed(line)) {
            // 流内 error 事件（research R1-1：官方 SDK 抛错终止）。
            if (frame.event == 'error') {
              throw _StreamApiError(_errorEventMessage(frame));
            }
            if (isAnthropicMessageStop(frame)) {
              reachedMessageStop = true;
            }
            final token = extractAnthropicText(frame);
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
      // 流结束但未收到终态帧：可区分「连接中断」而非正常完成。
      if (!reachedMessageStop) {
        throw LLMConnectionInterruptedError();
      }
    } finally {
      // 无论正常 / 异常 / 消费方取消，都强制关闭连接避免泄漏。
      client.close(force: true);
    }
  }

  /// 组装 Messages API 请求体；temperature 不透传（R8），不携带该键。
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
    final raw = baseUrl?.trim() ?? '';
    final base = raw.isEmpty ? _defaultEndpoint : _stripTrailingSlash(raw);
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

  LLMError _translateDio(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return translateSdkError(
        _providerName,
        failure: LlmTransportFailure.timeout,
        cause: e,
      );
    }
    final status = e.response?.statusCode;
    if (status != null) {
      return _translateStatus(status, _responseText(e.response), cause: e);
    }
    return translateSdkError(
      _providerName,
      message: e.message ?? '${e.error ?? e}',
      cause: e,
    );
  }

  /// 状态码 → LLM 族：408 / 504（请求超时 / 网关超时）归 Timeout，
  /// 其余交 translateSdkError（401/429/400-content_filter 专属，其余兜底）。
  LLMError _translateStatus(int statusCode, String body, {required Object cause}) {
    if (statusCode == 408 || statusCode == 504) {
      return translateSdkError(
        _providerName,
        failure: LlmTransportFailure.timeout,
        message: body,
        cause: cause,
      );
    }
    return translateSdkError(
      _providerName,
      statusCode: statusCode,
      message: body,
      cause: cause,
    );
  }

  /// 从 dio 错误响应提取人类可读文本：优先 `error.message`（Map 或 JSON 文本
  /// 均可解出），否则返回原始体（字符串原样 / Map 序列化）。
  String _responseText(Response<dynamic>? response) {
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      final message = _errorMessageFromMap(data);
      if (message != null) {
        return message;
      }
      try {
        return jsonEncode(data);
      } on JsonUnsupportedObjectError {
        return '';
      }
    }
    if (data is String && data.isNotEmpty) {
      final decoded = _decodeJson(data);
      if (decoded != null) {
        final message = _errorMessageFromMap(decoded);
        if (message != null) {
          return message;
        }
      }
      return data;
    }
    return '';
  }

  /// 提取 Anthropic / OpenAI 通用错误体 `{"error":{"message":...}}` 的消息。
  String? _errorMessageFromMap(Map<String, dynamic> data) {
    final error = data['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  /// 提取 Anthropic error 事件负载中的 `error.message`。
  String _errorEventMessage(SseFrame frame) {
    final decoded = _decodeJson(frame.data);
    final error = decoded?['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    return frame.data;
  }

  Map<String, dynamic>? _decodeJson(String data) {
    try {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

/// wire 层 HTTP 状态错误原语（流式路径抛出，translateError 统一翻译）。
class _HttpStatusError implements Exception {
  _HttpStatusError(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// Anthropic 流内 `error` 事件原语（抛错终止，translateError 翻译进 LLM 族）。
class _StreamApiError implements Exception {
  _StreamApiError(this.message);

  final String message;
}
