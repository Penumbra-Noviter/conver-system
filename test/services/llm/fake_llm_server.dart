/// FakeLLMServer — dart:io HttpServer 播放 canned Anthropic / OpenAI SSE 序列、
/// HTTP 状态码与可控断连，供 T02 双协议 wire 测试使用。
///
/// - 捕获每个请求（方法 / 路径 / 原始头 / 原始体），供 wire 逐字段断言
///   （鉴权头、anthropic-version、数据体 JSON 字段、temperature 透传与否）。
/// - 内置 canned 处理器：完整 / 中断的 Anthropic 与 OpenAI SSE 会话、
///   HTTP 错误状态码、200 JSON 成功体。
/// - 断连三类场景：
///   - 连接拒绝：构造服务器 → `start()` → `close()` 后复用其基址（端口已关），
///     provider 连接该端口抛 SocketException（进入 LLM 族翻译路径）；
///   - 流中途 EOF（未到终态）：`withStop/withDone: false` 正常关闭连接，
///     客户端收到流末尾但无终态帧；
///   - 流中途连接重置：[FakeResetServer]（原始 ServerSocket）以大于实际发送的
///     Content-Length 声明响应、随即销毁 socket，客户端读到部分 SSE 后收到
///     连接重置（HttpClient 读不满声明长度即报错）。
///
/// 只服务于测试（test/ 目录），对 provider 代码零依赖。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

/// 已捕获的客户端请求（端口级 wire 断言用）。
class CapturedRequest {
  CapturedRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  /// HTTP 方法（POST）。
  final String method;

  /// 请求路径（不含 query，如 `/v1/messages`）。
  final String path;

  /// 原始请求头：头名 → 首个值（重复头取首值）。
  final Map<String, String> headers;

  /// 原始请求体文本。
  final String body;

  /// 请求体 JSON 解码；非 JSON 体返回 null。
  Map<String, dynamic>? get jsonBody {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}

/// 请求处理器别名：读取已捕获后由测试摆布的响应行为。
typedef FakeLlmHandler = Future<void> Function(HttpRequest request);

/// 播放 canned 双协议 SSE / 状态码的假 LLM 服务。
class FakeLlmServer {
  FakeLlmServer(this.handler);

  /// 本服务器对每个请求执行的响应行为。
  final FakeLlmHandler handler;

  /// 被处理的请求记录（顺序捕获）。
  final List<CapturedRequest> captured = [];

  HttpServer? _server;
  int _port = 0;

  /// 绑定环回地址宣告服务；基址取操作系统分配的临时端口。
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    _port = _server!.port;
    _server!.listen(
      _dispatch,
      onError: (Object error, StackTrace stackTrace) {
        // 个别测试用客户端主动重置连接的日志型错误：不视为服务器故障。
      },
    );
  }

  /// 停止服务（force 关闭残留 keep-alive 连接，避免测试退出悬挂）。
  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// 可用的服务基址，如 `http://127.0.0.1:PORT`。
  String get baseUrl => 'http://127.0.0.1:$_port';

  /// 拼装完整 URL（供断言 provider 请求路径等场景手动发起时使用）。
  Uri uri(String path) => Uri.parse('$baseUrl$path');

  Future<void> _dispatch(HttpRequest request) async {
    // 先完整读取请求体（解除背压）；读失败算作空体（客户端重置场景）。
    String body = '';
    try {
      body = await utf8.decoder.bind(request).join();
    } on Exception {
      body = '';
    }
    final headers = <String, String>{};
    request.headers.forEach((name, values) {
      headers.putIfAbsent(name, () => values.isNotEmpty ? values.first : '');
    });
    captured.add(
      CapturedRequest(
        method: request.method,
        path: request.uri.path,
        headers: headers,
        body: body,
      ),
    );
    try {
      await handler(request);
    } catch (error) {
      // 尽力关闭响应防止客户端挂起；错误向上传播使测试可见。
      try {
        await request.response.close();
      } on Exception {
        // 处理器已自行关 / detached 时忽略二次关闭。
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // canned 处理器构造
  // ---------------------------------------------------------------------

  /// 播放一轮完整 Anthropic Messages SSE 会话。
  ///
  /// `message_start` → 可选 `ping` → `content_block_start` → 逐 token
  /// `content_block_delta`（text_delta）→ `content_block_stop` →
  /// `message_delta` → `message_stop`。`withStop: false` 时缺 message_stop
  /// （流在终态前正常关闭 = EOF 未到终态场景）。
  static FakeLlmHandler anthropic(
    List<String> tokens, {
    bool withStop = true,
    bool withPing = false,
  }) {
    return (request) async {
      final response = request.response;
      _sseHeaders(response);
      _event(response, 'message_start', {
        'type': 'message_start',
        'message': {
          'id': 'msg_1',
          'type': 'message',
          'role': 'assistant',
          'content': const <Map<String, dynamic>>[],
          'stop_reason': null,
          'stop_sequence': null,
          'usage': {'input_tokens': 5, 'output_tokens': 0},
        },
      });
      if (withPing) {
        _event(response, 'ping', {'type': 'ping'});
      }
      _event(response, 'content_block_start', {
        'type': 'content_block_start',
        'index': 0,
        'content_block': {'type': 'text', 'text': ''},
      });
      for (final token in tokens) {
        _event(response, 'content_block_delta', {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': token},
        });
        await response.flush();
      }
      _event(response, 'content_block_stop', {
        'type': 'content_block_stop',
        'index': 0,
      });
      if (withStop) {
        _event(response, 'message_delta', {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
          'usage': {'output_tokens': 0},
        });
        _event(response, 'message_stop', {'type': 'message_stop'});
      }
      await response.close();
    };
  }

  /// 播放一轮完整（或中断）OpenAI Chat Completions SSE 会话。
  ///
  /// role 初始化 chunk → 逐 token `choices[0].delta.content` → 可选
  /// `include_usage` 空 choices chunk → 收尾 chunk（delta:{}）→ `[DONE]`。
  /// `withDone: false` 时缺 `[DONE]`（EOF 未到终态）。
  static FakeLlmHandler openAi(
    List<String> tokens, {
    bool withDone = true,
    bool withUsageChunk = false,
  }) {
    return (request) async {
      final response = request.response;
      _sseHeaders(response);
      _data(response, {
        'id': 'chatcmpl-1',
        'object': 'chat.completion.chunk',
        'created': 1694268190,
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'delta': {'role': 'assistant', 'content': null},
            'logprobs': null,
            'finish_reason': null,
          },
        ],
      });
      for (final token in tokens) {
        _data(response, {
          'choices': [
            {
              'index': 0,
              'delta': {'content': token},
              'logprobs': null,
              'finish_reason': null,
            },
          ],
        });
        await response.flush();
      }
      if (withUsageChunk) {
        _data(response, {
          'choices': const <Map<String, dynamic>>[],
          'usage': {'prompt_tokens': 5, 'completion_tokens': 2, 'total_tokens': 7},
        });
      }
      _data(response, {
        'choices': [
          {
            'index': 0,
            'delta': const <String, dynamic>{},
            'logprobs': null,
            'finish_reason': 'stop',
          },
        ],
      });
      if (withDone) {
        _data(response, '[DONE]');
      }
      await response.close();
    };
  }

  /// HTTP 错误响应（非 SSE）：指定状态码 + 可选文本错误体。
  static FakeLlmHandler httpError(int statusCode, {String body = ''}) {
    return (request) async {
      final response = request.response;
      response.statusCode = statusCode;
      if (body.isNotEmpty) {
        response.write(body);
      }
      await response.close();
    };
  }

  /// 200 JSON 成功体（非流式 generate / testConnection 用例）。
  static FakeLlmHandler jsonResponse(Map<String, dynamic> body,
      {int statusCode = 200}) {
    return (request) async {
      final response = request.response;
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(body));
      await response.close();
    };
  }

