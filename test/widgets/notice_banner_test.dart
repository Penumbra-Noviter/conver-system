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

  group('动效（M6-07 验收 3 + W5 B1：出现/消失过渡 140ms 消费 token）', () {
    testWidgets('进出过渡内建于组件：AnimatedOpacity 140ms + notice 可空占位',
        (tester) async {
      await pumpNoticeBanner(tester, notice: '回复已中断', onDismiss: () {});

      // 组件自身内建过渡（AnimatedOpacity 驱动淡入淡出）。
      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('回复已中断'),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.duration, const Duration(milliseconds: 140),
          reason: '进出过渡 140ms（消费 ConverDurations.fast，非硬编码）');
      expect(opacity.opacity, 1.0,
          reason: 'notice 非空时完全可见（出现态）');

      // 完整 pump 后收敛为稳态、内容可见。
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('回复已中断'), findsOneWidget);

      // notice 置空 → 透明空占位（组件始终挂载，父级零改动）。
      await pumpNoticeBanner(tester, notice: null, onDismiss: () {});
      expect(find.byType(NoticeBanner), findsOneWidget,
          reason: 'notice 为 null 时组件仍挂载（空占位）');
      expect(find.text('回复已中断'), findsNothing, reason: '文案随 notice 清空消失');
    });

    testWidgets('关闭 → 出口过渡进行中旧提示仍在树中（Fade 渐隐）→ 过渡完成后卸载',
        (tester) async {
      // 宿主模拟真实父级契约：onDismiss 后 notice 置空（controller 语义）。
      final hostKey = GlobalKey<_NoticeBannerHostState>();
      await tester.pumpWidget(_NoticeBannerHost(key: hostKey));

      expect(find.text('回复已中断'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pump();
      // 过渡中（~70ms）：AnimatedOpacity 渐隐，旧提示仍在树中。
      await tester.pump(const Duration(milliseconds: 70));
      expect(find.text('回复已中断'), findsOneWidget,
          reason: '出口过渡进行中：旧提示仍在树中（非即时卸载）');
      final midOpacity = tester
          .widget<AnimatedOpacity>(find.ancestor(
            of: find.text('回复已中断'),
            matching: find.byType(AnimatedOpacity),
          ))
          .opacity;
      expect(midOpacity, lessThan(1.0),
          reason: '过渡中 Fade 渐隐：opacity < 1');
      expect(hostKey.currentState!.dismissed, 0,
          reason: '过渡未完成不派发 onDismiss');

      // 过渡完成（>140ms）：提示卸载 + onDismiss 派发。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(hostKey.currentState!.dismissed, 1,
          reason: '过渡完成后派发 onDismiss');
      expect(find.text('回复已中断'), findsNothing, reason: '过渡完成：提示卸载');
    });

    testWidgets('过渡窗口内 notice 被替换 → 陈旧回调不误清新 notice（Falsify）',
        (tester) async {
      final hostKey = GlobalKey<_NoticeBannerHostState>();
      await tester.pumpWidget(_NoticeBannerHost(key: hostKey));

      // 点关闭进入出口过渡（140ms 计时中）。
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));

      // 过渡窗口内父级把 notice 替换成新提示（陈旧回调不得清除它）。
      hostKey.currentState!.replaceNotice('已导出');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // 越过 140ms 计时
      await tester.pump();

      expect(hostKey.currentState!.dismissed, 0,
          reason: '陈旧关闭回调不得派发（notice 已非被关闭的那条）');
      expect(find.text('已导出'), findsOneWidget,
          reason: '新 notice 不被陈旧回调误清、正常呈现');
      expect(find.text('回复已中断'), findsNothing,
          reason: '旧文案随 notice 替换消失');
    });

    testWidgets('过渡窗口内同文案 notice 被替换 → 陈旧回调不误清新 notice'
        '（F-65④：notice 身份 seq，同文案新旧可区分）', (tester) async {
      final hostKey = GlobalKey<_NoticeBannerHostState>();
      await tester.pumpWidget(_NoticeBannerHost(key: hostKey));

      // 点关闭进入出口过渡（140ms 计时中）。
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));

      // 过渡窗口内父级把 notice 替换成**同文案**新提示（新一轮断流 arrive 同
      // 文案「回复已中断」；host 分配新身份 seq）。修复前文案相等守卫
      // （stillSame = 文本相等）误判 → 陈旧 dismiss 清新 notice。
      hostKey.currentState!.replaceNotice('回复已中断');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // 越过 140ms 计时
      await tester.pump();

      expect(hostKey.currentState!.dismissed, 0,
          reason: 'F-65④：陈旧关闭回调不得派发（同文案但 notice 身份不同）');
      expect(find.text('回复已中断'), findsOneWidget,
          reason: '同文案新 notice 不被陈旧回调误清、正常呈现');
    });

    testWidgets('陈旧 dismiss 与新 dismiss 竞态：同文案新 notice 在陈旧窗口过后'
        '仍可正常关闭（新 dismiss 不因陈旧在场被吞）', (tester) async {
      final hostKey = GlobalKey<_NoticeBannerHostState>();
      await tester.pumpWidget(_NoticeBannerHost(key: hostKey));

      // 关 A（id1）→ 陈旧过渡窗口中同文案新 notice B（id2）到达并渲染。
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      hostKey.currentState!.replaceNotice('回复已中断');
      await tester.pump(); // 新 notice 先渲染（生产：下一帧）再让陈旧 timer 越过。
      await tester.pump(const Duration(milliseconds: 100)); // 越过陈旧 140ms
      await tester.pump();
      expect(hostKey.currentState!.dismissed, 0,
          reason: '陈旧 dismiss（id1）不派发（id2 在场）');
      expect(find.text('回复已中断'), findsOneWidget, reason: 'B 呈现');

      // B 自己的关闭（id2==id2）仍正常派发——不因陈旧回调在场被吞。
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();
      expect(hostKey.currentState!.dismissed, 1,
          reason: '新 dismiss 正常派发（首错者胜语义不被陈旧回调破坏）');
      expect(find.text('回复已中断'), findsNothing, reason: 'B 正常关闭卸载');
    });
  });
}

/// 模拟父级渲染契约的状态宿主：持有 [notice]，[onDismiss] 将 notice 置空
/// （对齐 ChatController/CharactersController 的 dismissNotice 语义）。
class _NoticeBannerHost extends StatefulWidget {
  const _NoticeBannerHost({super.key});

  @override
  State<_NoticeBannerHost> createState() => _NoticeBannerHostState();
}

class _NoticeBannerHostState extends State<_NoticeBannerHost> {
  /// 当前 notice（模拟父级控制器状态）。
  String? _notice = '回复已中断';

  /// 当前 notice 的身份 seq（模拟 NoticeRunner 递增语义；F-65④）。
  int _noticeSeq = 1;

  /// 当前 notice 身份（null = 无 notice）。
  int? _noticeId = 1;

  /// onDismiss 派发计数（出口过渡完成后触发）。
  int dismissed = 0;

  /// 父级把 notice 替换为 [next]（模拟过渡窗口内 arrive 新提示）：分配新身份
  /// seq——同文案重现值也可区分（对齐 NoticeRunner.set）。
  void replaceNotice(String next) => setState(() {
        _notice = next;
        _noticeId = ++_noticeSeq;
      });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ConverTheme.dark(),
      home: Scaffold(
        body: NoticeBanner(
          notice: _notice,
          noticeId: _noticeId,
          onDismiss: () => setState(() {
            dismissed++;
            _notice = null; // 父级清空 notice → 组件转空占位。
            _noticeId = null;
          }),
        ),
      ),
    );
  }
}