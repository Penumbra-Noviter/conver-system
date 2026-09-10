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
/// - **T3 同源反代（/proxy 路由）**：请求 path 首段 ==
///   [SimulatorContracts.proxyPrefix]，任意 method → 转发到「配置的 OpenAI
///   兼容 base」的 `scheme://netloc` + 请求剩余 path；游戏 Authorization 被弃、
///   App 侧 key 注入 Bearer（空 key 不注入）；其余请求头透传（剥
///   host/content-length/authorization/connection/accept-encoding）；请求体与
///   响应（SSE 流式，逐块冲洗）逐字节透传，响应 content-length 剥除；
///   未配置（reader 未注入 / 返回 null / endpoint 空或无 netloc / 读取抛错）→
///   503；上游不可达 → 502。凭据面经 [proxyConfigReader] 构造注入——server
///   是纯 Dart 托管模块，不 import 数据层（凭据来源与注入链同源：app.dart 接
///   `SettingsRepository.baseUrl('openai')` + `SecretStore` openai 槽）。
///
/// 协议表面（深模块，外部只通过这些符号与本模块交互）：
/// `SimulatorServer` / `SimulatorPortInUseException` / `ProxyRouteConfig` /
/// `ProxyConfigReader`。
library;

import 'dart:convert' show utf8;
import 'dart:io';

import 'simulator_contracts.dart' show SimulatorContracts;

// 构造公开命名参数 proxyConfigReader 赋私有 `_` 字段：initializing formal 无法
// 同时满足「装配点语义 + 私有字段」（对齐 simulators_controller.dart 惯例）。
// ignore_for_file: prefer_initializing_formals

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

/// 反代路由配置（T3）——被代理目标端点 + 注入密钥。
///
/// 语义对齐桌面 `api/routes/simulators.py` 反代的 creds 面：
/// - [endpoint]：配置的 OpenAI 兼容 base（如 `https://host/v1`）。目标拼接只
///   取 `scheme://netloc`，endpoint 自身 path 段不参与（注入改写已把该段写入
///   请求 path，避免 `/v1` 重复）；空串 / 无 netloc → 视为未配置（503）。
/// - [apiKey]：为空串 → 不注入 Authorization（桌面语义：仅 api_key 非空注入
///   `Authorization: Bearer <key>`）；claude key 恒不进（装配面只暴露 openai
///   协议槽凭据）。本类不读任何存储，纯数据。
class ProxyRouteConfig {
  /// 构造反代配置。
  const ProxyRouteConfig({required this.endpoint, required this.apiKey});

  /// 配置的 OpenAI 兼容 base URL（`scheme://netloc` 参与目标拼接）。
  final String endpoint;

  /// App 侧密钥（非空 → 注入 Bearer；空串 → 不注入）。
  final String apiKey;
}

/// 反代凭据读取 seam：返回「OpenAI 兼容 base + key」配置；null / 抛错 → 未
/// 配置（/proxy 一律 503 防御）。构造注入——测试注入 fake，生产接 app.dart
/// 装配面（`SettingsRepository.baseUrl('openai')` + SecretStore openai 槽）。
typedef ProxyConfigReader = Future<ProxyRouteConfig?> Function();

/// 模拟器本地托管服务器深模块：serve [simDir]（模拟器数据目录）下游戏文件。
///
/// 生产装配（F-M5-03）：`SimulatorServer(simDir: await SimulatorDataDir().resolve())`
/// → 懒启动 `start(port: SimulatorContracts.defaultPort)`（首进模拟器 tab 时
/// bind，App 存续期常驻）。
class SimulatorServer {
  /// 构造：serve 根目录 [simDir]（模拟器数据目录，含 manifest.json 与游戏
  /// HTML，由 F-M5-01 种子产出）。固定绑定回环，不提供公网地址参数。
  ///
  /// T3：可选 [proxyConfigReader] 注入 /proxy 反代凭据 seam（未注入 → /proxy
  /// 一律 503 防御）；[SimulatorServerFactory] typedef 的单参签名保持兼容，
  /// 控制器零改动。可选 [proxyConnectTimeout] 覆盖反代上游连接超时
  /// （缺省 [defaultProxyConnectTimeout] = 60s，spec D3 对齐桌面 httpx
  /// timeout=60；测试注入短值验证 stall 场景）。
  SimulatorServer(
    this._simDir, {
    ProxyConfigReader? proxyConfigReader,
    Duration proxyConnectTimeout = defaultProxyConnectTimeout,
  })  : _proxyConfigReader = proxyConfigReader,
        _proxyConnectTimeout = proxyConnectTimeout;

