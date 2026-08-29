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
        throw HttpStatusError(response.statusCode, errorBody);
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
