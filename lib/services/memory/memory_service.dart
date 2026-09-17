/// MemoryService — 记忆编排（人机恋板块 AC-02/AC-03 + VR-07 混合检索）。
///
/// 深模块：协议表面仅 [buildInjection] / [applyAssistantReply] 两个方法，实现
/// 内聚「记忆注入组装」与「回复指令解析落库」两条链路，复用纯函数
/// （memory_commands / memory_prompt）与 [MemoryRepository]。
///
/// VR-07（阶段 3）：注入可空 [EmbeddingService] seam 实现 `<search:>` 混合
/// 检索——关键词 LIKE 零命中时经语义兜底（semanticSearch 内部含 enabled 门 +
/// 懒补嵌 + 命中入队 + 失败降级），命中延迟一轮经 SemanticHits 队列注入；
/// null = 关键词-only 原行为（既有构造调用零破坏）。
///
/// 语义锚点：ADR-0003（prompt 指令驱动记忆，零额外 LLM 调用）+ 逆向对照材料
/// （`.scratch/aiyun-unpack/DYNAMIC_UNPACK_REPORT.md` 指令系统，仅本地对照学习）。
///
/// - [buildInjection]：每轮组装时调用，产出追加进 system 的消息（记忆三模式
///   指令模板 + 人格事实全量 + 近期情景记忆 + 未消费语义命中≤3），供
///   [ChatService] 注入；语义命中断言经队列消费删除（注入后不再出现）；
/// - [applyAssistantReply]：完整 assistant 回复落库前调用，解析 `<add:>` /
///   `<persona:>` / `<search:>` 标签，add/persona 落库、search 本地检索 +
///   零命中时语义兜底，返回剥离标签后的展示文本（防标签泄漏进聊天 UI）。
library;

// ignore_for_file: prefer_initializing_formals — 构造为公开命名参数（装配点
// 横向一致性），字段私有下划线（项目多文件先例，embedding_service 同款）。

import 'package:flutter/foundation.dart' show debugPrint;

import '../../data/database/app_database.dart' show SemanticHit;
import '../../data/database/tables.dart' show MemoryKind;
import '../../data/repositories/memory_repository.dart';
import '../embedding/embedding_service.dart';
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

  /// 检索信号条数（`<search:>`；MVP 阶段本地检索 + 零命中语义兜底入队，
  /// 不回填当前回复，下一轮 [buildInjection] 注入队列）。
  final int searchCount;
}

/// 记忆编排服务 — 注入组装 + 指令解析落库。
class MemoryService {
  /// 构造服务；[memoryRepository] 为记忆数据访问层，[embeddingService] 为
  /// 可空语义兜底 seam（null = 关键词-only 原行为，阶段 2 零回归）。
  MemoryService(this._memoryRepository, {EmbeddingService? embeddingService})
    : _embeddingService = embeddingService;

  final MemoryRepository _memoryRepository;

  /// 语义兜底 seam（VR-07）；null = 混合检索未启用（关键词-only）。
  final EmbeddingService? _embeddingService;

  /// 组装记忆注入消息（每轮调用）：记忆三模式指令模板 + 记忆库内容。
  ///
  /// [mode] 为记忆三模式（strong / medium / weak），决定指令模板的「记录积极
  /// 性」措辞（由调用方从设置读取）。人格事实全量注入（抗 OOC）、近期情景记忆
  /// 少数次注入（缺省最近 10 条）；未消费语义命中以「语义相关记忆」小节并入
  /// （至多 3 条，注入后消费删除）；全部皆空时只注入指令模板。
  Future<List<LlmMessage>> buildInjection(
    int characterId, {
    MemoryPromptMode mode = MemoryPromptMode.medium,
  }) async {
    final facts = await _memoryRepository.listPersonaFacts(characterId);
    final episodic = await _memoryRepository.listRecentEpisodic(characterId);
    final semantic = await _pendingSemanticContents(characterId);
    final library = buildMemoryLibrarySection(
      personaFacts: [for (final f in facts) f.content],
      recentEpisodic: [for (final e in episodic) e.content],
      recentSemantic: semantic,
    );
    return [
      LlmMessage(role: 'system', content: memorySystemPrompt(mode)),
      if (library.isNotEmpty) LlmMessage(role: 'system', content: library),
    ];
  }

  /// 解析 assistant 回复全文的记忆标签并落库，返回剥离后的展示文本。
  ///
  /// - `<add:内容>` → 落库 episodic；`<persona:内容>` → 落库 persona_fact；
  /// - `<search:关键词>` → 本地检索（`searchEntries`），**零命中**时经
  ///   [EmbeddingService.semanticSearch] 语义兜底（命中入 SemanticHits 队列，
  ///   延迟一轮由 [buildInjection] 注入）；embedding 未启用/失败 → 降级空
  ///   结果，不阻断主回复（阶段 2 原行为）；
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
      final hits = await _memoryRepository.searchEntries(characterId, query);
      if (hits.isEmpty) {
        // 关键词零命中 → 语义兜底（embedding 未启用/失败在服务内降级不抛）。
        await _maybeSemanticFallback(characterId, query);
      }
    }

    return MemoryApplyResult(
      displayContent: parsed.displayContent,
      episodicAdded: episodicAdded,
      personaAdded: personaAdded,
      searchCount: parsed.searchQueries.length,
    );
  }

  // ── VR-07 混合检索私有编排 ──

  /// 语义兜底：关键词零命中时经 [EmbeddingService.semanticSearch] 尝试召回。
  ///
  /// semanticSearch 内部已收敛 enabled 门（未启用零调用）、懒补嵌、命中入队
  /// 与失败降级（不抛）；此处仅防御意外异常（降级 log 不阻断主回复）。
  Future<void> _maybeSemanticFallback(int characterId, String query) async {
    final embeddingService = _embeddingService;
    if (embeddingService == null) {
      return;
    }
    try {
      await embeddingService.semanticSearch(characterId, query);
    } catch (e) {
      debugPrint('语义兜底检索失败，降级空结果: ${e.runtimeType}');
    }
  }

  /// 读取未消费语义命中（≤3 条）并消费删除，返回命中条目内容。
  ///
  /// 队列读失败 → 降级空列表（不阻断注入，无语义小节）；consumed 删除失败 →
  /// 降级 log（队列残留，下次注入幂等重试）。条目已删（entryId 失效）→
  /// 跳过内容但仍消费删除（防僵尸队列滞留）。
  Future<List<String>> _pendingSemanticContents(int characterId) async {
    final List<SemanticHit> pending;
    try {
      pending = await _memoryRepository.listPendingSemanticHits(characterId);
    } catch (e) {
      debugPrint('语义命中队列读取失败，跳过语义小节: ${e.runtimeType}');
      return const <String>[];
    }
    if (pending.isEmpty) {
      return const <String>[];
    }
    final entries = await _memoryRepository.listEntries(characterId);
    final entryById = <int, String>{
      for (final entry in entries) entry.id: entry.content,
    };
    final contents = <String>[];
    for (final hit in pending) {
      final content = entryById[hit.entryId];
      if (content != null) {
        contents.add(content);
      }
      try {
        await _memoryRepository.deleteSemanticHit(hit.id);
      } catch (e) {
        debugPrint('语义命中消费删除失败（留待下次）: ${e.runtimeType}');
      }
    }
    return contents;
  }
}
