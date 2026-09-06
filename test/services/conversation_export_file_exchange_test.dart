/// M4-02：ConversationExportFileExchange 导出文件 seam 测试。
///
/// 测试 seam（公共接口边界）：[ConversationExportFileExchange] 构造注入
/// [ResolveTempDirectory] / [ShareFile] 类型化 fake——断言调用链与文件
/// 内容；平台腿「挂起不抛错 → 超时降级」防御测试已随共享腿收敛至
/// `test/services/platform_file_exchange_test.dart`（2026-09-07 架构深化）。
/// 永不触真平台通道（path_provider / share_plus 缺省实现不落执行路径）。
///
/// 输入为 M4-01 [ConversationExportResult]（fileName+content）。
library;

import 'dart:async';
import 'dart:io';

import 'package:conver_system_mobile/services/conversation_export_file_exchange.dart';
import 'package:conver_system_mobile/services/conversation_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造导出结果（fileName 含扩展名、content 为导出文本）。
ConversationExportResult _result({
  String fileName = '艾莉亚.json',
  String content = '{"conversation":{}}',
}) {
  return ConversationExportResult(fileName: fileName, content: content);
}

void main() {
  group('exportFile · 临时目录写入 + 分享调用链（fake 注入）', () {
    test('成功 → 写入临时目录 + share 收到文件路径与净化名 + 返回成功文案', () async {
      late File sharedFile;
      late String sharedName;
      final tempDir = await Directory.systemTemp.createTemp('m4-02-test');
      addTearDown(() => tempDir.delete(recursive: true));
      final seam = ConversationExportFileExchange(
        resolveTempDirectory: () async => tempDir,
        shareFile: (file, name) async {
          sharedFile = file;
          sharedName = name;
        },
      );

      final message = await seam.exportFile(_result());

      expect(sharedName, '艾莉亚.json');
      expect(sharedFile.path, endsWith('艾莉亚.json'));
      expect(sharedFile.path,
          startsWith('${tempDir.path}${Platform.pathSeparator}'));
      expect(await sharedFile.readAsString(), '{"conversation":{}}');
      expect(message, '已导出 艾莉亚.json（分享面板已打开）');
    });

    test('JSON 与 Markdown 两种产物走同一条 seam（无格式分支，full-path 一致）',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('m4-02-test');
      addTearDown(() => tempDir.delete(recursive: true));
      final shared = <String>[];
      final seam = ConversationExportFileExchange(
        resolveTempDirectory: () async => tempDir,
        shareFile: (file, name) async => shared.add(name),
      );

      await seam.exportFile(_result(fileName: '艾莉亚.json'));
      await seam.exportFile(_result(fileName: '艾莉亚.md', content: '# md'));

      expect(shared, ['艾莉亚.json', '艾莉亚.md']);
    });

    test('文件名原样透传（净化在服务层，seam 不做二次净化）', () async {
      final tempDir = await Directory.systemTemp.createTemp('m4-02-test');
      addTearDown(() => tempDir.delete(recursive: true));
      late File sharedFile;
      final seam = ConversationExportFileExchange(
        resolveTempDirectory: () async => tempDir,
        shareFile: (file, name) async => sharedFile = file,
      );

      await seam.exportFile(_result(fileName: '安全名.md'));

      expect(sharedFile.path, endsWith('安全名.md'));
    });

    test('tempDir 挂起 + 短超时 → StateError（platformTimeout 接线到共享腿）',
        () async {
      // 共享腿超时防御已收敛至 platform_file_exchange_test；此处保留一条
      // seam 级接线断言，兜住未来 seam 忘记透传 platformTimeout 的回归。
      final hanging = Completer<Directory>().future;
      final seam = ConversationExportFileExchange(
        resolveTempDirectory: () => hanging,
        shareFile: (file, name) async {},
        platformTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        seam.exportFile(_result()),
        throwsA(isA<StateError>()),
      );
    });
  });
}