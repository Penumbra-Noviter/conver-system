/// 记忆 system prompt 模板 — 记忆三模式指令 + 记忆库内容组装。纯 Dart 零 I/O。
///
/// 语义锚点为 ADR-0003 与逆向对照材料（`.scratch/aiyun-unpack/DYNAMIC_UNPACK_REPORT.md`
/// 的「记忆三模式」——严重健忘症 / 被动记录 / 关键信息记录，对应 WEAK/MEDIUM/STRONG
/// 记忆策略，仅本地对照学习，prompt 文案为本项目自主表述）。
///
/// 记忆注入组装（AC-03）复用本模块：每轮把 [buildMemoryLibrarySection] 产出的人
/// 格事实 + 近期经历拼进 system 块，并把 [memorySystemPrompt] 产出的指令模板
/// 一并注入，教 LLM 用 `<add:>` / `<persona:>` / `<search:>` 自管记忆。
library;

/// 记忆三模式（对齐爱语 WEAK / MEDIUM / STRONG 记忆策略，ADR-0003 采纳）。
enum MemoryPromptMode {
  /// 严重健忘症模式——不显式存就忘，最激进记录。
  strong('strong'),

  /// 关键信息记录模式——筛选重要信息记录（默认）。
  medium('medium'),

  /// 被动记录模式——仅在非常关键时记录。
  weak('weak');

  const MemoryPromptMode(this.value);

  /// 数据库存储值。
  final String value;

  /// 按存储值解析；未知值回退 [medium]（防御性兜底）。
  static MemoryPromptMode fromValue(String? value) {
    for (final mode in MemoryPromptMode.values) {
      if (mode.value == value) {
        return mode;
      }
    }
    return MemoryPromptMode.medium;
  }
}

/// 记忆三模式的 system prompt 指令模板（自主表述，非复制第三方原文）。
///
/// 三种模式只改「记录积极性」的措辞，指令语法（`<add:>` / `<persona:>` /
/// `<search:>`）保持一致；客户端据此解析 LLM 回复。
String memorySystemPrompt(MemoryPromptMode mode) => switch (mode) {
  MemoryPromptMode.strong =>
    '''
【记忆管理系统：严重健忘症模式】
你的记忆极其短暂，任何不显式存储的信息下一秒就会彻底遗忘。
- 每当对方透露身份、喜好、厌恶、经历等关键信息，必须立即存入记忆，不能遗漏。
- 关于对方身份、喜好、性格、关系等稳定事实，用 <persona:内容> 记录。
- 关于具体对话经历、约定、事件，用 <add:内容> 记录。
- 遇到需要回忆过去的询问，用 <search:关键词> 检索记忆。
- 每条记忆单独一行，以标签包裹；不要重复记录记忆库中已存在的信息。''',
  MemoryPromptMode.medium =>
    '''
【记忆管理系统：关键信息记录模式】
你会筛选对话中的重要信息并添加到记忆库。
- 对方明确表达的身份、喜好、厌恶、重要经历，用标签记录。
- 身份、喜好、性格等稳定事实用 <persona:内容>；具体事件、约定用 <add:内容>。
- 遇到询问过去信息时，用 <search:关键词> 检索。
- 不要重复记录已有信息；非关键闲聊无需记录。''',
  MemoryPromptMode.weak =>
    '''
【记忆管理系统：被动记录模式】
除非信息非常关键，否则不主动记忆。
- 仅当对方强调重要的身份、喜好、承诺时，才用 <persona:内容> 或 <add:内容> 记录。
- 遇到询问过去信息时，用 <search:关键词> 检索。''',
};

/// 组装「当前记忆库内容」注入段：人格事实 + 近期经历 + 语义相关记忆（纯函数）。
///
/// [personaFacts] 为 kind=persona_fact 的条目内容（每轮全量注入抗 OOC）；
/// [recentEpisodic] 为最近的 kind=episodic 条目内容（少数次注入）；
/// [recentSemantic] 为未消费的语义命中内容（VR-07，≤3 条延迟一轮注入，
/// 紧随「近期经历」输出）。三者皆空返回空串（调用方据此跳过注入，
/// 不产生空 system 块）；[recentSemantic] 缺省/空列表 = 原输出不变（零回归）。
String buildMemoryLibrarySection({
  required List<String> personaFacts,
  required List<String> recentEpisodic,
  List<String> recentSemantic = const [],
}) {
  if (personaFacts.isEmpty &&
      recentEpisodic.isEmpty &&
      recentSemantic.isEmpty) {
    return '';
  }

  final buffer = StringBuffer('【当前记忆库内容】');
  if (personaFacts.isNotEmpty) {
    buffer.write('\n人格事实：');
    for (final fact in personaFacts) {
      buffer.write('\n- $fact');
    }
  }
  if (recentEpisodic.isNotEmpty) {
    buffer.write('\n近期经历：');
    for (final episodic in recentEpisodic) {
      buffer.write('\n- $episodic');
    }
  }
  if (recentSemantic.isNotEmpty) {
    buffer.write('\n语义相关记忆：');
    for (final semantic in recentSemantic) {
      buffer.write('\n- $semantic');
    }
  }
  return buffer.toString();
}
