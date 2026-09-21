/// 模拟器导入服务（F-M5-07）——校验链全量纯 Dart + manifest 原子注册。
///
/// 桌面权威源（只读，语义逐字锚点）：
/// - `desktop/backend/app/services/simulator_import.py`（导入族全部语义）：
///   校验矩阵（非 .html / 超 5MB / 空文件 / 缺名 → 400）、SHA-256 去重（409，
///   改名之前判定）、`sanitize_filename` / `slugify` / `next_available_filename`
///   （负向兼容规则逐字）、`probe_config` 三层（L1 严格 cfg- 三元组 → L2 关键词
///   启发全量候选 → L3 local）、`probe_endpoint_mode`、双层控件 id 扫描
///   （静态层手写标签扫描器 + 脚本层 raw-regex）、`scan_suspicious` 粗筛、编排
///   顺序（校验先于一切副作用；manifest 缺失/损坏先自愈落盘再算 id，避免两次
///   重建口径不一致；注册失败回滚已落盘文件不遗留孤儿）；
/// - `desktop/backend/app/services/simulator_manifest.py`（原子写契约）：
///   同目录 `.tmp` + 原子替换（Dart `File.rename` 对既有文件替换语义以实测
///   锁定，见测试），自愈重建（非法 JSON / 非 UTF-8 / 结构非预期 → 以磁盘现存
///   .html 重建 version=2 type=local）。
///
/// 与桌面的形态差异（语义等价）：桌面按 HTTP multipart 上传路径编排；移动端
/// 为本地 file_picker 路径，编排函数逐字对应——`validateImportInput` 供 UI
/// 预检复用（纯函数，零副作用，校验单源不重复）。恶意命中服务层只收集不拦截
/// （`scanSuspicious` 命中归 ImportResult.warnings），「拒绝 + 关键词清单 +
/// 强制二次确认」的交互决策归 `import_flow.dart`（共识 D13/Q14：比桌面「提示
/// 不拦截」更紧）。
///
/// 协议表面（深模块）：`maxImportBytes` / `maxFilenameBytes` /
/// `validateImportInput` / `sanitizeFilename` / `slugify` / `sha256Bytes` /
/// `findDuplicate` / `nextAvailableFilename` / `scanInputIds` / `probeConfig` /
/// `probeEndpointMode` / `scanSuspicious` / `readManifest` / `writeManifest` /
/// `readManifestOrRebuild` / `rebuildManifest` / `appendManifestEntry` /
/// `updateManifestEntryDescription` / `importGame` / `ImportResult` /
/// `SimulatorImportError` / `SimulatorDuplicateError` / `ManifestAppender`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'seed_service.dart' show manifestFileName;
import 'suspicious_patterns.dart' show SuspiciousPatterns;

/// 导入文件大小上限（≤5MB；桌面 MAX_IMPORT_BYTES 逐字）。
const int maxImportBytes = 5 * 1024 * 1024;

/// 文件名 UTF-8 字节上限（含 .html 后缀；桌面 F-17 定版 120 字节逐字——
/// Windows MAX_PATH = 260 全路径上限与 255 组件上限在真实数据目录前缀下不可
/// 达，120 = 260 - 常见前缀余量，超长名截断静默收敛）。
const int maxFilenameBytes = 120;

/// 文件名净化剔除字符：Windows 非法字符 + 路径分隔符 + `%` `#`（`#` 为 URL
/// fragment 分隔符，iframe src 截断风险）+ 控制字符（桌面 `_FORBIDDEN_FILENAME_CHARS` 逐字）。
const String _forbiddenFilenameChars = '<>:"/\\|?*%#';

