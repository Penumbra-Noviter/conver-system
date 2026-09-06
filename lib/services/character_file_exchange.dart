/// 角色文件导入/导出的平台通道 seam（M3-01 定义接口 + Stub 壳；M3-03 追加
/// 真实现 [FilePickerShareFileExchange]；2026-09-07 架构深化：平台腿与
/// [safeFileName] 迁出至 `platform_file_exchange.dart` / `file_name.dart`）。
///
/// 通道契约（M3-01 工件）：
/// - 视图层/控制器不直接触碰 file_picker / share_plus / path_provider——
///   全部平台调用收口在本接口的实现之后；
/// - [CharacterFileExchangeStub] 为占位壳：导出按钮经此调用并展示
///   「随后续批次交付」提示，**永不触真平台通道**（测试注入 fake seam
///   断言调用链）；
/// - 实现约定：导出产物文件名由实现方以 `{safeName}.json` 构造（文件名
///   安全净化纯函数 [safeFileName] 定义于 `file_name.dart`），返回值为用户
///   可读文案；平台超时兜底（`.timeout` + 降级）收敛于共享平台腿。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../data/database/app_database.dart' show Character;
import 'character_card.dart';
import 'file_name.dart' show safeFileName;
import 'platform_file_exchange.dart';

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

/// 真实现：file_picker 选单个 `.json` → 临时目录写入 → share_plus 分享。
///
/// 构造注入 [PickJsonBytes] / [ResolveTempDirectory] / [ShareFile] 类型化
/// fake（测试永不触真平台通道）+ [platformTimeout]（缺省 3s）。平台腿
/// （超时兜底 + 降级语义）收敛于 `platform_file_exchange.dart`：pick 挂起 →
/// 降级为未选择（null）；临时目录 / 分享挂起 → 降级抛 [StateError]（控制器
/// 转 notice），不挂死。
class FilePickerShareFileExchange implements CharacterFileExchange {
  /// [pickJsonBytes] 缺省用 file_picker（选单个 .json 读字节）；
  /// [resolveTempDirectory] 缺省 path_provider；[shareFile] 缺省 share_plus
  /// 分享面板；[platformTimeout] 全部平台调用点的超时兜底（缺省 3s）。
  FilePickerShareFileExchange({
    PickJsonBytes? pickJsonBytes,
    ResolveTempDirectory? resolveTempDirectory,
    ShareFile? shareFile,
    this.platformTimeout = const Duration(seconds: 3),
  })  : _pickJsonBytes = pickJsonBytes ?? defaultPickJsonFile,
        _resolveTempDirectory =
            resolveTempDirectory ?? defaultResolveTempDirectory,
        _shareFile = shareFile ?? defaultShareViaPlus;

  final PickJsonBytes _pickJsonBytes;
  final ResolveTempDirectory _resolveTempDirectory;
  final ShareFile _shareFile;

  /// 平台调用点超时兜底时长（缺省 3s；测试注入短时长断言防御存在）。
  final Duration platformTimeout;

  @override
  Future<CharacterDraft?> importCharacter() async {
    final bytes = await pickJsonWithTimeout(
      pickJsonBytes: _pickJsonBytes,
      platformTimeout: platformTimeout,
    );
    if (bytes == null) {
      return null; // 用户取消或超时降级为未选择（不挂死）。
    }
    return parseCharacterCardBytes(bytes);
  }

  @override
  Future<String> exportCharacter(Character character) async {
    final safeName = '${safeFileName(character.name)}.json';
    final card = jsonEncode(toV2Card(character));
    return writeTempAndShare(
      fileName: safeName,
      content: card,
      resolveTempDirectory: _resolveTempDirectory,
      shareFile: _shareFile,
      platformTimeout: platformTimeout,
    );
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