  // ---------------------------------------------------------------------
  // 内部小工具
  // ---------------------------------------------------------------------

  static void _sseHeaders(HttpResponse response) {
    response.headers.contentType =
        ContentType('text', 'event-stream', charset: 'utf-8');
  }

  /// 写 Anthropic 事件帧：`event: <name>\ndata: <json>\n\n`。
  static void _event(HttpResponse response, String name, Object data) {
    response.write('event: $name\n');
    response.write('data: ${jsonEncode(data)}\n');
    response.write('\n');
  }

  /// 写 OpenAI data 帧：`data: <json>\n\n`（字符串直接原样输出，如 `[DONE]`）。
  static void _data(HttpResponse response, Object data) {
    final payload = data is String ? data : jsonEncode(data);
    response.write('data: $payload\n\n');
  }
}

/// 原始 TCP「流中途连接重置」服务器。
///
/// `HttpServer` 抽象不暴露底层 socket，且 chunked 编码下 `detachSocket` 会等待
/// 终止块导致死锁（Windows 实测挂起）。改用原始 `ServerSocket` 精确复刻
/// 「响应写到一半连接被重置」：完整收到客户端请求后，回写 HTTP 响应头 + 部分
/// SSE 帧（声明 Content-Length 远大于实际发送），随即 `destroy()`。客户端读到
/// 部分数据后因「未收到声明长度即 EOF / 连接重置」报错——用于验证 provider
/// 将流中途断连转为 [LLMConnectionInterruptedError] 而非穿透原始异常。
class FakeResetServer {
  FakeResetServer({required this.body, this._declaredLength = 1 << 20});

  /// 实际发送的响应体（部分 SSE 帧，不含响应头）。
  final String body;

  /// 声明的 Content-Length（故意大于实际发送字节数）。
  final int _declaredLength;

  ServerSocket? _server;
  int _port = 0;

  /// 绑定环回地址宣告服务。
  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
    _port = _server!.port;
    _server!.listen(
      _handle,
      onError: (Object error, StackTrace stackTrace) {},
    );
  }

  Future<void> close() async {
    await _server?.close();
    _server = null;
  }

  /// 可用的服务基址，如 `http://127.0.0.1:PORT`。
  String get baseUrl => 'http://127.0.0.1:$_port';

  void _handle(Socket socket) {
    final buffer = BytesBuilder();
    socket.listen(
      (chunk) {
        buffer.add(chunk);
        final bytes = buffer.toBytes();
        final headerEnd = _headerEnd(bytes);
        if (headerEnd == -1) {
          return;
        }
        final headers = utf8.decode(bytes.sublist(0, headerEnd));
        final lengthMatch =
            RegExp(r'content-length:\s*(\d+)', caseSensitive: false)
                .firstMatch(headers);
        final bodyLength = lengthMatch == null ? 0 : int.parse(lengthMatch.group(1)!);
        // 等客户端完整发完请求再响应，确保重置发生在客户端读响应阶段（流中途）。
        if (bytes.length < headerEnd + 4 + bodyLength) {
          return;
        }
        socket.add(utf8.encode(
          'HTTP/1.1 200 OK\r\n'
          'Content-Type: text/event-stream; charset=utf-8\r\n'
          'Content-Length: $_declaredLength\r\n'
          'Connection: close\r\n'
          '\r\n'
          '$body',
        ));
        socket.flush();
        socket.destroy();
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