/// Windows 保留设备名（大小写不敏感、带任意扩展名仍视为保留；判定取首点前
/// 组件——NUL.tar.gz 等价 NUL——mycon/com10/lpt10 等邻近名不受影响）。
const Set<String> _windowsReservedNames = {
  'con', 'prn', 'aux', 'nul',
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// cfg- 契约所需的三元组 input id（key-injector 探测用，常量单源——生成器
/// 校验层复用；桌面 CFG_REQUIRED_IDS 逐字）。
const Set<String> _cfgRequiredIds = {'cfg-endpoint', 'cfg-apikey', 'cfg-model'};

/// 端点字段关键词（id 判定；endpoint 组覆盖引擎系全部约定——endpoint/url
/// 子串 + base 结尾；database 等尾部 base 的非控件 id 属已接受残留，须三组
/// 同时命中才判 ai）。
final RegExp _endpointRe = RegExp(r'endpoint|url|base$', caseSensitive: false);
final RegExp _keyRe = RegExp(r'key', caseSensitive: false);
final RegExp _modelRe = RegExp(r'model', caseSensitive: false);

/// 脚本层 raw-regex：注释剥离后扫描 `<input|select ... id="...">`（覆盖 JS
/// 模板字符串渲染的运行时控件——静态层不解析 script 内容）。只匹配带引号 id
/// 形式，不匹配无引号形式（桌面 `_SCRIPT_TIER_RE` 同精度）。
final RegExp _scriptTierRe = RegExp(
  r'''<(?:input|select)\b[^>]*?\bid=["']([^"']+)["']''',
  caseSensitive: false,
);

/// 端点默认值提取正则（endpointMode 推断用）：匹配 JS 中 endpoint 赋值引号内
/// URL。
final RegExp _endpointDefaultRe = RegExp(
  r'''endpoint\s*[:=]\s*["'](https?://[^"']+)["']''',
  caseSensitive: false,
);

/// 原子写临时文件后缀（同目录临时文件 + rename；桌面 MANIFEST_TMP_SUFFIX
/// `.tmp` 逐字）。
const String _manifestTmpSuffix = '.tmp';

/// 导入校验失败（非 .html / 超 5MB / 空文件 / 缺文件名）→ 400 语义。
class SimulatorImportError implements Exception {
  const SimulatorImportError(this.message);

  /// 面向用户的失败文案（HTTP 400 detail 同构）。
  final String message;

  @override
  String toString() => message;
}

/// SHA-256 内容重复（文案含「已存在」）→ 409 语义。
class SimulatorDuplicateError implements Exception {
  const SimulatorDuplicateError(this.message);

  /// 面向用户的失败文案（HTTP 409 detail 同构）。
  final String message;

  @override
  String toString() => message;
}

/// manifest 追加回调（测试注入失败路径验证落盘回滚；生产默认
/// [appendManifestEntry]）。
typedef ManifestAppender =
    void Function(Directory simDir, Map<String, dynamic> entry);

/// 导入成功结果：game 为 manifest 条目 dict；renamed 是否自动改名；warnings
/// 粗筛命中键集（输出序 = [SuspiciousPatterns.keys] 声明序）。
class ImportResult {
  const ImportResult({
    required this.game,
    required this.renamed,
    required this.warnings,
  });

  /// manifest 条目（id/file/name/type/source，ai 时含 config、探测到时含
  /// endpointMode）。
  final Map<String, dynamic> game;

  /// 是否冲突自动改名。
  final bool renamed;

  /// 恶意模式粗筛命中键集（输出序 = [SuspiciousPatterns.keys] 声明序；空 = 干净，
  /// 非空由 UI 展示清单 + 二次确认）。
  final List<String> warnings;
}

/// 内容字节的 SHA-256 十六进制摘要（去重主键）。
String sha256Bytes(List<int> content) => sha256.convert(content).toString();

/// UTF-8 字节截断（不劈裂多字节字符；sanitize 与改名路径共用，桌面
/// `_truncate_utf8_bytes` 逐字）。
///
/// 仅当 s 编码后字节数超 [maxBytes] 才截断（未超原样返回）；按 Unicode 码点
/// 累加完整字符字节数，到顶即停——等价桌面「字节截 + 回落完整字符边界 +
/// errors=ignore 丢弃残缺序列」（Dart `allowMalformed` 会以 U+FFFD 替换残缺
/// 序列而非丢弃，故不采用）；截断后复用首尾点/空格剔除（防截出尾随点等非法
/// 形态）。截断为空时返回空串，兜底回退由调用方决定。
String _truncateUtf8Bytes(String s, int maxBytes) {
  if (utf8.encode(s).length <= maxBytes) {
    return s;
  }
  final out = StringBuffer();
  var used = 0;
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    final byteLength = utf8.encode(ch).length;
    if (used + byteLength > maxBytes) {
      break;
    }
    out.write(ch);
    used += byteLength;
  }
  return _stripDotsAndSpaces(out.toString());
}

