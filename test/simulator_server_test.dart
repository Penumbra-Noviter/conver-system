/// F-M5-02 SimulatorServer — 本地 HTTP 托管深模块（真监听 + 真实 HttpClient 断言）。
///
/// seam 语义（spec §7 测试决策）：`bind(InternetAddress.loopbackIPv4, 0)` 起真实
/// 监听 + 真实 dart:io HttpClient 走路由全矩阵——`dart:io` 在 flutter test 宿主
/// 可真实运行，不碰平台通道（M2 SSE 宿主先例）。
///
/// 测例锁定契约（工单验收语义契约第 2~5/7 条）：
/// - 生命周期：start(port: 0) 返回真实端口；重复 start/stop 幂等不抛；stop 后
///   同端口重绑成功；stop 后不再响应；
/// - 路由契约：`/simulators/manifest.json`（application/json）、
///   `/simulators/<file>.html`（text/html; charset=utf-8）、`/` 最小 index
///   HTML（含可识别文案）、其余路径/方法 404；
/// - 目录墙：`..` 段 / 绝对路径 / `%2e%2e` 编码穿越 / 反斜杠隐藏分隔符 /
///   非并列后缀 → 一律 404 且不触盘（断言响应不携带目录外 sentinel 内容）；
/// - Content-Type 两值手写映射；405 不得出现（非 GET 一律 404）；
/// - 固定端口被占 → 明确抛 [SimulatorPortInUseException]（含端口号）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/simulator_contracts.dart';
import 'package:conver_system_mobile/services/simulator/simulator_server.dart';

/// 目录外哨兵文件（断言穿越不触盘：任何响应不得携带其内容）。
const String secretContent = 'OUTSIDE-SECRET-SENTINEL-DO-NOT-LEAK';

/// 单级逃逸落点哨兵（simDir/../passwd-sentinel.html）——**落点必须存在且带
/// .html 后缀**：否则守卫失效时 Content-Type 两值映射也会巧合 404，测试对
/// 守卫灵敏度为 0（Falsify 突变抽查发现两次巧合：无后缀落点 + 逃逸目标不存在）。
const String escapeTargetName = 'passwd-sentinel.html';
const String escapeTargetContent = 'ESCAPED-FILE-MUST-NOT-BE-SERVED';

/// 测试目录 fixtures：manifest.json / game-a.html / 中文名 html / 非并列后缀
/// 文件（应 404）/ 目录外哨兵（`..` 逃逸落点必须存在，断言不触盘）。
Future<Directory> makeSimDir() async {
  final parent = await Directory.systemTemp.createTemp('sim-server-test-');
  addTearDown(() => parent.delete(recursive: true));
  final simDir = Directory('${parent.path}${Platform.pathSeparator}simulators');
  simDir.createSync(recursive: true);
  File('${simDir.path}${Platform.pathSeparator}manifest.json')
      .writeAsStringSync('{"version":2,"simulators":[]}');
  File('${simDir.path}${Platform.pathSeparator}game-a.html')
      .writeAsStringSync('<html><body>GAME A</body></html>');
  File('${simDir.path}${Platform.pathSeparator}人生模拟器v3.html')
      .writeAsStringSync('<html>中文游戏</html>');
  File('${simDir.path}${Platform.pathSeparator}style.css')
      .writeAsStringSync('body{color:red}');
  File('${simDir.path}${Platform.pathSeparator}noext').writeAsStringSync('x');
  File('${parent.path}${Platform.pathSeparator}outside-secret.json')
      .writeAsStringSync(secretContent);
  // 单级逃逸落点（simDir/../passwd-sentinel.html）：必须存在，使守卫失效可被断言
  File('${parent.path}${Platform.pathSeparator}$escapeTargetName')
      .writeAsStringSync(escapeTargetContent);
  return simDir;
}

/// 真实 HttpClient GET：返回 (status, content-type, body)。
Future<(int, String, String)> httpGet(int port, String path) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final ct = resp.headers.value(HttpHeaders.contentTypeHeader) ?? '';
    return (resp.statusCode, ct, body);
  } finally {
    client.close(force: true);
  }
}

/// 真实 HttpClient 非 GET 请求：返回 status。
Future<int> httpMethod(int port, String method, String path) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    final resp = await req.close();
    await resp.transform(utf8.decoder).join();
    return resp.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// 原始 socket 请求（HttpClient 无法发出的目标，如 `//` authority 歧义）。
