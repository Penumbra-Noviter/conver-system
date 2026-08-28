import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme/conver_theme.dart';
import 'view_models/shell_navigation.dart';
import 'views/home_shell.dart';

/// 应用根组件（入口层）：provider 装配 + MaterialApp 主题注入。
///
/// 主题经显式 [ThemeMode.dark] 注入，不跟随系统深浅色切换，保证 M0
/// 视觉基线（Warm Stone 深色）始终生效；导航状态在入口装配，全局可读。
class ConverApp extends StatelessWidget {
  const ConverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ShellNavigation()),
      ],
      child: MaterialApp(
        title: '汇流',
        theme: ConverTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const HomeShell(),
      ),
    );
  }
}
