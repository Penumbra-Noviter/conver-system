/// 模拟器本地 HTTP 托管深模块（F-M5-02）——`dart:io HttpServer` 以普通 http
/// 源（`127.0.0.1:8642`）同源托管游戏 HTML / manifest：localStorage 正常持久化、
/// CORS 行为与桌面同构。
///
/// 契约（spec §4.2-3 / 工单 F-M5-02 验收语义契约逐条）：
/// - 生命周期：`start({required port})` 绑定回环（[InternetAddress.loopbackIPv4]，
///   无公网暴露）并返回**真实监听端口**（测试传 0 得实际端口；生产固定 8642）；
///   已在运行 → 幂等返回既有端口不重复 bind；`stop()` 幂等可重入；stop 后同
///   端口可重绑（App 存续期常驻）。固定端口被占 → 抛 [SimulatorPortInUseException]
///   （含端口号，语义可读），**绝不静默换端口**——换端口 = 换 origin =
///   localStorage 存档静默丢失（共识 D5）。
/// - 路由：`GET /simulators/manifest.json` → 目录下 manifest 原文 +
///   `application/json`；`GET /simulators/<file>.html` → 文件原样 +
///   `text/html; charset=utf-8`；`GET /` → 最小 index HTML（含可识别文案，供
///   存档 sheet 建立 server origin）；其余路径 / 非 GET 方法 → 404。
/// - 目录墙（穿越守卫）：以 `request.uri.pathSegments`（已解码 + 规范化的
///   规范化路径）校验——结构必须恰为 `[simDir, <file>]` 两段且前缀段恰等于
///   [SimulatorContracts.simDir]；文件段拒绝空串 / `..` / 含 `/` 或 `\`（解码
///   后段内分隔符，Windows 隐藏分隔符逃逸面）。`..` 段与 `%2e%2e` 被 Dart
///   Uri 规范化消解后必然脱离 `/simulators` 前缀 → 前缀失配 404；段内解码
///   分隔符（`..%5c` / `%2f`）因 Uri 解码不重新分割段而保留在段内 → 显式
///   拒绝。越界一律 404 且不触盘。
/// - Content-Type 两值手写映射（.html / .json，其余后缀 404），**不引 mime /
///   shelf 包**（依赖版本清单零新增，共识 D15）。
///
/// 协议表面（深模块，外部只通过这些符号与本模块交互）：
/// `SimulatorServer` / `SimulatorPortInUseException`。
library;

import 'dart:convert' show utf8;
import 'dart:io';

import 'simulator_contracts.dart' show SimulatorContracts;

/// 固定端口被占异常（共识 D5）——错误含端口号、语义可读；抛错 = 明确错误态，
/// 由 F-M5-03 承载 UI 错误态 + 重试按钮。
class SimulatorPortInUseException implements Exception {
  /// 构造：被占端口 [port] 与底层 [SocketException]（可空）。
  const SimulatorPortInUseException(this.port, [this.underlying]);

  /// 请求绑定的固定端口号。
  final int port;

  /// 底层 socket 异常（用于日志/诊断，可空）。
  final SocketException? underlying;

  @override
  String toString() =>
      '本地模拟器服务器端口 $port 已被占用（换端口 = 换 origin = 存档丢失，'
      '绝不静默换端口）；请关闭占用该端口的进程后重试';
}

/// 模拟器本地托管服务器深模块：serve [simDir]（模拟器数据目录）下游戏文件。
///
/// 生产装配（F-M5-03）：`SimulatorServer(simDir: await SimulatorDataDir().resolve())`
/// → 懒启动 `start(port: SimulatorContracts.defaultPort)`（首进模拟器 tab 时
/// bind，App 存续期常驻）。
class SimulatorServer {
  /// 构造：serve 根目录 [simDir]（模拟器数据目录，含 manifest.json 与游戏
  /// HTML，由 F-M5-01 种子产出）。固定绑定回环，不提供公网地址参数。
  SimulatorServer(this._simDir);

  final Directory _simDir;

  HttpServer? _httpServer;

  /// 是否正在监听（start 成功 → true；stop / 启动失败 → false）。
  bool get isRunning => _httpServer != null;

  /// 当前实际监听端口（未监听时 0；监听时与 `start` 返回值一致）。
  int get port => _httpServer?.port ?? 0;

