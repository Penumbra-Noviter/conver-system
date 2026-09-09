/// 文件名安全净化纯函数（与平台无关）。
///
/// 由平台文件交换 seam（M3-03）迁出（2026-09-07 架构深化）——纯函数归纯处，
/// 平台薄层不再夹带；消费方：角色卡导出 / 对话导出 / 平台 seam 共用。
///
/// C3 架构审查（2026-09-10）：双文件名净化器（对话导出锚 [safeFileName] /
/// 存档导出锚 `sanitizeFilename`）合并为参数化单核心 [safeFileNameCore] +
/// 各自声明配置的薄包装——核心不复刻双路径逻辑，两薄包装不内联重复逻辑。
/// 双锚逐字符行为由对照矩阵测试锁定（`test/services/file_name_test.dart`）。
library;

/// 首尾修剪规则（双锚现状语义的分叉点）。
enum FileNameEdgeTrim {
  /// 不修剪（仅做非法字符替换；供核心直接调用方 / 测试显式声明）。
  none,

  /// 首尾 Unicode 空白 + 首尾点剔除（导出锚 [safeFileName] 现状语义：
  /// `.trim()` 后剔除 `^\.+|\.+$`）。
  whitespaceAndDotsBothEdges,

  /// 仅剔除尾部连续点与空格（存档锚 `sanitizeFilename` 现状语义：
  /// `[. ]+$`——保留前导点与空白）。
  trailingDotsAndSpaces,
}

/// 参数化文件名净化核心的行为配置（两薄包装各自声明，默认值仅作「无行为」
/// 基线——差异字段必须显式命名，防默认值误改导出文件名）。
class FileNameSanitizerConfig {
  const FileNameSanitizerConfig({
    this.extraChars = '',
    this.edgeTrim = FileNameEdgeTrim.none,
    this.maxLength,
    this.trimAfterTruncate = false,
    this.fallback = 'character',
  });

  /// 附加非法字符（以**字面字符**追加进核心基础字符集
  /// `<>:"/\\|?*\x00-\x1f`，不支持正则 / 区间；存档锚声明 `\x7f%`）。
  final String extraChars;

  /// 首尾修剪规则。
  final FileNameEdgeTrim edgeTrim;

  /// 截断上限（字符数）；null = 不截断。导出锚 100，存档锚 null。
  final int? maxLength;

  /// 截断后是否二次修剪（导出锚「截断后二次修剪」逐字；存档锚 false）。
  final bool trimAfterTruncate;

  /// 空结果兜底（导出锚 `character`，存档锚 `game`；非 String 输入同样
  /// 短路回退此值）。
  final String fallback;
}

/// 核心基础非法字符集（两锚共用：Windows 非法文件名字符 + 控制字符 <0x20）。
final RegExp _illegalBase = RegExp(r'[<>:"/\\|?*\x00-\x1f]');

/// 首尾点剔除（导出锚修剪步骤：`trim()` 后剔 `^\.+|\.+$`）。
final RegExp _edgeDots = RegExp(r'^\.+|\.+$');

/// 尾部连续点与空格剔除（存档锚修剪步骤：`[. ]+$`）。
final RegExp _trailingDotSpace = RegExp(r'[. ]+$');

/// 按 [mode] 应用首尾修剪。
///
/// 两锚修剪算法本身不同（导出锚先 Unicode 空白修剪再剔首尾点、且截断后
/// 二次修剪会遗留尾部空格；存档锚单次整段剔尾点空格），故不可合并为同一步
/// ——由 [FileNameSanitizerConfig.edgeTrim] 显式声明分支。
String _applyEdgeTrim(String input, FileNameEdgeTrim mode) {
  switch (mode) {
    case FileNameEdgeTrim.none:
      return input;
    case FileNameEdgeTrim.whitespaceAndDotsBothEdges:
      return input.trim().replaceAll(_edgeDots, '');
    case FileNameEdgeTrim.trailingDotsAndSpaces:
      return input.replaceAll(_trailingDotSpace, '');
  }
}

/// 参数化文件名净化核心（C3 双锚合并，2026-09-10）。
///
/// 单条净化流水线，行为由 [config] 声明：
/// 1. 非 String 输入 → 直接返回 [FileNameSanitizerConfig.fallback]（存档锚
///    「非 String → game」逐字；导出锚签名收窄为 String，此分支不可达）；
/// 2. 非法字符替换：基础字符集恒定，外加 [FileNameSanitizerConfig.extraChars]
///    字面字符 → `_`；
/// 3. 按 [FileNameSanitizerConfig.edgeTrim] 修剪；
/// 4. 空结果 → 兜底；
/// 5. [FileNameSanitizerConfig.maxLength] 非空则截断；
/// 6. [FileNameSanitizerConfig.trimAfterTruncate] 为真则截断后二次修剪
///    （导出锚逐字）；
/// 7. 二次空结果 → 兜底。
///
/// 两薄包装 [safeFileName]（导出锚）与 `sanitizeFilename`（存档锚）各自声明
/// 配置委托本核心——双锚行为逐字符保持（对照矩阵测试锁定）。
String safeFileNameCore(Object? name, {required FileNameSanitizerConfig config}) {
  if (name is! String) return config.fallback;
  var result = name.replaceAll(_illegalBase, '_');
  for (final int codeUnit in config.extraChars.codeUnits) {
    result = result.replaceAll(String.fromCharCode(codeUnit), '_');
  }
  result = _applyEdgeTrim(result, config.edgeTrim);
  if (result.isEmpty) return config.fallback;
  final int? maxLength = config.maxLength;
  if (maxLength != null && result.length > maxLength) {
    result = result.substring(0, maxLength);
  }
  if (config.trimAfterTruncate) {
    result = _applyEdgeTrim(result, config.edgeTrim);
  }
  return result.isEmpty ? config.fallback : result;
}

/// 顶层纯函数：文件名安全净化（验收 6）——导出锚薄包装。
///
/// Windows 非法文件名字符（`\ / : * ? " < > |`）及控制字符（码点 < 0x20）
/// 替换为 `_`；首尾空白与点剔除（防 `..` 段穿越与隐藏文件形态，对齐桌面
/// `sanitize_filename` 首尾点收敛）；超 100 字符截断（对齐角色名上限，
/// Windows 文件名组件上限 255 UTF-16 码元）；截断后二次修剪；空结果回退
/// `character`。输出安全可作为 `{safeName}.json` 前缀使用（无路径分隔符，
/// 杜绝穿越）。行为委托 [safeFileNameCore]，此处仅声明导出锚配置
/// （对照矩阵锁定逐字符不变）。
String safeFileName(String rawName) {
  return safeFileNameCore(
    rawName,
    config: const FileNameSanitizerConfig(
      edgeTrim: FileNameEdgeTrim.whitespaceAndDotsBothEdges,
      maxLength: 100,
      trimAfterTruncate: true,
      fallback: 'character',
    ),
  );
}
