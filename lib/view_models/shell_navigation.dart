import 'package:flutter/foundation.dart';

/// 底部导航的五个目的地（设计文档 §6 信息架构：设置独立 tab）。
enum ShellTab {
  chat('聊天'),
  characters('角色'),
  search('搜索'),
  simulators('模拟器'),
  settings('设置');

  const ShellTab(this.label);

  /// 底部导航标签与占位页标题共用的中文文案锚点。
  final String label;
}

/// HomeShell 的导航状态：持有当前目的地，供底部导航与后续深层页面复用。
///
/// M0 由 app 层经 provider 注入；tap 切换经 [notifyListeners] 路径驱动 UI 重建。
class ShellNavigation extends ChangeNotifier {
  ShellTab _current = ShellTab.chat;

  /// 当前目的地（默认落在首个 tab：聊天）。
  ShellTab get current => _current;

  /// 当前目的地索引（与 [ShellTab.values] 顺序一致）。
  int get index => _current.index;

  /// 切换到 [tab]；重复选择当前目的地时不重复通知。
  void select(ShellTab tab) {
    if (tab == _current) {
      return;
    }
    _current = tab;
    notifyListeners();
  }
}