/// 剔除首尾的点与空格（Python `str.strip(" .")` 逐字）。
String _stripDotsAndSpaces(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && (s[start] == ' ' || s[start] == '.')) {
    start++;
  }
  while (end > start && (s[end - 1] == ' ' || s[end - 1] == '.')) {
    end--;
  }
  return s.substring(start, end);
}

/// 净化上传文件名 → 安全落盘名（防目录穿越 + Windows 非法字符 + `%`/`#` +
/// 保留设备名 + 120 字节上限）。
///
/// 定版规则（桌面 `sanitize_filename` 逐字）：取最后路径段（`/` 与 `\` 皆按
/// 分隔符）；剔除 Windows 非法字符与控制字符、剔除 `%` 与 `#`（前端
/// isValidSimulatorFile 单点拒绝，落盘名必须兼容）；剔除首尾点与空格（防
/// 隐藏文件与 `..` 段）；空名回退 `imported-game`；stem（去 .html 后的主名）
/// 按「首点前组件」大小写不敏感判定 Windows 保留设备名 → 加 `_` 前缀（非
/// 精确匹配如 mycon/com10 不受影响）；总名（含 .html 后缀）UTF-8 超 120 字节
/// → 按字节截断 stem 且不劈裂多字节字符。净化静默收敛不报错（校验失败仅限
/// 400 矩阵，见 [validateImportInput] / [importGame]）。
String sanitizeFilename(String raw) {
  var name = raw.trim().replaceAll(r'\', '/');
  name = name.split('/').last;
  final buffer = StringBuffer();
  for (final codeUnit in name.codeUnits) {
    final ch = String.fromCharCode(codeUnit);
    if (codeUnit < 32) {
      continue; // 控制字符剔除
    }
    if (_forbiddenFilenameChars.contains(ch)) {
      continue;
    }
    buffer.write(ch);
  }
  name = _stripDotsAndSpaces(buffer.toString());
  if (name.isEmpty) {
    name = 'imported-game';
  }
  var stem = name.toLowerCase().endsWith('.html')
      ? name.substring(0, name.length - '.html'.length)
      : name;
  if (_windowsReservedNames.contains(stem.split('.').first.toLowerCase())) {
    stem = '_$stem';
  }
  const suffix = '.html';
  stem = _truncateUtf8Bytes(stem, maxFilenameBytes - suffix.length);
  if (stem.isEmpty) {
    stem = 'imported-game';
  }
  return '$stem$suffix';
}

/// id slug（定版规则，导入/生成共享）：仅保留 [a-z0-9-]、分隔符折叠、无 ASCII
/// 回退 `imported-game`。
String slugify(String stem) {
  final slug = stem
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'imported-game' : slug;
}

/// 校验导入输入（纯函数，供 [importGame] 与 UI 预检复用；校验失败抛
/// [SimulatorImportError]，400 语义，**零副作用**）。
///
/// 矩阵（桌面 import_game 校验段逐字）：未提供文件名 / 非 .html（含伪装扩展
/// 名）/ 超 5MB / 空文件内容。
void validateImportInput(String filename, List<int> content) {
  if (filename.trim().isEmpty) {
    throw const SimulatorImportError('未提供文件名');
  }
  if (!filename.toLowerCase().endsWith('.html')) {
    throw SimulatorImportError('仅支持 .html 文件（当前：$filename）');
  }
  if (content.length > maxImportBytes) {
    throw const SimulatorImportError('文件超过 5MB 上限');
  }
  if (content.isEmpty) {
    throw const SimulatorImportError('文件内容为空');
  }
}

/// SHA-256 去重：与 sim_dir 现存 *.html 文件比对，命中返回文件名。
///
/// 仅比对 .html（后缀大小写不敏感）：per-game CSS 等非游戏文件是内容独立
/// 资产，字节相同不得误报「游戏已存在」。种子后内置游戏即数据目录内容，
/// 重复判定自然覆盖内置重复。目录不存在视为无重复。
String? findDuplicate(Directory simDir, List<int> content) {
  final digest = sha256Bytes(content);
  if (!simDir.existsSync()) {
    return null;
  }
  for (final entity in simDir.listSync()) {
    if (entity is! File) {
      continue;
    }
    final name = entity.uri.pathSegments.last;
    if (name == manifestFileName) {
      continue;
    }
    if (!name.toLowerCase().endsWith('.html')) {
      continue;
    }
    if (sha256Bytes(entity.readAsBytesSync()) == digest) {
      return name;
    }
  }
  return null;
}

/// 文件名冲突自动改名：xxx-2.html 递增；冲突判定大小写不敏感（Windows 定版）。
///
/// 改名路径保证总名（含 -N 后缀与扩展名）UTF-8 不超过 [maxFilenameBytes] 字
/// 节：拼 -N 后缀前按余量对 stem 重做字节截断（不劈裂多字节字符）。目录不
/// 存在视为无冲突。入参契约：desired 应为含扩展名的完整文件名（调用方保证
/// stem 非空——空兜底由 [sanitizeFilename] 的 imported-game 承担）；无点或
/// 空 stem 输入为契约外行为，抛 [ArgumentError]（不静默产出畸形名）。
String nextAvailableFilename(Directory simDir, String desired) {
  final dot = desired.lastIndexOf('.');
  if (dot <= 0) {
    throw ArgumentError.value(
      desired,
      'desired',
      '冲突改名要求含非空主名的完整文件名（如 game.html）',
    );
  }
  final ext = desired.substring(dot + 1);
  final stem = desired.substring(0, dot);
  final Iterable<String> existing = simDir.existsSync()
      ? simDir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last)
      : const [];
  final existingLower = existing.map((e) => e.toLowerCase()).toSet();
  var candidate = desired;
  var n = 2;
  while (existingLower.contains(candidate.toLowerCase())) {
    final suffix = '-$n.$ext';
    candidate = _truncateUtf8Bytes(stem, maxFilenameBytes - suffix.length) +
        suffix;
    n++;
  }
  return candidate;
}

