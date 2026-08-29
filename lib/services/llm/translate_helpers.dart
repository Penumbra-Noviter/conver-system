/// 双 provider（Claude / OpenAI）共享的错误翻译栈（T4 / F-14 抽取）。
///
/// 承载 DioException 分类、408/504 状态码特判、响应文本提取、
/// `{"error":{"message":…}}` JSON 错误体解析、容错 decodeJson 与
/// [HttpStatusError] 单实例化——此前在 `claude_provider.dart` 与
/// `openai_provider.dart` 中约 120 行逐字重复，现收敛为单一来源。
///
/// 依赖契约：本模块引入 dio（持有 `DioException` / `Response` 类型）与
/// `errors.dart`；`errors.dart` 保持零 dio 依赖，不反向引入本模块。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'errors.dart';

/// wire 层 HTTP 状态错误原语（流式路径抛出，translateError 统一翻译）。
///
/// 取代两 provider 各自私有的 `_HttpStatusError`，单一定义共享。
class HttpStatusError implements Exception {
  HttpStatusError(this.statusCode, this.body);

  /// HTTP 状态码。
  final int statusCode;

  /// 非 SSE 错误体原文。
  final String body;
}

/// 分类 DioException 并翻译为 LLM 错误族（对齐原 provider `_translateDio`）。
///
/// - timeout 族（connection / send / receive）→ [LlmTransportFailure.timeout]；
/// - 携带 HTTP 状态码 → 交 [translateStatusError]（含 408/504 特判）；
/// - 其余（连接失败 / 无响应）→ LLM 族兜底（消息带 dio message 或 error）。
LLMError translateDioError(String providerName, DioException e) {
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return translateSdkError(
      providerName,
      failure: LlmTransportFailure.timeout,
      cause: e,
    );
  }
  final status = e.response?.statusCode;
  if (status != null) {
    return translateStatusError(
      providerName,
      status,
      responseText(e.response),
      cause: e,
    );
  }
  return translateSdkError(
    providerName,
    message: e.message ?? '${e.error ?? e}',
    cause: e,
  );
}

/// 状态码 → LLM 族：408 / 504（请求超时 / 网关超时）归 Timeout，
/// 其余交 translateSdkError（401/429/400-content_filter 专属，其余兜底）。
///
/// 对齐原 provider `_translateStatus` 逐字语义。
LLMError translateStatusError(
  String providerName,
  int statusCode,
  String body, {
  required Object cause,
}) {
  if (statusCode == 408 || statusCode == 504) {
    return translateSdkError(
      providerName,
      failure: LlmTransportFailure.timeout,
      message: body,
      cause: cause,
    );
  }
  return translateSdkError(
    providerName,
    statusCode: statusCode,
    message: body,
    cause: cause,
  );
}

/// 从 dio 错误响应提取人类可读文本：优先 `error.message`（Map 或 JSON 文本
/// 均可解出），否则返回原始体（字符串原样 / Map 序列化）。
///
/// 对齐原 provider `_responseText` 逐字语义。
String responseText(Response<dynamic>? response) {
  final data = response?.data;
  if (data is Map<String, dynamic>) {
    final message = errorMessageFromMap(data);
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
    final decoded = decodeJson(data);
    if (decoded != null) {
      final message = errorMessageFromMap(decoded);
      if (message != null) {
        return message;
      }
    }
    return data;
  }
  return '';
}

/// 提取 Anthropic / OpenAI 通用错误体 `{"error":{"message":...}}` 的消息。
///
/// 对齐原 provider `_errorMessageFromMap` 逐字语义。
String? errorMessageFromMap(Map<String, dynamic> data) {
  final error = data['error'];
  if (error is Map<String, dynamic>) {
    final message = error['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
  }
  return null;
}

/// 容错 JSON 解析：仅当解码结果为 JSON 对象时返回，非 JSON / 非对象返回 null。
///
/// 对齐原 provider `_decodeJson` 容错语义（不抛异常）。
Map<String, dynamic>? decodeJson(String data) {
  try {
    final decoded = jsonDecode(data);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
