/// Warm Stone MarkdownStyleSheet 主题化（dark / light 两套）。
///
/// R4 spike 结论（`.scratch/m2-kickoff/prototype/markdown-theme/README.md`，
/// 探针工程已弃用，本文件是产品落地）：
/// - `flutter_markdown_plus 1.0.12` 可无头定制；样式映射表见下方
///   [warmStoneMarkdownDark] 注释与各字段断言
///   （`test/theme/chat_markdown_style_test.dart`）；
/// - `styleSheet.code` 同时作用于行内 code 与围栏代码块文本（builder 的
///   `formatText` 直接用 `styleSheet.code`）→ 代码块视觉区分走
///   `codeblockDecoration`（容器底 + 圆角边框），`code` 只给琥珀文字 +
///   monospace，不给行内 code 背景 chip（避免泄漏进代码块）；
/// - 流式占位气泡的纯文本样式 = `styleSheet.p`（ink1 / 15 / height 1.5，
///   与最终 Markdown 段落视觉一致，两级降频 streaming 侧）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'colors.dart';

/// 深色 [MarkdownStyleSheet]：逐项命中 [ConverColors] token（R4 映射表）。
///
/// 映射表（README §4.2，测试逐值断言锁定；列表项 / 表格文本复用 `p`——
/// flutter_markdown_plus 1.0.12 无独立 `li` / `table` TextStyle 字段）：
/// | 字段 | 值 |
/// |---|---|
/// | `p`（段落，含 li / table 文本） | ink1，15，height 1.5 |
/// | `h1`–`h4` | ink1，w700/w700/w600/w600，22/19/17/15.5 |
/// | `h5`/`h6` | ink1/ink2，w600，14.5/13.5 |
/// | `strong` | ink1，w700 |
/// | `em` | ink2 + italic |
/// | `del` | ink4 + lineThrough |
/// | `code`（行内 + 代码块文本共用） | accent + monospace（15×0.85） |
/// | `a` | accent + underline |
/// | `blockquote` | ink2 + italic |
/// | `listBullet` | accent |
/// | `codeblockDecoration` | panel1 底 + border 1px + radius 6，padding 10 |
/// | `blockquoteDecoration` | accent 左缘 3px + accent α0.07 wash，padding 左12 |
/// | `horizontalRuleDecoration` | border 1px |
/// | `tableHead` / `tableBody` | ink1 w600 / ink2 |
MarkdownStyleSheet warmStoneMarkdownDark() => _build(
      p: ConverColors.ink1,
      ink2: ConverColors.ink2,
      ink4: ConverColors.ink4,
      accent: ConverColors.accent,
      panel: ConverColors.panel1,
      border: ConverColors.border,
      tableHeadBg: ConverColors.panel4,
    );

/// 浅色 [MarkdownStyleSheet]：逐项命中 [ConverColorsLight] token，结构镜像
/// [warmStoneMarkdownDark]（同一映射表，仅 token 换浅色板）。
MarkdownStyleSheet warmStoneMarkdownLight() => _build(
      p: ConverColorsLight.ink1,
      ink2: ConverColorsLight.ink2,
      ink4: ConverColorsLight.ink4,
      accent: ConverColorsLight.accent,
      panel: ConverColorsLight.panel1,
      border: ConverColorsLight.border,
      tableHeadBg: ConverColorsLight.panel4,
    );

/// 两套样式共用的组装基座（探针 `_build` 平移，色值替换为真实 token）。
MarkdownStyleSheet _build({
  required Color p,
  required Color ink2,
  required Color ink4,
  required Color accent,
  required Color panel,
  required Color border,
  required Color tableHeadBg,
}) {
  return MarkdownStyleSheet(
    p: TextStyle(color: p, fontSize: 15, height: 1.5),
    a: TextStyle(
      color: accent,
      decoration: TextDecoration.underline,
      decorationColor: accent,
    ),
    // `code` 同时作用于行内 code 与围栏代码块文本（builder.formatText 用
    // styleSheet.code），不能只给行内；代码块底色走 codeblockDecoration。
    code: TextStyle(color: accent, fontFamily: 'monospace', fontSize: 12.75),
    h1: TextStyle(color: p, fontSize: 22, fontWeight: FontWeight.w700),
    h2: TextStyle(color: p, fontSize: 19, fontWeight: FontWeight.w700),
    h3: TextStyle(color: p, fontSize: 17, fontWeight: FontWeight.w600),
    h4: TextStyle(color: p, fontSize: 15.5, fontWeight: FontWeight.w600),
    h5: TextStyle(color: p, fontSize: 14.5, fontWeight: FontWeight.w600),
    h6: TextStyle(color: ink2, fontSize: 13.5, fontWeight: FontWeight.w600),
    strong: TextStyle(color: p, fontWeight: FontWeight.w700),
    em: TextStyle(color: ink2, fontStyle: FontStyle.italic),
    del: TextStyle(color: ink4, decoration: TextDecoration.lineThrough),
    blockquote: TextStyle(color: ink2, fontStyle: FontStyle.italic),
    blockquoteDecoration: BoxDecoration(
      color: accent.withValues(alpha: 0.07),
      border: Border(left: BorderSide(color: accent, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    codeblockDecoration: BoxDecoration(
      color: panel,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(6),
    ),
    codeblockPadding: const EdgeInsets.all(10),
    listBullet: TextStyle(color: accent, fontSize: 15),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: border, width: 1)),
    ),
    tableHead: TextStyle(color: p, fontWeight: FontWeight.w600),
    tableBody: TextStyle(color: ink2),
    tableHeadCellsDecoration: BoxDecoration(color: tableHeadBg),
    blockSpacing: 12,
  );
}