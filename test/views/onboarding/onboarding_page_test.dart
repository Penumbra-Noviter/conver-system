/// OnboardingPage 呈现层行为契约（工单 05 / spec §U-4）。
///
/// seam 边界：只测 [OnboardingPage] 公开接口（`onFinished` 回调 + 渲染输出），
/// 不测内部状态。语义锚点：PageView 3–5 页、每页「跳过」、末页「开始使用」、
/// 「跳过」/「开始使用」触发 `onFinished`。
library;

import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/onboarding/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpOnboarding(
    WidgetTester tester, {
    Future<void> Function()? onFinished,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: OnboardingPage(onFinished: onFinished ?? () async {}),
      ),
    );
  }

  testWidgets('渲染 PageView 且页数在 3–5 之间', (tester) async {
    await pumpOnboarding(tester);

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(
      pageView.childrenDelegate.estimatedChildCount,
      isNotNull,
      reason: 'PageView 应以显式列表构造',
    );
    expect(
      pageView.childrenDelegate.estimatedChildCount,
      inInclusiveRange(3, 5),
    );
  });

  testWidgets('每页顶部有「跳过」（首屏即见，持久可见）', (tester) async {
    await pumpOnboarding(tester);

    expect(find.text('跳过'), findsOneWidget);
  });

  testWidgets('首屏无「开始使用」；末页「开始使用」出现', (tester) async {
    await pumpOnboarding(tester);

    // 首屏只有「下一步」，无「开始使用」。
    expect(find.text('开始使用'), findsNothing);
    expect(find.text('下一步'), findsOneWidget);

    // 逐页推进直到「开始使用」出现（页数 3–5，至多 4 次）。
    var reachedLast = false;
    for (var i = 0; i < 4 && !reachedLast; i++) {
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      reachedLast = find.text('开始使用').evaluate().isNotEmpty;
    }

    expect(reachedLast, isTrue, reason: '末页应出现「开始使用」');
    expect(find.text('开始使用'), findsOneWidget);
    expect(find.text('下一步'), findsNothing);
  });

  testWidgets('「跳过」触发 onFinished', (tester) async {
    var finished = 0;
    await pumpOnboarding(tester, onFinished: () async => finished++);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(finished, 1);
  });

  testWidgets('末页「开始使用」触发 onFinished', (tester) async {
    var finished = 0;
    await pumpOnboarding(tester, onFinished: () async => finished++);

    // 推进到末页。
    while (find.text('开始使用').evaluate().isEmpty) {
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('开始使用'));
    await tester.pumpAndSettle();

    expect(finished, 1);
  });
}