  /// 在回环地址上监听 [port]（0 = 系统分配）并返回实际绑定端口。
  ///
  /// 已在运行 → 幂等返回既有端口（不重复 bind 不抛）。绑定失败（端口被占）→
  /// 抛 [SimulatorPortInUseException]（绝不静默换端口）。
  Future<int> start({required int port}) async {
    if (_httpServer != null) {
      return _httpServer!.port;
    }
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _httpServer = server;
      server.listen(_handle);
      return server.port;
    } on SocketException catch (exc) {
      throw SimulatorPortInUseException(port, exc);
    }
  }

  /// 停止监听（幂等可重入：未监听时调用不抛；停止后可同端口重绑）。
  Future<void> stop() async {
    final server = _httpServer;
    _httpServer = null;
    await server?.close(force: true);
  }

  /// 每请求处理：先完整解析 (status, contentType, body) 再一次性写出，保证
  /// 请求必有终态（不挂连接）；异常一律 500 兜底不崩溃。
  Future<void> _handle(HttpRequest req) async {
    final resp = req.response;
    var status = HttpStatus.notFound;
    var contentType = _textPlainType;
    var body = utf8.encode('404 Not Found');

    try {
      if (req.method == 'GET') {
        final segments = req.uri.pathSegments;
        if (segments.isEmpty) {
          // GET / → 最小 index HTML（存档 sheet 经离屏 WebView 加载本页建立
          // server origin 访问 localStorage）。
          status = HttpStatus.ok;
          contentType = _htmlType;
          body = utf8.encode(_indexHtml);
        } else {
          final resolved = _resolveServerFile(segments);
          if (resolved != null && resolved.file.existsSync()) {
            status = HttpStatus.ok;
            contentType = resolved.contentType;
            body = await resolved.file.readAsBytes();
          }
        }
      }
    } catch (_) {
      // 读取竞态 / 文件系统异常 → 500（不是 404；不吞、不挂连接）。
      status = HttpStatus.internalServerError;
      contentType = _textPlainType;
      body = utf8.encode('500 Internal Server Error');
    }

    try {
      resp.statusCode = status;
      resp.headers.contentType = ContentType.parse(contentType);
      resp.add(body);
      await resp.close();
    } catch (_) {
      // 客户端提前断开等：保证终态，静默关闭。
      try {
        await resp.close();
      } catch (_) {}
    }
  }

  /// 目录墙：把规范化 pathSegments 解析为 serve 目标（含两值 Content-Type）。
  ///
  /// 结构必须恰为 `[simDir, <file>]`（两段不多不少）；文件段须通过
  /// [_isSafeFileSegment] 且后缀命中两值映射，否则返回 null（→ 404）。
  _ResolvedServerFile? _resolveServerFile(List<String> segments) {
    if (segments.length != 2) {
      return null;
    }
    if (segments[0] != SimulatorContracts.simDir) {
      return null;
    }
    final name = segments[1];
    if (!_isSafeFileSegment(name)) {
      return null;
    }
    final contentType = _contentTypeFor(name);
    if (contentType == null) {
      return null;
    }
    return _ResolvedServerFile(
      File('${_simDir.path}${Platform.pathSeparator}$name'),
      contentType,
    );
  }

  /// 文件段安全判据（解码后段级，目录墙第二道）：非空、非 `..`、段内不得含
  /// `/` 或 `\`——Uri.pathSegments 已做百分号解码（`%2f`→`/`、`%5c`→`\`）但
  /// **不重新分割段**，单段内解码出的分隔符在 Windows 上即隐藏路径穿越
  /// （`..\x` 逃逸 simDir），必须显式拒绝。
  static bool _isSafeFileSegment(String name) {
    if (name.isEmpty || name == '..') {
      return false;
    }
    return !name.contains('/') && !name.contains(r'\');
  }

  /// Content-Type 两值手写映射（不引 mime 包）：`.html` → `text/html;
  /// charset=utf-8`、`.json` → `application/json`；其余后缀 → null（404）。
  static String? _contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.html')) {
      return _htmlType;
    }
    if (lower.endsWith('.json')) {
      return _jsonType;
    }
    return null;
  }
}

/// 目录墙解析结果（serve 目标文件 + 命中 Content-Type）。
class _ResolvedServerFile {
  _ResolvedServerFile(this.file, this.contentType);

  final File file;
  final String contentType;
}

/// 两值 Content-Type 常量（手写映射，桌面同构）。
const String _htmlType = 'text/html; charset=utf-8';
const String _jsonType = 'application/json';
const String _textPlainType = 'text/plain; charset=utf-8';

/// 最小 index 页（含可识别文案；存档 sheet 经本页建立 server origin）。
const String _indexHtml = '<!DOCTYPE html>\n'
    '<html lang="zh-CN">\n'
    '<head><meta charset="utf-8"><title>Conver System 模拟器</title></head>\n'
    '<body>\n'
    '<h1>Conver System 模拟器</h1>\n'
    '<p>本地游戏托管服务</p>\n'
    '</body>\n'
    '</html>\n';
