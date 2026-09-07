/// 存档桥读写层（F-M5-06）——`LocalStorageAccess` 抽象 + runJavaScript 生产
/// 实现 + `SaveBridge` 编排。
///
/// 职责分界（spec §3.5 Q9 逐字）：契约层纯函数由 F-M5-05
/// `save_contract.dart` 承载（白名单收集 / payload / 整包校验 / 写前快照回滚 /
/// 删除 / 5MB / 文件名净化，本模块只消费不重复实现）；**本模块 = 读写层**
/// —— 对 server origin 页面的 localStorage 双向访问（`LocalStorageAccess`
/// seam + runJavaScript 往返解析的 [JsBridgeLocalStorageAccess]）+ **编排层**
/// [SaveBridge]（面板读 / 导出走 M4 `writeTempAndShare` / 导入走
/// `pickJsonWithTimeout` + 校验应用回滚 / 删除）。
///
/// U2（最大风险，spec §6 登记）：Flutter 主进程与游戏非同源，sheet 需访问
/// server origin 的 localStorage → **生产实现经 [JavaScriptEvaluator] seam 注入**
/// （webview_flutter `runJavaScriptReturningResult` 薄适配，装配点 = sheet，
/// 见 save_sheet.dart）；隔离后本模块零 webview 依赖，宿主 `flutter test` 可
/// 全量直测（测试注入 Map 型 fake 地址）。
///
/// 读写语义锚（桌面 save-manager.js 逐字）：
/// - 枚举：runJavaScript `JSON.stringify(Object.entries(localStorage))` 往返
///   解析为全量键值 Map；挂起/失败 → **超时兜底降级空 Map**（面板显示 0 键，
///   不挂死不抛错 —— 桌面 TD-69 存储异常降级空结果同构）；
/// - **平台契约（F-M5-09 AVD 实证）**：Android `evaluateJavascript` 返回
///   JSON 编码串（字符串结果带外层引号），`runJavaScriptReturningResult`
///   原样透传 → [parseLocalStorageEntries] 对编码串解包一次；iOS/macOS 返回
///   裸值（一次 [jsonDecode] 即数组），二者归一（见函数 docstring）；
/// - 写回：setItem / removeItem 脚本注入（键值经 JSON 转义，无注入面）；
///   **写失败上抛**（quota 等），由 [SaveBridge] 编排「写前快照 + 尽力回滚」
///   （承接契约 TD-63/TD-73 语义的异步落地位）；
/// - 导出 payload / 导入校验的键值语义全部复用契约层。
///
/// 协议表面（深模块）：`LocalStorageAccess` / `JavaScriptEvaluator` /
/// `enumerateLocalStorageScript` / `buildSetItemScript` / `buildRemoveItemScript`
/// / `parseLocalStorageEntries` / `JsBridgeLocalStorageAccess` / `SaveGame` /
/// `GameSaveSummary` / `SaveActionResult` / `SaveBridge`。
library;

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（对齐 simulators_controller.dart 惯例）。
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../platform_file_exchange.dart'
    show
        PickJsonBytes,
        ResolveTempDirectory,
        ShareFile,
        defaultPickJsonFile,
        defaultResolveTempDirectory,
        defaultShareViaPlus,
        pickJsonWithTimeout,
        writeTempAndShare;
import 'save_contract.dart'
    show
        SaveStorage,
        applyImportPayload,
        buildExportPayload,
        collectGameKeys,
        deleteGameKeys,
        maxImportBytes,
        sanitizeFilename,
        validateImportPayload;

// ══════════════════════════════════════════════════
// localStorage 访问抽象（U2 seam）
// ══════════════════════════════════════════════════