/// 扫描 HTML 中所有 input/select 元素的 id 集合（含脚本模板字符串内的运行时
/// 控件），双层扫描取并集。
///
/// 1. 静态层手写标签扫描器（input/select 标签 + id 属性；script 内容与注释
///    不解析，属性含 `>` 引号边界正确处理——HTMLParser 语义纯 Dart 移植）；
/// 2. 脚本层 raw-regex：注释剥离后对全文正则匹配 `<input|select ... id="...">`
///    （引号 id，桌面 `_SCRIPT_TIER_RE` 同精度）。
Set<String> scanInputIds(String htmlText) =>
    _collectOrderedIds(htmlText).toSet();

/// 返回文档序的控件 id 列表（静态层在前，脚本层去重补漏在后）——启发式探测
/// 须按文档序取各组命中，避免 set 无序。
List<String> _collectOrderedIds(String htmlText) {
  final seen = <String>{};
  final result = <String>[];
  for (final cid in _staticLayerIds(htmlText)) {
    if (seen.add(cid)) {
      result.add(cid);
    }
  }
  for (final match in _scriptTierRe.allMatches(_stripHtmlComments(htmlText))) {
    final cid = match.group(1)!;
    if (seen.add(cid)) {
      result.add(cid);
    }
  }
  return result;
}

/// 剥离 HTML 注释（<!-- ... -->），供脚本层 raw-regex 提供干净文本。
String _stripHtmlComments(String text) =>
    text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// 静态层扫描：input/select 标签的 id 属性（script 内容与注释不解析）。
