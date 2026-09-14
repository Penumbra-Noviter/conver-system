import 'package:conver_system_mobile/app.dart';
import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/theme/colors.dart' show ConverColors;
import 'package:conver_system_mobile/view_models/shell_navigation.dart';
import 'package:conver_system_mobile/views/characters/characters_view.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:conver_system_mobile/views/chat/chat_view.dart';
import 'package:conver_system_mobile/views/search/search_view.dart';
import 'package:conver_system_mobile/views/settings/settings_view.dart';
import 'package:conver_system_mobile/views/simulators/simulators_view.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/in_memory_secret_store.dart';

/// [SettingsReader] 的内存假实现（ConversationRepository 装配用）。
class _FakeSettingsReader implements SettingsReader {
  const _FakeSettingsReader();

  @override
  Future<String> get defaultProvider async => '';

  @override
  Future<String> get defaultModel async => '';

  @override
  Future<String> get userName async => '';

  @override
  Future<Map<String, String>> get templateVars async => const {};
}

/// 预写 `onboarding_completed` 标记，使启动门直接进 [HomeShell]（工单 05）。
Future<void> _markOnboardingCompleted(AppDatabase db) =>
    SettingsRepository(database: db, secretStore: InMemorySecretStore())
        .setMany({'onboarding_completed': 'true'});

ShellNavigation _navigationOf(WidgetTester tester) =>
    tester.element(find.byType(NavigationBar)).read<ShellNavigation>();

