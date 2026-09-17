/// FakeEmbeddingServer — dart:io HttpServer 播放 canned `/embeddings` 响应，
/// 供 VR-02 OpenAICompatibleEmbeddingClient 测试使用（本地 fake HTTP，
/// 不依赖真实网络）。
///
/// - 捕获每个请求（方法 / 路径 / 原始头 / 原始体），供请求契约断言
///   （Authorization Bearer 头、body `input`/`model`、URL 归一路径）。
/// - 内置 canned 处理器：JSON 成功体（可指定状态码 / Content-Type）、
///   纯文本体（非 JSON 畸形响应）、HTTP 错误状态码、延迟响应
///   （触发 dio receiveTimeout 的真实传输超时路径）。
///
/// 只服务于测试（test/ 目录），对生产代码零依赖。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 已捕获的客户端请求（端口级 wire 断言用）。
class FakeEmbeddingRequest {
  FakeEmbeddingRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  /// HTTP 方法（POST）。
  final String method;

  /// 请求路径（不含 query，如 `/v1/embeddings`）。
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

/// 请求处理器别名：读捕获后由测试摆布的响应行为。
typedef FakeEmbeddingHandler = Future<void> Function(HttpRequest request);

/// 播放 canned `/embeddings` 响应的假 embedding 服务。
class FakeEmbeddingServer {
  FakeEmbeddingServer(this.handler);

  /// 本服务器对每个请求执行的响应行为。
  final FakeEmbeddingHandler handler;

  /// 被处理的请求记录（顺序捕获）。
  final List<FakeEmbeddingRequest> captured = [];

  HttpServer? _server;
  int _port = 0;

  /// 绑定环回地址宣告服务；基址取操作系统分配的临时端口。
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    _port = _server!.port;
    _server!.listen(
      _dispatch,
      onError: (Object error, StackTrace stackTrace) {
        // 客户端主动断连等日志型错误：不视为服务器故障。
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

  Future<void> _dispatch(HttpRequest request) async {
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
      FakeEmbeddingRequest(
        method: request.method,
        path: request.uri.path,
        headers: headers,
        body: body,
      ),
    );
    try {
      await handler(request);
    } catch (error) {
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

  /// 200 JSON 成功体（响应体为 raw JSON 文本时用 [jsonBody]）。
  static FakeEmbeddingHandler ok(
    Map<String, dynamic> body, {
    int statusCode = 200,
  }) {
    return (request) async {
      final response = request.response;
      response.statusCode = statusCode;
      final type = ContentType.json;
      // ContentType.json 常量带 utf-8 charset；此处显式确保（含中文 body）。
      response.headers.contentType = ContentType(
        type.primaryType,
        type.subType,
        charset: 'utf-8',
      );
      response.write(jsonEncode(body));
      await response.close();
    };
  }

  /// 指定 Content-Type 的文本体（text/plain → dio 不预解码，供客户端
  /// 侧 JSON 解析路径验证；application/json + 非法体 → dio transformer
  /// FormatException 路径验证）。
  ///
  /// 显式补 utf-8 charset（HttpResponse 无 charset 时按 latin1 写，
  /// 中文 fixture 体将抛 Invalid argument）。
  static FakeEmbeddingHandler text(
    String body, {
    int statusCode = 200,
    String contentType = 'text/plain',
  }) {
    final parsed = ContentType.parse(contentType);
    final effective = parsed.charset == null
        ? ContentType(parsed.primaryType, parsed.subType, charset: 'utf-8')
        : parsed;
    return (request) async {
      final response = request.response;
      response.statusCode = statusCode;
      response.headers.contentType = effective;
      response.write(body);
      await response.close();
    };
  }

  /// HTTP 错误响应：指定状态码 + 可选文本错误体。
  static FakeEmbeddingHandler httpError(int statusCode, {String body = ''}) {
    return (request) async {
      final response = request.response;
      response.statusCode = statusCode;
      if (body.isNotEmpty) {
        response.write(body);
      }
      await response.close();
    };
  }

  /// 延迟 [delay] 后再回 200 JSON 体（真实 receiveTimeout 传输超时路径）。
  static FakeEmbeddingHandler delayed(
    Duration delay, {
    Map<String, dynamic>? body,
    int statusCode = 200,
  }) {
    return (request) async {
      await Future<void>.delayed(delay);
      final response = request.response;
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.json;
      if (body != null) {
        response.write(jsonEncode(body));
      }
      await response.close();
    };
  }
}