///
/// 手写扫描器（纯 Dart 无 HTMLParser）：逐 `<` 分派注释 / script 块跳过 /
/// 目标标签属性解析，覆盖「属性值内含 `>`」「无引号属性值」等边界。
List<String> _staticLayerIds(String html) {
  final ids = <String>[];
  var i = 0;
  final n = html.length;
  while (i < n) {
    final open = html.indexOf('<', i);
    if (open < 0) {
      break;
    }
    if (html.startsWith('<!--', open)) {
      final end = html.indexOf('-->', open + 4);
      if (end < 0) {
        break;
      }
      i = end + 3;
      continue;
    }
    var j = open + 1;
    var closing = false;
    if (j < n && html[j] == '/') {
      closing = true;
      j++;
    }
    final nameStart = j;
    while (j < n && !_isTagBreak(html[j])) {
      j++;
    }
    final tagName = html.substring(nameStart, j).toLowerCase();
    if (tagName.isEmpty || !_isAsciiLetter(tagName.codeUnitAt(0))) {
      i = j; // 孤立的 `<`（非标签）→ 越过继续
      continue;
    }
    if (tagName == 'script') {
      // script 内容为 RAW TEXT：跳至 </script>（HTMLParser 语义）
      final close = html.toLowerCase().indexOf('</script', j);
      if (close < 0) {
        break;
      }
      final gt = html.indexOf('>', close + '</script'.length);
      if (gt < 0) {
        break;
      }
      i = gt + 1;
      continue;
    }
    if (!closing && (tagName == 'input' || tagName == 'select')) {
      final attrs = _parseTagAttributes(html, j);
      i = attrs.end;
      for (final (key, value) in attrs.items) {
        if (key == 'id' && value != null && value.trim().isNotEmpty) {
          ids.add(value.trim());
        }
      }
      continue;
    }
    final gt = html.indexOf('>', j);
    if (gt < 0) {
      break;
    }
    i = gt + 1;
  }
  return ids;
}

/// 标签名后的字符是否终止标签名。
bool _isTagBreak(String ch) =>
    ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '/' || ch == '>';

/// 是否 ASCII 字母。
bool _isAsciiLetter(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7A);

/// 解析标签属性（引号值含 `>` / 无引号值 / 自闭合 `/>` 边界），返回属性列表
/// 与消费终点（`>` 之后的索引）。
({List<(String, String?)> items, int end}) _parseTagAttributes(
  String text,
  int start,
) {
  final items = <(String, String?)>[];
  var i = start;
  final n = text.length;
  while (i < n) {
    while (i < n && _isWhitespace(text[i])) {
      i++;
    }
    if (i >= n) {
      break;
    }
    final ch = text[i];
    if (ch == '>') {
      i++;
      break;
    }
    if (ch == '/') {
      if (i + 1 < n && text[i + 1] == '>') {
        i += 2;
        break;
      }
      i++;
      continue;
    }
    final nameStart = i;
    while (i < n &&
        !_isWhitespace(text[i]) &&
        text[i] != '=' &&
        text[i] != '>' &&
        text[i] != '/') {
      i++;
    }
    final name = text.substring(nameStart, i).toLowerCase();
    var v = i;
    while (v < n && _isWhitespace(text[v])) {
      v++;
    }
    String? value;
    if (v < n && text[v] == '=') {
      v++;
      while (v < n && _isWhitespace(text[v])) {
        v++;
      }
      if (v < n) {
        final quote = text[v];
        if (quote == '"' || quote == "'") {
          v++;
          final valueStart = v;
          while (v < n && text[v] != quote) {
            v++;
          }
          value = text.substring(valueStart, v);
          if (v < n) {
            v++; // 跳过闭合引号
          }
        } else {
          final valueStart = v;
          while (v < n && !_isWhitespace(text[v]) && text[v] != '>') {
            v++;
          }
          value = text.substring(valueStart, v);
        }
      }
      i = v;
    } else {
      i = v;
    }
    items.add((name, value));
  }
  return (items: items, end: i);
}

/// 是否空白字符。
bool _isWhitespace(String ch) =>
    ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\f';

/// 关键词启发式探测：endpoint/url/base、key、model 三组各命中 ≥1 时返回
/// config（每组按文档序收集**全部**命中 id——多套同义控件族全部纳入，注入
/// 按候选逐个尝试；单候选保持字符串，多候选 → 数组）。
Map<String, dynamic>? _probeKeywordGroups(List<String> orderedIds) {
  final groups = <String, List<String>>{
    'endpoint': [],
    'apikey': [],
    'model': [],
  };
  for (final cid in orderedIds) {
    if (_endpointRe.hasMatch(cid)) {
      groups['endpoint']!.add(cid);
    }
    if (_keyRe.hasMatch(cid)) {
      groups['apikey']!.add(cid);
    }
    if (_modelRe.hasMatch(cid)) {
      groups['model']!.add(cid);
    }
  }
  if (groups.values.any((value) => value.isEmpty)) {
    return null;
  }
  return {
    'endpoint':
        groups['endpoint']!.length == 1 ? groups['endpoint']![0] : groups['endpoint'],
    'apikey':
        groups['apikey']!.length == 1 ? groups['apikey']![0] : groups['apikey'],
    'model':
        groups['model']!.length == 1 ? groups['model']![0] : groups['model'],
  };
}

