/// 模拟器 AI 生成校验闸门（F-M5-08a）——六项校验纯 Dart + GAME_SCENES
/// 括号配对提取器。
///
/// 桌面权威源（只读，语义逐字锚点）：`desktop/backend/app/services/game_generator.py`
/// （六项校验语义：structure / template / cfg / parseability / security / data，
/// `_extract_scenes_literal` 括号配对 + 字符串字面量跳过含转义，`_try_extract_scenes`
/// 数据契约与中文文案，`validate_generated_html` 错误全收集不中断）。
///
/// 于桌面的形态差异（语义等价）：
/// - 无 HTMLParser（纯 Dart 无解析库依赖）→ `checkHtmlSyntax` 以手写扫描器
///   近似：未闭合的 HTML 注释 / `<script>` 块视为语法错误，其余畸形标签宽容
///   （畸形不崩即视为可解析，U3 语义）；
/// - cfg- 契约复用 F-M5-07 导入侧 [scanInputIds] 双层扫描（静态层忽略注释与
///   script 内容）——注释内的 cfg- id 不计数，与桌面 `scan_input_ids` 同语义；
/// - security 复用 F-M5-07 [scanSuspicious]（SUSPICIOUS_PATTERNS 三键集单源），
///   可选传入 [precomputedWarnings]（08b 编排单次扫描复用，对齐桌面 T-03
///   预计算路径，不传时自行扫描）。
///
/// 协议表面（深模块）：`GenValidationError` / `validateGeneratedHtml` /
/// `extractScenesLiteral` / `checkHtmlStructure` / `checkTemplateCompleteness` /
/// `checkCfgContract` / `checkHtmlSyntax` / `checkSecurity` / `checkGameData`。
library;

import 'dart:convert';

import 'game_seed_template.dart' show GameSeedTemplate;
import 'import_service.dart' show scanInputIds, scanSuspicious;

/// 校验闸门单项错误（`{field, message}`，中文文案对齐桌面，可展示给用户）。
class GenValidationError {
  const GenValidationError({required this.field, required this.message});

  /// 错误所属检查项（桌面 field 命名逐字）：structure / template / cfg /
  /// syntax / security / data。
  final String field;

  /// 面向用户的中文错误文案（桌面 message 语义逐字）。
  final String message;

  @override
  bool operator ==(Object other) =>
      other is GenValidationError &&
      other.field == field &&
      other.message == message;

  @override
  int get hashCode => Object.hash(field, message);

  @override
  String toString() => 'GenValidationError(field: $field, message: $message)';
}

/// 检查 1：HTML 骨架完整性——以 `<!DOCTYPE html` 开头，或前 200 字符含
/// `<html`（桌面 `_check_html_structure` 逐字：`lower.strip()` 后判定）。
GenValidationError? checkHtmlStructure(String htmlText) {
  final lower = htmlText.toLowerCase().trim();
  final head = lower.length > 200 ? lower.substring(0, 200) : lower;
  if (lower.startsWith('<!doctype html') || head.contains('<html')) {
    return null;
  }
  return const GenValidationError(
    field: 'structure',
    message: '生成的 HTML 缺少 <!DOCTYPE html> 或 <html> 标签',
  );
}

/// 检查 2：模板标记完整性——无残留 `<!-- GEN:` 标记（桌面
/// `_check_template_completeness` / MARKER_PATTERN 逐字，大小写不敏感）。
GenValidationError? checkTemplateCompleteness(String htmlText) {
  if (GameSeedTemplate.markerPattern.hasMatch(htmlText)) {
    return const GenValidationError(
      field: 'template',
      message: '模板标记未完全填充（仍有 <!-- GEN: --> 未替换）',
    );
  }
  return null;
}

/// 检查 3：cfg- 契约完整性——cfg-endpoint / cfg-apikey / cfg-model 三 input
/// 齐全（桌面 `_check_cfg_contract` 逐字；id 集合来自 [scanInputIds] 双层
/// 扫描，注释与 script 内的 cfg- id 不计数）。缺件按字典序 `、` 连接列出。
GenValidationError? checkCfgContract(String htmlText) {
  final ids = scanInputIds(htmlText);
  final present = ids.where((id) => id.startsWith('cfg-')).toSet();
  final missing = GameSeedTemplate.cfgRequiredIds.difference(present);
  if (missing.isEmpty) {
    return null;
  }
  final names = (missing.toList()..sort()).join('、');
  return GenValidationError(field: 'cfg', message: '缺少 AI 配置输入框：$names');
}

