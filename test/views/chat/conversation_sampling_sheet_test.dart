/// SP-02 对话级采样参数弹层契约（三态回显 + clamp 纯函数）。
///
/// 测试 seam（公共接口边界）：
/// - `ConversationSamplingSheet` 公开 widget（initial 回显 / 保存结果 /
///   取消 / 输入阻止）；
/// - `parseSamplingDouble` / `parseSamplingInt` 公开 clamp 纯函数（SR-24 值域
///   口径：UI 层 clamp + 服务层兜底双保险，本层只做输入限制与提示）。
///
/// 契约锁：保存结果 = 显式覆盖值 或 NULL（沿用全局/不覆盖 → null；覆盖 →
/// clamp 后数值）。落库侧断言在 chat_controller_test / chat_view_test
/// （controller / view 集成），本文件只锁弹层自身行为。
library;

import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/chat/conversation_sampling_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 挂载「打开弹层」按钮：点击经 showModalBottomSheet 弹出
/// [ConversationSamplingSheet]，关闭结果回传 [onResult]（与真实调用形态一致）。
class _SheetLauncher extends StatelessWidget {
  const _SheetLauncher({
    required this.initial,
    required this.onResult,
  });

  final ConversationSamplingInput initial;
  final ValueChanged<ConversationSamplingInput?> onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final result =
                await showModalBottomSheet<ConversationSamplingInput>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ConversationSamplingSheet(initial: initial),
            );
            onResult(result);
          },
          child: const Text('打开设置'),
        ),
      ),
    );
  }
}

Future<void> openSheet(
  WidgetTester tester,
  ConversationSamplingInput initial,
  ValueChanged<ConversationSamplingInput?> onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ConverTheme.dark(),
      home: _SheetLauncher(initial: initial, onResult: onResult),
    ),
  );
  await tester.tap(find.text('打开设置'));
  await tester.pumpAndSettle();
}