  /// 反代上游连接超时缺省值（spec D3：对齐桌面 httpx timeout=60）。
  static const Duration defaultProxyConnectTimeout = Duration(seconds: 60);

  final Directory _simDir;
  final ProxyConfigReader? _proxyConfigReader;
  final Duration _proxyConnectTimeout;

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
      // 关闭服务端自动 gzip（dart HttpServer 缺省 true）：/proxy 反代响应
      // 必须逐字节透传（内容编码由上游原样回传，游戏 fetch 自行解压）；且
      // gzip 压缩会把 SSE 小分块积压到流尾，破坏打字机效果。
      server.autoCompress = false;
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
  ///
  /// T3：`/proxy` 前缀命中 → 独立反代分支（任意 method，转发 + 流式回传），
  /// **不进** GET 静态托管逻辑；既有路由行为（GET /simulators/*、GET /、
  /// 404、非 GET 静态）完全不变。
  Future<void> _handle(HttpRequest req) async {
    final resp = req.response;
    var status = HttpStatus.notFound;
    var contentType = _textPlainType;
    var body = utf8.encode('404 Not Found');

    try {
      if (_isProxyPath(req.uri)) {
        await _handleProxy(req);
        return;
      }
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

  // ── T3 · /proxy 同源反代（桌面 api/routes/simulators.py 逐字语义）─────────

  /// 是否命中 /proxy 反代前缀（首段 == `SimulatorContracts.proxyPrefix` 去首
  /// 斜杠；常量单源消费，T2 模板占位符替换值与本路由匹配共用同一字面量）。
  bool _isProxyPath(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.isEmpty) {
      return false;
    }
    final prefix =
        SimulatorContracts.proxyPrefix.replaceFirst(RegExp(r'^/+'), '');
    return segments.first == prefix;
  }

  /// 反代处理：读取配置 → 目标解析 → 头组装 → HttpClient 流式转发 → 响应
  /// 逐块回传。错误分级（对齐桌面 HTTPException 语义）：未配置（reader 未注入
  /// / 返回 null / 抛错 / endpoint 空串 / 无 netloc）→ 503；上游连接失败 →
  /// 502；流中客户端断开 → 静默关闭（不挂连接）。
  Future<void> _handleProxy(HttpRequest req) async {
    final resp = req.response;

    final config = await _resolveProxyConfig();
    if (config == null) {
      await _closePlain(
        resp,
        HttpStatus.serviceUnavailable,
        _unconfiguredEndpointMessage,
      );
      return;
    }
    final target =
        _buildProxyTarget(config.endpoint, _proxyRemainingPath(req.uri));
    if (target == null) {
      await _closePlain(
        resp,
        HttpStatus.serviceUnavailable,
        _invalidEndpointMessage,
      );
      return;
    }

    // 连接超时（spec D3：缺省 60s 对齐桌面 httpx timeout=60；测试可注入短值）；
    // autoUncompress 关闭保持字节保真（见下 accept-encoding 剥除注释）。
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = _proxyConnectTimeout;
    try {
      final outReq = await client.openUrl(req.method, Uri.parse(target));
      _copyRequestHeaders(req, outReq);
      // dart HttpClient 无条件注入 `accept-encoding: gzip`（与文化无关的 SDK
      // 行为）——剥除：与桌面 `_PROXY_SKIP_HEADERS` 一致，压缩协商层不转发，
      // 上游以 identity 回传（字节保真；配合 outbound autoUncompress=false，
      // 若上游无视协商仍 gzip，则原样回传 + content-encoding 头由游戏自行解压）。
      outReq.headers.removeAll(HttpHeaders.acceptEncodingHeader);
      if (config.apiKey.isNotEmpty) {
        outReq.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${config.apiKey}',
        );
      }
      // 请求体逐字节透传（addStream）后 close 得上游响应（dart:io 流式先例）。
      // 全相位超时（spec D3 对齐桌面 httpx timeout=60）：connectionTimeout
      // 只管连接建立；上游「接受连接但不返回响应头 / 响应体 stall」须由
      // close() 与响应流的 timeout 兜底（桌面 httpx 全局 timeout 语义），
      // 否则请求无限挂起。
      await outReq.addStream(req);
      final outResp =
          await outReq.close().timeout(_proxyConnectTimeout);

      try {
        resp.statusCode = outResp.statusCode;
        // 关闭响应层小 chunk 缓冲（dart HttpServer 缺省缓冲到缓冲区满/close
        // 才落 socket）：SSE 逐 token 分块必须逐块直写，否则游戏端首 token
        // 迟到、打字机效果坏掉。必须早于任何响应字节写出。
        resp.bufferOutput = false;
        outResp.headers.forEach((name, values) {
          final lower = name.toLowerCase();
          if (lower == HttpHeaders.contentLengthHeader ||
              lower == HttpHeaders.transferEncodingHeader) {
            return; // 响应头剥 content-length/transfer-encoding：流式补帧。
          }
          resp.headers.add(name, values);
        });
        // SSE 兼容：逐块回写 + 逐块 flush；客户端提前断开 → 静默关闭。
        // 响应体读取同样受 [_proxyConnectTimeout] 约束（数据间静默 stall 兜底）。
        await for (final chunk in outResp.timeout(_proxyConnectTimeout)) {
          resp.add(chunk);
          await resp.flush();
        }
        await resp.close();
      } catch (_) {
        try {
          await resp.close();
        } catch (_) {}
      }
    } catch (_) {
      // 上游连接失败 / 请求体转发失败 → 502（明确状态码，不挂连接）。
      try {
        await _closePlain(
          resp,
          HttpStatus.badGateway,
          '502 Bad Gateway：转发上游请求失败',
        );
      } catch (_) {}
    } finally {
      client.close(force: true);
    }
  }