/// localStorage 双向访问抽象：全量枚举读 + 键写 / 键删。
///
/// 生产 = [JsBridgeLocalStorageAccess]（对 server origin 页 runJavaScript）；
/// 测试 = Map 型 fake（`test/support/fake_local_storage_access.dart`）。读取
/// 失败一律降级空 Map（不抛错挂死）；写失败上抛（编排层负责快照回滚提示）。
abstract interface class LocalStorageAccess {
  /// 全量键值枚举（挂起/失败 → 返回空 Map 的降级信号，不抛错）。
  Future<Map<String, String>> enumerate();

  /// 写入键 [key]（同键替换）；失败上抛（调用方回滚/提示）。
  Future<void> setItem(String key, String value);

  /// 移除键 [key]（不存在为 no-op）；失败上抛。
  Future<void> removeItem(String key);
}

/// 页内 JS 求值能力 seam：执行 [script] 并返回其结果字符串（生产 =
/// webview_flutter `runJavaScriptReturningResult` 薄适配，装配点 = sheet；
/// 测试注入 Map 型 fake 不经 WebView）。
typedef JavaScriptEvaluator = Future<String> Function(String script);

// ══════════════════════════════════════════════════
// JS 脚本契约（生产执行面；测试对原文金样断言）
// ══════════════════════════════════════════════════

/// 全量枚举脚本（锚 U2 方案：`JSON.stringify(Object.entries(localStorage))`
/// → `[["key","value"],…]` 数组 JSON 返回 Flutter）。
const String enumerateLocalStorageScript =
    'JSON.stringify(Object.entries(localStorage))';

/// setItem 注入脚本：键值经 [jsonEncode] 转义（安全嵌入为 JS 双引号字面量，
/// 引号/反斜杠/控制字符无注入面）。
String buildSetItemScript(String key, String value) =>
    'localStorage.setItem(${jsonEncode(key)}, ${jsonEncode(value)})';

/// removeItem 注入脚本（键经 [jsonEncode] 转义）。
String buildRemoveItemScript(String key) =>
    'localStorage.removeItem(${jsonEncode(key)})';

/// 往返解析：`JSON.stringify(Object.entries(localStorage))` 的产物数组 →
/// `Map<String,String>`。
///
/// 平台契约容错（F-M5-09 AVD 实证，缺陷 #1）：Android `evaluateJavascript`
/// 对字符串结果返回 **JSON 编码串**（带外层引号，如 `"[[\"k\",\"v\"]]"`），
/// `runJavaScriptReturningResult`（webview_flutter_android）对字符串**原样
/// 透传**——因此对 [jsonDecode] 后得 `String` 的编码串**再解包一次**（内层
/// 即 `JSON.stringify` 产物数组 JSON）；iOS/macOS 等平台返回**裸值**（外层
/// 无引号的数组 JSON 串），一次 [jsonDecode] 直接得 `List`，原样处理。二者
/// 归一为数组条目解析。
///
/// 防御（对抗性）：顶层非 List 或 JSON 非法（含编码串二次解码失败）→ 抛
/// [FormatException]（由 [JsBridgeLocalStorageAccess.enumerate] 兜底降级空
/// Map）；单条非 `[k,v]` 二元组 / 键值非字符串 → 跳过该条不炸（localStorage
/// 枚举产物应为同位字符串，畸形条属异常数据面，静默略过）。
Map<String, String> parseLocalStorageEntries(String json) {
  final Object? decoded = _decodeLocalStorageEntriesJson(json);
  if (decoded is! List) {
    throw const FormatException('localStorage 枚举结果必须是数组');
  }
  final Map<String, String> out = {};
  for (final Object? element in decoded) {
    if (element is! List || element.length != 2) continue;
    final Object? key = element[0];
    final Object? value = element[1];
    if (key is! String || value is! String) continue;
    out[key] = value;
  }
  return out;
}

