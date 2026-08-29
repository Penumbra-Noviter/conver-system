// F-11 ConverPalette 安全访问 helper（of / maybeOf）契约测试。
//
// 契约（spec §T2 + T2.md 验收标准）：
// - of(context)：未注册抛描述性 FlutterError（消息含「未注册」与
//   ConverTheme/MaterialApp（ConverApp）装配指引）；已注册返回与
//   `Theme.of(context).extension<ConverPalette>()` 相同的实例。
// - maybeOf(context)：未注册返回 null、不抛；已注册返回实例。
library;

import 'package:conver_system_mobile/theme/conver_palette.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 默认 MaterialApp（ThemeData() 无 extensions）→ ConverPalette 未注册。
  Future<void> pumpUnregistered(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: const Text('probe')),
    );
  }

  // 经 [ConverTheme] 装配 ConverPalette 的 MaterialApp → 已注册。
  Future<void> pumpRegistered(
    WidgetTester tester, {
    required ThemeData theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(theme: theme, home: const Text('probe')),
    );
  }

  // 取 home widget（唯一 'probe' 文本）所在 BuildContext——位于 MaterialApp
  // 之下，Theme 已装配。
  BuildContext ctx(WidgetTester tester) => tester.element(find.text('probe'));

  group('ConverPalette.of（F-11 安全访问）', () {
    testWidgets('未注册：抛 FlutterError 且消息含「未注册」', (tester) async {
      await pumpUnregistered(tester);
      expect(
        () => ConverPalette.of(ctx(tester)),
        throwsA(
          isA<FlutterError>().having(
            (e) => e.message,
            'message',
            contains('未注册'),
          ),
        ),
      );
    });

    testWidgets('未注册：错误消息含装配指引（ConverTheme / MaterialApp / ConverApp）', (tester) async {
      await pumpUnregistered(tester);
      expect(
        () => ConverPalette.of(ctx(tester)),
        throwsA(
          isA<FlutterError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('ConverTheme'),
              contains('MaterialApp'),
              contains('ConverApp'),
            ),
          ),
        ),
      );
    });

    testWidgets('已注册：返回与 extension<ConverPalette>() 相同的实例', (tester) async {
      await pumpRegistered(tester, theme: ConverTheme.dark());
      final viaOf = ConverPalette.of(ctx(tester));
      final viaExtension = Theme.of(ctx(tester)).extension<ConverPalette>();
      expect(viaOf, same(viaExtension));
    });

    testWidgets('已注册：返回 token 值与深色板逐字一致', (tester) async {
      await pumpRegistered(tester, theme: ConverTheme.dark());
      final palette = ConverPalette.of(ctx(tester));
      expect(palette.ink1, ConverPalette.dark().ink1);
      expect(palette.ink2, ConverPalette.dark().ink2);
      expect(palette.ink3, ConverPalette.dark().ink3);
      expect(palette.ink4, ConverPalette.dark().ink4);
      expect(palette.border, ConverPalette.dark().border);
    });
  });

  group('ConverPalette.maybeOf（可空路径）', () {
    testWidgets('未注册：返回 null、不抛', (tester) async {
      await pumpUnregistered(tester);
      expect(ConverPalette.maybeOf(ctx(tester)), isNull);
    });

    testWidgets('已注册：返回与 extension<ConverPalette>() 相同的实例', (tester) async {
      await pumpRegistered(tester, theme: ConverTheme.light());
      final maybe = ConverPalette.maybeOf(ctx(tester));
      expect(maybe, isNotNull);
      expect(maybe, same(Theme.of(ctx(tester)).extension<ConverPalette>()));
    });
  });
}
