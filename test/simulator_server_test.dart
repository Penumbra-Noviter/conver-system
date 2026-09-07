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
}