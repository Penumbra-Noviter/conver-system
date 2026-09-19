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

/// 伴侣域时间窗口常量集 — 协议表面 = [activeWindow] / [localDayOf] /
/// [isSameLocalDay] 三个符号（深模块）。
abstract final class CompanionTimeWindows {
  /// 近 7 天活跃窗口长度（判定⑨：最近消息 createdAt 距今 ≤ 7d 视为活跃）。
  ///
  /// 边界：`最近活跃时间 >= now − 7d` 允许、`< now − 7d` 拒绝；恰 7 天
  /// 允许。为伴侣域**唯一**定义点（F-91），proactive 与 relationship 两
  /// 侧服务经各自常量符号引用本值。
  static const Duration activeWindow = Duration(days: 7);

  /// 本地日历日归一化（F-129：日历日口径伴侣域唯一定义点）。
  ///
  /// 截断时间部分返回同年/月/日零时零点——「本地日期」身份（[DateTime] 本地
  /// 时区口径）。proactive（同日比较）与 relationship（distinct 日计数）两
  /// 侧服务统一经本函数取日历日，消除各自实现的口径漂移。
  static DateTime localDayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  /// 两个时刻是否属于同一本地日历日（[localDayOf] 相等判定）。
  static bool isSameLocalDay(DateTime a, DateTime b) =>
      localDayOf(a) == localDayOf(b);
}