Future<int> rawRequestStatus(int port, String rawTarget) async {
  final sock = await Socket.connect('127.0.0.1', port);
  sock.write('GET $rawTarget HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n');
  await sock.flush();
  final bytes = <int>[];
  await for (final chunk in sock) {
    bytes.addAll(chunk);
  }
  sock.destroy();
  final head = utf8.decode(bytes, allowMalformed: true).split('\r\n').first;
  return int.parse(head.split(' ')[1]);
}

/// ── T3 · /proxy 同源反代契约矩阵（真上游测试服务器 + 真转发）───────────────
///
/// seam 语义（工单 03 验收 + 桌面锚点逐字）：测 seam = 构造注入
/// `proxyConfigReader`（返回「OpenAI 兼容 base + key」）；行为经真实监听
/// SimulatorServer + 真实 dart:io HttpClient 转发到**真实 upstream 测试
/// 服务器**断言——method/目标/请求体/头（key 注入 / 游戏头丢弃）/SSE 字节
/// 透传/未配置 503。桌面对齐：`api/routes/simulators.py` `simulator_api_proxy`
/// / `_build_proxy_target` / `_proxy_headers`。

/// 上游记录的一条请求（供断言「到达目标的事实」）。
class _UpstreamRequest {
  _UpstreamRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;

  /// 头名小写 → join 值（断言按小写键读）。
  final Map<String, String> headers;

  final List<int> body;

  String get bodyText => utf8.decode(body);
}

/// 真实 upstream 测试服务器：记录每请求 (method/path/headers/body)，可按
/// 测试配置状态码 / 响应头 / 响应体 / SSE 分块流（分块间延迟 + 逐块 flush）。
class _FakeUpstream {
  _FakeUpstream._(this._server);

  final HttpServer _server;

  int get port => _server.port;

  /// 记录到的请求（按到达顺序；每个测试内请求为顺序执行，无并发竞态）。
  final List<_UpstreamRequest> requests = [];

  int statusCode = HttpStatus.ok;
  Map<String, String> respHeaders = const {};
  bool hasBody = true;
  List<int> Function() bodyProvider = () => utf8.encode('{"ok":true}');

  /// 非空 → SSE 分块模式：逐块延迟 [sseChunkDelay] 后下发（验证流式透传）。
  List<String>? sseChunks;
  Duration sseChunkDelay = const Duration(milliseconds: 20);

  static Future<_FakeUpstream> start() async {
    final server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, /* port */ 0);
    // 模拟真实 OpenAI 兼容端点：不自动 gzip（代理 outbound 已关 autoUncompress，
    // 不会带 accept-encoding）。
    server.autoCompress = false;
    final fake = _FakeUpstream._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final body = <int>[];
    await for (final chunk in req) {
      body.addAll(chunk);
    }
    final headers = <String, String>{};
    req.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values.join(',');
    });
    requests.add(_UpstreamRequest(
      method: req.method,
      path: req.uri.path,
      headers: headers,
      body: body,
    ));

    final resp = req.response;
    resp.statusCode = statusCode;
    respHeaders.forEach((name, value) => resp.headers.set(name, value));
    if (sseChunks != null) {
      // 关闭响应层小 chunk 缓冲：分块间延迟 + 逐块 flush，使「真流式透传
      // 时序」测试对代理缓冲实现有灵敏度（缓冲实现首字节必迟到）。
      resp.bufferOutput = false;
      resp.headers.set(HttpHeaders.contentTypeHeader, 'text/event-stream');
      for (final chunk in sseChunks!) {
        if (sseChunkDelay > Duration.zero) {
          await Future<void>.delayed(sseChunkDelay);
        }
        resp.add(utf8.encode(chunk));
        await resp.flush();
      }
      await resp.close();
      return;
    }
    final bodyBytes = bodyProvider();
    if (hasBody) {
      // 显式 content-length：断言代理响应侧已剥除（服务端仍按流式补帧）。
      resp.headers.set(HttpHeaders.contentLengthHeader, '${bodyBytes.length}');
      resp.add(bodyBytes);
    }
    await resp.close();
  }
}