/// 单层解包 [json]：Android evaluateJavascript 返回的**编码 JSON 串**
/// （[jsonDecode] 后得 `String`，其内容为二次 JSON 编码的数组 JSON）再解一次；
/// 裸 JSON / 非数组形态原样返回（非 List 由调用方判非数组）。JSON 非法（含
/// 编码串内容畸形）上抛 [FormatException]，交 [enumerate] 降级空 Map。
Object? _decodeLocalStorageEntriesJson(String json) {
  final Object? decoded = jsonDecode(json);
  if (decoded is String) {
    // 锚 Android `evaluateJavascript`：字符串结果带外层引号返回 Flutter（
    // `runJavaScriptReturningResult` 原样透传）——解包一次即得
    // `JSON.stringify` 产物数组 JSON。
    return jsonDecode(decoded);
  }
  return decoded;
}

// ══════════════════════════════════════════════════
// 生产实现（runJavaScript 双向，U2）
// ══════════════════════════════════════════════════

/// runJavaScript 生产实现：经注入的 [JavaScriptEvaluator] 对 server origin
/// 页面执行枚举 / setItem / removeItem 脚本。
///
/// 超时兜底契约：求值挂起超时（[timeout]）——
/// - [enumerate]：降级返回空 Map（不抛错挂死，供 UI 呈现 0 键/降级提示）；
/// - [setItem] / [removeItem]：上抛 [TimeoutException]（写失败是编排层快照
///   回滚的触发点，不能吞——「不挂死」由调用方捕获转化为可见文案保证）。
/// 求值返回非预期内容（畸形 JSON）同走枚举降级路径。
class JsBridgeLocalStorageAccess implements LocalStorageAccess {
  /// [evaluate] JS 求值回调（生产 = WebViewController
  /// `runJavaScriptReturningResult` 薄适配）；[timeout] 单次求值超时守卫。
  JsBridgeLocalStorageAccess(
    this._evaluate, {
    this.timeout = const Duration(milliseconds: 8000),
  });

  final JavaScriptEvaluator _evaluate;

  /// 单次求值超时守卫（sheet 面板专用口径，装配可缩短）。
  final Duration timeout;

  @override
  Future<Map<String, String>> enumerate() async {
    try {
      final json = await _evaluate(enumerateLocalStorageScript).timeout(timeout);
      return parseLocalStorageEntries(json);
    } on TimeoutException {
      return const {}; // 挂起降级：不挂死
    } catch (_) {
      return const {}; // 畸形/异常降级：不挂死
    }
  }

  @override
  Future<void> setItem(String key, String value) async {
    await _evaluate(buildSetItemScript(key, value)).timeout(timeout);
  }

  @override
  Future<void> removeItem(String key) async {
    await _evaluate(buildRemoveItemScript(key)).timeout(timeout);
  }
}

// ══════════════════════════════════════════════════
// 编排数据面（去视图化最小面）
// ══════════════════════════════════════════════════

/// 存档管理的单游戏信息（契约层消费 id / name / saveKeys 的最小数据面；
/// 由视图从列表模型映射，避免服务层倒挂引用 UI 模型）。
class SaveGame {
  /// 构造单游戏存档信息。
  const SaveGame({required this.id, required this.name, this.saveKeys});

  /// 游戏 id（导出文件名净化源）。
  final String id;

  /// 展示名（透传契约 game_name）。
  final String name;

  /// saveKeys 白名单（null = 无存档管理降级信号）。
  final List<String>? saveKeys;

  /// 契约层入参等价 Map（saveKey 匹配 / 收集 / payload 共用）。
  Map<String, Object?> toGameMap() =>
      {'id': id, 'name': name, 'saveKeys': saveKeys};
}

/// 面板行数据（键数 / 字符大小 / 是否有存档管理判据）。
class GameSaveSummary {
  /// 构造单游戏汇总行。
  const GameSaveSummary({
    required this.gameId,
    required this.name,
    required this.keyCount,
    required this.totalChars,
    required this.saveKeysDeclared,
  });

  /// 游戏 id（操作入参）。
  final String gameId;

  /// 展示名。
  final String name;