/// cfg 探测结果（type: 'ai' | 'local'；ai 时 config 三元组——值可为 string 或
/// string[] 多候选；local 时 null）。
typedef ProbeConfigResult = ({String type, Map<String, dynamic>? config});

/// 元数据探测：三层判定（L1 严格 cfg- 三元组 → L2 关键词启发 → L3 local）。
///
/// L1：cfg-endpoint/cfg-apikey/cfg-model 三个控件齐全 → ('ai', 三元组 config)；
/// 不降级到 L2 的 cfg- 前缀（生成器作者契约）。L2：endpoint|url|base / key /
/// model 三组关键词各命中 ≥1 个 id → ('ai', 每组全量命中候选组成的 config——
/// 单候选为字符串、多候选为数组，按文档序）。L3：('local', null)。
ProbeConfigResult probeConfig(String htmlText) {
  final allIds = scanInputIds(htmlText);
  final cfgIds = allIds.where((id) => id.startsWith('cfg-'));
  if (_cfgRequiredIds.every(cfgIds.contains)) {
    return (
      type: 'ai',
      config: {
        'endpoint': 'cfg-endpoint',
        'apikey': 'cfg-apikey',
        'model': 'cfg-model',
      },
    );
  }
  final heuristic = _probeKeywordGroups(_collectOrderedIds(htmlText));
  if (heuristic != null) {
    return (type: 'ai', config: heuristic);
  }
  return (type: 'local', config: null);
}

/// 从源码默认端点值推断 endpointMode（SIM-API-1 口径，桌面
/// `probe_endpoint_mode` 逐字）。
///
/// 匹配 JS 中 `endpoint = '...'` 或 `endpoint: '...'` 的默认 URL 值：以
/// `/chat/completions` 结尾（rstrip 尾部 `/` 后判定）→ 'full'；其他 → 'base'；
/// 未匹配默认值 → null。
String? probeEndpointMode(String htmlText) {
  final match = _endpointDefaultRe.firstMatch(htmlText);
  if (match == null) {
    return null;
  }
  final url = match.group(1)!.replaceAll(RegExp(r'/+$'), '');
  return url.endsWith('/chat/completions') ? 'full' : 'base';
}

/// 恶意模式粗筛：按 [SuspiciousPatterns] 常量清单命中收集键集——输出序 = 键序
/// （即 [SuspiciousPatterns.keys] 声明序，非独立排序；不拦截——静态审查不承诺
/// 防住，拦截决策归 UI 二次确认）。
List<String> scanSuspicious(String htmlText) {
  final hits = <String>[];
  for (final key in SuspiciousPatterns.keys) {
    if (SuspiciousPatterns.patternFor(key).hasMatch(htmlText)) {
      hits.add(key);
    }
  }
  return hits;
}

// ── manifest 原子写与自愈（桌面 simulator_manifest.py 逐字）──

/// 读取 sim_dir/manifest.json 并解析为 dict；文件不存在 → FileSystemException
/// 原样上抛（与桌面 read_manifest FileNotFoundError 同语义）。
Map<String, dynamic> readManifest(Directory simDir) {
  final path =
      '${simDir.path}${Platform.pathSeparator}$manifestFileName';
  final text = File(path).readAsStringSync();
  final data = json.decode(text);
  if (data is! Map<String, dynamic>) {
    throw const FormatException('manifest 顶层必须是非 null 对象');
  }
  return data;
}

/// 原子写 sim_dir/manifest.json：同目录临时文件 + `File.rename` 原子替换
/// （UTF-8 明文，中文保真，缩进可读——桌面 os.replace / indent=2 语义）。
///
/// 目录缺失自动创建；入参由 Dart 静态类型保证恒为 Map（桌面数据为动态值，
/// 其 TypeError 前置拦截在类型系统层面吸收——json.encode 对 Map 恒可编码）；
/// 写入失败时旧 manifest 保持原样（原子替换保证），临时文件残留无害（读取
/// 方只消费 manifest.json）。
void writeManifest(Directory simDir, Map<String, dynamic> manifest) {
  simDir.createSync(recursive: true);
  final tmp = File(
    '${simDir.path}${Platform.pathSeparator}$manifestFileName$_manifestTmpSuffix',
  );
  tmp.writeAsStringSync(_encodeManifest(manifest), flush: true);
  tmp.renameSync('${simDir.path}${Platform.pathSeparator}$manifestFileName');
}