/// 检查 4 辅助：手写扫描器寻找首个语法级问题（未闭合注释 / 未闭合 script 块）。
///
/// 除这两类结构性损伤外，其余畸形输入宽容处理（畸形不崩即视为可解析，
/// U3 语义等价）：返回 null 表示可解析。
///
/// F-40 定版：开/闭标签同口径——`<script` 与 `</script` 均在统一小写化文本上
/// 判定（大小写不敏感，对齐 HTML 标签名大小写不敏感语义）；`<script>` 为
/// RAW TEXT 元素，块内 `<!--` 文本不算 HTML 注释（整体跳至 `</script>`，
/// 不做注释配对）。
String? _firstSyntaxProblem(String html) {
  final lower = html.toLowerCase();
  var i = 0;
  final n = html.length;
  while (i < n) {
    final open = html.indexOf('<', i);
    if (open < 0) {
      break;
    }
    if (lower.startsWith('<!--', open)) {
      final end = html.indexOf('-->', open + 4);
      if (end < 0) {
        return '未闭合的 HTML 注释（<!-- 缺少匹配的 -->）';
      }
      i = end + 3;
      continue;
    }
    if (lower.startsWith('<script', open) &&
        _isTagBreakAt(html, open + '<script'.length)) {
      final close = lower.indexOf('</script', open + 7);
      if (close < 0) {
        return '未闭合的 <script> 标签（缺少对应的 </script>）';
      }
      i = close + 8;
      continue;
    }
    i = open + 1;
  }
  return null;
}

/// 检查 4：基础 HTML 可解析性（场景扫描器可完整扫完 → 通过）。
GenValidationError? checkHtmlSyntax(String htmlText) {
  final problem = _firstSyntaxProblem(htmlText);
  if (problem == null) {
    return null;
  }
  return GenValidationError(field: 'syntax', message: 'HTML 语法错误：$problem');
}

/// 检查 5：安全扫描——复用 F-M5-07 [scanSuspicious]（SUSPICIOUS_PATTERNS 三键
/// 集单源）；[precomputedWarnings] 非 null 时直接采用（08b 单次扫描复用，
/// 对齐桌面 T-03 路径），不传时自行扫描。命中键集 `、` 连接，返回 0 或 1 条
/// security 错误（桌面同构）。
List<GenValidationError> checkSecurity(
  String htmlText, {
  List<String>? precomputedWarnings,
}) {
  final warnings = precomputedWarnings ?? scanSuspicious(htmlText);
  if (warnings.isEmpty) {
    return const [];
  }
  return [
    GenValidationError(
      field: 'security',
      message: '检测到可疑模式：${warnings.join('、')}',
    ),
  ];
}

/// 定位 `var/const/let GAME_SCENES = [` 数组字面量并按括号深度配对切分
/// （字符串字面量内字符整体跳过，含 `\` 转义序列；`"` / `'` / `` ` `` 三引号态）。
///
/// 修复点（桌面 code-review 发现，本移植复刻）：非贪婪正则会在 narrative 含
/// `];` 时提前截断导致合法游戏误报 JSON 解析失败——本实现以括号配对 + 字符串
/// 跳过为准。
///
/// Returns: 完整数组文本（含两端方括号）；找不到起始或括号不闭合 → null。
String? extractScenesLiteral(String htmlText) {
  final match = RegExp(r'(?:var|const|let)\s+GAME_SCENES\s*=\s*\[')
      .firstMatch(htmlText);
  if (match == null) {
    return null;
  }
  var i = match.end - 1; // 指向 '['
  var depth = 0;
  String? quote; // 当前字符串引号态（" / ' / `）；null = 不在字符串内
  final n = htmlText.length;
  while (i < n) {
    final ch = htmlText[i];
    if (quote != null) {
      if (ch == r'\') {
        i += 2; // 跳过转义序列（可能为转义引号）
        continue;
      }
      if (ch == quote) {
        quote = null;
      }
      i += 1;
      continue;
    }
    if (ch == '"' || ch == "'" || ch == '`') {
      quote = ch;
    } else if (ch == '[') {
      depth += 1;
    } else if (ch == ']') {
      depth -= 1;
      if (depth == 0) {
        return htmlText.substring(match.end - 1, i + 1);
      }
    }
    i += 1;
  }
  return null;
}

