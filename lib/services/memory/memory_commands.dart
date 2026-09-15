/// 记忆指令解析 — 从 LLM 回复中提取记忆标签（`<add:>` / `<persona:>` / `<search:>`）
/// 并剥离标签得到展示文本。纯 Dart 零 I/O，可独立单测。
///
/// 语义锚点为 ADR-0003（prompt 指令驱动记忆，零额外 LLM 调用）与逆向对照材料
/// （`.scratch/aiyun-unpack/DYNAMIC_UNPACK_REPORT.md` 指令系统，仅本地对照学习）。
///
/// 标签语法（内容到 `>` 结束，不含换行）：
/// - `<add:内容>` → 情景记忆（对话经历 / 事件，episodic）
/// - `<persona:内容>` → 人格事实（身份 / 喜好 / 性格，persona_fact）
/// - `<search:关键词>` → 检索信号（询问过去信息时发出）
///
/// 客户端在完整 assistant 回复落库前调用 [parseMemoryCommands]：得到剥离标签后
/// 的展示文本（避免标签泄漏进聊天 UI）与结构化指令列表（供落库 / 检索）。
library;

/// 记忆指令类型。
enum MemoryCommandKind {
  /// `<add:内容>` —— 情景记忆。
  add,

  /// `<persona:内容>` —— 人格事实。
  persona,

  /// `<search:关键词>` —— 检索信号。
  search,
}

/// 单条解析出的记忆指令（类型 + 内容，内容已 trim）。
class MemoryCommand {
  /// 构造指令。
  const MemoryCommand(this.kind, this.content);

  /// 指令类型。
  final MemoryCommandKind kind;

  /// 标签内容（已 trim；空内容标签在解析层被丢弃，不会出现于此）。
  final String content;
}

/// [parseMemoryCommands] 的产出：剥离标签后的展示文本 + 结构化指令列表。
class MemoryParseResult {
  /// 构造解析结果。
  const MemoryParseResult({
    required this.displayContent,
    required this.commands,
  });

  /// 剥离全部记忆标签后的展示文本（保留其他文本与换行）。
  final String displayContent;

  /// 解析出的全部指令（按原文出现顺序）。
  final List<MemoryCommand> commands;

  /// `<add:>` 情景记忆内容列表（保持出现顺序）。
  List<String> get addEntries => _contentsOf(MemoryCommandKind.add);

  /// `<persona:>` 人格事实内容列表（保持出现顺序）。
  List<String> get personaEntries => _contentsOf(MemoryCommandKind.persona);

  /// `<search:>` 检索关键词列表（保持出现顺序）。
  List<String> get searchQueries => _contentsOf(MemoryCommandKind.search);

  List<String> _contentsOf(MemoryCommandKind kind) => [
        for (final c in commands)
          if (c.kind == kind) c.content,
      ];
}

/// 记忆标签匹配正则：`<(add|persona|search):内容>`，内容不含 `>` 与换行。
///
/// 非贪婪匹配内容段，`>` 为终止符（prompt 教导 LLM 内容内不出现 `>`）。
final RegExp _commandPattern = RegExp(r'<(add|persona|search):([^>\n]*?)>');

/// 解析 LLM 回复全文：提取记忆标签并剥离，返回展示文本与指令列表。
///
/// 规则：
/// - 空串 → 空指令 + 空展示文本（零标签可剥离）；
/// - 标签类型仅认 `add` / `persona` / `search`（大小写敏感），未知标签保留原文；
/// - 标签内容 trim 后为空 → 该标签视为无效丢弃（不产生指令，但标签文本仍被剥离）；
/// - 未闭合 / 内容含换行的标签不匹配（`[^>\n]` 限制），原样保留。
MemoryParseResult parseMemoryCommands(String reply) {
  if (reply.isEmpty) {
    return const MemoryParseResult(displayContent: '', commands: []);
  }

  final commands = <MemoryCommand>[];
  final buffer = StringBuffer();
  var lastIndex = 0;

  for (final match in _commandPattern.allMatches(reply)) {
    // 保留标签之前的普通文本。
    buffer.write(reply.substring(lastIndex, match.start));

    final kind = switch (match.group(1)) {
      'add' => MemoryCommandKind.add,
      'persona' => MemoryCommandKind.persona,
      'search' => MemoryCommandKind.search,
      _ => null,
    };
    final content = match.group(2)!.trim();
    if (kind != null && content.isNotEmpty) {
      commands.add(MemoryCommand(kind, content));
    }
    lastIndex = match.end;
  }
  // 收尾：最后一个标签之后的剩余文本。
  buffer.write(reply.substring(lastIndex));

  return MemoryParseResult(
    displayContent: buffer.toString(),
    commands: List<MemoryCommand>.unmodifiable(commands),
  );
}
