/// 文件名安全净化纯函数（与平台无关）。
///
/// 由平台文件交换 seam（M3-03）迁出（2026-09-07 架构深化）——纯函数归纯处，
/// 平台薄层不再夹带；消费方：角色卡导出 / 对话导出 / 平台 seam 共用。
library;

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
  final truncated = trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed;
  final result = truncated.trim().replaceAll(RegExp(r'^\.+|\.+$'), '');
  return result.isEmpty ? 'character' : result;
}
