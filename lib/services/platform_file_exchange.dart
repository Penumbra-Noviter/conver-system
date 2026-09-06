/// 平台文件交换共享腿（2026-09-07 架构深化——候选 1 收拢）。
///
/// 角色卡 seam（`character_file_exchange.dart`）与对话导出 seam
/// （`conversation_export_file_exchange.dart`）各自的「平台通道 + 超时兜底 +
/// StateError 降级」腿收敛于此：typedef 单一归属、缺省平台实现单一归属、
/// 「写临时目录 + 分享」组合与超时文案单一归属。消费 seam 只保留业务数据
/// 组装与注入契约（平台防御：Flutter 平台通道挂起**不抛错**，须 `.timeout`
/// 兜底不挂死——测试注入「挂起不抛错」的类型化 fake 断言防御存在）。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 平台 pick 回调：返回选中文件字节（`null` = 用户取消）。
typedef PickJsonBytes = Future<Uint8List?> Function();

/// 平台临时目录回调（返回可写 [Directory]）。
typedef ResolveTempDirectory = Future<Directory> Function();

/// 平台分享回调（[file] 为已写入的临时文件，[fileName] 为净化后的分享名）。
typedef ShareFile = Future<void> Function(File file, String fileName);

/// 写出 [content] 到临时目录并经分享面板分享；返回用户可读文案。
///
/// 组合级共享腿（消费 seam 不再各自实现）：临时目录（带超时）→ 写盘
/// flush → 分享（带超时）；平台调用点挂起 → 超时降级抛 [StateError]
/// （「获取临时目录超时」/「分享面板超时」），不挂死。文件名净化由消费方
/// 服务层完成（[safeFileName]），本腿原样透传。
Future<String> writeTempAndShare({
  required String fileName,
  required String content,
  required ResolveTempDirectory resolveTempDirectory,
  required ShareFile shareFile,
  required Duration platformTimeout,
}) async {
  final Directory tempDir;
  try {
    tempDir = await resolveTempDirectory().timeout(platformTimeout);
  } on TimeoutException {
    throw StateError('获取临时目录超时');
  }

  final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(content, flush: true);

  try {
    await shareFile(file, fileName).timeout(platformTimeout);
  } on TimeoutException {
    throw StateError('分享面板超时');
  }
  return '已导出 $fileName（分享面板已打开）';
}

/// pick 单文件（带超时）：挂起 → 降级为未选择（`null`，不挂死）。
Future<Uint8List?> pickJsonWithTimeout({
  required PickJsonBytes pickJsonBytes,
  required Duration platformTimeout,
}) async {
  try {
    return await pickJsonBytes().timeout(platformTimeout);
  } on TimeoutException {
    return null;
  }
}

/// 缺省临时目录：path_provider `getTemporaryDirectory`。
Future<Directory> defaultResolveTempDirectory() => getTemporaryDirectory();

/// 缺省 pick：file_picker 选单个 `.json` 并读取字节（用户取消 → null）。
///
/// `FilePicker.pickFile`（12.x）本身即单文件语义（返回 `PlatformFile?`），
/// 配合 `FileType.custom + allowedExtensions: ['json']` 过滤扩展名。
// coverage:ignore-start
Future<Uint8List?> defaultPickJsonFile() async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  return picked?.readAsBytes();
}
// coverage:ignore-end

/// 缺省 share：share_plus 分享单文件面板。
// coverage:ignore-start
Future<void> defaultShareViaPlus(File file, String fileName) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, name: fileName)],
      subject: fileName,
      text: fileName,
    ),
  );
}
// coverage:ignore-end
