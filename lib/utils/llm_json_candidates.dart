/// LLM 输出 JSON 候选段枚举（AD-03 S2 三级容错提取单源）。
///
/// 对齐 F-114/F-115 `utf16_truncate.dart` 先例：纯字符串顶层函数、零 LLM
/// 域依赖。三处调用方（document_parse_service / reflection_service /
/// proactive_message_service）各自保留类型化解码，本模块只承载候选段枚举
/// 顺序与 marker 字面量单源。
library;

/// 枚举 [raw] 中的 JSON 候选段，顺序固定：**原文 trim 在前 → fenced 代码块
/// 段 → open/close 范围段**。
///
/// - [open] / [close]：范围段分隔符；dict/object 传 `{`/`}`，array 传
///   `[`/`]`；
/// - [fenceMarkers]：fenced 段开标记（含换行的 `text.indexOf` 匹配语义），
///   默认值即三处既有实现的 marker 字面量单源；闭 fence 恒为 ` ``` `；
/// - fenced 段提取后 trim；范围段提取不 trim（与既有实现逐字等价）；
/// - 本函数为纯字符串操作，**自身不抛异常**：trim 后为空（无候选）→ 空
///   列表；其余输入至少返回原文候选；解析失败语义由调用方逐候选类型化
///   解码决定（ADR-0004 三级容错决策实质不在此处）。
List<String> llmJsonCandidates(
  String raw, {
  required String open,
  required String close,
  List<String> fenceMarkers = const ['```json\n', '```\n', '```'],
}) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const <String>[];
  }

  final candidates = <String>[text];

  // fenced 段：每个 marker 找最近开标记与其后的闭 ```；无闭合（end<0）
  // 则跳过该 marker（与既有实现 indexOf 语义一致，不做容错猜测）。
  for (final marker in fenceMarkers) {
    final start = text.indexOf(marker);
    if (start < 0) {
      continue;
    }
    final end = text.indexOf('```', start + marker.length);
    if (end >= 0) {
      candidates.add(text.substring(start + marker.length, end).trim());
    }
  }

  // 范围段：首个 open 到末个 close；空分隔符为无效输入直接跳过（避免
  // indexOf('')/lastIndexOf('') 使 substring 越界——不抛异常契约）。
  if (open.isNotEmpty && close.isNotEmpty) {
    final rangeStart = text.indexOf(open);
    if (rangeStart >= 0) {
      final rangeEnd = text.lastIndexOf(close);
      if (rangeEnd > rangeStart) {
        candidates.add(text.substring(rangeStart, rangeEnd + 1));
      }
    }
  }

  return candidates;
}
