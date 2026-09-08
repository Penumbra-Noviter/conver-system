/// F-M5-01 首启种子 ensureSeeded — 幂等契约逐字锚桌面 simulator_store.py。
///
/// 语义逐字锚点（只读）：`desktop/backend/app/services/simulator_store.py`
/// ensure_seeded（种子标记 / 整目录拷贝 / manifest 最后落盘 / 源缺降级不
/// 崩溃 / 数据目录不可写抛带路径错误）。
///
/// 测例锁定契约（工单验收语义契约逐条）：
/// - manifest 存在 = 已种子（返回 false 不重种、不读资产）；
/// - 全新目录整目录拷贝 + manifest 最后落盘（请求顺序可断言）；
/// - 种子源缺 manifest → 返回 false 且不创建目录（降级不崩溃）；
/// - 种子中断时序：manifest 落盘前中断 → 下次调用重种；manifest 落盘后 →
///   幂等跳过；
/// - 数据目录不可写 → 抛带目录路径的明确错误；
/// - SimulatorDataDir 数据目录解析 seam（注入回调，生产 path_provider）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/seed_service.dart';
import 'package:conver_system_mobile/services/simulator/simulator_data_dir.dart';

/// 种子源最小合法 manifest（2 款：ai 带 saveKeys + local）。
final Map<String, Object?> seedManifestData = <String, Object?>{
  'version': 2,
  'simulators': <Object?>[
    <String, Object?>{'id': 'game-a', 'file': 'game-a.html', 'name': 'Game A', 'type': 'ai', 'saveKeys': <Object?>['ga_save']},
    <String, Object?>{'id': 'game-b', 'file': 'game-b.html', 'name': 'Game B', 'type': 'local'},
  ],
};

Uint8List seedManifestBytes() => Uint8List.fromList(utf8.encode(json.encode(seedManifestData)));

const String assetRoot = 'assets/simulators';

String assetOf(String file) => '$assetRoot/$file';

/// 假资产加载器：记录请求顺序；可按路径缺资产或按请求序号模拟中断。
class FakeSeedLoader {
  FakeSeedLoader(Map<String, Uint8List> files) : files = Map.of(files);

  final Map<String, Uint8List> files;

  /// 请求记录（含顺序）。
  final List<String> requested = <String>[];

  /// 请求数超过该值后抛错（模拟种子中断；-1 = 不中断）。
  int interruptAfterRequests = -1;

  Future<Uint8List> load(String path) async {
    requested.add(path);
    if (interruptAfterRequests >= 0 && requested.length > interruptAfterRequests) {
      throw StateError('模拟种子中断');
    }
    final bytes = files[path];
    if (bytes == null) {
      throw StateError('种子源资产缺失: $path');
    }
    return bytes;
  }
}

Future<Directory> makeTempDir() async {
  final temp = await Directory.systemTemp.createTemp('seed-test-');
  addTearDown(() => temp.delete(recursive: true));
  return temp;
}

