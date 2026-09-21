/// 模拟器游戏简介规则提取器（本批次，混合方案）——零 LLM 零成本本地提取。
///
/// 背景：AI 驱动游戏的「内容」不在可见 UI（每款仅 400~500 字符按钮词），而
/// 在 JS 字符串里的设定段（世界观 / 你扮演 / 背景等）；本地游戏则以可见文本
/// 为主。本模块从游戏 HTML 提取三类候选（`<title>` / 可见 UI 文本 / prompt
/// 设定段），供 [buildFallbackSummary] 拼兜底简介（导入游戏 description 为空
/// 时的即时文案）与 LLM 精修（`game_description_generator.dart`）作输入。
///
/// 纯函数零 IO 零依赖（消费方读文件后传入字符串），全部规则可单测；容错逐级
/// 降级不抛：坏 HTML / 无 title / 废 title / 无 prompt 段均返回可拼接候选，
/// 最差 [buildFallbackSummary] 返回空串（调用方决定是否写回）。
library;

/// 规则简介最大长度（字符）——对齐卡片简介显示区域（三行），超出截断。
const int maxFallbackChars = 60;

/// prompt 设定段抽取关键词（AI 驱动游戏的核心设定所在——JS 字符串内
/// 「世界观/你扮演/背景」等上下文；按声明序命中，命中即抽该段上下文）。
const List<String> _promptKeywords = <String>[
  '世界观',
  '背景设定',
  '游戏背景',
  '故事背景',
  '系统设定',
  '你扮演',
  '玩法介绍',
  '玩法说明',
  '游戏简介',
  '角色设定',
];

/// 关键词上下文窗口（前后各取字符数）——足以覆盖「世界观：……」整句。
const int _snippetWindow = 60;

/// 抽取 prompt 段数量上限（拼接预算内，防候选膨胀）。
const int _maxSnippets = 3;

/// 可见 UI 文本送入 LLM 精修的长度上限（按钮词为主，取前段即可）。
const int _maxVisibleChars = 120;

/// 简介候选：从游戏 HTML 提取的三类内容。
class GameSummaryCandidate {
  const GameSummaryCandidate({
    required this.title,
    required this.visibleText,
    required this.promptSnippets,
  });

  /// `<title>` 净化后文本（去标签）；缺失 → 空串。
  final String title;

  /// 去 script/style/注释/标签后的可见 UI 文本（空白归一，截断
  /// [_maxVisibleChars]）。
  final String visibleText;

  /// prompt 设定段（关键词上下文抽取，空白归一去重，≤ [_maxSnippets] 条）。
  final List<String> promptSnippets;
}

/// 提取游戏简介候选（纯函数）：title + 可见文本 + prompt 设定段三类。
///
/// 逐级容错：任一提取失败（缺 title / 无关键词命中）返回空串或空列表，不抛
/// 异常；[html] 为空串同样安全返回（空候选）。
GameSummaryCandidate extractGameSummary(String html) {
  return GameSummaryCandidate(
    title: _extractTitle(html),
    visibleText: _extractVisibleText(html),
    promptSnippets: _extractPromptSnippets(html),
  );
}

/// 拼规则兜底简介（零 LLM）：优先「可用 title —— 首条 prompt 段」；title 废
/// 或缺失时退可见文本；全空返回空串（调用方决定是否写回）。
///
/// [candidate] 来自 [extractGameSummary]；输出 ≤ [maxFallbackChars] 字符
/// （按 Unicode 码点截断，不劈裂代理对）。
String buildFallbackSummary(GameSummaryCandidate candidate) {
  final parts = <String>[];
  final title = _usableTitle(candidate.title);
  if (title.isNotEmpty) {
    parts.add(title);
  }
  if (candidate.promptSnippets.isNotEmpty) {
    parts.add(_truncateChars(candidate.promptSnippets.first, 40));
  }
  var summary = parts.join('——');
  if (summary.isEmpty && candidate.visibleText.isNotEmpty) {
    summary = _truncateChars(candidate.visibleText, maxFallbackChars);
  }
  return summary.isEmpty ? '' : _truncateChars(summary, maxFallbackChars);
}

/// 提取 `<title>` 内容（去标签净化）；缺失 → 空串。
String _extractTitle(String html) {
  final match = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html);
  if (match == null) {
    return '';
  }
  return _collapse(_stripTags(match.group(1)!));
}

/// 提取可见 UI 文本：去 script/style/注释 → 去标签与截断残留 → 空白归一 →
/// 截断。
String _extractVisibleText(String html) {
  var text = html.replaceAll(
    RegExp(r'<script\b[\s\S]*?</script>', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(
    RegExp(r'<style\b[\s\S]*?</style>', caseSensitive: false),
    ' ',
  );
  text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  text = _collapse(_stripTagsAndFragments(text));
  return _truncateChars(text, _maxVisibleChars);
}

/// 抽取 prompt 设定段：关键词首次命中即取上下文窗口，去转义序列/标签/空白
/// 归一后去重入列；最多 [_maxSnippets] 条，按关键词声明序收集。
List<String> _extractPromptSnippets(String html) {
  final snippets = <String>[];
  final seen = <String>{};
  for (final keyword in _promptKeywords) {
    if (snippets.length >= _maxSnippets) {
      break;
    }
    var index = html.indexOf(keyword);
    while (index >= 0 && snippets.length < _maxSnippets) {
      final start = (index - _snippetWindow).clamp(0, html.length);
      final end =
          (index + keyword.length + _snippetWindow).clamp(0, html.length);
      var raw = html.substring(start, end);
      raw = raw.replaceAll(RegExp(r'\\n|\\t|\\r'), ' ');
      raw = _collapse(_stripTagsAndFragments(raw));
      // 短于「关键词 + 4 字符」的上下文视为无信息量，跳过。
      if (raw.length >= keyword.length + 4 && seen.add(raw)) {
        snippets.add(raw);
      }
      index = html.indexOf(keyword, index + keyword.length);
    }
  }
  return snippets;
}

/// title 是否可用（非空 / 非通用废标题 / 长度 ≥3）。
String _usableTitle(String title) {
  final t = title.trim();
  if (t.isEmpty || t.length < 3) {
    return '';
  }
  // 通用废标题黑名单：不携带任何题材信息（种子内 2 款实测）。
  const generic = <String>{'AI 角色扮演游戏', '微信 · AI', '微信·AI', '角色扮演游戏'};
  return generic.contains(t) ? '' : t;
}

/// 去 HTML 标签（替换为空格，防粘连）。
String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]+>'), ' ');

/// 去标签并清除截断/畸形残留的孤立 `<` `>`（窗口截断把半截标签留在文本内，
/// 如 仿微.html 实测 `<div class="char-preview"`——完整标签已被剥除，残留的
/// 孤立尖括号对摘要无意义，直接剔除）。
String _stripTagsAndFragments(String s) =>
    _stripTags(s).replaceAll(RegExp(r'[<>]'), ' ');

/// 空白归一（连续空白 → 单空格 + 首尾修剪）。
String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 按 Unicode 码点截断（不劈裂代理对/组合字符）；未超限原样返回。
String _truncateChars(String s, int max) {
  final runes = s.runes.toList();
  if (runes.length <= max) {
    return s;
  }
  return String.fromCharCodes(runes.take(max));
}