  /// 命中白名单且存在的键数（`{N} 个存档` 文案来源）。
  final int keyCount;

  /// 键值字符串长度之和（totalChars 口径，锚桌面）。
  final int totalChars;

  /// 是否声明了 saveKeys（false = 「无存档管理」降级行）。
  final bool saveKeysDeclared;
}

/// 面板操作结果（成功/失败统一面向用户文案；失败仅提示不崩）。
class SaveActionResult {
  /// 成功（[message] 如「已恢复 N 个存档键」）。
  const SaveActionResult.success(this.message) : ok = true;

  /// 失败（[message] 为可读文案）。
  const SaveActionResult.failure(this.message) : ok = false;

  /// 是否成功。
  final bool ok;

  /// 面向用户反馈文案。
  final String message;
}

// ══════════════════════════════════════════════════
// SaveBridge 编排
// ══════════════════════════════════════════════════

/// 存档管理编排（读写层消费方 + 平台 seam 组合腿）。
///
/// 全部平台 seam 复用既有腿（M4 `platform_file_exchange.dart` 只读）：导出 =
/// [writeTempAndShare]（临时目录 + share_plus 分享），导入 =
/// [pickJsonWithTimeout]（file_picker 单 .json）；本地读写经 [access]
/// （生产 runJavaScript / 测试 fake）。契约白名单 / 校验 / 应用 / 删除语义
/// 全部消费 F-M5-05 纯函数，本类不复制规则。
///
/// 写回时序（async storage ↔ sync 契约的适配位）：契约函数在内存缓存上执行
/// （白名单 + 写前快照回滚语义保留），成功后经 [LocalStorageAccess] flush 到
/// 真实 localStorage；flush 任一键失败 → 逆序**尽力回滚**已写键（TD-73）→
/// 上抛，调用方（sheet）刷新面板重新枚举，不残留半截数据。删除同构。
class SaveBridge {
  /// [access] localStorage 双向访问；[games] 面板管理的游戏集；
  /// [resolveTempDirectory] / [shareFile] / [pickJsonBytes] 平台 seam（缺省
  /// M4 生产腿）；[platformTimeout] 全部平台调用点超时守卫。
  SaveBridge({
    required LocalStorageAccess access,
    required List<SaveGame> games,
    ResolveTempDirectory? resolveTempDirectory,
    ShareFile? shareFile,
    PickJsonBytes? pickJsonBytes,
    this.platformTimeout = const Duration(seconds: 10),
  })  : _access = access,
        _games = games,
        _resolveTempDirectory =
            resolveTempDirectory ?? defaultResolveTempDirectory,
        _shareFile = shareFile ?? defaultShareViaPlus,
        _pickJsonBytes = pickJsonBytes ?? defaultPickJsonFile;

  final LocalStorageAccess _access;
  final List<SaveGame> _games;
  final ResolveTempDirectory _resolveTempDirectory;
  final ShareFile _shareFile;
  final PickJsonBytes _pickJsonBytes;

  /// 平台/IO 调用点超时守卫（挂起降级为失败文案，不挂死）。
  final Duration platformTimeout;

  /// 面板缓存（loadPanel / 懒枚举后持有；写操作经 [SaveStorage] 契约写入）。
  Map<String, String>? _cache;

  /// 缓存写日志（契约写操作全程记录，flush 失败以此为回滚依据）。
  final List<({String key, String? prev, String? next})> _journal = [];

  SaveGame? _gameById(String gameId) {
    for (final game in _games) {
      if (game.id == gameId) return game;
    }
    return null;
  }

  /// 惰性取当前缓存 storage 适配（契约同步 seam：读走缓存、写记日志）。
  Future<_JournaledStorage> _ensureStorage() async {
    final cache = _cache ?? await _access.enumerate();
    _cache = cache;
    return _JournaledStorage(cache, _journal);
  }

