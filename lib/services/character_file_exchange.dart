/// 角色文件导入/导出的平台通道 seam（M3-01 定义接口 + Stub 壳；M3-03 追加
/// 真实现 [FilePickerShareFileExchange] + 顶层纯函数 [safeFileName]）。
///
/// 通道契约（M3-01 工件）：
/// - 视图层/控制器不直接触碰 file_picker / share_plus / path_provider——
///   全部平台调用收口在本接口的实现之后；
/// - [CharacterFileExchangeStub] 为占位壳：导出按钮经此调用并展示
///   「随后续批次交付」提示，**永不触真平台通道**（测试注入 fake seam
///   断言调用链）；
/// - 实现约定：导出产物文件名由实现方以 `{safeName}.json` 构造（文件名
///   安全净化纯函数 [safeFileName] 本文件实现），返回值为用户可读文案。
///
/// 平台防御（验收 7）：pick / share / `getTemporaryDirectory` 每个平台调用
/// 点 `.timeout(3s)` + catch 降级（Flutter 平台通道挂起**不抛错**，须超时
/// 兜底不挂死）；测试注入「挂起不抛错」的类型化假实现断言防御存在。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database/app_database.dart' show Character;
import 'character_card.dart';

/// 角色 V2 卡文件交换 seam——导入/导出平台薄层。
///
/// 方法返回用户可读结果文案（成功路径由实现构造）；失败路径抛异常，
/// 由控制器兜底转 notice（平台调用点须 `.timeout(3s)` 防挂握 + catch
/// 降级，真实现落实，测试断言防御存在）。
abstract interface class CharacterFileExchange {
  /// 导入一张角色卡（系统文件选择器选单个 `.json`）。
  ///
  /// 返回解析归一化后的 [CharacterDraft]（由控制器装配合入仓库）；
  /// 用户取消或平台挂起超时降级 → 返回 `null`（零副作用）。解析失败 /
  /// 校验失败本方法不抛——由 [parseCharacterCardBytes] 抛出的异常
  /// （[CardFormatException] / [CardValidationException]）向上传播，控制器
  /// 按分级转 notice。
  Future<CharacterDraft?> importCharacter();

  /// 导出 [character] 为 V2 JSON 卡文件；返回展示给用户的提示文案。
  Future<String> exportCharacter(Character character);
}

/// 占位提示实现（M3-01）——不触碰任何平台通道。
///
/// 真实现（file_picker / share_plus 分享 / 临时目录写入）随 M3-03 追加于
/// [FilePickerShareFileExchange]，本类保持串行不动。文案锚「随后续批次
/// 交付」（验收 7 语义）；导入视为用户取消（null，零副作用）。
class CharacterFileExchangeStub implements CharacterFileExchange {
  const CharacterFileExchangeStub();

  @override
  Future<CharacterDraft?> importCharacter() async => null;

  @override
  Future<String> exportCharacter(Character character) async {
    return '角色导出（V2 JSON 卡）随后续批次交付';
  }
}

/// 平台 pick 回调：返回选中文件字节（`null` = 用户取消）。
typedef PickJsonBytes = Future<Uint8List?> Function();

/// 平台临时目录回调（返回可写 [Directory]）。
typedef ResolveTempDirectory = Future<Directory> Function();

/// 平台分享回调（[file] 为已写入的临时文件，[fileName] 为净化后的分享名）。
typedef ShareFile = Future<void> Function(File file, String fileName);

/// 真实现：file_picker 选单个 `.json` → 临时目录写入 → share_plus 分享。
///
/// 构造注入 [PickJsonBytes] / [ResolveTempDirectory] / [ShareFile] 类型化
/// fake（测试永不触真平台通道）+ [platformTimeout]（缺省 3s）。所有平台
/// 调用点 `.timeout(platformTimeout)` + catch 降级：pick 挂起 → 降级为
/// 未选择（null）；临时目录 / 分享挂起 → 降级抛 [StateError]（控制器转
/// notice），不挂死。
class FilePickerShareFileExchange implements CharacterFileExchange {
  /// [pickJsonBytes] 缺省用 file_picker（选单个 .json 读字节）；
  /// [resolveTempDirectory] 缺省 path_provider；[shareFile] 缺省 share_plus
  /// 分享面板；[platformTimeout] 全部平台调用点的超时兜底（缺省 3s）。
  FilePickerShareFileExchange({
    PickJsonBytes? pickJsonBytes,
    ResolveTempDirectory? resolveTempDirectory,
    ShareFile? shareFile,
    this.platformTimeout = const Duration(seconds: 3),
  })  : _pickJsonBytes = pickJsonBytes ?? _pickSingleJson,
        _resolveTempDirectory = resolveTempDirectory ?? getTemporaryDirectory,
        _shareFile = shareFile ?? _shareViaPlus;

