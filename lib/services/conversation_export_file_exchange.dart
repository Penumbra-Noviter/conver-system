/// 对话导出文件 seam（M4-02）—— 临时目录写入 + 系统分享面板。
///
/// 镜像 M3 `FilePickerShareFileExchange` 范式（`character_file_exchange.dart`）：
/// - 构造注入 [ResolveTempDirectory] / [ShareFile] 类型化 typedef +
///   [platformTimeout]（缺省 3s），测试注入 fake 永不触真平台通道；
/// - `ConversationExportService`（M4-01）产出的 [ConversationExportResult]
///   在此写入临时目录并分享：JSON 与 Markdown 两种导出产物走同一条路径
///   （不区分格式分支，full-path 一致）；文件名净化由服务层完成，
///   本 seam 原样透传 [ConversationExportResult.fileName]。
///
/// 平台防御（spec A6 / M3 先例契约）：取临时目录 / 分享每个平台调用点
/// `.timeout(platformTimeout)`——Flutter 平台通道挂起**不抛错**，须超时
/// 兜底不挂死；超时降级抛 [StateError]（文案锚 M3「获取临时目录超时」/
/// 「分享面板超时」），控制器转非阻塞 notice。
library;

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'conversation_export_service.dart';

/// 平台临时目录回调（返回可写 [Directory]）。
typedef ResolveTempDirectory = Future<Directory> Function();

/// 平台分享回调（[file] 为已写入的临时文件，[fileName] 为净化后的分享名）。
typedef ShareFile = Future<void> Function(File file, String fileName);

/// 对话导出结果 → 临时文件 + 分享面板的平台薄层。
///
/// 单表面方法 [exportFile]：写入 `{tempDir.path}{sep}{fileName}`（flush:
/// true）→ 以 XFile 分享 → 返回用户可读成功文案。测试注入 fake 决议
/// 临时目录 / fake 分享回调断言调用链与文件内容；「挂起不抛错」fake
/// 断言超时降级为 [StateError]。
class ConversationExportFileExchange {
  /// [resolveTempDirectory] 缺省 path_provider `getTemporaryDirectory`；
  /// [shareFile] 缺省 share_plus 分享面板；[platformTimeout] 全部平台
  /// 调用点的超时兜底（缺省 3s）。
  ConversationExportFileExchange({
    ResolveTempDirectory? resolveTempDirectory,
    ShareFile? shareFile,
    this.platformTimeout = const Duration(seconds: 3),
  })  : _resolveTempDirectory = resolveTempDirectory ?? getTemporaryDirectory,
        _shareFile = shareFile ?? _shareViaPlus;

  final ResolveTempDirectory _resolveTempDirectory;
  final ShareFile _shareFile;

  /// 平台调用点超时兜底时长（缺省 3s；测试注入短时长断言防御存在）。
  final Duration platformTimeout;

  /// 写出 [result] 并弹起系统分享面板；返回用户可读文案。
  ///
  /// 写入临时目录（文件路径 = `{tempDir.path}{pathSeparator}{fileName}`、
  /// `flush: true`）后以 [XFile] 分享（`file.path` + `name: fileName`）。
  /// 平台调用点挂起 → 超时降级抛 [StateError]（不挂死）。
  Future<String> exportFile(ConversationExportResult result) async {
    final Directory tempDir;
    try {
      tempDir = await _resolveTempDirectory().timeout(platformTimeout);
    } on TimeoutException {
      throw StateError('获取临时目录超时');
    }

    final file = File(
        '${tempDir.path}${Platform.pathSeparator}${result.fileName}');
    await file.writeAsString(result.content, flush: true);

    try {
      await _shareFile(file, result.fileName).timeout(platformTimeout);
    } on TimeoutException {
      throw StateError('分享面板超时');
    }
    return '已导出 ${result.fileName}（分享面板已打开）';
  }
}

/// 缺省 share：share_plus 分享单文件面板（与 M3 `_shareViaPlus` 同形）。
/// 真平台委托：测试契约注入 fake 永不触真通道（M3 先例同构，真分享行为归
/// 模拟器冒烟），此段不计入单测行覆盖。
// coverage:ignore-start
Future<void> _shareViaPlus(File file, String fileName) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, name: fileName)],
      subject: fileName,
      text: fileName,
    ),
  );
}
// coverage:ignore-end