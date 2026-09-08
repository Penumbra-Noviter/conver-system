/// NoticeBanner 共享组件契约（M6-02）——T3 流式级非阻塞提示条（notice 文案 +
/// 关闭按钮 + 预留动作槽）。
///
/// 验收语义（工单 02 验收 1/4 + spec §4.3 + 共识 §3.3）：
/// - notice 文案 bodyMedium ink2，表面 surfaceContainerHigh 底；关闭按钮
///   tooltip「关闭提示」（与 chat/characters 两处既有私有拷贝逐字一致）；
/// - onDismiss 关闭回调点击派发；
/// - 可选动作参数（actionLabel / onAction）本票仅定义契约、不接业务：两者齐备
///   时渲染动作按钮并派发 onAction，任一为 null 不渲染动作区（零行为）；
/// - 边界防御：空 notice / 超长 notice 不崩（Falsify）。
///
/// 测试 seam（公共接口边界）：[NoticeBanner] 公开构造参数（notice /
/// onDismiss / actionLabel / onAction），经 ConverTheme.dark
/// （ConverPalette 注册）装配。
library;

import 'package:conver_system_mobile/theme/conver_palette.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/widgets/notice_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpNoticeBanner(
    WidgetTester tester, {
    String? notice,
    required VoidCallback onDismiss,
    String? actionLabel,
    VoidCallback? onAction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(
          body: NoticeBanner(
            notice: notice,
            onDismiss: onDismiss,
            actionLabel: actionLabel,
            onAction: onAction,
          ),
        ),
      ),
    );
  }

  group('渲染与关闭（验收 1）', () {
    testWidgets('notice 文案 ink2 + 关闭按钮 tooltip 可用且点击派发', (tester) async {
      var dismissed = 0;
      await pumpNoticeBanner(
        tester,
        notice: '回复已中断',
        onDismiss: () => dismissed++,
      );

      final text = tester.widget<Text>(find.text('回复已中断'));
      expect(text.style?.color, ConverPalette.dark().ink2, reason: 'notice ink2');

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('回复已中断'),
          matching: find.byType(Container),
        ),
      );
      expect(container.color, ConverTheme.dark().colorScheme.surfaceContainerHigh,
          reason: 'surfaceContainerHigh 底');

      expect(find.byTooltip('关闭提示'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭提示'));
      // W5 B1：onDismiss 在 140ms 出口过渡完成后触发（先淡出后卸载）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();
      expect(dismissed, 1, reason: '关闭回调在出口过渡完成后被派发');
    });
  });

  group('动作槽（验收 4：本票仅契约、不接线）', () {
    testWidgets('actionLabel / onAction 缺省 → 零动作区（既有关闭-only 形态）',
        (tester) async {
      await pumpNoticeBanner(
        tester,
        notice: '已导出',
        onDismiss: () {},
      );

      expect(find.text('已导出'), findsOneWidget);
      expect(find.byTooltip('关闭提示'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing, reason: '缺省不渲染动作区');
    });

    testWidgets('actionLabel / onAction 齐备 → 渲染动作按钮且点击派发；仅 label '
        '不渲染', (tester) async {
      var acted = 0;
      await pumpNoticeBanner(
        tester,
        notice: '回复已中断',
        onDismiss: () {},
        actionLabel: '重试',
        onAction: () => acted++,
      );

      await tester.tap(find.text('重试'));
      expect(acted, 1, reason: '动作回调被派发');

      // 仅 label 无回调 → 不渲染动作区（半接线态不产生可用按钮）。
      await pumpNoticeBanner(
        tester,
        notice: '回复已中断',
        onDismiss: () {},
        actionLabel: '重试',
      );
      expect(find.text('重试'), findsNothing, reason: '仅 actionLabel 不渲染');
    });
  });

  group('边界输入（Falsify）', () {
    testWidgets('空 notice / 超长 notice 不崩', (tester) async {
      await pumpNoticeBanner(tester, notice: '', onDismiss: () {});
      expect(tester.takeException(), isNull);

      await pumpNoticeBanner(tester, notice: '长' * 500, onDismiss: () {});
      expect(tester.takeException(), isNull);
      expect(find.byType(NoticeBanner), findsOneWidget);
    });
  });

  group('动效（M6-07 验收 3：挂载淡入 140ms 消费 token）', () {
    testWidgets('挂载时 TweenAnimationBuilder 淡入 + 时长 140ms', (tester) async {
      await pumpNoticeBanner(tester, notice: '回复已中断', onDismiss: () {});

      // 组件自身内建挂载淡入（TweenAnimationBuilder 驱动 Opacity）。
      final tween = tester.widget<TweenAnimationBuilder<double>>(
        find.byType(TweenAnimationBuilder<double>),
      );
      expect(tween.duration, const Duration(milliseconds: 140),
          reason: '出现过渡 140ms（消费 ConverDurations.fast，非硬编码）');
      expect(tween.tween, isA<Tween<double>>(),
          reason: '挂载淡入动画在组件自身（进出来自共享组件）');

      // 完整 pump 后 opacity 收敛为 1（动画结束、内容可见）。
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('回复已中断'), findsOneWidget);
    });
  });
}