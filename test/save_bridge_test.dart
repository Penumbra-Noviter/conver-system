/// F-M5-06 存档桥读写层测试——`LocalStorageAccess` 抽象 + runJavaScript 生产
/// 实现（脚本契约 / 往返解析 / 超时兜底）+ `SaveBridge` 编排（面板汇总 /
/// 导出 / 导入校验应用回滚 / 删除 / 降级）。
///
/// 测试 seam：LocalStorageAccess 经 [FakeLocalStorageAccess]（Map 型）注入，
/// 永不触 WebView（runJavaScript 平台通道测试宿主挂起经验 → 生产实现经
/// [JsBridgeLocalStorageAccess] 单独对「eval 回调」单测，不触真通道）。
/// 编排层复用 F-M5-05 契约纯函数（白名单/校验/应用/删除），本测试只锚
/// 桥自身行为：脚本生成、往返解析、超时降级、编排次序与回滚、共享 seam
/// 调用参数。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/save_bridge.dart';
import 'package:conver_system_mobile/services/simulator/save_contract.dart'
    show maxImportBytes;

import 'support/fake_local_storage_access.dart';

void main() {
  group('LocalStorageAccess 生产实现——JS 脚本契约与超时兜底', () {
    test('enumerate 脚本原文 + Android 编码串往返解析为全量键值', () async {
      final calls = <String>[];
      final access = JsBridgeLocalStorageAccess((script) async {
        calls.add(script);
        // 锚 Android evaluateJavascript 生产契约（F-M5-09 AVD 实证，缺陷 #1）：
        // 字符串结果带外层引号返回 Flutter（JSON 编码串），webview_flutter
        // `runJavaScriptReturningResult` 对字符串**原样透传**——jsonEncode 外层
        // 模拟该引号层，内层 = `JSON.stringify` 产物数组 JSON。
        return jsonEncode('[["k1","v1"],["k2","v2"]]');
      });
      final result = await access.enumerate();
      expect(result, {'k1': 'v1', 'k2': 'v2'});
      expect(
        calls,
        [enumerateLocalStorageScript],
        reason: '枚举脚本逐字（JSON.stringify(Object.entries(localStorage))）',
      );
    });

    test('enumerate：裸 JSON 兼容（锚 iOS/macOS 返回裸值平台）', () async {
      final access = JsBridgeLocalStorageAccess(
        (script) async => '[["k1","v1"],["k2","v2"]]',
      );
      expect(await access.enumerate(), {'k1': 'v1', 'k2': 'v2'});
    });

    test('空 localStorage → 空 Map（不要求键存在）', () async {
      final access = JsBridgeLocalStorageAccess((script) async => '[]');
      expect(await access.enumerate(), isEmpty);
    });

    test('parseLocalStorageEntries：数组条目解析 / 空数组 / Android 编码串解包',
        () {
      expect(parseLocalStorageEntries('[["a","1"],["b","2"]]'), {
        'a': '1',
        'b': '2',
      });
      expect(parseLocalStorageEntries('[]'), isEmpty);
      // Android evaluateJavascript 编码串（带外层引号）→ 解包后归一数组解析。
      expect(
        parseLocalStorageEntries(jsonEncode('[["a","1"],["b","2"]]')),
        {'a': '1', 'b': '2'},
      );
      expect(parseLocalStorageEntries(jsonEncode('[]')), isEmpty);
    });

    test('畸形 JSON / 顶层非数组 → FormatException 上抛；enumerate 兜底空 Map',
        () async {
      expect(() => parseLocalStorageEntries('not-json'), throwsFormatException);
      expect(() => parseLocalStorageEntries('{"a":1}'),
          throwsFormatException);
      // 编码串二次解码失败（内容非 JSON）同样走 FormatException 降级路径。
      expect(
        () => parseLocalStorageEntries(jsonEncode('{broken')),
        throwsFormatException,
      );
      final access = JsBridgeLocalStorageAccess((script) async => '{broken');
      expect(await access.enumerate(), isEmpty, reason: '降级信号 = 空 Map');
      final encodedAccess = JsBridgeLocalStorageAccess(
        (script) async => jsonEncode('{broken'),
      );
      expect(
        await encodedAccess.enumerate(),
        isEmpty,
        reason: '编码串畸形同样降级空 Map（不崩）',
      );
    });

    test('条目非 [k,v] 二元组 / 值非字符串 → 跳过该条（不炸）', () {
      expect(parseLocalStorageEntries('[["a"],["b","x","y"],[5,2]]'), isEmpty);
      expect(parseLocalStorageEntries('[["a",42]]'), isEmpty);
    });

    test('enumerate 求值挂起 → 超时降级空 Map（不挂死不抛错）', () async {
      final access = JsBridgeLocalStorageAccess(
        (script) => Completer<String>().future,
        timeout: const Duration(milliseconds: 30),
      );
      expect(await access.enumerate(), isEmpty);
    });

    test('setItem 脚本：键值经 jsonEncode 转义（引号/反斜杠/换行）', () async {
      final calls = <String>[];
      final access = JsBridgeLocalStorageAccess((script) async {
        calls.add(script);
        return '';
      });
      await access.setItem('a"b\\c', 'v\n');
      expect(calls, ['localStorage.setItem("a\\"b\\\\c", "v\\n")']);
    });

    test('removeItem 脚本原文', () async {
      final calls = <String>[];
      final access = JsBridgeLocalStorageAccess((script) async {
        calls.add(script);
        return '';
      });
      await access.removeItem('k');
      expect(calls, ['localStorage.removeItem("k")']);
    });

    test('写操作挂起 → 上抛 TimeoutException（不挂死，交给调用方回滚提示）',
        () {
      final access = JsBridgeLocalStorageAccess(
        (script) => Completer<String>().future,
        timeout: const Duration(milliseconds: 30),
      );
      expect(access.setItem('k', 'v'), throwsA(isA<TimeoutException>()));
      expect(access.removeItem('k'), throwsA(isA<TimeoutException>()));
    });
  });

  group('SaveBridge 编排', () {
    late Directory tempDir;
    late FakeLocalStorageAccess access;

    const SaveGame lifeSim = SaveGame(
      id: 'life-sim',
      name: '人生模拟器',
      saveKeys: ['life_save'],
    );
    const SaveGame noSaveGame = SaveGame(id: 'local-x', name: '本地示例');
    final SaveGame twilight = const SaveGame(
      id: 'twilight-witch',
      name: '暮色女巫',
      saveKeys: ['twilight_slot_\\d+'],
    );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('m5-06-bridge-');
      access = FakeLocalStorageAccess();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    SaveBridge buildBridge({
      required List<SaveGame> games,
      List<int>? importBytes,
      Future<void> Function(File file, String fileName)? shareFile,
      Future<Directory> Function()? resolveTempDirectory,
      Duration platformTimeout = const Duration(seconds: 10),
    }) {
      return SaveBridge(
        access: access,
        games: games,
        pickJsonBytes: () async =>
            importBytes == null ? null : Uint8List.fromList(importBytes),
        resolveTempDirectory:
            resolveTempDirectory ?? () async => tempDir,
        shareFile: shareFile ?? (file, fileName) async {},
        platformTimeout: platformTimeout,
      );
    }

    Uint8List importBytesFor(Map<String, Object?> keys) => Uint8List.fromList(
          utf8.encode(jsonEncode({
            ...keys,
          })),
        );

    test('loadPanel：逐游戏键数 + 字符大小（totalChars = 键值长度之和，锚桌面）',
        () async {
      access = FakeLocalStorageAccess({
        'life_save': 'abc',
        'twilight_slot_1': 'x',
        'twilight_slot_2': 'yyyy',
        'cfg-endpoint': 'sk-secret', // 非白名单：天然排除
      });
      final bridge = buildBridge(games: [lifeSim, noSaveGame, twilight]);

      final rows = await bridge.loadPanel();

      expect(rows, hasLength(3));
      final byId = {for (final r in rows) r.gameId: r};
      expect(byId['life-sim']!.keyCount, 1);
      expect(byId['life-sim']!.totalChars, 3);
      expect(byId['life-sim']!.saveKeysDeclared, isTrue);
      expect(byId['twilight-witch']!.keyCount, 2);
      expect(byId['twilight-witch']!.totalChars, 5);
      expect(byId['local-x']!.keyCount, 0);
      expect(byId['local-x']!.saveKeysDeclared, isFalse,
          reason: '无 saveKeys = 无存档管理降级信号');
    });

    test('空 storage → 全部 0 键（降级不崩）', () async {
      final bridge = buildBridge(games: [lifeSim]);
      final rows = await bridge.loadPanel();
      expect(rows.single.keyCount, 0);
      expect(rows.single.totalChars, 0);
    });

    test('导出：payload 键值与 storage 一致 + 文件名 `<净化id>-saves.json`',
        () async {
      access = FakeLocalStorageAccess({'life_save': '{"hp":10}'});
      final shared = <({String content, String fileName})>[];
      final bridge = buildBridge(
        games: [lifeSim],
        shareFile: (file, name) async {
          shared.add((content: await file.readAsString(), fileName: name));
        },
      );

      await bridge.loadPanel();
      final result = await bridge.exportGame('life-sim');

      expect(result.ok, isTrue);
      expect(result.message, contains('life-sim-saves.json'));
      expect(shared, hasLength(1));
      expect(shared.single.fileName, 'life-sim-saves.json');
      final payload = jsonDecode(shared.single.content) as Map<String, dynamic>;
      expect(payload['game_id'], 'life-sim');
      expect(payload['game_name'], '人生模拟器');
      expect(payload['keys'], {'life_save': '{"hp":10}'});
      expect(payload['saved_at'], isA<String>());
    });

    test('导出：零键不分享 + 「没有可导出的存档键」', () async {
      final shared = <String>[];
      final bridge = buildBridge(
        games: [lifeSim],
        shareFile: (file, name) async => shared.add(name),
      );

      final result = await bridge.exportGame('life-sim');

      expect(result.ok, isFalse);
      expect(result.message, '没有可导出的存档键');
      expect(shared, isEmpty, reason: '零键不打开分享面板');
    });

    test('导出：文件名净化（TD-65 字符 → _，尾部点裁剪）', () async {
      access = FakeLocalStorageAccess({'sv': '1'});
      const oddGame = SaveGame(id: 'life/sim:..', name: 'x', saveKeys: ['sv']);
      final shared = <String>[];
      final bridge = buildBridge(
        games: [oddGame],
        shareFile: (file, name) async => shared.add(name),
      );

      final result = await bridge.exportGame('life/sim:..');

      expect(result.ok, isTrue);
      // 语义与桌面逐字：/ 和 : → _，尾部点裁剪（裁后残留该 _）。
      expect(shared.single, 'life_sim_-saves.json');
    });

    test('导出：临时目录解析挂起 → 「获取临时目录超时」失败文案（M4 超时兜底）',
        () async {
      access = FakeLocalStorageAccess({'life_save': 'x'});
      final bridge = buildBridge(
        games: [lifeSim],
        resolveTempDirectory: () => Completer<Directory>().future,
        platformTimeout: const Duration(milliseconds: 30),
      );

      final result = await bridge.exportGame('life-sim');

      expect(result.ok, isFalse);
      expect(result.message, '获取临时目录超时');
    });

    test('导出：分享抛非 StateError 异常 → 「导出失败：…」兜底文案不崩',
        () async {
      access = FakeLocalStorageAccess({'life_save': 'x'});
      final bridge = buildBridge(
        games: [lifeSim],
        shareFile: (file, name) async => throw Exception('share 故障'),
      );

      final result = await bridge.exportGame('life-sim');

      expect(result.ok, isFalse);
      expect(result.message, contains('导出失败'));
      expect(result.message, contains('share 故障'));
    });

    test('导入：选文件 → 整包校验放行 → 写回 storage → 「已恢复 N 个存档键」',
        () async {
      final bridge = buildBridge(
        games: [lifeSim],
        importBytes: importBytesFor({
          'game_id': 'life-sim',
          'game_name': '人生模拟器',
          'saved_at': '2026-09-07T00:00:00.000Z',
          'keys': {'life_save': '{"hp":10}'},
        }),
      );

      final result = await bridge.importGame('life-sim');

      expect(result, isNotNull);
      expect(result!.ok, isTrue);
      expect(result.message, '已恢复 1 个存档键');
      expect(access['life_save'], '{"hp":10}', reason: '白名单键写回真实 store');
    });

    test('导入：用户取消选择（null）→ 静默返回 null 零副作用', () async {
      final bridge = buildBridge(games: [lifeSim], importBytes: null);

      final result = await bridge.importGame('life-sim');

      expect(result, isNull);
      expect(access.snapshot, isEmpty);
    });

    test('导入：选文件抛非超时异常 → 「选择文件失败：…」', () async {
      final bridge = SaveBridge(
        access: access,
        games: [lifeSim],
        pickJsonBytes: () async => throw StateError('picker 故障'),
      );

      final result = await bridge.importGame('life-sim');

      expect(result!.ok, isFalse);
      expect(result.message, contains('选择文件失败'));
      expect(result.message, contains('picker 故障'));
      expect(access.snapshot, isEmpty);
    });

    test('导入：损坏 JSON → 「不是有效的 JSON 文件」', () async {
      final bridge = buildBridge(
        games: [lifeSim],
        importBytes: utf8.encode('not-json'),
      );

      final result = await bridge.importGame('life-sim');

      expect(result!.ok, isFalse);
      expect(result.message, '不是有效的 JSON 文件');
      expect(access.snapshot, isEmpty);
    });

    test('导入：超 5MB → 「存档文件过大（上限 5MB）」整包拒绝', () async {
      final bridge = buildBridge(
        games: [lifeSim],
        importBytes: List<int>.filled(maxImportBytes + 1, 0),
      );

      final result = await bridge.importGame('life-sim');

      expect(result!.ok, isFalse);
      expect(result.message, '存档文件过大（上限 5MB）');
      expect(access.snapshot, isEmpty);
    });

    test('导入：键不在白名单 → 整包拒绝（至多 10 条问题），不写任何键', () async {
      final bridge = buildBridge(
        games: [lifeSim],
        importBytes: importBytesFor({
          'keys': {'other_key': '{"x":1}', 'evil': 'x'},
        }),
      );

      final result = await bridge.importGame('life-sim');

      expect(result!.ok, isFalse);
      expect(result.message, contains('不在该游戏存档键白名单内'));
      expect(access.snapshot, isEmpty, reason: '任一问题整包拒绝零写入');
    });

    test('导入：`__proto__` 键命中白名单 → 完整写出（无原型累积器语义）',
        () async {
      const protoGame = SaveGame(id: 'proto', name: 'p', saveKeys: ['__proto__']);
      final bridge = buildBridge(
        games: [protoGame],
        importBytes: importBytesFor({
          'keys': {'__proto__': '{"ok":1}'},
        }),
      );

      final result = await bridge.importGame('proto');

      expect(result!.ok, isTrue);
      expect(access['__proto__'], '{"ok":1}');
    });

    test('导入：写回失败 → 尽力回滚（TD-73）+ 失败文案，store 不残留半截数据',
        () async {
      access = FakeLocalStorageAccess();
      access.setItemThrows['b'] = StateError('存储配额满');
      const twoKeyGame = SaveGame(id: 'two', name: 't', saveKeys: ['a', 'b']);
      final bridge = buildBridge(
        games: [twoKeyGame],
        importBytes: importBytesFor({
          'keys': {'a': '1', 'b': '2'},
        }),
      );

      final result = await bridge.importGame('two');

      expect(result!.ok, isFalse);
      expect(result.message, contains('导入失败'));
      expect(access.snapshot, isEmpty,
          reason: '先成功的 a 已逆序回滚（新键移除）');
    });

    test('导入：写回失败回滚还原旧值（prev 非空路径）', () async {
      // 目标键已存在旧值：回滚应还原旧值（setItem 回写 prev）而非删除。
      access = FakeLocalStorageAccess({'a': 'old-a', 'b': 'old-b'});
      access.setItemThrows['b'] = StateError('存储配额满');
      const twoKeyGame = SaveGame(id: 'two', name: 't', saveKeys: ['a', 'b']);
      final bridge = buildBridge(
        games: [twoKeyGame],
        importBytes: importBytesFor({
          'keys': {'a': 'new-a', 'b': 'new-b'},
        }),
      );

      final result = await bridge.importGame('two');

      expect(result!.ok, isFalse);
      expect(access['a'], 'old-a', reason: '已写的 a 回滚还原旧值');
      expect(access['b'], 'old-b', reason: '抛错键本身未写入（原子性）');
    });

    test('删除：确认后删除 → 「已删除 N 个存档键」+ store 清空白名单键',
        () async {
      access = FakeLocalStorageAccess({'life_save': 'x', 'other': 'y'});
      final bridge = buildBridge(games: [lifeSim]);

      final result = await bridge.deleteGame('life-sim');

      expect(result.ok, isTrue);
      expect(result.message, '已删除 1 个存档键');
      expect(access['life_save'], isNull);
      expect(access['other'], 'y', reason: '非白名单键不被误删');
    });

    test('删除：零键 → 「没有可删除的存档键」', () async {
      final bridge = buildBridge(games: [lifeSim]);
      final result = await bridge.deleteGame('life-sim');
      expect(result.ok, isFalse);
      expect(result.message, '没有可删除的存档键');
    });

    test('删除后 loadPanel → 键数归零（撤销后刷新不残留）', () async {
      access = FakeLocalStorageAccess({'life_save': 'x'});
      final bridge = buildBridge(games: [lifeSim]);

      await bridge.loadPanel();
      await bridge.deleteGame('life-sim');
      final rows = await bridge.loadPanel();

      expect(rows.single.keyCount, 0);
      expect(rows.single.totalChars, 0);
    });

    test('未知 gameId → 明确失败文案不崩', () async {
      final bridge = buildBridge(games: [lifeSim]);
      expect((await bridge.exportGame('nope')).message, '未找到游戏');
      expect((await bridge.deleteGame('nope')).message, '未找到游戏');
      final imported = await bridge.importGame('nope');
      expect(imported!.message, '未找到游戏');
    });
  });
}