Future<Directory> simDirUnder(Directory parent) async =>
    Directory('${parent.path}${Platform.pathSeparator}simulators');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ensureSeeded — 全新目录整目录拷贝', () {
    test('全新目录：先 HTML 后 manifest（manifest 最后落盘），字节一致，返回 true', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);
      final manifestBytes = seedManifestBytes();
      final loader = FakeSeedLoader(<String, Uint8List>{
        assetOf('manifest.json'): manifestBytes,
        assetOf('game-a.html'): Uint8List.fromList(utf8.encode('<html>a</html>')),
        assetOf('game-b.html'): Uint8List.fromList(utf8.encode('<html>b</html>')),
      });

      final seeded = await ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loader.load);

      expect(seeded, isTrue);
      expect(simDir.existsSync(), isTrue);
      // 资产读取序列可断言落盘顺序：探测（源检查）→ 游戏文件 → manifest 最后
      expect(loader.requested.first, assetOf('manifest.json'), reason: '首请求 = 种子源探测（存在性检查）');
      expect(loader.requested.last, assetOf('manifest.json'), reason: 'manifest 最后加载/落盘（种子标记最晚生效）');
      final gameRequests = loader.requested.where((p) => p != assetOf('manifest.json')).toList();
      expect(gameRequests, hasLength(2));
      expect(gameRequests.toSet(), <String>{assetOf('game-a.html'), assetOf('game-b.html')});
      // 字节一致（整目录拷贝语义）
      expect(File('${simDir.path}${Platform.pathSeparator}game-a.html').readAsBytesSync(),
          loader.files[assetOf('game-a.html')]);
      expect(File('${simDir.path}${Platform.pathSeparator}game-b.html').readAsBytesSync(),
          loader.files[assetOf('game-b.html')]);
      expect(File('${simDir.path}${Platform.pathSeparator}manifest.json').readAsBytesSync(),
          loader.files[assetOf('manifest.json')]);
      // 落盘文件名恰为无路径 basename（防 manifest file 穿越写目录外）
      expect(simDir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList(),
          hasLength(3));
    });
  });

  group('ensureSeeded — 幂等契约', () {
    test('目标已有 manifest（已种子标记）→ 返回 false 不重种、不读任何资产', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);
      simDir.createSync(recursive: true);
      File('${simDir.path}${Platform.pathSeparator}manifest.json').writeAsStringSync('stale');

      final loader = FakeSeedLoader(<String, Uint8List>{
        assetOf('manifest.json'): seedManifestBytes(),
        assetOf('game-a.html'): Uint8List.fromList(utf8.encode('<html>a</html>')),
      });

      final seeded = await ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loader.load);

      expect(seeded, isFalse, reason: 'manifest 存在 = 已种子标记，幂等跳过');
      // 幂等路径只做源探测（桌面先查源后查目标，同序），不触游戏资产、不写目标
      expect(loader.requested, <String>[assetOf('manifest.json')],
          reason: '幂等路径仅探测源 manifest，无游戏读取、无末尾落盘');
      expect(File('${simDir.path}${Platform.pathSeparator}game-a.html').existsSync(), isFalse,
          reason: '不重种，不补拷游戏文件（标记语义，不做逐文件自愈）');
      expect(File('${simDir.path}${Platform.pathSeparator}manifest.json').readAsStringSync(), 'stale',
          reason: '目标 manifest 原样保留（不写）');
    });

    test('Falsify: 目标 manifest 为同名目录 → 仍计为已种子（桌面 Path.exists 文件/目录同语义）', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);
      Directory('${simDir.path}${Platform.pathSeparator}manifest.json').createSync(recursive: true);

      final loader = FakeSeedLoader(<String, Uint8List>{
        assetOf('manifest.json'): seedManifestBytes(),
        assetOf('game-a.html'): Uint8List.fromList(utf8.encode('<html>a</html>')),
      });

      final seeded = await ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loader.load);

      expect(seeded, isFalse, reason: 'manifest 形态（文件或目录）均计为已种子标记');
      expect(simDir.listSync().whereType<File>(), isEmpty, reason: '不触发重种写入');
    });

    test('种子源缺 manifest → 返回 false 且不创建目录（降级不崩溃）', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);
      final loader = FakeSeedLoader(<String, Uint8List>{
        assetOf('game-a.html'): Uint8List.fromList(utf8.encode('<html>a</html>')),
      });

      final seeded = await ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loader.load);

      expect(seeded, isFalse);
      expect(simDir.existsSync(), isFalse, reason: '源缺 manifest 不建目录');
    });

    test('种子源 manifest 损坏（非法 JSON）→ 返回 false 降级不崩溃', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);
      final loader = FakeSeedLoader(<String, Uint8List>{
        assetOf('manifest.json'): Uint8List.fromList(utf8.encode('not-json{{{')),
        assetOf('game-a.html'): Uint8List.fromList(utf8.encode('<html>a</html>')),
      });

      final seeded = await ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loader.load);

      expect(seeded, isFalse);
      expect(simDir.existsSync(), isFalse, reason: '源 manifest 不可枚举 → 源缺陷降级');
    });
  });

  group('ensureSeeded — F-25 单游戏资产缺失降级（TD-1）', () {
    test('manifest 列出但 game-a 资产缺失 → 跳过缺失款继续种其余，返回 true', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);
      final manifestBytes = seedManifestBytes();
      final loader = FakeSeedLoader(<String, Uint8List>{
        assetOf('manifest.json'): manifestBytes,
        // game-a.html 缺（未登记资产，rootBundle 裸抛）
        assetOf('game-b.html'): Uint8List.fromList(utf8.encode('<html>b</html>')),
      });

      final seeded = await ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loader.load);

      expect(seeded, isTrue, reason: '单游戏缺失降级：跳过缺失款不中止整次种子');
      expect(File('${simDir.path}${Platform.pathSeparator}game-a.html').existsSync(), isFalse,
          reason: '缺失款不落盘');
      expect(File('${simDir.path}${Platform.pathSeparator}game-b.html').existsSync(), isTrue,
          reason: '其余款照常落盘');
      expect(File('${simDir.path}${Platform.pathSeparator}manifest.json').existsSync(), isTrue,
          reason: 'manifest 照常最后落盘（种子标记语义不变）');
      expect(loader.requested.where((p) => p != assetOf('manifest.json')), hasLength(2),
          reason: '两款均被尝试加载（含缺失款），缺失款跳过不中止');
    });

    test('Falsify: 缺失款抛 FlutterError 形态（rootBundle 裸抛 FlutterError 而非 StateError）→ 同样跳过不中止', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);
      Future<Uint8List> load(String path) async {
        if (path == assetOf('manifest.json')) {
          return seedManifestBytes();
        }
        if (path == assetOf('game-a.html')) {
          throw const _FlutterErrorLike('未登记资产 仿微.html');
        }
        return Uint8List.fromList(utf8.encode('<html>b</html>'));
      }

      final seeded = await ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: load);

      expect(seeded, isTrue, reason: 'FlutterError 形态同样按单游戏缺失降级');
      expect(File('${simDir.path}${Platform.pathSeparator}game-b.html').existsSync(), isTrue);
      expect(File('${simDir.path}${Platform.pathSeparator}manifest.json').existsSync(), isTrue);
    });

    test('Falsify: 缺失款以 FileSystemException 形态抛（文件系统层错误）→ 不被降级吞，上抛带路径错误', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);
      Future<Uint8List> load(String path) async {
        if (path == assetOf('game-a.html')) {
          throw const FileSystemException('asset read failed', 'game-a.html');
        }
        if (path == assetOf('manifest.json')) {
          return seedManifestBytes();
        }
        return Uint8List.fromList(utf8.encode('<html>b</html>'));
      }

      await expectLater(
        ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: load),
        throwsA(isA<FileSystemException>()
            .having((e) => e.message, 'message', contains(simDir.path))),
      );
      expect(File('${simDir.path}${Platform.pathSeparator}game-b.html').existsSync(), isFalse,
          reason: '文件系统层错误 → 中止整次并上抛（目录不可用语义，非单游戏降级）');
    });
  });

  group('ensureSeeded — 种子中断时序（可测契约）', () {
    test('manifest 落盘前中断 → 抛错且目标无 manifest；下次调用重种', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);
      final manifestBytes = seedManifestBytes();
      final loader = FakeSeedLoader(<String, Uint8List>{
        assetOf('manifest.json'): manifestBytes,
        assetOf('game-a.html'): Uint8List.fromList(utf8.encode('<html>a</html>')),
        assetOf('game-b.html'): Uint8List.fromList(utf8.encode('<html>b</html>')),
      })..interruptAfterRequests = 3; // 第 4 次请求（末尾 manifest 加载）抛错中断

      await expectLater(
        ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loader.load),
        throwsStateError,
      );
      expect(File('${simDir.path}${Platform.pathSeparator}manifest.json').existsSync(), isFalse,
          reason: 'manifest 最后落盘：中断于 manifest 之前 → 无种子标记');

      // 二次调用：目标存有部分文件但无 manifest → 重种（整目录重拷）返回 true
      final loader2 = FakeSeedLoader(<String, Uint8List>{
        assetOf('manifest.json'): manifestBytes,
        assetOf('game-a.html'): Uint8List.fromList(utf8.encode('<html>a</html>')),
        assetOf('game-b.html'): Uint8List.fromList(utf8.encode('<html>b</html>')),
      });
      final reseeded = await ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loader2.load);

      expect(reseeded, isTrue, reason: 'manifest 落盘前中断 → 下次调用重种');
      expect(File('${simDir.path}${Platform.pathSeparator}manifest.json').existsSync(), isTrue);
    });

    test('manifest 落盘后 → 下次调用幂等跳过（返回 false，不触资产）', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);
      final manifestBytes = seedManifestBytes();
      final loader = FakeSeedLoader(<String, Uint8List>{
        assetOf('manifest.json'): manifestBytes,
        assetOf('game-a.html'): Uint8List.fromList(utf8.encode('<html>a</html>')),
        assetOf('game-b.html'): Uint8List.fromList(utf8.encode('<html>b</html>')),
      });

      expect(await ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loader.load), isTrue);

      final requested2 = <String>[];
      final again = await ensureSeeded(
        simDir: simDir,
        assetRoot: assetRoot,
        loadAsset: (String path) async {
          requested2.add(path);
          if (path == assetOf('manifest.json')) {
            return seedManifestBytes();
          }
          throw StateError('幂等路径不应读取游戏资产: $path');
        },
      );

      expect(again, isFalse);
      expect(requested2, <String>[assetOf('manifest.json')], reason: '幂等路径仅探测源 manifest 即早退');
    });
  });

  group('ensureSeeded — 数据目录不可写', () {
    test('目标父路径为文件 → mkdir 失败，抛带目录路径的明确错误', () async {
      final parent = await makeTempDir();
      final blocker = File('${parent.path}${Platform.pathSeparator}blocker');
      blocker.writeAsStringSync('x');
      final simDir = Directory('${blocker.path}${Platform.pathSeparator}simulators');
      final loader = FakeSeedLoader(<String, Uint8List>{
        assetOf('manifest.json'): seedManifestBytes(),
        assetOf('game-a.html'): Uint8List.fromList(utf8.encode('<html>a</html>')),
      });

      await expectLater(
        ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loader.load),
        throwsA(isA<FileSystemException>()
            .having((e) => e.message, 'message', contains(simDir.path))
            .having((e) => e.path, 'path', simDir.path)),
      );
    });
  });

  group('ensureSeeded — 真实 22 款内置资产（rootBundle 端到端）', () {
    test('全量种子：22 HTML + manifest 落盘；二次调用幂等跳过', () async {
      final parent = await makeTempDir();
      final simDir = await simDirUnder(parent);

      Future<Uint8List> loadViaRootBundle(String path) async {
        final data = await rootBundle.load(path);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }

      final seeded = await ensureSeeded(simDir: simDir, assetRoot: assetRoot, loadAsset: loadViaRootBundle);
      expect(seeded, isTrue);

      final names = simDir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList();
      expect(names, hasLength(23), reason: '22 款 HTML + manifest.json');
      expect(names.where((n) => n.endsWith('.html')), hasLength(22));
      expect(names, contains('manifest.json'));

      final requested2 = <String>[];
      final again = await ensureSeeded(
        simDir: simDir,
        assetRoot: assetRoot,
        loadAsset: (String path) async {
          requested2.add(path);
          if (path == assetOf('manifest.json')) {
            return seedManifestBytes();
          }
          throw StateError('幂等路径不应读取游戏资产: $path');
        },
      );
      expect(again, isFalse);
      expect(requested2, <String>[assetOf('manifest.json')], reason: '幂等路径仅探测源 manifest 即早退');
    });
  });

  group('SimulatorDataDir — 数据目录解析 seam', () {
    test('resolve = 文档目录下 simulators/（注入回调），目录名常量唯一归属', () async {
      final parent = await makeTempDir();
      final dataDir = SimulatorDataDir(resolveDocumentsDir: () async => parent);
      final dir = await dataDir.resolve();
      expect(dir.path, '${parent.path}${Platform.pathSeparator}simulators');
    });

    test('resolve 不创建目录（种子/服务器各自按需建目录）', () async {
      final parent = await makeTempDir();
      final dataDir = SimulatorDataDir(resolveDocumentsDir: () async => parent);
      final dir = await dataDir.resolve();
      expect(dir.existsSync(), isFalse);
    });
  });
}

/// flutter_test 无法直接构造 [FlutterError]，用同形异常模拟 rootBundle 裸抛
/// （F-2 复现路径：未登记资产 → 非 FileSystemException → 旧实现整次种子中止）。
class _FlutterErrorLike implements Exception {
  const _FlutterErrorLike(this.message);

  final String message;

  @override
  String toString() => 'FlutterError: $message';
}