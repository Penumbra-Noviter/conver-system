/// 伴侣域时间窗口常量 — 单一事实来源（F-91 技术债消费）。
///
/// 归属声明：近 7 天活跃窗口（activeWindow）的定义只允许存在于本模块，
/// 由 [ProactiveThresholds.activeWindow]（主动消息节流）与
/// [RelationshipThresholds.recentWindow]（关系状态机启发式）两侧共同引用。
/// 修改窗口长度只需改本文件一处，两处判定同步生效。
///
/// 边界语义（两侧判定统一锚）：`最近活跃时间 >= now − 7d` 判定为「近 7 天
/// 活跃」（允许）；`最近活跃时间 < now − 7d` 判定为「滑出窗口」（拒绝）。
/// 恰 7 天（`最近活跃时间 == now − 7d`）属于允许侧。
library;

/// 伴侣域时间窗口常量集 — 协议表面 = [activeWindow] 一个符号（深模块）。
abstract final class CompanionTimeWindows {
  /// 近 7 天活跃窗口长度（判定⑨：最近消息 createdAt 距今 ≤ 7d 视为活跃）。
  ///
  /// 边界：`最近活跃时间 >= now − 7d` 允许、`< now − 7d` 拒绝；恰 7 天
  /// 允许。为伴侣域**唯一**定义点（F-91），proactive 与 relationship 两
  /// 侧服务经各自常量符号引用本值。
  static const Duration activeWindow = Duration(days: 7);
}
