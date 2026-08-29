/// Warm Stone MarkdownStyleSheet 主题化契约（R4 结论就是本测试的规格）。
///
/// 锚：`.scratch/m2-kickoff/prototype/markdown-theme/README.md` 映射表 +
/// `test/markdown_theme_probe_test.dart`（断言模式复刻：无头跑、递归收集
/// RichText 叶子 TextSpan，逐 token 值比对）。
///
/// 被测 seam：`warmStoneMarkdownDark() / warmStoneMarkdownLight()` 两个顶层
/// 函数 + 消费真实 `ConverColors` / `ConverColorsLight` token。
library;

import 'package:conver_system_mobile/theme/chat_markdown_style.dart';
import 'package:conver_system_mobile/theme/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// 覆盖：标题 / 段落 / 加粗 / 斜体 / 行内 code / 链接 / 围栏代码块 /
/// 引用块 / 无序列表 / 删除线 / 分隔线。
const String _probeMd = '''
# h1-marker 一级标题

一段普通正文，包含 **bold-marker 加粗**、*em-marker 斜体*、~~del-marker 删除~~、`icode-marker 行内代码` 和 [link-marker 链接](https://example.com)。

> bq-marker 这是一段引用。

- bullet-marker 列表项一
- 列表项二

```dart
codeblock-marker
final tokens;
```

---

分隔线之后。
''';

/// 递归收集 RichText 叶子 TextSpan 的 (text, style)。
void _walk(InlineSpan span, Map<String, TextStyle> out) {
  if (span is TextSpan) {
    if (span.children == null || span.children!.isEmpty) {
      if (span.text != null && span.text!.isNotEmpty) {
        out[span.text!] = span.style ?? const TextStyle();
      }
    } else {
      for (final c in span.children!) {
        _walk(c, out);
      }
    }
  }
}

Map<String, TextStyle> _allTextStyles(WidgetTester tester) {
  final out = <String, TextStyle>{};
  for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
    _walk(rt.text, out);
  }
  for (final st in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
    if (st.textSpan != null) {
      _walk(st.textSpan!, out);
    }
  }
  return out;
}

/// BoxDecoration.border 是 BoxBorder（抽象），只对 Border 有 left 边。
Border? _asBorder(BoxDecoration d) => d.border is Border ? d.border as Border : null;

