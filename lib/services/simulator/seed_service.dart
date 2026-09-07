/// 模拟器首启种子服务（F-M5-01 数据底座）——ensureSeeded 契约逐字移植。
///
/// 桌面权威源（只读，语义逐字锚点）：
/// `desktop/backend/app/services/simulator_store.py` ensure_seeded。
///
/// 首启种子契约（spec 3.2 Q3 逐字）：
/// 1. 种子标记 = 目标数据目录 `manifest.json` 存在（幂等；不做逐文件自愈，
///    用户删了就是删了——数据目录为唯一事实来源）；
/// 2. 全新目录：从内置资产整目录拷贝（HTML 先、manifest 最后落盘，字节
///    一致）；
/// 3. manifest **最后**落盘：中断于 manifest 之前 → 下次启动重种；中断于
///    manifest 之后 → 视为已种子（标记语义，不逐文件修复）；
/// 4. 种子源缺失（资产源不可枚举 / 源缺 manifest）→ 降级不崩溃（返回
///    false，不创建目录）；数据目录不可写 → 抛带目录路径的明确错误。
///
/// 与桌面的形态差异（语义等价）：桌面保险种源在文件系统（`builtin_dir`
/// iterdir 枚举）；移动端内置资产随包（rootBundle），无法枚举目录，资产
/// 清单以源 `manifest.json` 的 `simulators[].file` 为准——源 manifest 加载
/// 失败或结构不可枚举视为「种子源缺失」降级（桌面源缺 manifest 同语义）。
/// 资产读取经注入 [LoadSeedAsset] 回调（生产 rootBundle，测试 fake——可
/// 断言落盘顺序与中断时序）。
///
/// 协议表面（深模块）：`LoadSeedAsset` / `ensureSeeded` / `manifestFileName`。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 数据目录下的清单文件名（种子标记 = 本文件存在；桌面 MANIFEST_FILE
/// `manifest.json` 同键，单一归属）。
const String manifestFileName = 'manifest.json';

/// 内置资产读取回调：按 pubspec 声明的资产路径返回字节（生产 rootBundle，
/// 测试 fake）。路径含 manifest 时即源清单与待写内容同一字节源。
typedef LoadSeedAsset = Future<Uint8List> Function(String path);

/// 首启种子：目标目录 `simDir` 缺 manifest → 从内置资产源 [assetRoot] 整目录
/// 拷贝（先游戏 HTML 后 manifest，**manifest 最后落盘**）。
///
/// 返回 true = 本次执行了种子拷贝；false = 已种子（标记存在）或种子源缺失
/// （源 manifest 不可加载 / 结构不可枚举，降级不崩溃，不创建目录）。
/// 数据目录不可写 → 抛 [FileSystemException]（消息含 `simDir` 完整路径）。
/// 游戏资产加载失败（源缺陷）→ 原样抛出（启动期可闻，不静默吞掉）。
///
/// 源文件清单 = [assetRoot] 下 `manifest.json` 的 `simulators[].file`
/// （manifest 条目序即拷贝序）；目标落盘名取自 file 的路径 basename
/// （防 manifest file 字段含分隔符穿越写目录外——数据目录扁平化，与桌面
/// 整目录拷贝形态一致）。生产装配：
/// `ensureSeeded(simDir: await SimulatorDataDir().resolve(), assetRoot:
/// 'assets/simulators', loadAsset: rootBundle.load 适配字节)`。
Future<bool> ensureSeeded({
  required Directory simDir,
  required String assetRoot,
  required LoadSeedAsset loadAsset,
}) async {
  final manifestAssetPath = '$assetRoot/$manifestFileName';

  // 种子源 manifest（虚拟目录入口）：探测加载失败 = 源缺 → 降级（不建目录）。
  // 探测仅作源存在性检查（桌面 `builtin_dir` is_dir + manifest is_file），
  // 字节在末尾落盘阶段重载——保证资产读取序列「游戏文件先、manifest 最后」，
  // 使注入 fake 可直接断言落盘顺序（工单可测性契约）。
  final Uint8List probeManifest;
  try {
    probeManifest = await loadAsset(manifestAssetPath);
  } catch (_) {
    return false;
  }
  // 目标已种子（manifest 存在）→ 幂等跳过：标记语义，不读不写。
  // 存在性口径逐字锚桌面 `Path.exists()`：文件与目录均计为已种子标记
  // （`File.existsSync()` 对目录返回 false，会误判「未种子」触发重种）。
  final targetManifestPath = '${simDir.path}${Platform.pathSeparator}$manifestFileName';
  if (_pathExists(targetManifestPath)) {
    return false;
  }
  // 源 manifest 结构不可枚举（非对象 / simulators 非列表 / file 缺失）→ 源
  // 缺陷降级（不建目录不崩溃）。
  final seedFiles = _listSeedFiles(probeManifest);
  if (seedFiles == null) {
    return false;
  }

  try {
    simDir.createSync(recursive: true);
    for (final file in seedFiles) {
      final bytes = await loadAsset('$assetRoot/$file');
      final target = File('${simDir.path}${Platform.pathSeparator}${_basename(file)}');
      await target.writeAsBytes(bytes, flush: true);
    }
    // manifest 最后落盘：种子标记最晚生效（半拷中断语义见模块 docstring）。
    final manifestBytes = await loadAsset(manifestAssetPath);
    await File(targetManifestPath).writeAsBytes(manifestBytes, flush: true);
  } on FileSystemException catch (exc) {
    throw FileSystemException(
      '模拟器数据目录不可用，无法写入种子：${simDir.path}（${exc.message}）',
      simDir.path,
    );
  }
  return true;
}

/// 从源 manifest 字节枚举待拷贝文件名列表；结构不可枚举返回 null。
///
/// 轻量结构检查（仅取 `simulators[].file`，不做 parseManifest 全量校验——
/// 桌面种子同样只枚举不校验；源 manifest 为打包产物，结构责任归打包面）。
List<String>? _listSeedFiles(Uint8List manifestBytes) {
  try {
    final data = json.decode(utf8.decode(manifestBytes));
    if (data is! Map<String, dynamic>) {
      return null;
    }
    final simulators = data['simulators'];
    if (simulators is! List<Object?>) {
      return null;
    }
    final files = <String>[];
    for (final entry in simulators) {
      if (entry is! Map<String, dynamic>) {
        return null;
      }
      final file = entry['file'];
      if (file is! String || file.isEmpty) {
        return null;
      }
      files.add(file);
    }
    return files;
  } catch (_) {
    return null;
  }
}

/// 取路径最后一段（兼容 `/` 与 `\` 分隔符）——目标落盘扁平化，杜绝穿越。
String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

/// 路径是否存在（文件或目录均计为存在）——桌面 `Path.exists()` 语义。
bool _pathExists(String path) =>
    FileSystemEntity.typeSync(path, followLinks: true) != FileSystemEntityType.notFound;