/// streamSse 共享流式骨架测试（2026-09-07 架构深化——候选 3 收拢）。
///
/// 收敛自 claude / openai 两 provider 的 `_streamRequest` 骨架（原 ~50 行
/// ×2 逐行同构）；本文件单测骨架统一兜底：逐 token 产出 / 终态帧判定 /
/// 非 200 → HttpStatusError / EOF 未终态 → ReadPhaseInterruptedError（读取
/// 相位）/ connect 段传输失败（拒连 / 连接超时 / 响应头前断）→
/// ConnectPhaseInterruptedError（连接相位）/ idle 断线 → ReadPhaseInterruptedError /
/// 流内错误帧工厂（claude 语义）与缺省忽略（openai 语义）。双 provider
/// 端到端（FakeLlmServer 播放 canned SSE）仍各自覆盖差异面。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

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

/// 原始 TCP SSE 响应写入器：字节级 `send`（真实 flush），供 idle timeout 时序
/// 敏感测试精确摆布帧到达时刻。
class _RawSseWriter {
  _RawSseWriter(this._socket);

  final Socket _socket;

  /// 发送一段 SSE 原文并 flush 到 socket（真实 TCP 时序，不经 HttpServer 缓冲）。
  Future<void> send(String sse) {
    _socket.add(utf8.encode(sse));
    return _socket.flush();
  }
}

/// 原始 TCP SSE 服务器（idle timeout 时序敏感测试专用）。
///
/// dart:io [HttpServer] 在 Windows 下 chunked 编码存在缓冲/挂起怪癖（先例见
/// fake_llm_server.dart 的 [FakeResetServer] 注释），`response.flush()` 不可靠
/// 送达 → 帧间隔 / 静默挂起的断言必须用原始 [ServerSocket] 字节级摆布：收到
/// 完整请求后回写 HTTP 响应头，随后交给 [handler] 以 [RawSseWriter.send] 注入
/// 节奏发帧；handler 返回后 destroy socket（无 Content-Length，连接关闭即 EOF，
/// 客户端据此自然收束）。
class _RawSseServer {
  _RawSseServer(
    this.handler, {
    this.extraHeaders = '',
  });

  final Future<void> Function(_RawSseWriter writer) handler;

  /// 追加到固定响应头之后的额外头部行（如 `Transfer-Encoding: chunked`，
  /// 供读段 HttpException 路径测试注入畸形帧）。
  final String extraHeaders;

  ServerSocket? _server;
  int _port = 0;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
    _port = _server!.port;
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> close() async {
    await _server?.close();
    _server = null;
  }

  /// 可用的 SSE 端点（`http://127.0.0.1:PORT/v1/stream`）。
  Uri get uri => Uri.parse('http://127.0.0.1:$_port/v1/stream');

  void _handle(Socket socket) {
    final buffer = BytesBuilder();
    var responded = false;
    socket.listen(
      (chunk) {
        if (responded) {
          return; // 已响应：忽略请求残留 chunk（客户端的 chunked 请求体）。
        }
        buffer.add(chunk);
        final bytes = buffer.toBytes();
        final headerEnd = _headerEnd(bytes);
        if (headerEnd == -1) {
          return; // 响应头未收齐（或尚未收到）——继续积累。
        }
        // 请求体可 chunked（dart HttpClient 无 Content-Length 时按块发送、
        // 无 content-length 头）——响应只需头部就绪即可发起（与 FakeResetServer
        // 同先例：不等请求体，双方字节互不阻塞）。
        responded = true;
        socket.add(utf8.encode(
          'HTTP/1.1 200 OK\r\n'
          'Content-Type: text/event-stream; charset=utf-8\r\n'
          'Connection: close\r\n'
          '$extraHeaders'
          '\r\n',
        ));
        unawaited(() async {
          try {
            try {
              await handler(_RawSseWriter(socket));
            } on Exception {
              // 客户端断开后的余写可能失败（SocketException / StateError 兼容
              // 落于 catch Object 之下不吞判定）：伪服务器尽力而为。
              // 仅忽略 Exception；Error 类仍上抛使测试可见。
            } finally {
              socket.destroy(); // 连接关闭 = 客户端 EOF 收束。
            }
          } catch (_) {
            socket.destroy();
          }
        }());
      },
      onError: (Object error) {},
      cancelOnError: false,
    );
  }