  final PickJsonBytes _pickJsonBytes;
  final ResolveTempDirectory _resolveTempDirectory;
  final ShareFile _shareFile;

  /// 平台调用点超时兜底时长（欠省 3s；测试注入短时长断言防御存在）。
  final Duration platformTimeout;

  @override
  Future<CharacterDraft?> importCharacter() async {
    Uint8List? bytes;
    try {
      bytes = await _pickJsonBytes().timeout(platformTimeout);
    } on TimeoutException {
      return null; // 挂起不抛错 → 超时降级为未选择（不挂死）。
    }
    if (bytes == null) {
      return null; // 用户取消。
    }
    return parseCharacterCardBytes(bytes);
  }

  @override
  Future<String> exportCharacter(Character character) async {
    final safeName = '${safeFileName(character.name)}.json';
    final card = jsonEncode(toV2Card(character));

    final Directory tempDir;
    try {
      tempDir = await _resolveTempDirectory().timeout(platformTimeout);
    } on TimeoutException {
      throw StateError('获取临时目录超时');
    }

    final file = File('${tempDir.path}${Platform.pathSeparator}$safeName');
    await file.writeAsString(card, flush: true);

    try {
      await _shareFile(file, safeName).timeout(platformTimeout);
    } on TimeoutException {
      throw StateError('分享面板超时');
    }
    return '已导出 $safeName（分享面板已打开）';
  }
}

/// 角色卡文件字节（UTF-8 `.json`）→ 解析归一化 [CharacterDraft]。
///
/// 文件内容非合法 UTF-8 / JSON → 抛 [CardFormatException]（「无法识别的
/// 角色卡格式」含引导）；结构合法后交 [fromV2Card] 做四格式识别（其抛错
/// 语义原样传播）。
CharacterDraft parseCharacterCardBytes(Uint8List bytes) {
  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const CardFormatException('无法识别的角色卡格式（文件不是合法的 UTF-8 文本）');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const CardFormatException('无法识别的角色卡格式（文件不是合法的 JSON）');
  }
  return fromV2Card(decoded);
}

/// 顶层纯函数：文件名安全净化（验收 6）。
///
/// Windows 非法文件名字符（`\ / : * ? " < > |`）及控制字符（码点 < 0x20）
/// 替换为 `_`；首尾空白与点剔除（防 `..` 段穿越与隐藏文件形态，对齐桌面
/// `sanitize_filename` 首尾点收敛）；超 100 字符截断（对齐角色名上限，
/// Windows 文件名组件上限 255 UTF-16 码元）；空结果回退 `character`。
/// 输出安全可作为 `{safeName}.json` 前缀使用（无路径分隔符，杜绝穿越）。
String safeFileName(String rawName) {
  final replaced = rawName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
  final trimmed = replaced.trim().replaceAll(RegExp(r'^\.+|\.+$'), '');
  if (trimmed.isEmpty) {
    return 'character';
  }
  final truncated =
      trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed;
  final result = truncated.trim().replaceAll(RegExp(r'^\.+|\.+$'), '');
  return result.isEmpty ? 'character' : result;
}

/// 缺省 pick：file_picker 选单个 `.json` 并读取字节（用户取消 → null）。
///
/// `FilePicker.pickFile`（12.x）本身即单文件语义（返回 `PlatformFile?`），
/// 配合 `FileType.custom + allowedExtensions: ['json']` 过滤扩展名。
Future<Uint8List?> _pickSingleJson() async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  return picked?.readAsBytes();
}

/// 缺省 share：share_plus 分享单文件面板。
Future<void> _shareViaPlus(File file, String fileName) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, name: fileName)],
      subject: fileName,
      text: fileName,
    ),
  );
}