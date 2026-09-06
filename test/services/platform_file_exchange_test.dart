/// 平台文件交换共享腿测试（2026-09-07 架构深化——候选 1 收拢）。
///
/// 平台腿（[writeTempAndShare] / [pickJsonWithTimeout]）的调用链与超时防御
/// 在此单一归属测试：两个消费 seam（角色卡 / 对话导出）不再各自复制
/// 「挂起不抛错 → 超时降级」用例，改由此处覆盖；seam 测试只保留消费方
/// 语义锚（业务组装 + 注入契约）。永不触真平台通道（path_provider /
/// share_plus 缺省实现不落执行路径）。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:conver_system_mobile/services/platform_file_exchange.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('writeTempAndShare · 临时目录写入 + 分享调用链（fake 注入）', () {
    test('成功 → 写入临时目录 + share 收到文件路径与净化名 + 返回成功文案',
        () async {
      late File sharedFile;
      late String sharedName;
      final tempDir = await Directory.systemTemp.createTemp('pfe-test');
      addTearDown(() => tempDir.delete(recursive: true));

      final message = await writeTempAndShare(
        fileName: '测试.json',
        content: '{"a":1}',
        resolveTempDirectory: () async => tempDir,
        shareFile: (file, name) async {
          sharedFile = file;
          sharedName = name;
        },
        platformTimeout: const Duration(seconds: 3),
      );

      expect(sharedName, '测试.json');
      expect(sharedFile.path,
          startsWith('${tempDir.path}${Platform.pathSeparator}'));
      expect(await sharedFile.readAsString(), '{"a":1}');
      expect(message, '已导出 测试.json（分享面板已打开）');
    });
  });

  group('writeTempAndShare · 平台挂起超时降级（防御存在）', () {
    test('tempDir 挂起不抛错 → 超时降级 StateError，分享不执行', () async {
      var shared = false;
      final hanging = Completer<Directory>().future;

      await expectLater(
        writeTempAndShare(
          fileName: '测试.json',
          content: '{}',
          resolveTempDirectory: () => hanging,
          shareFile: (file, name) async => shared = true,
          platformTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message, 'message', '获取临时目录超时',
        )),
      );
      expect(shared, isFalse, reason: '临时目录未就绪不进入分享');
    });

    test('share 挂起不抛错 → 超时降级 StateError（不挂死）', () async {
      final hanging = Completer<void>().future;
      final tempDir = await Directory.systemTemp.createTemp('pfe-test');
      addTearDown(() => tempDir.delete(recursive: true));

      await expectLater(
        writeTempAndShare(
          fileName: '测试.json',
          content: '{}',
          resolveTempDirectory: () async => tempDir,
          shareFile: (file, name) => hanging,
          platformTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message, 'message', '分享面板超时',
        )),
      );
    });
  });

  group('pickJsonWithTimeout · pick 单文件（带超时）', () {
    test('正常返回字节（fake picker 注入）', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = await pickJsonWithTimeout(
        pickJsonBytes: () async => bytes,
        platformTimeout: const Duration(seconds: 3),
      );
      expect(result, bytes);
    });

    test('用户取消（pick 返回 null）→ null 零副作用', () async {
      final result = await pickJsonWithTimeout(
        pickJsonBytes: () async => null,
        platformTimeout: const Duration(seconds: 3),
      );
      expect(result, isNull);
    });

    test('挂起不抛错 → 超时降级为 null（不挂死）', () async {
      final hanging = Completer<Uint8List?>().future;
      final result = await pickJsonWithTimeout(
        pickJsonBytes: () => hanging,
        platformTimeout: const Duration(milliseconds: 50),
      );
      expect(result, isNull,
          reason: '挂起 → 超时兜底降级为未选择（不抛错不挂死）');
    });
  });
}