/// manifest JSON 编码（缩进两空格，桌面 json.dumps(indent=2) 同构。
String _encodeManifest(Map<String, dynamic> manifest) =>
    const JsonEncoder.withIndent('  ').convert(manifest);

/// 读取 manifest；缺失或损坏 → 以磁盘现存 .html 重建兜底（自愈：数据目录为
/// 唯一事实来源）。
///
/// 损坏口径（桌面 F-8/F-15 定版）：非法 JSON / 非 UTF-8 / 合法 JSON 但结构非
/// 预期（顶层非对象或 simulators 非 list）一律视为损坏重建；读取路径
/// FileSystemException 族同样并入自愈。[persist] = true 时重建结果立即原子落盘
/// （importGame 先自愈再算 id，避免「id 唯一化用瞬态重建、append 用磁盘重建」
/// 两次重建口径不一致产生退化重复条目）；落盘写失败按既有契约抛出明确异常
/// （写路径在 except 之外不受影响）。
Map<String, dynamic> readManifestOrRebuild(Directory simDir,
    {bool persist = false}) {
  Map<String, dynamic>? manifest;
  try {
    manifest = readManifest(simDir);
  } on FileSystemException {
    manifest = null;
  } on FormatException {
    manifest = null;
  }
  if (manifest == null || manifest['simulators'] is! List<Object?>) {
    final rebuilt = rebuildManifest(simDir);
    if (persist) {
      writeManifest(simDir, rebuilt);
    }
    return rebuilt;
  }
  return manifest;
}

/// 以现存 .html 文件重建 manifest（自愈：数据目录为唯一事实来源）。
///
/// 条目：id = 文件名干 slug（冲突 -2/-3 唯一化，保证结构性唯一）、file/name
/// 取实际文件名、type=local（重建为降级态，不逐文件探测）。
Map<String, dynamic> rebuildManifest(Directory simDir) {
  simDir.createSync(recursive: true);
  final files = simDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.html'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final simulators = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final stem =
        name.substring(0, name.length - '.html'.length);
    final base = slugify(stem);
    var id = base;
    var n = 2;
    while (seen.contains(id)) {
      id = '$base-$n';
      n++;
    }
    seen.add(id);
    simulators.add({'id': id, 'file': name, 'name': stem, 'type': 'local'});
  }
  return {'version': 2, 'simulators': simulators};
}

/// manifest 读-改-写原子追加：合法则既有条目原样保留；缺失/损坏 → 以磁盘现存
/// .html 自愈重建（version=2，type=local 降级）再追加。
void appendManifestEntry(Directory simDir, Map<String, dynamic> entry) {
  final manifest = readManifestOrRebuild(simDir);
  (manifest['simulators'] as List).add(entry);
  writeManifest(simDir, manifest);
}

/// 将 description 写回 sim_dir/manifest.json 对应 id 条目（读-改-写原子替换）——
/// 幂等：条目不存在 / 已一致 / id 缺失均不写盘（读操作经
/// [readManifestOrRebuild] 自带自愈口径，与导入链一致）。
///
/// 本函数是「description 补写回 manifest」的单一落点：GameGenerator 派生描述
/// （F-47）与简介生成（本批次导入挂点）共用；[onlyIfEmpty] = true 时条目已有
/// 非空 description 则跳过（用于「仅填充缺失描述」路径——导入游戏补简介不
/// 覆盖既有描述）。
void updateManifestEntryDescription(
  Directory simDir,
  String id,
  String description, {
  bool onlyIfEmpty = false,
}) {
  final manifest = readManifestOrRebuild(simDir);
  final simulators = manifest['simulators'];
  if (simulators is! List) {
    return;
  }
  for (final entry in simulators) {
    if (entry is Map && entry['id'] == id) {
      final current = entry['description'];
      if (onlyIfEmpty && current is String && current.isNotEmpty) {
        return; // 仅填充缺失描述：既有描述不覆盖
      }
      if (current == description) {
        return; // 幂等：已一致不重写
      }
      entry['description'] = description;
      writeManifest(simDir, manifest);
      return;
    }
  }
}

