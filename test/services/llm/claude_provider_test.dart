/// Claude wire（工单 02 验收：Anthropic Messages API 双栈 wire）。
///
/// 经 FakeLlmServer（dart:io HttpServer 播放 canned SSE / 状态码）验证：
/// - 非流式 generate 走 dio；流式 streamGenerate 走 dart:io HttpClient 直连；
/// - POST {base}/v1/messages、x-api-key + anthropic-version 头、system 顶层参数、
///   content_block_delta 的 text_delta 逐 token、temperature 不透传（R8）；
/// - 401/429/400(content_filter)/408/504/连接拒绝 → LLM 族；
/// - 流中途 EOF（未到 message_stop）/ 连接重置 → 可区分的 LLMConnectionInterruptedError；
/// - 零 token 正常完成（message_stop 已收）不抛错。
/// 锚：`desktop/backend/app/services/llm/claude.py` + `errors.dart::translateSdkError`。
library;

import 'dart:io';

import 'package:conver_system_mobile/services/llm/claude_provider.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
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

  ClaudeProvider makeProvider(FakeLlmServer server) =>
      ClaudeProvider(apiKey: apiKey, baseUrl: server.baseUrl);

  const messages = [
    LlmMessage(role: 'system', content: 'You are helpful'),
    LlmMessage(role: 'user', content: 'hi'),
    LlmMessage(role: 'assistant', content: 'hello'),
  ];

  group('generate 非流式（dio）— 成功路径', () {
    test('文本块提取 + wire 逐字段（路径/头/体）', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse({
        'id': 'msg_1',
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'Hello world'},
        ],
        'stop_reason': 'end_turn',
      }));

      final result = await makeProvider(server).generate(messages: messages);

      expect(result, 'Hello world');

      final captured = server.captured.single;
      expect(captured.method, 'POST');
      expect(captured.path, '/v1/messages');
      expect(captured.headers['x-api-key'], apiKey);
      expect(captured.headers['anthropic-version'], '2023-06-01');
      expect(captured.headers['content-type'], contains('application/json'));

      final body = captured.jsonBody!;
      expect(body['model'], 'claude-sonnet-5');
      expect(body['system'], 'You are helpful');
      expect(body['messages'], [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
      ]);
      expect(body['max_tokens'], 2048);
      // R8：temperature 不透传，body 不含该键。
      expect(body, isNot(contains('temperature')));
      // 非流式不置 stream 标记。
      expect(body, isNot(contains('stream')));
    });

    test('多文本块取首个 text 块；无文本块返回空串', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse({
        'id': 'msg_2',
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'First'},
          {'type': 'text', 'text': 'Second'},
        ],
      }));
      expect(await makeProvider(server).generate(messages: messages), 'First');

      final empty = await startedServer(FakeLlmServer.jsonResponse({
        'id': 'msg_3',
        'type': 'message',
        'role': 'assistant',
        'content': <Map<String, dynamic>>[],
      }));
      expect(await makeProvider(empty).generate(messages: messages), '');
    });

    test('无 system 时顶层 system 为 []（对齐锚 claude.py system or []）', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse({
        'id': 'msg_4',
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'ok'},
        ],
      }));
      await makeProvider(server).generate(messages: const [
        LlmMessage(role: 'user', content: 'u'),
      ]);
      expect(server.captured.single.jsonBody!['system'], const <Object>[]);
    });

    test('model 参数透传；缺省用 claude-sonnet-5', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse({
        'id': 'msg_5',
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'ok'},
        ],
      }));
      await makeProvider(server)
          .generate(messages: messages, model: 'claude-haiku-4-5');
      expect(server.captured.single.jsonBody!['model'], 'claude-haiku-4-5');
    });
  });

  group('generate 非流式 — HTTP 状态码 → LLM 族', () {
    Future<LLMError> errorOf(FakeLlmHandler handler, {String? baseUrl}) async {
      final server = await startedServer(handler);
      try {
        await makeProvider(server).generate(messages: messages);
        fail('应抛出 LLM 族错误');
      } on LLMError catch (e) {
        return e;
      }
    }

    test('401 → LLMAuthError', () async {
      final e = await errorOf(
        FakeLlmServer.httpError(401,
            body: '{"error":{"type":"authentication_error","message":"invalid x-api-key"}}'),
      );
      expect(e, isA<LLMAuthError>());
      expect(e.message, 'Claude API Key 无效或未配置');
    });

    test('429 → LLMRateLimitError', () async {
      final e = await errorOf(
        FakeLlmServer.httpError(429,
            body: '{"error":{"type":"rate_limit_error","message":"rate limited"}}'),
      );
      expect(e, isA<LLMRateLimitError>());
      expect(e.message, 'Claude API 请求频率超限');
    });

    test('504 → LLMTimeoutError', () async {
      final e = await errorOf(FakeLlmServer.httpError(504));
      expect(e, isA<LLMTimeoutError>());
      expect(e.message, 'Claude API 请求超时');
    });

    test('408 → LLMTimeoutError', () async {
      final e = await errorOf(FakeLlmServer.httpError(408));
      expect(e, isA<LLMTimeoutError>());
    });

    test('400 content_filter → LLMContentFilterError', () async {
      final e = await errorOf(FakeLlmServer.httpError(400,
          body: '{"error":{"type":"invalid_request_error","message":"Content filtered by content_filter"}}'));
      expect(e, isA<LLMContentFilterError>());
      expect(e.message, '内容被 Claude 内容过滤器拦截');
    });

    test('400 其余 → LLMBadRequestError（消息带服务端 error.message）', () async {
      final e = await errorOf(FakeLlmServer.httpError(400,
          body: '{"error":{"type":"invalid_request_error","message":"bad payload"}}'));
      expect(e, isA<LLMBadRequestError>());
      expect(e.message, 'Claude API 请求错误: bad payload');
    });

    test('400 JSON Map 体无 error.message → BadRequest 带原始 JSON', () async {
      final e = await errorOf(
        FakeLlmServer.jsonResponse({'foo': 'bar'}, statusCode: 400),
      );
      expect(e, isA<LLMBadRequestError>());
      expect(e.message, 'Claude API 请求错误: {"foo":"bar"}');
    });

    test('400 体非 JSON 文本 → BadRequest 带原文', () async {
      final e = await errorOf(FakeLlmServer.httpError(400, body: 'not-json'));
      expect(e, isA<LLMBadRequestError>());
      expect(e.message, 'Claude API 请求错误: not-json');
    });

    test('200 非标准成功体（缺 content）→ LLMResponseParseFailedError', () async {
      final e = await errorOf(FakeLlmServer.jsonResponse({
        'id': 'msg_x',
        'type': 'message',
        'role': 'assistant',
      }));
      expect(e, isA<LLMResponseParseFailedError>());
      expect(e.message, startsWith('Claude API 返回格式异常：'));
      expect(e.message, contains('兼容 Claude'));
    });

    test('连接拒绝（端口关闭）→ LLM 族兜底', () async {
      final server = await startedServer(FakeLlmServer.httpError(200));
      final baseUrl = server.baseUrl;
      await server.close();
      setUpServer.remove(server);

      try {
        await ClaudeProvider(apiKey: apiKey, baseUrl: baseUrl)
            .generate(messages: messages);
        fail('应抛出 LLM 族错误');
      } on LLMError catch (e) {
        expect(e.message, startsWith('Claude API 调用失败:'));
      } on SocketException {
        fail('SocketException 必须经 translateError 进入 LLM 族，不得穿透');
      }
    });
  });

  group('streamGenerate 流式（dart:io）— 成功路径', () {
    test('text_delta 逐 token 产出，message_stop 正常收束', () async {
      final server = await startedServer(
        FakeLlmServer.anthropic(['Hello', ', ', 'world'], withPing: true),
      );

      final tokens = await makeProvider(server)
          .streamGenerate(messages: messages)
          .toList();

      expect(tokens, ['Hello', ', ', 'world']);
    });

    test('wire 逐字段：路径 / 头 / stream:true / 无 temperature', () async {
      final server = await startedServer(FakeLlmServer.anthropic(['ok']));
      await makeProvider(server).streamGenerate(messages: messages).toList();

      final captured = server.captured.single;
      expect(captured.path, '/v1/messages');
      expect(captured.headers['x-api-key'], apiKey);
      expect(captured.headers['anthropic-version'], '2023-06-01');
      final body = captured.jsonBody!;
      expect(body['stream'], isTrue);
      expect(body['system'], 'You are helpful');
      expect(body, isNot(contains('temperature')));
    });

    test('零 token 正常完成：message_stop 已收、无 token、不抛错', () async {
      final server = await startedServer(FakeLlmServer.anthropic(const []));
      final tokens =
          await makeProvider(server).streamGenerate(messages: messages).toList();
      expect(tokens, isEmpty);
    });

    test('model 参数透传', () async {
      final server = await startedServer(FakeLlmServer.anthropic(['ok']));
      await makeProvider(server)
          .streamGenerate(messages: messages, model: 'claude-opus-4-6')
          .toList();
      expect(server.captured.single.jsonBody!['model'], 'claude-opus-4-6');
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
      expect(e.message, 'Claude API Key 无效或未配置');
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
        await ClaudeProvider(apiKey: apiKey, baseUrl: baseUrl)
            .streamGenerate(messages: messages)
            .toList();
        fail('应抛出 LLM 族错误');
      } on LLMError catch (e) {
        expect(e.message, startsWith('Claude API 调用失败:'));
      } on SocketException {
        fail('流式连接拒绝的 SocketException 必须经 translateError 进入 LLM 族');
      }
    });
  });

  group('streamGenerate 流式 — 断连可区分异常（供 T03 断流处理）', () {
    test('EOF 未到 message_stop → LLMConnectionInterruptedError', () async {
      final server = await startedServer(
        FakeLlmServer.anthropic(['partial'], withStop: false),
      );
      await expectLater(
        makeProvider(server).streamGenerate(messages: messages).toList(),
        throwsA(isA<LLMConnectionInterruptedError>()),
      );
    });

    test('零 token + EOF 未到终态同样识别为中断（非正常完成）', () async {
      final server = await startedServer(
        FakeLlmServer.anthropic(const [], withStop: false),
      );
      await expectLater(
        makeProvider(server).streamGenerate(messages: messages).toList(),
        throwsA(isA<LLMConnectionInterruptedError>()),
      );
    });

    test('流中途连接重置 → LLMConnectionInterruptedError', () async {
      final reset = FakeResetServer(
        body: 'event: message_start\ndata: {"type":"message_start"}\n\n'
            'event: content_block_delta\n'
            'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}\n\n',
      );
      await reset.start();
      addTearDown(reset.close);

      await expectLater(
        ClaudeProvider(apiKey: apiKey, baseUrl: reset.baseUrl)
            .streamGenerate(messages: messages)
            .toList(),
        throwsA(isA<LLMConnectionInterruptedError>()),
      );
    });

    test('Anthropic error 事件（流内错误）→ LLM 族（非穿透原始异常）', () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        response.write('event: error\n');
        response.write(
            'data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}\n\n');
        await response.close();
      });
      await expectLater(
        makeProvider(server).streamGenerate(messages: messages).toList(),
        throwsA(isA<LLMError>()
            .having((e) => e.message, 'message', 'Claude API 调用失败: Overloaded')),
      );
    });

    test('error 事件 data 非 JSON → 消息回退原始 data（可读兜底，不崩溃）', () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
        response.write('event: error\n');
        response.write('data: not-json\n\n');
        await response.close();
      });
      await expectLater(
        makeProvider(server).streamGenerate(messages: messages).toList(),
        throwsA(isA<LLMError>()
            .having((e) => e.message, 'message', 'Claude API 调用失败: not-json')),
      );
    });
  });

  group('translateError 错误翻译原语契约（Falsify：原始异常不得穿透）', () {
    ClaudeProvider provider() => ClaudeProvider(apiKey: apiKey);

    test('HttpException → LLM 族兜底（消息带原文）', () {
      final e = provider().translateError(HttpException('Connection reset'));
      expect(e, isA<LLMError>());
      expect(e.message, 'Claude API 调用失败: Connection reset');
    });

    test('未分类异常（StateError）→ LLM 族兜底', () {
      final e = provider().translateError(StateError('boom'));
      expect(e, isA<LLMError>());
      expect(e.message, 'Claude API 调用失败: Bad state: boom');
    });

    test('已映射 LLMError 直通不二次翻译', () {
      final original = LLMAuthError('Claude');
      final e = provider().translateError(original);
      expect(e, same(original));
    });
  });

  group('testConnection 默认最小生成（锚 base.py）', () {
    test('max_tokens=1、消息为 ping、成功不抛错', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse({
        'id': 'msg_t',
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'ok'},
        ],
      }));
      await makeProvider(server).testConnection();

      final body = server.captured.single.jsonBody!;
      expect(body['max_tokens'], 1);
      expect(body['messages'], [
        {'role': 'user', 'content': 'ping'},
      ]);
      expect(body, isNot(contains('temperature')));
    });
  });
}
