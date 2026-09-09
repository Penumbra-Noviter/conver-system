/// 占位条目的数据载体：单行 label + note。
///
/// 原占位骨架组件类已随架构审查 C4 删除（M0 五个空壳占位页全部由真实页面
/// 取代，类全库零实例化为死代码并移除）；本文件现仅承载 `PlaceholderItem`，
/// 继续作为设置页「对话」「模板变量」两占位行（锚共识 D1）的数据载体。
class PlaceholderItem {
  const PlaceholderItem(this.label, this.note);

  /// 条目名（占位行左侧文案，测试锚点）。
  final String label;

  /// 状态备注（占位行右侧说明）。
  final String note;
}