/// 现存 manifest 条目 id 集（缺失/损坏按磁盘重建口径，与 append 自愈一致）。
Set<String> _existingGameIds(Directory simDir) {
  final manifest = readManifestOrRebuild(simDir);
  final simulators = manifest['simulators'];
  if (simulators is! List<Object?>) {
    return const {};
  }
  return {
    for (final entry in simulators)
      if (entry is Map<String, dynamic> && entry['id'] is String)
        entry['id'] as String,
  };
}

/// id 按现存 id 集唯一化（-2/-3 后缀）——id 重复是 manifest 结构性错误（前端
/// parseManifest 整体失败），必须保证唯一。
String _uniqueGameId(Directory simDir, String base) {
  final existing = _existingGameIds(simDir);
  var id = base;
  var n = 2;
  while (existing.contains(id)) {
    id = '$base-$n';
    n++;
  }
  return id;
}

/// 导入单文件 HTML 模拟器游戏（服务编排：校验 → 净化 → 去重 → 改名 → 探测 →
/// 粗筛 → 落盘 → manifest 注册）。
///
/// [simDir] 数据目录 simulators；[filename] 原始文件名（扩展名校验与净化均在
/// 此进行）；[content] 上传文件字节；[source] manifest 条目 source 标记（默认
/// imported；生成器消费 generated）。[appendEntry] 测试注入的可失败注册回调
/// （生产默认 [appendManifestEntry]）。
///
/// Raises：
/// - [SimulatorImportError]：非 .html / 超 5MB / 空文件 / 缺文件名（400 语义）；
/// - [SimulatorDuplicateError]：SHA-256 与现存文件重复（409 语义，文案含
///   「已存在」，改名之前判定）；
/// - [FileSystemException]：数据目录不可写等落盘失败（500 语义，不静默吞掉）。
///
/// 顺序保证（桌面逐字）：校验先于一切副作用（校验失败零落盘）；去重在改名之
/// 前；manifest 缺失/损坏先自愈落盘再算 id（口径一致）；manifest 注册失败
/// 回滚已落盘文件（不遗留孤儿）。
Future<ImportResult> importGame(
  Directory simDir,
  String filename,
  List<int> content, {
  String source = 'imported',
  ManifestAppender? appendEntry,
}) async {
  validateImportInput(filename, content);

  final safeName = sanitizeFilename(filename);
  final dup = findDuplicate(simDir, content);
  if (dup != null) {
    throw SimulatorDuplicateError('游戏已存在（内容与现有文件相同）：$dup');
  }

  final finalName = nextAvailableFilename(simDir, safeName);
  final renamed = finalName != safeName;
  final stem = finalName.substring(0, finalName.lastIndexOf('.'));

  // manifest 缺失/损坏先自愈落盘（口径一致性见 readManifestOrRebuild persist）。
  readManifestOrRebuild(simDir, persist: true);

  final text = utf8.decode(content, allowMalformed: true);
  final probe = probeConfig(text);
  final gameType = probe.type;
  final config = probe.config;
  final endpointMode = probeEndpointMode(text);
  final warnings = scanSuspicious(text);

  final entry = <String, dynamic>{
    'id': _uniqueGameId(simDir, slugify(stem)),
    'file': finalName,
    'name': stem,
    'type': gameType,
    'source': source,
  };
  if (config != null) {
    entry['config'] = config;
  }
  if (endpointMode != null) {
    entry['endpointMode'] = endpointMode;
  }

  simDir.createSync(recursive: true);
  final target = File('${simDir.path}${Platform.pathSeparator}$finalName');
  await target.writeAsBytes(content, flush: true);
  try {
    final appender = appendEntry ?? appendManifestEntry;
    appender(simDir, entry);
  } catch (_) {
    if (target.existsSync()) {
      target.deleteSync();
    }
    rethrow;
  }
  return ImportResult(game: entry, renamed: renamed, warnings: warnings);
}