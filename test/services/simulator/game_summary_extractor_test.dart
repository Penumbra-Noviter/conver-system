/// 模拟器简介规则提取器单测（本批次）——真实种子 HTML 实证（证伪：提取内容
/// 非空且可读）+ 合成边界（坏 HTML / 无 title / 废 title / 无 prompt 段 /
/// 空串 / 长文本截断）。
///
/// 真实样本契约（对齐 AGENTS「解析器证伪不能只靠合成 fixture」）：全部 22 款
/// 随包种子逐一遍历断言——fallback 恒非空、恒 ≤ [maxFallbackChars] 码点。
library;

import 'dart:io';

import 'package:conver_system_mobile/services/simulator/game_summary_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 读取种子游戏 HTML（真实样本）。
String _seed(String name) =>
    File('assets/simulators/$name').readAsStringSync();

void main() {
  group('真实种子提取（22 款全部遍历）', () {
    final seedFiles = Directory('assets/simulators')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.html'))
        .map((f) => f.uri.pathSegments.last)
        .toList();

    test('全部种子：fallback 恒非空 + 不超长 + 无残留标签/空白', () {
      expect(seedFiles.length, 22, reason: '种子数量漂移即本测试需同步');
      for (final name in seedFiles) {
        final html = _seed(name);
        final candidate = extractGameSummary(html);
        final summary = buildFallbackSummary(candidate);
        expect(summary, isNotEmpty, reason: '$name fallback 为空');
        expect(
          summary.runes.length,
          lessThanOrEqualTo(maxFallbackChars),
          reason: '$name fallback 超长: $summary',
        );
        expect(
          summary.contains('<') || summary.contains('>'),
          isFalse,
          reason: '$name fallback 残留 HTML 标签',
        );
        expect(
          RegExp(r'\s{2,}').hasMatch(summary),
          isFalse,
          reason: '$name fallback 残留连续空白',
        );
      }
    });

    test('AI 驱动游戏：prompt 设定段非空（内容载体在 JS 字符串）', () {
      final candidate = extractGameSummary(_seed('蛛网之影.html'));
      expect(candidate.title, contains('蜘蛛侠'));
      expect(candidate.promptSnippets, isNotEmpty);
      expect(candidate.promptSnippets.length, lessThanOrEqualTo(3));
    });

    test('废 title 游戏（小马宝莉）：title 不进 fallback，prompt 段兜底', () {
      final candidate = extractGameSummary(_seed('小马宝莉.html'));
      expect(candidate.title, 'AI 角色扮演游戏'); // 真实废 title
      final summary = buildFallbackSummary(candidate);
      expect(summary, isNotEmpty);
      expect(summary, isNot(contains('AI 角色扮演游戏')));
    });

    test('可见文本恒可提取（去 script/style 后仍有 UI 文案）', () {
      final candidate = extractGameSummary(_seed('仙途.html'));
      expect(candidate.visibleText, isNotEmpty);
    });
  });

  group('合成边界（证伪）', () {
    test('空串 / 纯空白 → 空候选 + 空 fallback，不抛', () {
      final empty = extractGameSummary('');
      expect(empty.title, '');
      expect(empty.visibleText, '');
      expect(empty.promptSnippets, isEmpty);
      expect(buildFallbackSummary(empty), '');

      final blank = extractGameSummary('   \n\t  ');
      expect(blank.title, '');
      expect(buildFallbackSummary(blank), '');
    });

    test('无 title + 有 prompt 关键词 → fallback 取自 snippet', () {
      final html = '<html><body><script>'
          'const WORLD = "世界观：赛博朋克都市里，你是一名义体医生。";'
          '</script></body></html>';
      final candidate = extractGameSummary(html);
      expect(candidate.title, '');
      final summary = buildFallbackSummary(candidate);
      expect(summary, contains('赛博朋克'));
    });

    test('废 title 黑名单不进 fallback（合成验证）', () {
      final candidate = GameSummaryCandidate(
        title: 'AI 角色扮演游戏',
        visibleText: '',
        promptSnippets: const ['修仙问道，逆天而行'],
      );
      final summary = buildFallbackSummary(candidate);
      expect(summary, isNot(contains('AI 角色扮演游戏')));
      expect(summary, contains('修仙问道'));
    });

    test('无任何可提取内容（纯 CSS）→ fallback 空，不抛', () {
      final html = '<style>body{color:#fff}</style>';
      final candidate = extractGameSummary(html);
      expect(buildFallbackSummary(candidate), '');
    });

    test('长文本 fallback 按码点截断 ≤ 上限（含 emoji 不劈裂代理对）', () {
      final long = '${'游' * 50}😀${'戏' * 50}';
      final candidate = GameSummaryCandidate(
        title: long,
        visibleText: '',
        promptSnippets: const [],
      );
      final summary = buildFallbackSummary(candidate);
      expect(summary.runes.length, lessThanOrEqualTo(maxFallbackChars));
      final lastCodeUnit =
          summary.isNotEmpty ? summary.codeUnitAt(summary.length - 1) : 0;
      expect(
        lastCodeUnit < 0xD800 || lastCodeUnit > 0xDFFF,
        isTrue,
        reason: '截断不得劈裂代理对（尾字符不得为孤立代理项）',
      );
    });

    test('script 内容不进可见文本（可见文本只含 UI 文案）', () {
      final html = '<html><body><script>var x=1;</script>'
          '<button>开始游戏</button></body></html>';
      final candidate = extractGameSummary(html);
      expect(candidate.visibleText, isNot(contains('var x')));
      expect(candidate.visibleText, contains('开始游戏'));
    });
  });
}
