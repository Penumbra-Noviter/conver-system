/// OpenAI wire（工单 02 验收：Chat Completions 双栈 wire + _normalize_base_url）。
///
/// 经 FakeLlmServer 验证：
/// - 非流式 generate 走 dio；流式 streamGenerate 走 dart:io HttpClient 直连；
/// - POST {base}/v1/chat/completions、Bearer 头、temperature 透传、
///   choices[0].delta.content 逐 token（null 跳过）、[DONE] 收束；
/// - [normalizeBaseUrl] 末尾段 v1 / v1beta 原样、否则补 /v1、空值返回 null；
/// - 401/429/408/504/连接拒绝 → LLM 族；[DONE] 前 EOF / 连接重置 →
///   LLMConnectionInterruptedError；零 token 正常完成不抛错。
/// 锚：`desktop/backend/app/services/llm/openai.py`（_normalize_base_url /
/// temperature 透传）+ `errors.dart::translateSdkError`。
library;

import 'dart:io';

import 'package:conver_system_mobile/services/llm/claude_provider.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/llm/openai_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_llm_server.dart';

void main() {
  const apiKey = 'test-key';

  final setUpServer = <FakeLlmServer>{};
  tearDown(() async {
    for (final server in setUpServer.toList()) {
      await server.close();
      setUpServer.remove(server);
    }
  });

  FakeLlmServer server(FakeLlmHandler handler) {
    final server = FakeLlmServer(handler);
    setUpServer.add(server);
    return server;
  }

  Future<FakeLlmServer> startedServer(FakeLlmHandler handler) async {
    final srv = server(handler);
    await srv.start();
    return srv;
  }

  OpenAIProvider makeProvider(FakeLlmServer server, {double temperature = 0.7}) =>
      OpenAIProvider(
          apiKey: apiKey, baseUrl: server.baseUrl, temperature: temperature);

  const messages = [
    LlmMessage(role: 'system', content: 'You are helpful'),
    LlmMessage(role: 'user', content: 'hi'),
    LlmMessage(role: 'assistant', content: 'hello'),
  ];

  group('normalizeBaseUrl（锚 openai.py::_normalize_base_url）', () {
    test('空值 / null → null', () {
      expect(normalizeBaseUrl(null), isNull);
      expect(normalizeBaseUrl(''), isNull);
      expect(normalizeBaseUrl('   '), isNull);
    });

    test('末尾段 v1 → 原样', () {
      expect(normalizeBaseUrl('https://api.example.com/v1'),
          'https://api.example.com/v1');
    });

    test('末尾段 v1beta → 原样', () {
      expect(normalizeBaseUrl('https://api.example.com/v1beta'),
          'https://api.example.com/v1beta');
      expect(normalizeBaseUrl('https://api.deepseek.com/v2beta'),
          'https://api.deepseek.com/v2beta');
    });

    test('末尾段非版本段 → 补 /v1', () {
      expect(normalizeBaseUrl('https://api.example.com'),
          'https://api.example.com/v1');
      expect(normalizeBaseUrl('https://api.example.com/custom'),
          'https://api.example.com/custom/v1');
    });

    test('末尾斜杠剥离后再判定（补 /v1 / 原样）', () {
      expect(normalizeBaseUrl('https://api.example.com/'),
          'https://api.example.com/v1');
      expect(normalizeBaseUrl('https://api.example.com/v1/'),
          'https://api.example.com/v1');
      expect(normalizeBaseUrl('https://api.example.com/v1beta/'),
          'https://api.example.com/v1beta');
    });

    test('多段路径：仅看最后一段', () {
      expect(normalizeBaseUrl('https://api.example.com/relay/openai/v1'),
          'https://api.example.com/relay/openai/v1');
      expect(normalizeBaseUrl('https://gateway.example.com/x/proxy'),
          'https://gateway.example.com/x/proxy/v1');
    });
  });

  group('generate 非流式（dio）— 成功路径', () {
    test('choices[0].message.content 提取 + wire 逐字段', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse({
        'id': 'chatcmpl-1',
        'object': 'chat.completion',
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': 'Hello world'},
            'finish_reason': 'stop',
          },
        ],
      }));

      final result = await makeProvider(server).generate(messages: messages);
      expect(result, 'Hello world');

      final captured = server.captured.single;
      expect(captured.method, 'POST');
      expect(captured.path, '/v1/chat/completions');
      expect(captured.headers['authorization'], 'Bearer $apiKey');
      expect(captured.headers['content-type'], contains('application/json'));

      final body = captured.jsonBody!;
      expect(body['model'], 'gpt-4o');
      expect(body['temperature'], 0.7);
      expect(body['max_tokens'], 2048);
      // system 包裹回 {"role":"system"} 并插到最前（锚 openai.py generate）。
      expect(body['messages'], [
        {'role': 'system', 'content': 'You are helpful'},
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
      ]);
    });

    test('content 缺失 / 空 → 空串（对齐锚 content or ""）', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse({
        'choices': [
          {'index': 0, 'message': {'role': 'assistant'}, 'finish_reason': 'stop'},
        ],
      }));
      expect(await makeProvider(server).generate(messages: messages), '');
    });

    test('无 system 时消息列表不插 system', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse({
        'choices': [
          {'index': 0, 'message': {'role': 'assistant', 'content': 'x'}},
        ],
      }));
      await makeProvider(server).generate(messages: const [
        LlmMessage(role: 'user', content: 'u'),
      ]);
      expect(server.captured.single.jsonBody!['messages'], [
        {'role': 'user', 'content': 'u'},
      ]);
    });

    test('temperature 透传（R8：OpenAI 侧照传，可配置默认 0.7）', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse({
        'choices': [
          {'message': {'role': 'assistant', 'content': 'x'}},
        ],
      }));
      await makeProvider(server, temperature: 0.9).generate(messages: messages);
      expect(server.captured.single.jsonBody!['temperature'], 0.9);
    });
  });

  group('generate 非流式 — HTTP 状态码 → LLM 族', () {
    Future<LLMError> errorOf(FakeLlmHandler handler) async {
      final server = await startedServer(handler);
      try {
        await makeProvider(server).generate(messages: messages);
        fail('应抛出 LLM 族错误');
      } on LLMError catch (e) {
        return e;
      }
    }

    test('401 → LLMAuthError', () async {
      final e = await errorOf(FakeLlmServer.httpError(401,
          body: '{"error":{"message":"Incorrect API key"}}'));
      expect(e, isA<LLMAuthError>());
      expect(e.message, 'OpenAI API Key 无效或未配置');
    });

    test('429 → LLMRateLimitError', () async {
      final e = await errorOf(FakeLlmServer.httpError(429,
          body: '{"error":{"message":"Rate limit reached"}}'));
      expect(e, isA<LLMRateLimitError>());
      expect(e.message, 'OpenAI API 请求频率超限');
    });

    test('408 → LLMTimeoutError', () async {
      final e = await errorOf(FakeLlmServer.httpError(408));
      expect(e, isA<LLMTimeoutError>());
    });

    test('504 → LLMTimeoutError', () async {
      final e = await errorOf(FakeLlmServer.httpError(504));
      expect(e, isA<LLMTimeoutError>());
    });

    test('连接拒绝（端口关闭）→ LLM 族兜底', () async {
      final server = await startedServer(FakeLlmServer.httpError(200));
      final baseUrl = server.baseUrl;
      await server.close();
      setUpServer.remove(server);
      try {
        await OpenAIProvider(apiKey: apiKey, baseUrl: baseUrl)
            .generate(messages: messages);
        fail('应抛出 LLM 族错误');
      } on LLMError catch (e) {
        expect(e.message, startsWith('OpenAI API 调用失败:'));
      }
    });

    test('400 JSON Map 体无 error.message → BadRequest 带原始 JSON', () async {
      final e = await errorOf(
        FakeLlmServer.jsonResponse({'foo': 'bar'}, statusCode: 400),
      );
      expect(e, isA<LLMBadRequestError>());
      expect(e.message, 'OpenAI API 请求错误: {"foo":"bar"}');
    });

    test('400 体非 JSON 文本 → BadRequest 带原文', () async {
      final e = await errorOf(FakeLlmServer.httpError(400, body: 'not-json'));
      expect(e, isA<LLMBadRequestError>());
      expect(e.message, 'OpenAI API 请求错误: not-json');
    });

    test('200 非标准成功体（缺 choices）→ LLMResponseParseFailedError', () async {
      final e = await errorOf(FakeLlmServer.jsonResponse({'id': 'cmpl-x'}));
      expect(e, isA<LLMResponseParseFailedError>());
      expect(e.message, startsWith('OpenAI API 返回格式异常：'));
      expect(e.message, contains('兼容 OpenAI'));
    });
  });

  group('streamGenerate 流式（dart:io）— 成功路径', () {
    test('delta.content 逐 token 产出，[DONE] 收束（含 null 跳过）', () async {
      final server = await startedServer(
        FakeLlmServer.openAi(['Hello', ', ', 'world'], withUsageChunk: true),
      );

      final tokens =
          await makeProvider(server).streamGenerate(messages: messages).toList();

      // role 初始化 chunk（content:null）、usage chunk（choices 空）均被跳过。
      expect(tokens, ['Hello', ', ', 'world']);
    });

    test('wire 逐字段：路径 / Bearer / temperature / stream:true', () async {
      final server = await startedServer(FakeLlmServer.openAi(['ok']));
      await makeProvider(server).streamGenerate(messages: messages).toList();

      final captured = server.captured.single;
      expect(captured.path, '/v1/chat/completions');
      expect(captured.headers['authorization'], 'Bearer $apiKey');
      final body = captured.jsonBody!;
      expect(body['stream'], isTrue);
      expect(body['temperature'], 0.7);
      expect(body['messages'], [
        {'role': 'system', 'content': 'You are helpful'},
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
      ]);
    });

    test('零 token 正常完成：[DONE] 已收、无 token、不抛错', () async {
      final server = await startedServer(FakeLlmServer.openAi(const []));
      final tokens =
          await makeProvider(server).streamGenerate(messages: messages).toList();
      expect(tokens, isEmpty);
    });

    test('base_url 已含 /v1 时路径仍为 /v1/chat/completions', () async {
      final server = await startedServer(FakeLlmServer.openAi(['ok']));
      await OpenAIProvider(apiKey: apiKey, baseUrl: '${server.baseUrl}/v1')
          .streamGenerate(messages: messages)
          .toList();
      expect(server.captured.single.path, '/v1/chat/completions');
    });

    test('base_url 已含 /v1beta 时路径为 /v1beta/chat/completions', () async {
      final server = await startedServer(FakeLlmServer.openAi(['ok']));
      await OpenAIProvider(apiKey: apiKey, baseUrl: '${server.baseUrl}/v1beta')
          .streamGenerate(messages: messages)
          .toList();
      expect(server.captured.single.path, '/v1beta/chat/completions');
    });
  });

  group('streamGenerate 流式 — HTTP 状态码 → LLM 族', () {
    Future<LLMError> errorOf(FakeLlmHandler handler) async {
      final server = await startedServer(handler);
      try {
        await makeProvider(server).streamGenerate(messages: messages).toList();
        fail('应抛出 LLM 族错误');
      } on LLMError catch (e) {
        return e;
      }
    }

    test('401 → LLMAuthError', () async {
      final e = await errorOf(FakeLlmServer.httpError(401, body: '{"error":{}}'));
      expect(e, isA<LLMAuthError>());
      expect(e.message, 'OpenAI API Key 无效或未配置');
    });

    test('429 → LLMRateLimitError', () async {
      final e = await errorOf(FakeLlmServer.httpError(429, body: '{"error":{}}'));
      expect(e, isA<LLMRateLimitError>());
    });

    test('504 → LLMTimeoutError', () async {
      final e = await errorOf(FakeLlmServer.httpError(504));
      expect(e, isA<LLMTimeoutError>());
    });

    test('连接拒绝（端口关闭）→ LLM 族兜底（SocketException 不穿透）', () async {
      final server = await startedServer(FakeLlmServer.httpError(200));
      final baseUrl = server.baseUrl;
      await server.close();
      setUpServer.remove(server);

      try {
        await OpenAIProvider(apiKey: apiKey, baseUrl: baseUrl)
            .streamGenerate(messages: messages)
            .toList();
        fail('应抛出 LLM 族错误');
      } on LLMError catch (e) {
        expect(e.message, startsWith('OpenAI API 调用失败:'));
      } on SocketException {
        fail('流式连接拒绝的 SocketException 必须经 translateError 进入 LLM 族');
      }
    });
  });

  group('streamGenerate 流式 — 断连可区分异常（供 T03 断流处理）', () {
    test('[DONE] 前 EOF → LLMConnectionInterruptedError', () async {
      final server = await startedServer(
        FakeLlmServer.openAi(['partial'], withDone: false),
      );
      await expectLater(
        makeProvider(server).streamGenerate(messages: messages).toList(),
        throwsA(isA<LLMConnectionInterruptedError>()),
      );
    });

    test('流中途连接重置 → LLMConnectionInterruptedError（不穿透原始异常）', () async {
      final reset = FakeResetServer(
        body: 'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'
            'data: {"choices":[{"delta":{"content":" reset"}}]}\n\n',
      );
      await reset.start();
      addTearDown(reset.close);

      await expectLater(
        OpenAIProvider(apiKey: apiKey, baseUrl: reset.baseUrl)
            .streamGenerate(messages: messages)
            .toList(),
        throwsA(isA<LLMConnectionInterruptedError>()),
      );
    });
  });

  group('translateError 错误翻译原语契约（Falsify：原始异常不得穿透）', () {
    OpenAIProvider provider() => OpenAIProvider(apiKey: apiKey);

    test('HttpException → LLM 族兜底（消息带原文）', () {
      final e = provider().translateError(HttpException('Connection reset'));
      expect(e, isA<LLMError>());
      expect(e.message, 'OpenAI API 调用失败: Connection reset');
    });

    test('未分类异常（StateError）→ LLM 族兜底', () {
      final e = provider().translateError(StateError('boom'));
      expect(e, isA<LLMError>());
      expect(e.message, 'OpenAI API 调用失败: Bad state: boom');
    });

    test('已映射 LLMError 直通不二次翻译', () {
      final original = LLMAuthError('OpenAI');
      final e = provider().translateError(original);
      expect(e, same(original));
    });
  });

  group('testConnection 默认最小生成（锚 base.py）', () {
    test('max_tokens=1、消息为 ping、成功不抛错', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse({
        'choices': [
          {'index': 0, 'message': {'role': 'assistant', 'content': 'pong'}},
        ],
      }));
      await makeProvider(server).testConnection();

      final body = server.captured.single.jsonBody!;
      expect(body['max_tokens'], 1);
      expect(body['messages'], [
        {'role': 'user', 'content': 'ping'},
      ]);
      expect(body['temperature'], 0.7);
    });
  });
}