  /// 面板读：全量枚举 → 逐游戏 [collectGameKeys] + 键数/字符大小汇总。
  ///
  /// 每次调用重建缓存（面板打开 / 操作后刷新共享入口）；枚举降级空 Map 时
  /// 全部行 0 键（不崩）。
  Future<List<GameSaveSummary>> loadPanel() async {
    final cache = await _access.enumerate();
    _cache = cache;
    _journal.clear();
    final storage = _JournaledStorage(cache, _journal);
    return [for (final game in _games) _summarize(game, storage)];
  }

  GameSaveSummary _summarize(SaveGame game, SaveStorage storage) {
    final keyNames = collectGameKeys(game.toGameMap(), storage);
    var totalChars = 0;
    for (final name in keyNames) {
      totalChars += storage.getItem(name)?.length ?? 0;
    }
    return GameSaveSummary(
      gameId: game.id,
      name: game.name,
      keyCount: keyNames.length,
      totalChars: totalChars,
      saveKeysDeclared: game.saveKeys != null,
    );
  }

  /// 导出单游戏：白名单键收集 → [buildExportPayload] → 2 空格缩进 JSON →
  /// [writeTempAndShare]（文件名 `${sanitizeFilename(gameId)}-saves.json`，
  /// TD-65 净化）。零键 → 「没有可导出的存档键」，不打开分享面板。
  Future<SaveActionResult> exportGame(String gameId) async {
    final game = _gameById(gameId);
    if (game == null) return const SaveActionResult.failure('未找到游戏');
    final SaveStorage storage = await _ensureStorage();
    final keyNames = collectGameKeys(game.toGameMap(), storage);
    if (keyNames.isEmpty) {
      return const SaveActionResult.failure('没有可导出的存档键');
    }
    final payload = buildExportPayload(game.toGameMap(), keyNames, storage);
    final fileName = '${sanitizeFilename(game.id)}-saves.json';
    final content = const JsonEncoder.withIndent('  ').convert(payload);
    try {
      final message = await writeTempAndShare(
        fileName: fileName,
        content: content,
        resolveTempDirectory: _resolveTempDirectory,
        shareFile: _shareFile,
        platformTimeout: platformTimeout,
      );
      return SaveActionResult.success(message);
    } on StateError catch (error) {
      // M4 超时兜底降级（「获取临时目录超时」/「分享面板超时」）。
      return SaveActionResult.failure(error.message);
    } catch (error) {
      return SaveActionResult.failure('导出失败：$error');
    }
  }

  /// 导入单游戏：选 .json（[pickJsonWithTimeout]）→ 5MB 守卫 → JSON 解析 →
  /// [validateImportPayload] 整包拒绝/放行 → [applyImportPayload] 缓存应用 →
  /// flush 真实 storage（失败尽力回滚）。
  ///
  /// 返回 `null` = 用户取消 / 选择超时（调用方静默，零副作用）。
  Future<SaveActionResult?> importGame(String gameId) async {
    final game = _gameById(gameId);
    if (game == null) return const SaveActionResult.failure('未找到游戏');
    final Uint8List? bytes;
    try {
      bytes = await pickJsonWithTimeout(
        pickJsonBytes: _pickJsonBytes,
        platformTimeout: platformTimeout,
      );
    } on TimeoutException {
      return null; // pickJsonWithTimeout 已转 null（防御路径）
    } catch (error) {
      return SaveActionResult.failure('选择文件失败：$error');
    }
    if (bytes == null) return null; // 取消 / 选择超时——静默
    if (bytes.length > maxImportBytes) {
      return const SaveActionResult.failure('存档文件过大（上限 5MB）');
    }
    final Object? payload;
    try {
      payload = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      return const SaveActionResult.failure('不是有效的 JSON 文件');
    }
    final result = validateImportPayload(payload, game.toGameMap());
    if (!result.ok) {
      return SaveActionResult.failure(result.error ?? '存档文件校验失败');
    }
    final SaveStorage storage = await _ensureStorage();
    final int written =
        applyImportPayload(game.toGameMap(), result.keys, storage);
    try {
      await _flushJournal();
    } catch (_) {
      // 写失败已尽力回滚；调用方刷新面板重新枚举（不残留半截数据）。
      return const SaveActionResult.failure('导入失败：写回存档失败（已回滚）');
    }
    return SaveActionResult.success('已恢复 $written 个存档键');
  }