  /// 读取反代凭据配置；reader 未注入 / 抛错 → null（视同未配置 → 503 防御）。
  Future<ProxyRouteConfig?> _resolveProxyConfig() async {
    final reader = _proxyConfigReader;
    if (reader == null) {
      return null;
    }
    try {
      return await reader();
    } catch (_) {
      return null;
    }
  }

  /// 反代剩余 path：`/proxy` 首段之后各段解码后 join（桌面 FastAPI
  /// `{path:path}` 解码 path 语义对齐；OpenAI 面为简单 ASCII 路径）。
  static String _proxyRemainingPath(Uri uri) =>
      uri.pathSegments.skip(1).join('/');

  /// 目标解析（桌面 `_build_proxy_target` 逐字）：endpoint 取 `scheme://netloc`
  /// （endpoint 自身 path 段不参与拼接，避免 `/v1` 重复）+ 请求剩余 path；
  /// scheme 缺失回退 https；无 netloc → null（→ 503）。
  static String? _buildProxyTarget(String endpoint, String path) {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || uri.authority.isEmpty) {
      return null;
    }
    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    final remaining = path.replaceFirst(RegExp(r'^/+'), '');
    return '$scheme://${uri.authority}/$remaining';
  }

  /// 转发请求头剥除集（桌面 `_PROXY_SKIP_HEADERS` 逐字）：host（HttpClient 按
  /// 目标重建）、content-length（服务端按流式补帧）、authorization（App 侧统一
  /// 注入）、connection / accept-encoding（连接层，不转发）。
  static const Set<String> _proxySkipHeaders = <String>{
    HttpHeaders.hostHeader,
    HttpHeaders.contentLengthHeader,
    HttpHeaders.authorizationHeader,
    HttpHeaders.connectionHeader,
    HttpHeaders.acceptEncodingHeader,
  };

  /// 复制请求头（剥除集内键跳过；其余原样透传含 Accept，保持上游协商）。
  static void _copyRequestHeaders(HttpRequest from, HttpClientRequest to) {
    from.headers.forEach((name, values) {
      if (_proxySkipHeaders.contains(name.toLowerCase())) {
        return;
      }
      to.headers.add(name, values);
    });
  }

  /// 写终态错误响应（正文可读；客户端断开静默收尾）。
  Future<void> _closePlain(HttpResponse resp, int status, String message) async {
    resp.statusCode = status;
    resp.headers.contentType = ContentType.parse(_textPlainType);
    final body = utf8.encode(message);
    try {
      resp.add(body);
      await resp.close();
    } catch (_) {
      try {
        await resp.close();
      } catch (_) {}
    }
  }

  /// 未配置端点 503 文案（桌面 detail 逐字）。
  static const String _unconfiguredEndpointMessage =
      '未配置 OpenAI 兼容端点，无法代理模拟器 API';

  /// 端点无效 503 文案（桌面 detail 逐字）。
  static const String _invalidEndpointMessage =
      'OpenAI 兼容端点无效，无法代理模拟器 API';

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