/// 经代理的请求结果（状态码 + 头 + 字节体）。
class _ProxyResult {
  _ProxyResult(this.status, this.headers, this.body);

  final int status;

  /// 头名小写 → join 值。
  final Map<String, String> headers;

  final List<int> body;

  String get text => utf8.decode(body);
}

/// 真实 HttpClient 经代理发任意 method：返回状态码 + 头 + 字节体。
Future<_ProxyResult> _proxyRequest(
  int port,
  String method,
  String path, {
  Map<String, String> headers = const {},
  List<int>? body,
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    headers.forEach((name, value) => req.headers.set(name, value));
    if (body != null) {
      req.add(body);
    }
    final resp = await req.close();
    final outHeaders = <String, String>{};
    resp.headers.forEach((name, values) {
      outHeaders[name.toLowerCase()] = values.join(',');
    });
    final outBody = <int>[];
    await for (final chunk in resp) {
      outBody.addAll(chunk);
    }
    return _ProxyResult(resp.statusCode, outHeaders, outBody);
  } finally {
    client.close(force: true);
  }
}

/// 反代 reader fake：返回给定配置（null = 未配置）。
Future<ProxyRouteConfig?> Function() _readerFor(ProxyRouteConfig? config) =>
    () async => config;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // flutter_test 绑定初始化后，全局 HttpOverrides 被替换为返回 400 的 mock，
    // 一切真实 HTTP 被拦（不在测试期发行真实网络请求的默认口径）。本 seam 的
    // 契约恰是「真起监听 + 真实 HttpClient 走路由全矩阵」（spec §7 测试决策），
    // 还原为 null 使 dart:io 走真实 socket——仅影响本套件进程内网络，不旁路
    // 平台通道断言。
    HttpOverrides.global = null;
  });

  group('SimulatorServer — 生命周期', () {
    test('start(port: 0) 返回真实监听端口，真实 HttpClient 可访问（port 0 得实际端口）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      expect(port, greaterThan(0));
      expect(server.isRunning, isTrue);
      expect(server.port, port);

      final (status, _, _) = await httpGet(port, '/');
      expect(status, 200, reason: '真实监听已起，HttpClient 可走通');
      await server.stop();
    });

    test('重复 start 幂等：已在运行返回同一端口，不新绑定不抛', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port1 = await server.start(port: 0);
      final port2 = await server.start(port: 0);
      expect(port2, port1, reason: '已在运行 → 返回既有端口（不重复 bind）');
      await server.stop();
    });

    test('stop 幂等可重入：重复 stop 不抛；isRunning 状态翻转', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      await server.start(port: 0);
      expect(server.isRunning, isTrue);
      await server.stop();
      expect(server.isRunning, isFalse);
      await server.stop();
      await server.stop();
      expect(server.isRunning, isFalse);
    });

    test('stop 后同端口重绑成功（App 存续期常驻可重绑）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);
      await server.stop();
      final reExit = await server.start(port: port);
      expect(reExit, port, reason: 'stop 释放端口后可重绑同端口成功');
      final (status, _, _) = await httpGet(port, '/');
      expect(status, 200);
      await server.stop();
    });

    test('stop 后不再响应：连接被拒（SocketException）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);
      await server.stop();
      await expectLater(
        Socket.connect('127.0.0.1', port).then((s) => s.destroy()),
        throwsA(isA<SocketException>()),
        reason: '监听已关闭，连接必须失败而非挂起',
      );
    });
  });

  group('SimulatorServer — 路由契约', () {
    test('GET /simulators/manifest.json → 200 + application/json + 原文', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      final (status, ct, body) = await httpGet(port, '/simulators/manifest.json');
      expect(status, 200);
      expect(ct, 'application/json');
      expect(body, '{"version":2,"simulators":[]}');
      await server.stop();
    });

    test('GET /simulators/<file>.html → 200 + text/html; charset=utf-8 + 原样内容', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      final (status, ct, body) = await httpGet(port, '/simulators/game-a.html');
      expect(status, 200);
      expect(ct, 'text/html; charset=utf-8');
      expect(body, '<html><body>GAME A</body></html>');
      await server.stop();
    });

    test('GET /simulators/<中文文件>.html → 200（URL 编码请求路径解码到达文件）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      final encoded = Uri.encodeComponent('人生模拟器v3.html');
      final (status, ct, body) = await httpGet(port, '/simulators/$encoded');
      expect(status, 200);
      expect(ct, 'text/html; charset=utf-8');
      expect(body, '<html>中文游戏</html>');
      await server.stop();
    });

    test('GET / → 最小 index HTML，含可识别文案，text/html; charset=utf-8', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      final (status, ct, body) = await httpGet(port, '/');
      expect(status, 200);
      expect(ct, 'text/html; charset=utf-8');
      expect(body, contains('Conver System 模拟器'),
          reason: '可识别文案供存档 sheet 建立 server origin');
      await server.stop();
    });

    test('文件名不存在（simulators/<x>）→ 404（html 与 json 各一）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      expect((await httpGet(port, '/simulators/missing.html')).$1, 404);
      expect((await httpGet(port, '/simulators/missing.json')).$1, 404);
      await server.stop();
    });
  });

  group('SimulatorServer — Content-Type 两值手写映射', () {
    test('存在的 .css 文件仍 404（仅 .html / .json 两值）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      final (status, _, body) = await httpGet(port, '/simulators/style.css');
      expect(status, 404, reason: '非并列后缀即使文件存在也 404');
      expect(body, isNot(contains('body{color:red}')));
      await server.stop();
    });

    test('存在的无后缀文件仍 404（非并列后缀）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      final (status, _, _) = await httpGet(port, '/simulators/noext');
      expect(status, 404);
      await server.stop();
    });
  });

  group('SimulatorServer — 目录墙（路径穿越一律 404 且不触盘）', () {
    test('字面 .. 段穿越 → 404（../manifest.json 与 ../passwd-sentinel.html，不触盘）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      expect((await httpGet(port, '/simulators/../manifest.json')).$1, 404);
      final (st2, _, body2) = await httpGet(port, '/simulators/../passwd-sentinel.html');
      expect(st2, 404, reason: '字面 .. 经 Uri 规范化脱离 /simulators 前缀 → 404');
      expect(body2, isNot(contains(escapeTargetContent)), reason: '不触盘：逃逸落点文件内容不得泄漏');
      await server.stop();
    });

    test('%2e%2e 编码穿越 → 404（单层与多层，不触盘）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      expect((await httpGet(port, '/simulators/%2e%2e/manifest.json')).$1, 404);
      expect((await httpGet(port, '/simulators%2e%2e/%2e%2e/etc/passwd')).$1, 404);
      final (st3, _, body3) = await httpGet(port, '/simulators/%2e%2e/passwd-sentinel.html');
      expect(st3, 404);
      expect(body3, isNot(contains(escapeTargetContent)), reason: '编码 .. 走同一条规范化失配路径');
      final (st, _, body) = await httpGet(port, '/simulators/%2e%2e/outside-secret.json');
      expect(st, 404);
      expect(body, isNot(contains(secretContent)));
      await server.stop();
    });

    test('反斜杠隐藏分隔符（%5c）→ 404 且不触盘（逃逸落点存在，守卫失效必泄漏）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      final (st1, _, body1) = await httpGet(port, '/simulators/..%5cpasswd-sentinel.html');
      expect(st1, 404, reason: '段内解码出反斜杠（Windows 分隔符）→ 目录墙拒绝');
      expect(body1, isNot(contains(escapeTargetContent)),
          reason: 'simDir/../passwd-sentinel.html 真实存在：守卫失效即触发，本断言即灵敏度');
      final (st2, _, body2) = await httpGet(port, '/simulators/..%5c..%5coutside-secret.json');
      expect(st2, 404);
      expect(body2, isNot(contains(secretContent)), reason: '多级反斜杠逃逸不触盘');
      await server.stop();
    });

    test('段内解码出 / 分隔符（%2f）→ 404（单段内再分割的穿越面，不触盘）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      final (st1, _, body1) = await httpGet(port, '/simulators/..%2fpasswd-sentinel.html');
      expect(st1, 404, reason: '段内 ..%2f → ../：目录墙拒绝，逃逸落点不可达');
      expect(body1, isNot(contains(escapeTargetContent)));
      expect((await httpGet(port, '/simulators/game-a.html%2f..%2fmanifest.json')).$1, 404,
          reason: '单段再分割解析回 simDir 内既有文件也必须 404（不旁路守卫）');
      await server.stop();
    });

    test('绝对路径地址（/etc/passwd 等越界）→ 404', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      expect((await httpGet(port, '/etc/passwd')).$1, 404);
      expect((await httpGet(port, '/C:/windows/system32/drivers/etc/hosts')).$1, 404);
      await server.stop();
    });

    test('双斜杠 // 前缀（authority 歧义）→ 404', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      expect(await rawRequestStatus(port, '//simulators/manifest.json'), 404);
      await server.stop();
    });

    test('结构残缺：simulators/ 尾斜杠与无尾斜杠 → 404（缺文件段）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      expect((await httpGet(port, '/simulators/')).$1, 404);
      expect((await httpGet(port, '/simulators')).$1, 404);
      await server.stop();
    });
  });

  group('SimulatorServer — 方法与未知路径', () {
    test('非 GET 方法（POST/PUT/DELETE）→ 404', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      expect(await httpMethod(port, 'POST', '/simulators/manifest.json'), 404);
      expect(await httpMethod(port, 'PUT', '/simulators/game-a.html'), 404);
      expect(await httpMethod(port, 'DELETE', '/simulators/game-a.html'), 404);
      await server.stop();
    });

    test('HEAD → 404（原始 socket 断言响应行状态码）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);
      final sock = await Socket.connect('127.0.0.1', port);
      sock.write('HEAD /simulators/game-a.html HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n');
      await sock.flush();
      final head = <int>[];
      await for (final c in sock) {
        head.addAll(c);
      }
      sock.destroy();
      final line = utf8.decode(head, allowMalformed: true).split('\r\n').first;
      expect(int.parse(line.split(' ')[1]), 404);
      await server.stop();
    });

    test('/simulators/ 之外前缀 → 404（只认固定目录前缀）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      expect((await httpGet(port, '/other/manifest.json')).$1, 404);
      expect((await httpGet(port, '/simulator/manifest.json')).$1, 404);
      await server.stop();
    });
  });

  group('SimulatorServer — 并发', () {
    test('并发 8 请求（混合路由）全部正确响应', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);
      final port = await server.start(port: 0);

      final results = await Future.wait(<Future<(int, String, String)>>[
        for (var i = 0; i < 8; i++)
          httpGet(port, i.isEven ? '/simulators/manifest.json' : '/simulators/game-a.html'),
      ]);
      for (final (status, _, _) in results) {
        expect(status, 200);
      }
      expect(results.first.$3, '{"version":2,"simulators":[]}');
      expect(results.last.$3, '<html><body>GAME A</body></html>');
      await server.stop();
    });
  });

  group('SimulatorServer — 固定端口被占', () {
    test('start(port: 8642) 且 8642 被占 → 明确抛错（含端口号），绝不静默换端口', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir);

      ServerSocket? holder;
      try {
        holder = await ServerSocket.bind(InternetAddress.loopbackIPv4, SimulatorContracts.defaultPort);
      } on SocketException {
        holder = null; // 8642 已被外部占用 → start 仍必须失败
      }
      addTearDown(() => holder?.close());

      await expectLater(
        server.start(port: SimulatorContracts.defaultPort),
        throwsA(isA<SimulatorPortInUseException>()
            .having((e) => e.port, 'port', SimulatorContracts.defaultPort)
            .having((e) => e.toString(), 'message', contains('${SimulatorContracts.defaultPort}'))),
        reason: '端口被占必须明确抛错且含端口信息（换端口 = 换 origin = 存档丢失）',
      );
      expect(server.isRunning, isFalse, reason: '抛错后未在监听');
    });
  });

  group('SimulatorServer — /proxy 反代 · 未配置防御', () {
    test('未注入 reader → /proxy 一律 503（防御），静态路由不受影响', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir); // 无 reader
      final port = await server.start(port: 0);

      for (final method in ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']) {
        final result = await _proxyRequest(port, method, '/proxy/v1/models');
        expect(result.status, 503, reason: '$method /proxy 未配置 → 503 不挂连接');
      }
      expect((await httpGet(port, '/simulators/manifest.json')).$1, 200,
          reason: '静态托管路由不受 /proxy 分支影响');
      await server.stop();
    });

    test('reader 返回 null（未配置）→ 503，文案可读', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(simDir, proxyConfigReader: _readerFor(null));
      final port = await server.start(port: 0);

      final (status, _, body) = await httpGet(port, '/proxy/v1/models');
      expect(status, 503);
      expect(body, contains('未配置 OpenAI 兼容端点'));
      await server.stop();
    });

    test('reader 返回 endpoint 空串 → 503（未配置语义）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(
          const ProxyRouteConfig(endpoint: '', apiKey: 'x'),
        ),
      );
      final port = await server.start(port: 0);

      expect((await httpGet(port, '/proxy/v1/models')).$1, 503);
      await server.stop();
    });

    test('reader 抛错 → 503 防御（配置读取失败视同未配置）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: () async => throw StateError('secret store down'),
      );
      final port = await server.start(port: 0);

      expect((await httpGet(port, '/proxy/v1/models')).$1, 503);
      await server.stop();
    });

    test('endpoint 无 netloc → 503（OpenAI 兼容端点无效语义）', () async {
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(
          const ProxyRouteConfig(endpoint: 'not-a-valid-url', apiKey: 'x'),
        ),
      );
      final port = await server.start(port: 0);

      final (status, _, body) = await httpGet(port, '/proxy/v1/models');
      expect(status, 503);
      expect(body, contains('OpenAI 兼容端点无效'));
      await server.stop();
    });
  });

  group('SimulatorServer — /proxy 反代 · 转发契约矩阵', () {
    test('POST 转发：method/目标/请求体逐字到达上游，App key 注入 Bearer，'
        '游戏 Authorization 被弃、自定义头透传、host/content-length/'
        'accept-encoding 剥除', () async {
      final upstream = await _FakeUpstream.start();
      addTearDown(upstream.close);
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${upstream.port}/v1',
          apiKey: 'app-secret-key',
        )),
      );
      final port = await server.start(port: 0);

      final body = '{"model":"deepseek-v4-flash","messages":[{"role":"user",'
          '"content":"hi"}]}';
      final result = await _proxyRequest(port, 'POST', '/proxy/v1/chat/completions',
        headers: {
          'authorization': 'Bearer game-token',
          'x-custom': 'keep-me',
          'accept-encoding': 'gzip',
          'content-type': 'application/json',
        },
        body: utf8.encode(body),
      );
      expect(result.status, 200);

      final req = upstream.requests.single;
      expect(req.method, 'POST', reason: '方法逐字转发');
      expect(req.path, '/v1/chat/completions', reason: '请求 path 原样拼到 netloc');
      expect(req.bodyText, body, reason: '聊天 payload 逐字透传');
      expect(req.headers['authorization'], 'Bearer app-secret-key',
          reason: 'App 侧 key 注入 Bearer，游戏 Authorization 被弃');
      expect(req.headers['x-custom'], 'keep-me', reason: '自定义头原样透传');
      expect(req.headers['host'], '127.0.0.1:${upstream.port}',
          reason: 'host 由 HttpClient 按目标重建（不转发游戏 Host）');
      expect(req.headers['content-length'], isNull,
          reason: 'content-length 剥除（服务端按流式补帧）');
      expect(req.headers['accept-encoding'], isNull,
          reason: 'accept-encoding 剥除（压缩层语义）');
      expect(req.headers['connection'], isNull, reason: 'connection 不转发');
      await server.stop();
    });

    test('App key 为空 → 不注入 Authorization；游戏 Authorization 仍被丢弃', () async {
      final upstream = await _FakeUpstream.start();
      addTearDown(upstream.close);
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${upstream.port}/v1',
          apiKey: '',
        )),
      );
      final port = await server.start(port: 0);

      await _proxyRequest(port, 'GET', '/proxy/v1/models',
        headers: {'authorization': 'Bearer game-token'});
      final req = upstream.requests.single;
      expect(req.headers['authorization'], isNull,
          reason: 'App key 为空 → 不注入 Authorization，游戏头也不达上游');
      await server.stop();
    });

    test('目标解析：base 自身 path 段（/v1）不参与拼接，短路径 /v1/models 命中', () async {
      final upstream = await _FakeUpstream.start();
      addTearDown(upstream.close);
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${upstream.port}/v1', // base 含 /v1
          apiKey: 'k',
        )),
      );
      final port = await server.start(port: 0);

      final result = await _proxyRequest(port, 'GET', '/proxy/v1/models');
      expect(result.status, 200);
      expect(upstream.requests.single.path, '/v1/models',
          reason: '/v1 来自请求 path（不重复拼接 base 自身 path 段）');
      await server.stop();
    });

    test('目标解析：base 无 path 段（netloc-only）→ 请求 path 原样追加', () async {
      final upstream = await _FakeUpstream.start();
      addTearDown(upstream.close);
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${upstream.port}', // 无路径
          apiKey: 'k',
        )),
      );
      final port = await server.start(port: 0);

      await _proxyRequest(port, 'GET', '/proxy/v1/models');
      expect(upstream.requests.single.path, '/v1/models');
      await server.stop();
    });

    test('任意 method 转发（GET/PUT/PATCH/DELETE/OPTIONS/HEAD）到达上游同一目标', () async {
      final upstream = await _FakeUpstream.start();
      addTearDown(upstream.close);
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${upstream.port}/v1',
          apiKey: 'k',
        )),
      );
      final port = await server.start(port: 0);

      for (final method in ['GET', 'PUT', 'PATCH', 'DELETE', 'OPTIONS', 'HEAD']) {
        final result = await _proxyRequest(port, method, '/proxy/v1/resource',
          headers: const {'access-control-request-method': 'POST'},
        );
        expect(result.status, 200, reason: '$method 透传且上游响应回传');
        if (method == 'HEAD') {
          expect(result.body, isEmpty, reason: 'HEAD 无响应体');
        }
      }
      expect(upstream.requests.map((r) => r.method), [
        'GET', 'PUT', 'PATCH', 'DELETE', 'OPTIONS', 'HEAD',
      ], reason: '方法逐一到达上游');
      expect(upstream.requests.first.path, '/v1/resource');
      await server.stop();
    });

    test('上游非 2xx 状态码透传（404）且响应体回传', () async {
      final upstream = await _FakeUpstream.start();
      addTearDown(upstream.close);
      upstream.statusCode = HttpStatus.notFound;
      upstream.bodyProvider = () => utf8.encode('{"error":"no such model"}');
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${upstream.port}/v1',
          apiKey: 'k',
        )),
      );
      final port = await server.start(port: 0);

      final result = await _proxyRequest(port, 'GET', '/proxy/v1/models');
      expect(result.status, 404, reason: '上游状态码透传');
      expect(result.text, '{"error":"no such model"}');
      await server.stop();
    });

    test('上游连接失败 → 502 明确状态码（转发失败语义），不挂连接', () async {
      // 先占一个端口再释放 → 保证连接被拒（而非撞上其他服务）。
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:$deadPort/v1',
          apiKey: 'k',
        )),
      );
      final port = await server.start(port: 0);

      final result = await _proxyRequest(port, 'GET', '/proxy/v1/models');
      expect(result.status, 502, reason: '上游不可达 → Bad Gateway 明确状态码');
      expect(result.text, contains('502'), reason: '文案可读');
      await server.stop();
    });

    test('裸 /proxy（无子路径）→ 转发到上游根路径，不挂连接不崩', () async {
      final upstream = await _FakeUpstream.start();
      addTearDown(upstream.close);
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${upstream.port}/v1',
          apiKey: 'k',
        )),
      );
      final port = await server.start(port: 0);

      for (final path in ['/proxy', '/proxy/']) {
        final result = await _proxyRequest(port, 'GET', path);
        expect(result.status, 200, reason: '$path 转发到上游根路径');
        expect(upstream.requests.last.path, '/');
      }
      await server.stop();
    });

    test('并发 6 个 /proxy 请求全部正确转发（独立 HttpClient 无共享状态竞态）', () async {
      final upstream = await _FakeUpstream.start();
      addTearDown(upstream.close);
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${upstream.port}/v1',
          apiKey: 'k',
        )),
      );
      final port = await server.start(port: 0);

      final results = await Future.wait(<Future<_ProxyResult>>[
        for (var i = 0; i < 6; i++)
          _proxyRequest(port, i.isEven ? 'GET' : 'POST',
              '/proxy/v1/chat/completions',
              body: i.isEven ? null : utf8.encode('{"n":$i}')),
      ]);
      for (final r in results) {
        expect(r.status, 200);
      }
      expect(upstream.requests.length, 6);
      expect(
        upstream.requests.map((r) => r.method).where((m) => m == 'POST').length,
        3,
      );
      await server.stop();
    });
  });

  group('SimulatorServer — /proxy 反代 · SSE 流式透传', () {
    test('SSE 分块流逐字节回传：状态码 + 头透传（content-length 除外），'
        '响应体字节保真', () async {
      final upstream = await _FakeUpstream.start();
      addTearDown(upstream.close);
      upstream.respHeaders = {'x-custom-resp': 'hello-upstream'};
      upstream.sseChunks = [
        'data: {"choices":[{"delta":{"content":"你"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":"好"}}]}\n\n',
        'data: [DONE]\n\n',
      ];
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${upstream.port}/v1',
          apiKey: 'k',
        )),
      );
      final port = await server.start(port: 0);

      final result = await _proxyRequest(port, 'POST', '/proxy/v1/chat/completions',
        body: utf8.encode('{"stream":true}'),
      );
      expect(result.status, 200);
      expect(result.headers['content-type'], 'text/event-stream',
          reason: '响应 content-type 透传');
      expect(result.headers['x-custom-resp'], 'hello-upstream',
          reason: '自定义响应头透传');
      expect(result.headers['content-length'], isNull,
          reason: '响应 content-length 剥除（流式补帧）');
      expect(result.text,
          'data: {"choices":[{"delta":{"content":"你"}}]}\n\n'
          'data: {"choices":[{"delta":{"content":"好"}}]}\n\n'
          'data: [DONE]\n\n',
          reason: 'SSE 帧逐字节透传（含 UTF-8 中文）');
      await server.stop();
    });

    test('流式透传时序：首字节早于上游全部帧完成（逐块冲洗，非整响应缓冲）', () async {
      final upstream = await _FakeUpstream.start();
      addTearDown(upstream.close);
      upstream.sseChunks = ['A', 'B', 'C'];
      upstream.sseChunkDelay = const Duration(milliseconds: 350);
      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${upstream.port}/v1',
          apiKey: 'k',
        )),
      );
      final port = await server.start(port: 0);

      final client = HttpClient();
      final sw = Stopwatch()..start();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/proxy/v1/chat/completions'),
      );
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(utf8.encode('{"stream":true}'));
      final resp = await req.close();
      Duration? firstChunkAt;
      final received = <int>[];
      await for (final chunk in resp) {
        firstChunkAt ??= sw.elapsed;
        received.addAll(chunk);
      }
      client.close(force: true);

      // 上游总时长 ≈ 3×350ms ≈ 1050ms；真流式透传首字节应在 700ms 内到达
      // （整响应缓冲则必须等上游 close 后才发首字节）。
      expect(firstChunkAt, isNotNull, reason: '响应流到达');
      expect(firstChunkAt!.inMilliseconds, lessThan(700),
          reason: '首字节逐块冲洗回传（缓冲实现必在 ~1050ms 后才发首字节）');
      expect(utf8.decode(received), 'ABC', reason: '字节保真');
      await server.stop();
    });

    test('上游接受连接但不响应（stall）：连接超时（注入短值）→ 502 不挂连接', () async {
      // 上游裸监听：接受连接并读完请求体，但永不响应（模拟上游挂死——
      // _FakeUpstream 常路径必响应，无法表达 stall，故单独绑一个）。
      final stall = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => stall.close(force: true));
      stall.listen((HttpRequest req) {
        req.drain<void>().ignore();
      });

      final simDir = await makeSimDir();
      final server = SimulatorServer(
        simDir,
        proxyConfigReader: _readerFor(ProxyRouteConfig(
          endpoint: 'http://127.0.0.1:${stall.port}/v1',
          apiKey: 'k',
        )),
        proxyConnectTimeout: const Duration(milliseconds: 300),
      );
      final port = await server.start(port: 0);

      final sw = Stopwatch()..start();
      final result =
          await _proxyRequest(port, 'POST', '/proxy/v1/chat/completions',
              body: utf8.encode('{"stream":true}'));
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: 'connectionTimeout 生效：stall 在 ~300ms 超时，绝不无限挂起');
      expect(result.status, HttpStatus.badGateway,
          reason: '上游超时 → 502（明确状态码，不挂连接）');
      await server.stop();
    });
  });
}