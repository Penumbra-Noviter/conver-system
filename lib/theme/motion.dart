/// 动效时长 token（M6-07）——克制动效的单一时间来源。
///
/// 语义锚点（spec §4.1 + 共识 §2 面1 1.3）：
/// - [fast] / [mid] / [slow] 三档**逐字对齐桌面**样式表
///   `desktop/frontend/css/style.css :root` 的 `--transition-fast:0.14s` /
///   `--transition:0.22s` / `--transition-slow:0.3s ease-out`；
/// - [tabFade] 为 tab 切换正文区淡入的专用档（共识 TP-1 ①「tab 切换 Fade
///   160ms」）——独立命名、不改变三档与桌面的逐字对齐契约；
/// - 消费契约（settle）：新建动效一律消费本 token 集，禁止硬编码时长字面量。
library;

/// Warm Stone 动效时长三档 + tab 切换专用档（克制子集的时间归属）。
abstract final class ConverDurations {
  /// 快档（桌面 `--transition-fast` 逐字）。
  static const Duration fast = Duration(milliseconds: 140);

  /// 中档（桌面 `--transition` 逐字）。
  static const Duration mid = Duration(milliseconds: 220);

  /// 慢档（桌面 `--transition-slow` 逐字）。
  static const Duration slow = Duration(milliseconds: 300);

  /// tab 切换正文区淡入档（共识 TP-1 ①，160ms）。
  static const Duration tabFade = Duration(milliseconds: 160);
}
