/// streamSse 共享流式骨架测试（2026-09-07 架构深化——候选 3 收拢）。
///
/// 收敛自 claude / openai 两 provider 的 `_streamRequest` 骨架（原 ~50 行
/// ×2 逐行同构）；本文件单测骨架统一兜底：逐 token 产出 / 终态帧判定 /
/// 非 200 → HttpStatusError / EOF 未终态 → LLMConnectionInterruptedError /
/// 流内错误帧工厂（claude 语义）与缺省忽略（openai 语义）。双 provider
/// 端到端（FakeLlmServer 播放 canned SSE）仍各自覆盖差异面。
library;

import 'dart:io';

import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/sse.dart';
import 'package:conver_system_mobile/services/llm/stream_wire.dart';
import 'package:conver_system_mobile/services/llm/translate_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_llm_server.dart';

/// 测试用流内错误异常（模仿 claude 私有 `_StreamApiError implements Exception`
/// 的语义；注意：StateError extends Error，**不是** Exception 子类型）。
class _StreamError implements Exception {
  const _StreamError(this.message);
  final String message;
}

void main() {
  final setUpServer = <FakeLlmServer>{};
  tearDown(() async {
    for (final server in setUpServer.toList()) {
      await server.close();
      setUpServer.remove(server);
    }
  });

  Future<FakeLlmServer> startedServer(FakeLlmHandler handler) async {
    final server = FakeLlmServer(handler);
    setUpServer.add(server);
    await server.start();
    return server;
  }

  Future<List<String>> collect(
    FakeLlmServer server, {
    Exception? Function(SseFrame frame)? errorFrameException,
    bool Function(SseFrame frame)? isTerminated,
    String? Function(SseFrame frame)? extractToken,
  }) async {
    return streamSse(
      uri: server.uri('/v1/stream'),
      body: '{}',
      headers: {'authorization': 'Bearer test-key'},
      errorFrameException: errorFrameException,
      isTerminated: isTerminated ?? isAnthropicMessageStop,
      extractToken: extractToken ?? extractAnthropicText,
    ).toList();
  }

  String frame(String event, String data) =>
      'event: $event\ndata: $data\n\n';

  group('streamSse · 成功路径', () {
    test('text_delta 逐 token 产出，终态帧正常收束', () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType = ContentType('text', 'event-stream');
        response.write(frame('message_start', '{"type":"message_start"}'));
        response.write(frame('content_block_delta',
            '{"type":"content_block_delta","delta":{"type":"text_delta","text":"He"}}'));
        response.write(frame('content_block_delta',
            '{"type":"content_block_delta","delta":{"type":"text_delta","text":"llo"}}'));
        response.write(frame('message_stop', '{"type":"message_stop"}'));
        await response.close();
      });

      expect(await collect(server), ['He', 'llo']);
    });

    test('零 token + 已收终态帧 → 空列表不抛错', () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType = ContentType('text', 'event-stream');
        response.write(frame('message_stop', '{"type":"message_stop"}'));
        await response.close();
      });

      expect(await collect(server), isEmpty);
    });
  });

  group('streamSse · 兜底路径（Falsify）', () {
    test('非 200 → HttpStatusError（状态码 + 原文）', () async {
      final server = await startedServer(FakeLlmServer.jsonResponse(
        {'error': 'bad request'},
        statusCode: HttpStatus.badRequest,
      ));

      await expectLater(
        collect(server),
        throwsA(isA<HttpStatusError>()
            .having((e) => e.statusCode, 'statusCode', HttpStatus.badRequest)),
      );
    });

    test('EOF 未到终态帧 → LLMConnectionInterruptedError', () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType = ContentType('text', 'event-stream');
        response.write(frame('content_block_delta',
            '{"type":"content_block_delta","delta":{"type":"text_delta","text":"He"}}'));
        await response.close(); // 无 message_stop，流直接结束。
      });

      await expectLater(
        collect(server),
        throwsA(isA<LLMConnectionInterruptedError>()),
      );
    });

    test('200 + 空响应体（零帧直接 EOF）→ LLMConnectionInterruptedError',
        () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType = ContentType('text', 'event-stream');
        await response.close(); // 无任何帧，直接结束。
      });

      await expectLater(
        collect(server),
        throwsA(isA<LLMConnectionInterruptedError>()),
      );
    });

    test('postUrl 连接拒绝 → SocketException 原样上抛（映射归 provider 层）',
        () async {
      // 分层契约：骨架只折叠**消费阶段**断连（内层 catch）；postUrl 阶段的
      // 连接拒绝原样上抛，由 provider 外层 translateError 映射进 LLM 族
      // （openai_provider_test「连接拒绝 → LLM 族兜底」端到端钉住）。
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final leakedPort = probe.port;
      await probe.close();

      await expectLater(
        streamSse(
          uri: Uri.parse('http://127.0.0.1:$leakedPort/v1/stream'),
          body: '{}',
          headers: {},
          isTerminated: isAnthropicMessageStop,
          extractToken: extractAnthropicText,
        ).toList(),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('streamSse · 流内错误帧（差异面）', () {
    test('errorFrameException 工厂（claude 语义）→ 抛出自定义异常', () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType = ContentType('text', 'event-stream');
        response.write(frame('error',
            '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'));
        await response.close();
      });

      await expectLater(
        collect(server, errorFrameException: (f) {
          if (f.event == 'error') {
            return _StreamError('overloaded_error: Overloaded');
          }
          return null;
        }),
        throwsA(isA<_StreamError>().having(
          (e) => e.message, 'message', 'overloaded_error: Overloaded',
        )),
      );
    });

    test('errorFrameException null（openai 语义）→ error 帧忽略、继续消费',
        () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType = ContentType('text', 'event-stream');
        // OpenAI 纯 data 型：正常 chunk + [DONE] 终态；无 error 帧概念。
        response.write('data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n');
        response.write('data: [DONE]\n\n');
        await response.close();
      });

      expect(
        await collect(
          server,
          isTerminated: isOpenAiDone,
          extractToken: extractOpenAiText,
        ),
        ['Hi'],
      );
    });

    test('挂起连接消费方取消 → 强制关闭不泄漏（无异常冒泡）', () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType = ContentType('text', 'event-stream');
        response.write(frame('message_stop', '{"type":"message_stop"}'));
        await response.close();
      });

      final sub = streamSse(
        uri: server.uri('/v1/stream'),
        body: '{}',
        headers: {},
        isTerminated: isAnthropicMessageStop,
        extractToken: extractAnthropicText,
      ).listen((_) {});
      // 消费方提前取消：骨架 finally 强制 close，无 Zone 未处理异常。
      await sub.cancel();
    });
  });
}