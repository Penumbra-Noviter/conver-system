/// LLM 错误族 + 领域错误族 + 传输异常翻译（工单 01b 验收 A：错误面）。
///
/// 锚文本逐字对齐（只读权威源）：
/// - `desktop/backend/app/services/llm/errors.py::translate_sdk_error`（LLM 族模板）
/// - `desktop/backend/app/services/exceptions.py` + `services/chat.py` +
///   `services/llm/resolver.py`（领域族模板）
library;

import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LLMError 基类', () {
    test('持 message 与 originalError，toString 返回 message', () {
      final cause = Exception('root');
      final error = LLMError('Claude API 调用失败: boom', originalError: cause);
      expect(error.message, 'Claude API 调用失败: boom');
      expect(error.originalError, same(cause));
      expect(error.toString(), 'Claude API 调用失败: boom');
    });

    test('LLM 族子类统一 isA<LLMError>', () {
      expect(LLMAuthError('Claude'), isA<LLMError>());
      expect(LLMRateLimitError('OpenAI'), isA<LLMError>());
      expect(LLMTimeoutError('Claude'), isA<LLMError>());
      expect(LLMContentFilterError('Claude'), isA<LLMError>());
      expect(LLMBadRequestError('OpenAI', 'bad'), isA<LLMError>());
      expect(LLMResponseParseFailedError('OpenAI', 'oops'), isA<LLMError>());
    });
  });

  group('LLMError 子类消息模板（逐字对齐 errors.py）', () {
    test('LLMAuthError「{provider} API Key 无效或未配置」', () {
      expect(LLMAuthError('Claude').message, 'Claude API Key 无效或未配置');
    });

    test('LLMRateLimitError「{provider} API 请求频率超限」', () {
      expect(LLMRateLimitError('OpenAI').message, 'OpenAI API 请求频率超限');
    });

    test('LLMTimeoutError「{provider} API 请求超时」', () {
      expect(LLMTimeoutError('Claude').message, 'Claude API 请求超时');
    });

    test('LLMContentFilterError「内容被 {provider} 内容过滤器拦截」', () {
      expect(
        LLMContentFilterError('OpenAI').message,
        '内容被 OpenAI 内容过滤器拦截',
      );
    });

    test('LLMBadRequestError「{provider} API 请求错误: {error}」', () {
      expect(
        LLMBadRequestError('OpenAI', 'model not found').message,
        'OpenAI API 请求错误: model not found',
      );
    });

    test('LLMResponseParseFailedError 含「请检查 API 地址是否为兼容 {provider} 协议的端点」', () {
      expect(
        LLMResponseParseFailedError('OpenAI', 'no choices').message,
        'OpenAI API 返回格式异常：no choices。'
        '请检查 API 地址是否为兼容 OpenAI 协议的端点（应返回标准响应结构）',
      );
    });
  });

  group('translateSdkError — 传输原语 → LLM 族（分支语义对齐 errors.py）', () {
    test('HTTP 401 → LLMAuthError', () {
      final error = translateSdkError('Claude', statusCode: 401, message: 'invalid x-api-key');
      expect(error, isA<LLMAuthError>());
      expect(error.message, 'Claude API Key 无效或未配置');
    });

    test('HTTP 429 → LLMRateLimitError', () {
      final error = translateSdkError('OpenAI', statusCode: 429, message: 'Rate limit');
      expect(error, isA<LLMRateLimitError>());
      expect(error.message, 'OpenAI API 请求频率超限');
    });

    test('failure=timeout → LLMTimeoutError（无状态码）', () {
      final error = translateSdkError(
        'Claude',
        message: 'Connection timed out',
        failure: LlmTransportFailure.timeout,
      );
      expect(error, isA<LLMTimeoutError>());
      expect(error.message, 'Claude API 请求超时');
    });

    test('HTTP 400 且 message 含 content_filter → LLMContentFilterError（大小写不敏感）', () {
      final error = translateSdkError(
        'OpenAI',
        statusCode: 400,
        message: 'rejected as a result of our safety system (Content_Filter)',
      );
      expect(error, isA<LLMContentFilterError>());
      expect(error.message, '内容被 OpenAI 内容过滤器拦截');
    });

    test('HTTP 400 其他原因 → LLMBadRequestError', () {
      final error =
          translateSdkError('Claude', statusCode: 400, message: 'temperature 2.0 invalid');
      expect(error, isA<LLMBadRequestError>());
      expect(error.message, 'Claude API 请求错误: temperature 2.0 invalid');
    });

    test('failure=responseParse → LLMResponseParseFailedError', () {
      final error = translateSdkError(
        'OpenAI',
        message: 'has no attribute choices',
        failure: LlmTransportFailure.responseParse,
      );
      expect(error, isA<LLMResponseParseFailedError>());
      expect(
        error.message,
        'OpenAI API 返回格式异常：has no attribute choices。'
        '请检查 API 地址是否为兼容 OpenAI 协议的端点（应返回标准响应结构）',
      );
    });

    test('HTTP 5xx → Generic LLMError 兜底', () {
      final error = translateSdkError('Claude', statusCode: 500, message: 'overloaded');
      expect(error, isA<LLMError>());
      expect(error, isNot(isA<LLMAuthError>()));
      expect(error, isNot(isA<LLMRateLimitError>()));
      expect(error, isNot(isA<LLMTimeoutError>()));
      expect(error, isNot(isA<LLMContentFilterError>()));
      expect(error, isNot(isA<LLMBadRequestError>()));
      expect(error, isNot(isA<LLMResponseParseFailedError>()));
      expect(error.message, 'Claude API 调用失败: overloaded');
    });

    test('非 400/401/429 的 4xx（403/404/422）→ Generic 兜底（对齐桌面 SDK 类语义）', () {
      for (final code in [403, 404, 422]) {
        final error = translateSdkError('Claude', statusCode: code, message: 'nope');
        expect(error, isA<LLMError>(), reason: 'code=$code 应为兜底');
        expect(error, isNot(isA<LLMBadRequestError>()));
        expect(error.message, 'Claude API 调用失败: nope');
      }
    });

    test('无任何分类信号 → Generic 兜底', () {
      final error = translateSdkError('OpenAI', message: 'connection refused');
      expect(error, isA<LLMError>());
      expect(error.message, 'OpenAI API 调用失败: connection refused');
    });

    test('message 为空时兜底落到 cause', () {
      final cause = Exception('SocketException: refused');
      final error = translateSdkError('Claude', cause: cause);
      expect(error.message, 'Claude API 调用失败: Exception: SocketException: refused');
    });

    test('originalError 透传至 LLM 族结果', () {
      final cause = Exception('root');
      final error = translateSdkError('Claude', statusCode: 401, cause: cause);
      expect(error.originalError, same(cause));
    });
  });

  group('DomainError 基类', () {
    test('领域族子类统一 isA<DomainError>', () {
      expect(ApiKeyMissingError('Claude'), isA<DomainError>());
      expect(ProviderNotSupportedError('foo'), isA<DomainError>());
      expect(InvalidRegenerateTargetError.noAssistantReply(), isA<DomainError>());
      expect(InvalidRegenerateTargetError.notAssistant(), isA<DomainError>());
      expect(InvalidRegenerateTargetError.noTriggerUser(), isA<DomainError>());
      expect(ConversationNotFoundError(), isA<DomainError>());
      expect(MessageNotFoundError(), isA<DomainError>());
    });

    test('toString 返回 message', () {
      expect(ConversationNotFoundError().toString(), '对话不存在');
    });
  });

  group('领域错误族消息模板（逐字对齐 exceptions.py / chat.py / resolver.py）', () {
    test('ApiKeyMissingError「未配置 {provider} API Key，请在设置中填写」', () {
      expect(
        ApiKeyMissingError('Claude').message,
        '未配置 Claude API Key，请在设置中填写',
      );
    });

    test('ProviderNotSupportedError「不支持的 Provider: {provider}」', () {
      expect(ProviderNotSupportedError('foo').message, '不支持的 Provider: foo');
    });

    test('InvalidRegenerateTargetError 三种文案', () {
      expect(
        InvalidRegenerateTargetError.noAssistantReply().message,
        '没有可重生成的 AI 回复',
      );
      expect(InvalidRegenerateTargetError.notAssistant().message, '只能重生成 AI 回复');
      expect(
        InvalidRegenerateTargetError.noTriggerUser().message,
        '没有可重生成的用户消息',
      );
    });

    test('ConversationNotFoundError「对话不存在」', () {
      expect(ConversationNotFoundError().message, '对话不存在');
    });

    test('MessageNotFoundError「消息不存在」', () {
      expect(MessageNotFoundError().message, '消息不存在');
    });
  });
}