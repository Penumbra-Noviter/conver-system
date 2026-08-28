import 'package:flutter/material.dart';

import '../../widgets/placeholder_group.dart';

/// 模拟器占位视图（M5 接入模拟器运行时后由真实页面替换，ADR-0002）。
class SimulatorsView extends StatelessWidget {
  const SimulatorsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderGroup(
      title: '模拟器',
      description: '交互式模拟器将在这里运行。',
      items: [
        PlaceholderItem('模拟器列表', '已配置的模拟器一览'),
        PlaceholderItem('运行方式', '内嵌 WebView · 隔离运行时'),
      ],
    );
  }
}