void main() {
  Future<void> pumpMarkdown(
    WidgetTester tester,
    MarkdownStyleSheet ss,
    Color bg,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: bg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MarkdownBody(data: _probeMd, styleSheet: ss),
        ),
      ),
    ));
  }

  group('warmStoneMarkdownDark（R4 映射表 / dark）', () {
    test('段落/标题/强调/代码/链接/引用/代码块文本命中 token', () {
      final ss = warmStoneMarkdownDark();
      expect(ss.p!.color, ConverColors.ink1);
      expect(ss.p!.fontSize, 15);
      expect(ss.p!.height, 1.5);

      expect(ss.h1!.color, ConverColors.ink1);
      expect(ss.h1!.fontSize, 22);
      expect(ss.h1!.fontWeight, FontWeight.w700);
      expect(ss.h2!.fontWeight, FontWeight.w700);
      expect(ss.h3!.fontWeight, FontWeight.w600);
      expect(ss.h4!.fontWeight, FontWeight.w600);

      expect(ss.strong!.color, ConverColors.ink1);
      expect(ss.strong!.fontWeight, FontWeight.w700);
      expect(ss.em!.color, ConverColors.ink2);
      expect(ss.em!.fontStyle, FontStyle.italic);
      expect(ss.del!.decoration, TextDecoration.lineThrough);

      expect(ss.code!.color, ConverColors.accent);
      expect(ss.code!.fontFamily, 'monospace');
      expect(ss.a!.color, ConverColors.accent);
      expect(ss.a!.decoration, TextDecoration.underline);

      expect(ss.blockquote!.color, ConverColors.ink2);
      expect(ss.blockquote!.fontStyle, FontStyle.italic);
      expect(ss.listBullet!.color, ConverColors.accent);
    });

    testWidgets('段落文字渲染层级命中 token（无头可跑，无异常）', (tester) async {
      await pumpMarkdown(tester, warmStoneMarkdownDark(), ConverColors.page);

      expect(tester.takeException(), isNull,
          reason: 'widget 测试无头渲染不应抛异常');
      final styles = _allTextStyles(tester);

      expect(styles['h1-marker 一级标题']!.color, ConverColors.ink1);
      expect(styles['h1-marker 一级标题']!.fontSize, 22);
      expect(styles['bold-marker 加粗']!.fontWeight, FontWeight.w700);
      expect(styles['em-marker 斜体']!.fontStyle, FontStyle.italic);
      expect(styles['del-marker 删除']!.decoration, TextDecoration.lineThrough);
      expect(styles['icode-marker 行内代码']!.color, ConverColors.accent);
      expect(styles['icode-marker 行内代码']!.fontFamily, 'monospace');
      expect(styles['link-marker 链接']!.color, ConverColors.accent);
      expect(styles['bq-marker 这是一段引用。']!.fontStyle, FontStyle.italic);
      expect(styles['codeblock-marker\nfinal tokens;']!.color,
          ConverColors.accent);
      final para =
          styles.keys.where((k) => k.contains('一段普通正文')).first;
      expect(styles[para]!.color, ConverColors.ink1);
    });

    testWidgets('代码块/引用块容器装饰命中 token', (tester) async {
      await pumpMarkdown(tester, warmStoneMarkdownDark(), ConverColors.page);

      bool hasDecoration(bool Function(BoxDecoration d) test) => tester.any(
            find.byWidgetPredicate((w) {
              final BoxDecoration? d = switch (w) {
                DecoratedBox() => w.decoration as BoxDecoration?,
                Container(:final decoration?) => decoration as BoxDecoration?,
                _ => null,
              };
              return d != null && test(d);
            }),
          );

      expect(
        hasDecoration((d) {
          final b = _asBorder(d);
          return b?.left.color == ConverColors.accent && b!.left.width == 3;
        }),
        isTrue,
        reason: '引用块左缘应命中 accent 3px',
      );
      expect(
        hasDecoration((d) => d.color == ConverColors.accent.withValues(alpha: 0.07)),
        isTrue,
        reason: '引用块底色应命中 accent 淡 wash（alpha 0.07）',
      );
      expect(
        hasDecoration((d) =>
            d.color == ConverColors.panel1 &&
            d.border?.top.color == ConverColors.border),
        isTrue,
        reason: '代码块容器应命中 panel1 + warm border',
      );
    });
  });

  group('warmStoneMarkdownLight（R4 映射表 / light，镜像 dark）', () {
    test('段落/标题/强调/代码/链接/引用命中浅色 token', () {
      final ss = warmStoneMarkdownLight();
      expect(ss.p!.color, ConverColorsLight.ink1);
      expect(ss.h1!.color, ConverColorsLight.ink1);
      expect(ss.h1!.fontSize, 22);
      expect(ss.strong!.color, ConverColorsLight.ink1);
      expect(ss.em!.color, ConverColorsLight.ink2);
      expect(ss.code!.color, ConverColorsLight.accent);
      expect(ss.a!.color, ConverColorsLight.accent);
      expect(ss.blockquote!.color, ConverColorsLight.ink2);
      expect(ss.listBullet!.color, ConverColorsLight.accent);
    });

    testWidgets('段落文字渲染层级命中浅色 token（无头可跑）', (tester) async {
      await pumpMarkdown(tester, warmStoneMarkdownLight(), ConverColorsLight.page);

      expect(tester.takeException(), isNull);
      final styles = _allTextStyles(tester);

      expect(styles['h1-marker 一级标题']!.color, ConverColorsLight.ink1);
      expect(styles['icode-marker 行内代码']!.color, ConverColorsLight.accent);
      expect(styles['link-marker 链接']!.color, ConverColorsLight.accent);
      expect(styles['bq-marker 这是一段引用。']!.color, ConverColorsLight.ink2);
      final para = styles.keys.where((k) => k.contains('一段普通正文')).first;
      expect(styles[para]!.color, ConverColorsLight.ink1);
    });

    testWidgets('引用块/代码块容器装饰命中浅色 token', (tester) async {
      await pumpMarkdown(tester, warmStoneMarkdownLight(), ConverColorsLight.page);

      expect(
        tester.any(find.byWidgetPredicate((w) {
          final BoxDecoration? d = switch (w) {
            DecoratedBox() => w.decoration as BoxDecoration?,
            Container(:final decoration?) => decoration as BoxDecoration?,
            _ => null,
          };
          return d != null &&
              _asBorder(d)?.left.color == ConverColorsLight.accent &&
              _asBorder(d)!.left.width == 3;
        })),
        isTrue,
      );
      expect(
        tester.any(find.byWidgetPredicate((w) {
          final BoxDecoration? d = switch (w) {
            DecoratedBox() => w.decoration as BoxDecoration?,
            Container(:final decoration?) => decoration as BoxDecoration?,
            _ => null,
          };
          return d != null &&
              d.color == ConverColorsLight.panel1 &&
              d.border?.top.color == ConverColorsLight.border;
        })),
        isTrue,
      );
    });
  });

  group('无平台通道依赖（无头能力）', () {
    testWidgets('MarkdownBody 无需插件注册即可 pump + 渲染', (tester) async {
      await pumpMarkdown(tester, warmStoneMarkdownDark(), ConverColors.page);
      expect(tester.takeException(), isNull);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.byType(RichText), findsWidgets);
    });
  });
}