  /// 删除单游戏白名单键（确认交互由 UI 层负责）：删除后 flush 真实 storage。
  Future<SaveActionResult> deleteGame(String gameId) async {
    final game = _gameById(gameId);
    if (game == null) return const SaveActionResult.failure('未找到游戏');
    final SaveStorage storage = await _ensureStorage();
    final List<String> keyNames = deleteGameKeys(game.toGameMap(), storage);
    if (keyNames.isEmpty) {
      return const SaveActionResult.failure('没有可删除的存档键');
    }
    try {
      await _flushJournal();
    } catch (_) {
      return const SaveActionResult.failure('删除失败：清理存档失败（已回滚）');
    }
    return SaveActionResult.success('已删除 ${keyNames.length} 个存档键');
  }

  /// 缓存写日志 flush 到真实 localStorage。
  ///
  /// 任一键写入失败 → 已写键逆序**尽力回滚**（TD-73：单键还原失败不中断，
  /// 继续尝试其余键）→ 上抛（回滚异常不遮蔽写入异常）。调用方捕获后刷新
  /// 面板重新枚举，缓存态与真实 store 归一到最新。
  Future<void> _flushJournal() async {
    if (_journal.isEmpty) return;
    final applied = <({String key, String? prev, String? next})>[];
    try {
      for (final entry in _journal) {
        final String? next = entry.next;
        if (next == null) {
          await _access.removeItem(entry.key).timeout(platformTimeout);
        } else {
          await _access.setItem(entry.key, next).timeout(platformTimeout);
        }
        applied.add(entry);
      }
      _journal.clear();
    } catch (_) {
      for (final entry in applied.reversed) {
        try {
          final String? prev = entry.prev;
          if (prev == null) {
            await _access.removeItem(entry.key).timeout(platformTimeout);
          } else {
            await _access.setItem(entry.key, prev).timeout(platformTimeout);
          }
        } catch (_) {
          // 尽力而为：单键还原失败继续尝试其余键（失败键残留新值）
        }
      }
      _journal.clear();
      rethrow;
    }
  }
}

/// [SaveStorage] 情境适配（契约同步 seam）：内存缓存 + 写日志。
///
/// 读（length / key / getItem）直读缓存；写（setItem / removeItem）更新缓存
/// 并记录 `{key, prev, next}` 日志（prev = 写前值 / null = 写前不存在；
/// next = null 表示删除）——契约层写前快照回滚在缓存上照常生效（TD-63），
/// 真实 store 的 flush 回滚由 [SaveBridge._flushJournal] 依据同一日志执行。
class _JournaledStorage implements SaveStorage {
  _JournaledStorage(this._map, this._journal);

  final Map<String, String> _map;
  final List<({String key, String? prev, String? next})> _journal;

  @override
  int get length => _map.length;

  @override
  String? key(int index) {
    if (index < 0 || index >= _map.length) return null;
    return _map.keys.elementAt(index);
  }

  @override
  String? getItem(String key) => _map[key];

  @override
  void setItem(String key, String value) {
    final String? prev = _map[key];
    _map[key] = value;
    _journal.add((key: key, prev: prev, next: value));
  }

  @override
  void removeItem(String key) {
    if (!_map.containsKey(key)) return; // 不存在为 no-op
    final String? prev = _map[key];
    _map.remove(key);
    _journal.add((key: key, prev: prev, next: null));
  }
}