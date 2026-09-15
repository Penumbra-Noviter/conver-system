/// MemoryService — 记忆编排（人机恋板块 AC-02/AC-03）。
///
/// 深模块：协议表面仅 [buildInjection] / [applyAssistantReply] 两个方法，实现
/// 内聚「记忆注入组装」与「回复指令解析落库」两条链路，复用纯函数
/// （memory_commands / memory_prompt）与 [MemoryRepository]。
///
/// 语义锚点：ADR-0003（prompt 指令驱动记忆，零额外 LLM 调用）+ 逆向对照材料
/// （`.scratch/aiyun-unpack/DYNAMIC_UNPACK_REPORT.md` 指令系统，仅本地对照学习）。
///
/// - [buildInjection]：每轮组装时调用，产出追加进 system 的消息（记忆三模式
///   指令模板 + 人格事实全量 + 近期情景记忆），供 [ChatService] 注入；
/// - [applyAssistantReply]：完整 assistant 回复落库前调用，解析 `<add:>` /
///   `<persona:>` / `<search:>` 标签，add/persona 落库、search 本地检索，返回
///   剥离标签后的展示文本（防标签泄漏进聊天 UI）。
library;

import '../../data/database/tables.dart' show MemoryKind;
import '../../data/repositories/memory_repository.dart';
import '../llm/llm_provider.dart' show LlmMessage;
import 'memory_commands.dart';
import 'memory_prompt.dart';

/// [MemoryService.applyAssistantReply] 的产出：剥离标签后的展示文本 + 落库计数。
class MemoryApplyResult {
  /// 构造应用结果。
  const MemoryApplyResult({
    required this.displayContent,
    required this.episodicAdded,
    required this.personaAdded,
    required this.searchCount,
  });

  /// 剥离记忆标签后的展示文本（落库进 messages.content）。
  final String displayContent;

  /// 落库的情景记忆条数（`<add:>`）。
  final int episodicAdded;

  /// 落库的人格事实条数（`<persona:>`）。
  final int personaAdded;

  /// 检索信号条数（`<search:>`，MVP 阶段仅本地检索、不回填当前回复）。
  final int searchCount;
}

/// 记忆编排服务 — 注入组装 + 指令解析落库。
class MemoryService {
  /// 构造服务；[memoryRepository] 为记忆数据访问层。
  MemoryService(this._memoryRepository);

  final MemoryRepository _memoryRepository;

  /// 组装记忆注入消息（每轮调用）：记忆三模式指令模板 + 记忆库内容。
  ///
  /// [mode] 为记忆三模式（strong / medium / weak），决定指令模板的「记录积极
  /// 性」措辞（由调用方从设置读取）。人格事实全量注入（抗 OOC）、近期情景记忆
  /// 少数次注入（缺省最近 10 条）；两者皆空时只注入指令模板。
  Future<List<LlmMessage>> buildInjection(
    int characterId, {
    MemoryPromptMode mode = MemoryPromptMode.medium,
  }) async {
    final facts = await _memoryRepository.listPersonaFacts(characterId);
    final episodic = await _memoryRepository.listRecentEpisodic(characterId);
    final library = buildMemoryLibrarySection(
      personaFacts: [for (final f in facts) f.content],
      recentEpisodic: [for (final e in episodic) e.content],
    );
    return [
      LlmMessage(role: 'system', content: memorySystemPrompt(mode)),
      if (library.isNotEmpty) LlmMessage(role: 'system', content: library),
    ];
  }

  /// 解析 assistant 回复全文的记忆标签并落库，返回剥离后的展示文本。
  ///
  /// - `<add:内容>` → 落库 episodic；`<persona:内容>` → 落库 persona_fact；
  /// - `<search:关键词>` → 本地检索（`searchEntries`，MVP 不回填当前回复，
  ///   下一轮 [buildInjection] 已全量注入人格事实 + 近期经历）；
  /// - 无标签 → 原样返回，零落库。
  Future<MemoryApplyResult> applyAssistantReply(
    int characterId,
    String reply,
  ) async {
    final parsed = parseMemoryCommands(reply);
    var episodicAdded = 0;
    var personaAdded = 0;

    for (final content in parsed.addEntries) {
      await _memoryRepository.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: content,
      );
      episodicAdded++;
    }
    for (final content in parsed.personaEntries) {
      await _memoryRepository.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: content,
      );
      personaAdded++;
    }
    for (final query in parsed.searchQueries) {
      await _memoryRepository.searchEntries(characterId, query);
    }

    return MemoryApplyResult(
      displayContent: parsed.displayContent,
      episodicAdded: episodicAdded,
      personaAdded: personaAdded,
      searchCount: parsed.searchQueries.length,
    );
  }
}