Finder _navLabel(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _markOnboardingCompleted(db);
    await tester.pumpWidget(ConverApp(database: db));
    await tester.pumpAndSettle();
  }

  test('select 切换目的地经 notifyListeners 通知；重复选择不重复通知', () {
    final navigation = ShellNavigation();
    var notified = 0;
    navigation.addListener(() => notified++);

    navigation.select(ShellTab.chat); // 与默认值相同，不应通知
    expect(notified, 0);

    navigation.select(ShellTab.settings);
    expect(notified, 1);
    expect(navigation.current, ShellTab.settings);
    expect(navigation.index, ShellTab.settings.index);

    navigation.select(ShellTab.settings); // 重复选择，不应重复通知
    expect(notified, 1);
  });

  testWidgets('入口装配：显式深色主题生效且 5 个中文目的地渲染', (tester) async {
    await pumpApp(tester);

    // 主题锚点：ThemeMode.dark 显式注入后，brightness 与 Warm Stone 页面底色锁定。
    final theme = Theme.of(tester.element(find.byType(NavigationBar)));
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF171512));

    // 5 个目的地文案锚点均在底部导航渲染。
    expect(_navLabel('聊天'), findsOneWidget);
    expect(_navLabel('角色'), findsOneWidget);
    expect(_navLabel('搜索'), findsOneWidget);
    expect(_navLabel('模拟器'), findsOneWidget);
    expect(_navLabel('设置'), findsOneWidget);

    // 默认落在首个目的地：聊天。
    expect(_navigationOf(tester).current, ShellTab.chat);
    expect(find.byType(ChatView), findsOneWidget);
    expect(find.byType(CharactersView), findsNothing);
  });

  testWidgets('依次 tap 各目的地：选中态、provider 状态与 body 同步切换', (tester) async {
    await pumpApp(tester);

    final navigation = _navigationOf(tester);
    var notified = 0;
    navigation.addListener(() => notified++);

    // (底部导航文案锚点, 目的地枚举, body 视图类型)。
    final cases = <(String, ShellTab, Type)>[
      ('角色', ShellTab.characters, CharactersView),
      ('搜索', ShellTab.search, SearchView),
      ('模拟器', ShellTab.simulators, SimulatorsView),
      ('设置', ShellTab.settings, SettingsView),
      ('聊天', ShellTab.chat, ChatView),
    ];

    Type? previousView;
    for (final (label, tab, view) in cases) {
      await tester.tap(_navLabel(label));
      await tester.pumpAndSettle();

      // provider 状态与 UI 一致。
      expect(navigation.current, tab, reason: 'tap $label 后 provider 状态');
      expect(navigation.index, tab.index);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        tab.index,
        reason: 'tap $label 后导航选中态',
      );

      // body 切换到对应占位视图，且占位页含自身 tab 名文案（title 锚点）。
      expect(find.byType(view), findsOneWidget, reason: 'tap $label 后 body 切换');
      expect(
        find.descendant(of: find.byType(view), matching: find.text(label)),
        findsOneWidget,
      );
      if (previousView != null) {
        expect(find.byType(previousView), findsNothing);
      }
      previousView = view;
    }

    // 5 次切换均经 notifyListeners 路径驱动。
    expect(notified, cases.length);
  });

  group('搜索跳转定位 · onSelectResult → 切 chat + 打开目标会话 + 高亮（M3-04c）', () {
    /// 计数带琥珀底（ConverColors.accentSoft）的气泡容器数。
    int amberBubbleCount(WidgetTester tester) {
      var count = 0;
      for (final w in tester.widgetList<Container>(find.byType(Container))) {
        final deco = w.decoration;
        if (deco is BoxDecoration && deco.color == ConverColors.accentSoft) {
          count++;
        }
      }
      return count;
    }

    testWidgets('点击搜索结果 → 切 chat tab + 打开目标会话 + 命中气泡高亮（验收 6）',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime(2026, 8, 30, 12, 34);
      final char = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(
              name: '艾莉亚',
              firstMes: const Value(''),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final conv = await ConversationRepository(db, const _FakeSettingsReader())
          .createConversation(characterId: char.id, title: '夜话');
      final msg = await MessageRepository(db).createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '今晚的星空很美',
      );
      await _markOnboardingCompleted(db);
      await tester.pumpWidget(ConverApp(database: db));
      await tester.pumpAndSettle();

      // 任意 tab（当前默认 chat）→ 搜索 tab。
      await tester.tap(_navLabel('搜索'));
      await tester.pumpAndSettle();
      expect(_navigationOf(tester).current, ShellTab.search);

      // 输入关键词（>=2 字符）+ 防抖 300ms → 结果出现。
      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('共找到 1 条匹配消息'), findsOneWidget);

      // 点击结果 → 切 chat + 打开目标会话 + 高亮。
      await tester.tap(find.text('夜话'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(_navigationOf(tester).current, ShellTab.chat, reason: '切到聊天 tab');
      expect(find.byType(ChatView), findsOneWidget);
      final controller = Provider.of<ChatController>(
        tester.element(find.byType(ChatView)),
        listen: false,
      );
      expect(controller.activeConversationId, conv.id, reason: '打开目标会话');
      expect(controller.highlightMessageIds, {msg.id}, reason: '高亮目标消息');
      expect(amberBubbleCount(tester), 1, reason: '命中气泡琥珀高亮');
      await db.close();
    });

    testWidgets('重复点击同一结果幂等（验收 6）', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime(2026, 8, 30, 12, 34);
      final char = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(
              name: '艾莉亚',
              firstMes: const Value(''),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final conv = await ConversationRepository(db, const _FakeSettingsReader())
          .createConversation(characterId: char.id, title: '夜话');
      final msg = await MessageRepository(db).createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '今晚的星空很美',
      );
      await _markOnboardingCompleted(db);
      await tester.pumpWidget(ConverApp(database: db));
      await tester.pumpAndSettle();

      // 搜索 → 点击 → 落地。
      await tester.tap(_navLabel('搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.tap(find.text('夜话'));
      await tester.pumpAndSettle();
      expect(_navigationOf(tester).current, ShellTab.chat);

      // 返回搜索 → 再次点击同一结果：幂等（不崩溃、状态一致、仍高亮）。
      await tester.tap(_navLabel('搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.tap(find.text('夜话'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '重复点击不报错');
      expect(_navigationOf(tester).current, ShellTab.chat);
      final controller = Provider.of<ChatController>(
        tester.element(find.byType(ChatView)),
        listen: false,
      );
      expect(controller.activeConversationId, conv.id);
      expect(controller.highlightMessageIds, {msg.id}, reason: '再次高亮同一目标');
      expect(amberBubbleCount(tester), 1);
      await db.close();
    });
  });

  group('动效（M6-07 验收 2：tab 切换正文区 Fade）', () {
    testWidgets('正文区 AnimatedSwitcher 160ms（消费 token）+ 过渡为 Fade', (tester) async {
      await pumpApp(tester);

      final switcher = tester.widget<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher).first,
      );
      expect(switcher.duration, const Duration(milliseconds: 160),
          reason: 'tab 切换正文区 Fade 160ms（消费 ConverDurations.tabFade）');
      expect(switcher.transitionBuilder, isNotNull,
          reason: '过渡为 FadeTransition（淡入切换）');
      expect(
        find.byWidgetPredicate((w) => w is KeyedSubtree && w.key is ValueKey),
        findsWidgets,
        reason: '正文区子 child 以目的地为 ValueKey（切换触发器）',
      );
    });

    testWidgets('切 tab 不保活：往返重建视图（characters initState 重新挂载）', (tester) async {
      await pumpApp(tester);

      // 切到角色 tab（pumpAndSettle 完成过渡 → 旧 child 被移除）。
      await tester.tap(_navLabel('角色'));
      await tester.pumpAndSettle();
      expect(find.byType(CharactersView), findsOneWidget);

      // 切回聊天 → 切走角色：AnimatedSwitcher 不保活旧视图。
      await tester.tap(_navLabel('聊天'));
      await tester.pumpAndSettle();
      expect(find.byType(CharactersView), findsNothing,
          reason: '切走角色后旧视图被卸载（无 IndexedStack 保活）');
      expect(find.byType(ChatView), findsOneWidget);

      // 再次切回角色 → 视图重新挂载（「切回 tab 重新 initState」既有契约）。
      await tester.tap(_navLabel('角色'));
      await tester.pumpAndSettle();
      expect(find.byType(CharactersView), findsOneWidget,
          reason: '切回 tab 视图重建（自动刷新依赖重新 initState）');
    });

    // W5 审核 N1（F-2 修复）：reduce-motion（disableAnimations=true）下 tab
    // 切换直接替换、无 160ms 淡入——与 05 光标停闪的降级面一致。F-2 书 tabFade
    // = 160ms 是全库唯一 >140ms 动效，「无需降级」说理不再覆盖它。
    testWidgets('reduce-motion：无 AnimatedSwitcher 淡入，直接切换重建视图', (tester) async {
      // 经测试平台调度器注入系统减弱动效（MediaQuery.disableAnimations 的
      // 来源：MediaQueryData.fromView 读 platformDispatcher.accessibilityFeatures）。
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await pumpApp(tester);

      // 降级面：无 AnimatedSwitcher 淡入壳（直接切换，无 Fade 过渡）。
      expect(find.byType(AnimatedSwitcher), findsNothing,
          reason: 'reduce-motion 下无 AnimatedSwitcher 淡入（直接切换）');

      // 切 tab → 单帧即达目标视图（无 160ms 过渡窗口）。
      await tester.tap(_navLabel('角色'));
      await tester.pump();
      expect(_navigationOf(tester).current, ShellTab.characters,
          reason: 'reduce-motion 下切 tab 状态即时生效');
      expect(find.byType(CharactersView), findsOneWidget,
          reason: 'reduce-motion 下直接切换：目标视图立即挂载');
      expect(find.byType(ChatView), findsNothing,
          reason: 'reduce-motion 下旧视图立即卸载（无淡出并存窗口）');

      // drain：清掉切 tab 触发的异步刷新计时（与「切 tab 不保活」测试一致）。
      await tester.pumpAndSettle();
    });
  });
}