/// 提取场景数据中的问题场景（记录两字段：scenes 列表 + 错误消息；成功时
/// scenes 非 null / error 为 null，失败时反之——桌面 `_try_extract_scenes` 逐字）。
///
/// 场景 id 契约：全字符串且唯一（重复 → data 错误）；`next` 引用必须存在于 id
/// 集合中（自引用与双向循环通过是设计允许——无限循环属叙事自由，不阻断）。
({List<Object?>? scenes, String? error}) _tryExtractScenes(String htmlText) {
  final raw = extractScenesLiteral(htmlText);
  if (raw == null) {
    return (scenes: null, error: '未找到 GAME_SCENES 数据定义');
  }
  final Object? decoded;
  try {
    decoded = json.decode(raw);
  } on FormatException catch (exc) {
    return (scenes: null, error: '场景数据 JSON 解析失败：$exc');
  }
  if (decoded is! List<Object?>) {
    return (scenes: null, error: '场景数据必须是数组');
  }
  final scenes = decoded;
  if (scenes.isEmpty) {
    return (scenes: null, error: '场景数据为空（至少需要一个场景）');
  }
  final ids = <String>[];
  for (var i = 0; i < scenes.length; i++) {
    final scene = scenes[i];
    if (scene is! Map<String, dynamic>) {
      return (scenes: null, error: '第 ${i + 1} 个场景不是对象');
    }
    final sid = scene['id'];
    if (!scene.containsKey('id')) {
      return (scenes: null, error: '第 ${i + 1} 个场景缺少 id 字段');
    }
    final narrative = scene['narrative'];
    if (narrative is! String || narrative.trim().isEmpty) {
      return (scenes: null, error: "场景「$sid」缺少叙事文本");
    }
    final choices = scene['choices'];
    if (choices is! List<Object?>) {
      return (scenes: null, error: "场景「$sid」缺少 choices 数组");
    }
    for (var j = 0; j < choices.length; j++) {
      final choice = choices[j];
      if (choice is! Map<String, dynamic>) {
        return (scenes: null, error: "场景「$sid」第 ${j + 1} 个选项不是对象");
      }
      final text = choice['text'];
      if (text is! String || text.isEmpty) {
        return (scenes: null, error: "场景「$sid」第 ${j + 1} 个选项缺少 text");
      }
      final next = choice['next'];
      if (next is! String || next.isEmpty) {
        return (scenes: null, error: "场景「$sid」第 ${j + 1} 个选项缺少 next");
      }
    }
    if (sid is! String) {
      return (
        scenes: null,
        error: '第 ${i + 1} 个场景 id 必须是字符串（收到 ${sid.runtimeType}）',
      );
    }
    ids.add(sid);
  }
  if (ids.toSet().length != ids.length) {
    final counts = <String, int>{};
    for (final id in ids) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final dup = counts.entries.firstWhere((e) => e.value > 1).key;
    return (scenes: null, error: '场景 id 存在重复：「$dup」（每个场景 id 必须唯一）');
  }
  final allIds = ids.toSet();
  for (final scene in scenes) {
    final entry = scene as Map<String, dynamic>;
    for (final choice in entry['choices'] as List<Object?>) {
      final c = choice as Map<String, dynamic>;
      final next = c['next'] as String;
      if (!allIds.contains(next)) {
        return (
          scenes: null,
          error: "场景「${entry['id']}」的选项「${c['text']}」引用了不存在的场景「$next」",
        );
      }
    }
  }
  return (scenes: scenes, error: null);
}

/// 检查 6：游戏数据有效性（场景 JSON 可解析、非空列表、每场景 id / narrative /
/// choices、每选项 text / next，id 全字符串且唯一、next 引用完整）。
GenValidationError? checkGameData(String htmlText) {
  final result = _tryExtractScenes(htmlText);
  if (result.error != null) {
    return GenValidationError(field: 'data', message: result.error!);
  }
  return null;
}

/// 校验闸门：对 AI 生成的 HTML 执行六项检查，全部错误收集不中断。
///
/// 检查项（桌面 `validate_generated_html` 逐字）：
/// 1. HTML 骨架完整性（structure）；
/// 2. 模板标记完整性，无残留 `<!-- GEN:`（template）；
/// 3. cfg- 契约完整性，cfg-endpoint / cfg-apikey / cfg-model（cfg）；
/// 4. 基础 HTML 可解析性（syntax）；
/// 5. 安全扫描，SUSPICIOUS_PATTERNS 命中键集（security）；
/// 6. 游戏数据有效性，GAME_SCENES JSON + 引用完整（data）。
///
/// 前面的失败不阻断后续检查（逐项跑完合并 errors，利于重试反馈）。
/// [precomputedWarnings] 非 null 时检查 5 直接采用（08b 单次扫描复用），
/// 不传时检查 5 自行扫描。
///
/// Returns: 错误列表（空列表 = 全部通过，可落盘）。
List<GenValidationError> validateGeneratedHtml(
  String htmlText, {
  List<String>? precomputedWarnings,
}) {
  final errors = <GenValidationError>[];
  final structure = checkHtmlStructure(htmlText);
  if (structure != null) {
    errors.add(structure);
  }
  final template = checkTemplateCompleteness(htmlText);
  if (template != null) {
    errors.add(template);
  }
  final cfg = checkCfgContract(htmlText);
  if (cfg != null) {
    errors.add(cfg);
  }
  final syntax = checkHtmlSyntax(htmlText);
  if (syntax != null) {
    errors.add(syntax);
  }
  errors.addAll(
    checkSecurity(htmlText, precomputedWarnings: precomputedWarnings),
  );
  final data = checkGameData(htmlText);
  if (data != null) {
    errors.add(data);
  }
  return errors;
}

/// 判断 `index` 处是否位于字符串尾或标签名终止字符（空白 / `>` / `/`）。
bool _isTagBreakAt(String html, int index) {
  if (index >= html.length) {
    return true;
  }
  final ch = html[index];
  return ch == ' ' ||
      ch == '\t' ||
      ch == '\n' ||
      ch == '\r' ||
      ch == '>' ||
      ch == '/';
}
