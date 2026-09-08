import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/settings_repository.dart';
import '../services/secure_store.dart';
import '../theme/motion.dart';
import '../view_models/shell_navigation.dart';
import '../view_models/simulators_controller.dart';
import '../view_models/theme_controller.dart';
import 'chat/chat_controller.dart';
import 'chat/chat_view.dart';
import 'characters/characters_controller.dart';
import 'characters/characters_view.dart';
import 'search/search_view.dart';
import 'settings/settings_view.dart';
import 'simulators/simulators_view.dart';

/// 应用主壳：底部导航 5 tab（设计文档 §6 信息架构）+ 正文区按当前目的地切换。
///
/// 当前目的地由 [ShellNavigation]（provider 注入）持有；选中态视觉走
/// T02 的 NavigationBarTheme（琥珀 accent 指示器与图标文字色）。
/// 设置页自 M1-T07 起注入应用级共享实例（同一 ThemeController 使主题
/// 切换端到端生效于 MaterialApp；同一 SettingsRepository 统一数据层）。
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final navigation = context.watch<ShellNavigation>();
    final body = switch (navigation.current) {
      ShellTab.chat => ChatView(
          controller: context.read<ChatController>(),
        ),
      ShellTab.characters => CharactersView(
          controller: context.read<CharactersController>(),
        ),
      // M3-04c：搜索点击 → 切聊天 tab + 打开目标会话并定位高亮（桌面
      // navigateToConversation(conversationId, { messageId }) 语义）。
      ShellTab.search => SearchView(
          onSelectResult: (conversationId, messageId) {
            context.read<ShellNavigation>().select(ShellTab.chat);
            unawaited(context
                .read<ChatController>()
                .openConversation(conversationId, highlightMessageId: messageId));
          },
        ),
      // M5-03：模拟器 tab 接真实列表页（懒启动编排见 SimulatorsController；
      // 服务器 App 存续期常驻，不随 tab 往返销毁）。
      ShellTab.simulators => SimulatorsView(
          controller: context.read<SimulatorsController>(),
        ),
      ShellTab.settings => SettingsView(
          settingsRepository: context.read<SettingsRepository>(),
          themeController: context.read<ThemeController>(),
          secretStore: context.read<SecretStore>(),
        ),
    };
    return Scaffold(
      body: AnimatedSwitcher(
        // M6-07 克制动效 ①：tab 切换正文区 Fade 160ms（消费 ConverDurations
        // token）。子 child 以目的地为 ValueKey——切换即替换重建视图，
        // 「切回 tab 重新 initState」既有契约不被保活破坏（无 IndexedStack）。
        duration: ConverDurations.tabFade,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: KeyedSubtree(
          key: ValueKey(navigation.current),
          child: body,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigation.index,
        onDestinationSelected: (index) {
          context.read<ShellNavigation>().select(ShellTab.values[index]);
        },
        destinations: [
          for (final tab in ShellTab.values)
            NavigationDestination(icon: Icon(_iconFor(tab)), label: tab.label),
        ],
      ),
    );
  }

  /// 克制线性图标语义（§5.2：禁 emoji 图标，统一线性图标）。
  static IconData _iconFor(ShellTab tab) => switch (tab) {
        ShellTab.chat => Icons.chat_bubble_outline,
        ShellTab.characters => Icons.person_outline,
        ShellTab.search => Icons.search,
        ShellTab.simulators => Icons.sports_esports_outlined,
        ShellTab.settings => Icons.settings_outlined,
      };
}