void main() {
  group('parseSamplingDouble · 值域 clamp/阻止（SR-24 口径）', () {
    test('合法值原样保留（边界含端点）', () {
      expect(parseSamplingDouble('0.5', min: 0, max: 1), 0.5);
      expect(parseSamplingDouble('0', min: 0, max: 1), 0.0);
      expect(parseSamplingDouble('1', min: 0, max: 1), 1.0);
      expect(parseSamplingDouble('-2', min: -2, max: 2), -2.0);
      expect(parseSamplingDouble('2', min: -2, max: 2), 2.0);
    });

    test('越界 clamp 到 [min, max]（对齐服务层 _guardSamplingRange）', () {
      expect(parseSamplingDouble('1.5', min: 0, max: 1), 1.0);
      expect(parseSamplingDouble('-0.5', min: 0, max: 1), 0.0);
      expect(parseSamplingDouble('3', min: -2, max: 2), 2.0);
      expect(parseSamplingDouble('-3', min: -2, max: 2), -2.0);
    });

    test('空串 / 空白 / 非数字 / NaN / ±Infinity → null（不覆盖）', () {
      expect(parseSamplingDouble(null, min: 0, max: 1), isNull);
      expect(parseSamplingDouble('', min: 0, max: 1), isNull);
      expect(parseSamplingDouble('   ', min: 0, max: 1), isNull);
      expect(parseSamplingDouble('abc', min: 0, max: 1), isNull);
      expect(parseSamplingDouble('1.2.3', min: 0, max: 1), isNull);
      expect(parseSamplingDouble('NaN', min: 0, max: 1), isNull);
      expect(parseSamplingDouble('Infinity', min: 0, max: 1), isNull);
      expect(parseSamplingDouble('-Infinity', min: 0, max: 1), isNull);
    });
  });

  group('parseSamplingInt · max_tokens ≥ 1', () {
    test('合法值原样；< 1 钳到 1；垃圾/空 → null', () {
      expect(parseSamplingInt('512'), 512);
      expect(parseSamplingInt('1'), 1);
      expect(parseSamplingInt('0'), 1);
      expect(parseSamplingInt('-3'), 1);
      expect(parseSamplingInt(''), isNull);
      expect(parseSamplingInt('abc'), isNull);
      expect(parseSamplingInt(null), isNull);
    });
  });

  group('ConversationSamplingSheet · 三态回显 + 保存/取消', () {
    const fieldKeys = [
      Key('sampling-field-top_p'),
      Key('sampling-field-presence_penalty'),
      Key('sampling-field-frequency_penalty'),
      Key('sampling-field-max_tokens'),
    ];

    const labels = ['top_p', 'presence_penalty', 'frequency_penalty', 'max_tokens'];

    TextField fieldOf(WidgetTester tester, Key key) =>
        tester.widget<TextField>(find.byKey(key));

    testWidgets('初始全 NULL → 四参数「沿用全局/默认」态，无数值输入；保存 → 全 null',
        (tester) async {
      ConversationSamplingInput? result;
      await openSheet(
        tester,
        const ConversationSamplingInput(),
        (r) => result = r,
      );

      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('沿用全局/默认'), findsNWidgets(4),
          reason: 'NULL → 沿用全局/默认态');
      for (final key in fieldKeys) {
        expect(find.byKey(key), findsNothing,
            reason: '未覆盖 → 不渲染数值输入');
      }

      await tester.tap(find.byKey(const Key('sampling-save')));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.topP, isNull);
      expect(result!.presencePenalty, isNull);
      expect(result!.frequencyPenalty, isNull);
      expect(result!.maxTokens, isNull);
    });

    testWidgets('初始覆盖值 → 开关开 + 数值回显（无「沿用全局」态）', (tester) async {
      ConversationSamplingInput? result;
      await openSheet(
        tester,
        const ConversationSamplingInput(
          topP: 0.4,
          presencePenalty: -1.2,
          frequencyPenalty: 0.8,
          maxTokens: 512,
        ),
        (r) => result = r,
      );

      expect(find.text('沿用全局/默认'), findsNothing);
      expect(fieldOf(tester, const Key('sampling-field-top_p')).controller!.text,
          '0.4');
      expect(
        fieldOf(tester, const Key('sampling-field-presence_penalty'))
            .controller!
            .text,
        '-1.2',
      );
      expect(
        fieldOf(tester, const Key('sampling-field-frequency_penalty'))
            .controller!
            .text,
        '0.8',
      );
      expect(
        fieldOf(tester, const Key('sampling-field-max_tokens')).controller!.text,
        '512',
      );

      await tester.tap(find.byKey(const Key('sampling-save')));
      await tester.pumpAndSettle();
      expect(result!.topP, 0.4);
      expect(result!.presencePenalty, -1.2);
      expect(result!.frequencyPenalty, 0.8);
      expect(result!.maxTokens, 512);
    });

    testWidgets('开覆盖 + 越界输入 → 保存 clamp 到值域（其余参数不覆盖 → null）',
        (tester) async {
      ConversationSamplingInput? result;
      await openSheet(
        tester,
        const ConversationSamplingInput(),
        (r) => result = r,
      );

      await tester.tap(find.byKey(const Key('sampling-switch-presence_penalty')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('sampling-field-presence_penalty')),
        '3',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sampling-save')));
      await tester.pumpAndSettle();

      expect(result!.presencePenalty, 2.0,
          reason: '越界 3 → clamp 到上限 2');
      expect(result!.topP, isNull);
      expect(result!.frequencyPenalty, isNull);
      expect(result!.maxTokens, isNull);
    });

    testWidgets('max_tokens 输入 < 1 → 保存钳到 1', (tester) async {
      ConversationSamplingInput? result;
      await openSheet(
        tester,
        const ConversationSamplingInput(),
        (r) => result = r,
      );

      await tester.tap(find.byKey(const Key('sampling-switch-max_tokens')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('sampling-field-max_tokens')),
        '0',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sampling-save')));
      await tester.pumpAndSettle();

      expect(result!.maxTokens, 1, reason: '<1 钳到 1（对齐 SR-24 下限）');
      expect(result!.topP, isNull);
    });

    testWidgets('开关开但输入为空 → 保存为 null（防御性不覆盖，不崩溃）', (tester) async {
      ConversationSamplingInput? result;
      await openSheet(
        tester,
        const ConversationSamplingInput(),
        (r) => result = r,
      );

      await tester.tap(find.byKey(const Key('sampling-switch-top_p')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('sampling-save')));
      await tester.pumpAndSettle();

      expect(result!.topP, isNull);
      expect(result!.presencePenalty, isNull);
      expect(result!.frequencyPenalty, isNull);
      expect(result!.maxTokens, isNull);
    });

    testWidgets('输入框阻止非法字符（字母被过滤）', (tester) async {
      await openSheet(
        tester,
        const ConversationSamplingInput(),
        (_) {},
      );

      await tester.tap(find.byKey(const Key('sampling-switch-top_p')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('sampling-field-top_p')),
        'abc',
      );
      await tester.pump();

      expect(
        fieldOf(tester, const Key('sampling-field-top_p')).controller!.text,
        isEmpty,
        reason: '字母被 formatter 过滤（阻止非法输入）',
      );
    });

    testWidgets('取消 → null（零副作用，不产结果）', (tester) async {
      ConversationSamplingInput? result;
      var launcherResult = false;
      await openSheet(
        tester,
        const ConversationSamplingInput(topP: 0.2),
        (r) {
          launcherResult = true;
          result = r;
        },
      );

      await tester.tap(find.byKey(const Key('sampling-cancel')));
      await tester.pumpAndSettle();

      expect(launcherResult, isTrue);
      expect(result, isNull);
    });
  });
}