  /// 返回首个 `\r\n\r\n`（头部结束）的起始下标；未找到返回 -1。
  static int _headerEnd(List<int> bytes) {
    for (var i = 0; i < bytes.length - 3; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }
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

    test('EOF 未到终态帧 → ReadPhaseInterruptedError（读取相位，伞判型仍成立）',
        () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType = ContentType('text', 'event-stream');
        response.write(frame('content_block_delta',
            '{"type":"content_block_delta","delta":{"type":"text_delta","text":"He"}}'));
        await response.close(); // 无 message_stop，流直接结束。
      });

      await expectLater(
        collect(server),
        // A4 伞判型双断言：读取相位叶子仍 isA<LLMConnectionInterruptedError>。
        throwsA(allOf(
          isA<ReadPhaseInterruptedError>(),
          isA<LLMConnectionInterruptedError>(),
        )),
      );
    });

    test('200 + 空响应体（零帧直接 EOF）→ ReadPhaseInterruptedError（读取相位）',
        () async {
      final server = await startedServer((request) async {
        final response = request.response;
        response.headers.contentType = ContentType('text', 'event-stream');
        await response.close(); // 无任何帧，直接结束。
      });

      await expectLater(
        collect(server),
        throwsA(isA<ReadPhaseInterruptedError>()),
      );
    });

    test('读段 HttpException：chunked 畸形块（响应头后读期）→ '
        'ReadPhaseInterruptedError（读取相位，originalError 透传）', () async {
      // dart:io HttpClient 在 chunked 传输下对畸形块大小行抛 HttpException——
      // 响应头已收齐（200），读体阶段落错 → 读段 2 catch 的 HttpException 分支
      // 收敛为读取相位叶子（与 SocketException 分支同构的防御面）。
      final server = _RawSseServer(
        (w) async {
          await w.send('ZZZ-invalid-chunk\r\n');
          await w.send('data: x\r\n');
          await w.send('0\r\n\r\n');
        },
        extraHeaders: 'Transfer-Encoding: chunked\r\n',
      );
      await server.start();
      addTearDown(server.close);

      await expectLater(
        streamSse(
          uri: server.uri,
          body: '{}',
          headers: {},
          isTerminated: isAnthropicMessageStop,
          extractToken: extractAnthropicText,
        ).toList(),
        throwsA(isA<ReadPhaseInterruptedError>()
            .having((e) => e.originalError, 'originalError', isA<HttpException>())),
      );
    });

    test('connect 段：postUrl 连接拒绝 → ConnectPhaseInterruptedError（收敛判型）',
        () async {
      // AR-1 相位契约：connect 段传输失败（DNS / 拒连 / 连接超时 / 响应头前断）
      // 确定未产生服务端生成，统一收敛为 ConnectPhaseInterruptedError（连接相位
      // 叶子），供服务层「连接相位」自动重试承接（读取相位叶子不可重试）。
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
        // A4 伞判型双断言：连接相位叶子仍 isA<LLMConnectionInterruptedError>。
        throwsA(allOf(
          isA<ConnectPhaseInterruptedError>(),
          isA<LLMConnectionInterruptedError>(),
        )),
      );
    });

    test('connect 段：connectTimeout 到期（握手黑洞）→ ConnectPhaseInterruptedError',
        () async {
      // https 黑洞 TCP：TLS 握手挂起 → connectionTimeout 到期抛 SocketException，
      // connect 段收敛判型（连接超时属「确定未产生服务端生成」的重试面）。
      final sink = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sub = sink.listen((_) {}, onError: (_) {});
      addTearDown(() async {
        await sub.cancel();
        await sink.close();
      });

      await expectLater(
        streamSse(
          uri: Uri.parse('https://127.0.0.1:${sink.port}/v1/stream'),
          body: '{}',
          headers: {},
          isTerminated: isAnthropicMessageStop,
          extractToken: extractAnthropicText,
          connectTimeout: const Duration(milliseconds: 300),
        ).toList(),
        throwsA(isA<ConnectPhaseInterruptedError>()),
      );
    });

    test('connect 段：响应头前断（部分头后关连接）→ ConnectPhaseInterruptedError',
        () async {
      // 服务端只发部分响应头后关连接：HttpException（未收完整响应头），connect
      // 段收敛判型——未收到状态码、无生成副作用 → 服务层重试面。
      final sink = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sub = sink.listen((socket) {
        socket.write('HTTP/1.1 200 OK\r\nX-Partial:');
        socket.flush().then((_) => socket.destroy());
      }, onError: (_) {});
      addTearDown(() async {
        await sub.cancel();
        await sink.close();
      });

      await expectLater(
        streamSse(
          uri: Uri.parse('http://127.0.0.1:${sink.port}/v1/stream'),
          body: '{}',
          headers: {},
          isTerminated: isAnthropicMessageStop,
          extractToken: extractAnthropicText,
        ).toList(),
        throwsA(isA<ConnectPhaseInterruptedError>()),
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

  group('streamSse · idle timeout（M6-09）', () {
    // idle 时序断言依赖真实字节到达时刻，统一用原始 ServerSocket（见
    // _RawSseServer 头注释：dart:io HttpServer Windows chunked 缓冲怪癖）。
    Stream<String> idleWire(Uri uri, Duration idleTimeout) => streamSse(
          uri: uri,
          body: '{}',
          headers: {},
          isTerminated: isAnthropicMessageStop,
          extractToken: extractAnthropicText,
          idleTimeout: idleTimeout,
        );

    String textDelta(String token) =>
        'event: content_block_delta\ndata: {"type":"content_block_delta",'
        '"delta":{"type":"text_delta","text":"$token"}}\n\n';

    test('流式中静默 ≥ idleTimeout（无任何行）→ ReadPhaseInterruptedError'
        '（读取相位，状态码必已收到；伞判型仍成立）', () async {
      final server = _RawSseServer((w) async {
        await w.send(textDelta('He'));
        // 首帧后静默挂起：不写不关（弱网假活连接），等 idleTimeout 到期。
        await Completer<void>().future;
      });
      await server.start();
      addTearDown(server.close);

      await expectLater(
        idleWire(server.uri, const Duration(milliseconds: 200)).toList(),
        // A4 伞判型双断言：idle 断线编码为读取相位叶子，仍 isA 伞下。
        throwsA(allOf(
          isA<ReadPhaseInterruptedError>(),
          isA<LLMConnectionInterruptedError>(),
        )),
      );
    });

    test('正常节奏（帧间隔 < idleTimeout）→ 不误杀，完整流正常完成', () async {
      final server = _RawSseServer((w) async {
        for (final token in ['He', 'llo']) {
          await w.send(textDelta(token));
          // 帧间隔 60ms < idleTimeout 200ms：计时器持续重启，不得误杀。
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        await w.send(frame('message_stop', '{"type":"message_stop"}'));
      });
      await server.start();
      addTearDown(server.close);

      expect(
        await idleWire(server.uri, const Duration(milliseconds: 200)).toList(),
        ['He', 'llo'],
      );
    });

    test('已收终态帧后静默（> idleTimeout，< 终态守卫 2s 缺省）→ 正常终态零变更：'
        '终态后 idle 守卫失效不误杀；终态守卫时长 > 服务端静默跨度 → 不触发，'
        '完成于服务端自然关闭（09 验收 4 elapsed 下限断言保持）', () async {
      final server = _RawSseServer((w) async {
        await w.send(textDelta('He'));
        await w.send(frame('message_stop', '{"type":"message_stop"}'));
        // 终态帧后静默挂起 800ms（4× idleTimeout 200ms、但 < 终态守卫 2s 缺省）
        // 再自然关闭：若终态后 idle 计时器未失效，会在 ~idleTimeout 提前触发
        // （被下方 elapsed 下限断言捕获/抛错）；终态守卫时长（2s）> 静默跨度
        // （800ms）→ 不触发（守卫仅补假活缺口，正常路径零变）。
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await server.start();
      addTearDown(server.close);

      final elapsed = Stopwatch()..start();
      final tokens = await idleWire(
        server.uri,
        const Duration(milliseconds: 200),
      ).toList();
      final took = elapsed.elapsed;

      expect(tokens, ['He']);
      expect(took >= const Duration(milliseconds: 500), isTrue,
          reason: '终态后不应触发任何守卫断线：完成过早（服务端 800ms 环境自然'
              '关闭）说明 idle 未在终态失效或终态守卫误触发: took=$took');
    });

    test('注释帧（: ping）静默忽略维持现状；作为活跃行持续重启计时器 → '
        '跨 idleTimeout 存活并正常完成（保守不误杀）；帧间隔加裕量防 flake'
        '（40ms 间隔 ≤ idleTimeout 300ms 的 1/7，抵御调度抖动）', () async {
      final server = _RawSseServer((w) async {
        await w.send(textDelta('He'));
        // 持续 : ping 注释帧（40ms 间隔），总跨度 360ms > idleTimeout 300ms。
        // 帧间隔与超时的比值放大（原 100ms/250ms、W3 实测 flake 1 次）——
        // 调度抖动下任何两行实际到达间隔仍远低于 idleTimeout，不得误杀。
        for (var i = 0; i < 9; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          await w.send(': ping\n\n');
        }
        await w.send(frame('message_stop', '{"type":"message_stop"}'));
      });
      await server.start();
      addTearDown(server.close);

      expect(
        await idleWire(server.uri, const Duration(milliseconds: 300)).toList(),
        ['He'],
      );
    });

    test('Falsify: 帧持续流动中（idle Timer 挂起）消费方取消 → 及时返回、finally '
        '清理（含 idle Timer）无泄漏、无未处理异常', () async {
      final server = _RawSseServer((w) async {
        // 帧每 40ms 持续流动（帧间隔 < idleTimeout 200ms 且 > 0）：idle Timer
        // 持续重启、挂起中。取消发生在帧间（非停滞）——停滞连接上 cancel 有界
        // 挂起为 F-17 既有已知（见 chat_service._stopStreamReply 超时兜底），
        // wire 层不测该面；此处验证「流动中取消 → 及时返回 + 无泄漏」。
        for (var i = 0; i < 4; i++) {
          await w.send(textDelta('t'));
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        await Completer<void>().future; // 后续不再写，等待 tearDown destroy。
      });
      await server.start();
      addTearDown(server.close);

      final sub = idleWire(server.uri, const Duration(milliseconds: 200))
          .listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final cancelWatch = Stopwatch()..start();
      await sub.cancel();
      expect(cancelWatch.elapsed < const Duration(seconds: 3), isTrue,
          reason: '流动流上 cancel 应及时返回（停滞挂起为 F-17 既有面，不适用）');
      // 越过注入 idleTimeout（200ms）：若计时器泄漏后触发 → 关闭已关闭 client
      // 应无副作用；zone 捕获未处理异步异常即测试失败。
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  });

  group('streamSse · 终态守卫（F-56 假活终态化）', () {
    // 假活终态化时序敏感测试与 idle 组同用原始 ServerSocket 字节级摆布；
    // idleTimeout 保持生产 60s 缺省值（终态后读阶段守卫已失效），仅注入
    // 短终态守卫，专测终态帧后的假活收束面。
    Stream<String> guardWire(Uri uri, Duration terminalTimeout) => streamSse(
          uri: uri,
          body: '{}',
          headers: {},
          isTerminated: isAnthropicMessageStop,
          extractToken: extractAnthropicText,
          idleTimeout: const Duration(seconds: 60),
          terminalTimeout: terminalTimeout,
        );

    String textDelta(String token) =>
        'event: content_block_delta\ndata: {"type":"content_block_delta",'
        '"delta":{"type":"text_delta","text":"$token"}}\n\n';

    test('假活终态化：终态帧后连接保持 + 无帧 → 终态守卫到期有界收束'
        '（终态后读阶段 idle 已失效、由守卫兜底；60s idle 不参与）', () async {
      final server = _RawSseServer((w) async {
        await w.send(textDelta('He'));
        await w.send(frame('message_stop', '{"type":"message_stop"}'));
        // 终态帧后连接保持、不再写也不关（假活）：idle 60s 缺省远大于守卫时长，
        // 唯一到期的就是终态守卫（200ms）——force-close 使 await-for 自然收束。
        await Completer<void>().future;
      });
      await server.start();
      addTearDown(server.close);

      final elapsed = Stopwatch()..start();
      final tokens = await guardWire(
        server.uri,
        const Duration(milliseconds: 200),
      ).toList().timeout(const Duration(seconds: 3)); // 有界：守卫缺失时防挂起。
      final took = elapsed.elapsed;

      expect(tokens, ['He']);
      expect(took >= const Duration(milliseconds: 200), isTrue,
          reason: '完成过早 = 收束非由终态守卫到期触发（took=$took）');
    });

    test('终态后尾随事件帧持续流动 → 终态守卫逐帧复位不误杀：全部尾随 token '
        '产出，完成于服务端自然关闭（非守卫提前触发）', () async {
      final server = _RawSseServer((w) async {
        await w.send(textDelta('He'));
        await w.send(frame('message_stop', '{"type":"message_stop"}'));
        // 终态后尾随事件帧：60ms 一帧（休眠间隔 < 守卫 300ms 的 1/5），总跨度
        // 360ms > 守卫时长——若守卫未逐帧复位，会在 ~300ms 到期截断尾随帧。
        for (var i = 1; i <= 6; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          await w.send(textDelta('t$i'));
        }
        // handler 返回后 socket.destroy() = 服务端自然关闭（正常收束路径）。
      });
      await server.start();
      addTearDown(server.close);

      final elapsed = Stopwatch()..start();
      final tokens = await guardWire(
        server.uri,
        const Duration(milliseconds: 300),
      ).toList();
      final took = elapsed.elapsed;

      expect(tokens, ['He', 't1', 't2', 't3', 't4', 't5', 't6']);
      expect(took >= const Duration(milliseconds: 300), isTrue,
          reason: '完成过早 = 终态守卫未随尾随帧复位、提前触发截断（took=$took）');
    });

    test('Falsify: 终态后守卫挂起中消费方取消 → 及时返回、finally 清理（含终态'
        '守卫计时器）无泄漏、无未处理异常', () async {
      final server = _RawSseServer((w) async {
        await w.send(textDelta('He'));
        await w.send(frame('message_stop', '{"type":"message_stop"}'));
        // 终态后尾随帧每 50ms 持续流动（< 守卫 200ms 且 > 0）：守卫持续复位挂起中，
        // 取消发生在流动中（停滞连接上 cancel 有界挂起为 F-17 既有已知，不适用）。
        for (var i = 0; i < 4; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await w.send(textDelta('t$i'));
        }
        await Completer<void>().future; // 后续不再写，等待 tearDown destroy。
      });
      await server.start();
      addTearDown(server.close);

      final sub = guardWire(server.uri, const Duration(milliseconds: 200))
          .listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final cancelWatch = Stopwatch()..start();
      await sub.cancel();
      expect(cancelWatch.elapsed < const Duration(seconds: 3), isTrue,
          reason: '流动流上 cancel 应及时返回（停滞挂起为 F-17 既有面，不适用）');
      // 越过终态守卫时长（200ms）：若守卫计时器泄漏后触发 → 关闭已关闭 client
      // 应无副作用；zone 捕获未处理异步异常即测试失败。
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  });
}