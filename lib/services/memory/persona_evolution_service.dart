/// PersonaEvolutionService — 人设演化（人机恋板块 AC-04）。
///
/// 深模块：协议表面仅 [proposeEvolution] / [applyRevision] / [discardRevision]
/// 三个方法，实现「LLM 反思 → PersonaRevisions 版本化快照 → 用户确认闸门回写
/// personality」的人设演化闭环。**不无条件回写** `characters.personality`：反思
/// 结果先落 [PersonaRevisions] 快照，用户确认后才经 [applyRevision] 回写。
///
/// 语义锚点：ADR-0003（人设演化 = 版本化 + 用户确认闸门，防漂移/失控）。
/// [PersonaReflector] 为 LLM 反思 seam（生产装配用 [reflectPersonaWithProvider]
/// 包装 [LLMProvider.generate]，测试注入 fake 返回固定文本），本类零 wire 依赖。
library;

import 'package:drift/drift.dart' show Value;

import '../../data/database/app_database.dart'
    show CharactersCompanion, PersonaRevision;
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/memory_repository.dart';
import '../embedding/embedding_service.dart';
import '../llm/errors.dart' show CharacterNotFoundError;
import '../llm/llm_provider.dart' show LlmMessage, LLMProvider;

/// 人设反思 seam：输入当前人格 + 角色名 + 已沉淀人格事实，产出演化后的人格
/// 设定文本（空串 = 无变化）。生产装配用 [reflectPersonaWithProvider] 包装，
/// 测试注入 fake。
///
/// [similarClusters]（可选，VR-08）：语义近似人格事实的逐组摘要；缺省不传 =
/// 阶段 1 行为。注意 Dart 函数子类型规则：本 typedef 增可选命名形参后，未声明
/// 该形参的既有函数字面量无法直接赋给本类型（需补同名形参声明或经
/// [buildClusteredReflector] 组合），运行时行为不受影响。
typedef PersonaReflector = Future<String> Function({
  required String currentPersonality,
  required String charName,
  required List<String> personaFacts,
  List<String> similarClusters,
});

/// 场景化人设反思器：比 [PersonaReflector] 多带 [characterId] 入参，供装配
/// helper（[buildClusteredReflector]）按角色取聚类输入后调用 inner。
typedef CharacterScopedReflector = Future<String> Function({
  required int characterId,
  required String currentPersonality,
  required String charName,
  required List<String> personaFacts,
});

/// 组装人设演化的反思 prompt 消息（纯函数，可单测）。
///
/// system 教导 LLM 只输出人格正文（无解释/前缀）；user 附当前人格 + 已记录人格
/// 事实，请求输出演化后的人格设定。VR-08：[similarClusters] 非空时在「已记录
/// 人格事实」之后附「语义相近，可能重复」段落，提示 LLM 合并近似事实；空/
/// 缺省不输出该段（阶段 1 行为完全一致）。
List<LlmMessage> buildEvolutionMessages({
  required String currentPersonality,
  required String charName,
  required List<String> personaFacts,
  List<String> similarClusters = const [],
}) {
  final factsBlock = personaFacts.isEmpty
      ? '（暂无已记录人格事实）'
      : personaFacts.map((f) => '- $f').join('\n');
  final clusterBlock = similarClusters.isEmpty
      ? ''
      : '\n\n以下事实语义相近，可能重复：\n'
            '${similarClusters.map((s) => '- $s').join('\n')}';
  return [
    LlmMessage(
      role: 'system',
      content:
          '你是「$charName」的人设演化助手。基于当前人格设定与对话中沉淀的'
          '人格事实，生成一版更完整、连贯、贴合该角色的人格设定文本。'
          '只输出人格设定正文，不要任何解释或前缀。',
    ),
    LlmMessage(
      role: 'user',
      content:
          '当前人格设定：\n$currentPersonality\n\n'
          '已记录人格事实：\n$factsBlock$clusterBlock\n\n'
          '请输出演化后的人格设定：',
    ),
  ];
}

/// 生产装配用的反射实现：组装 prompt 并经 [llm].generate 产出演化人格。
///
/// [model] 为调用模型名（透传 provider）；[similarClusters]（VR-08）透传给
/// [buildEvolutionMessages]，缺省不传 = 阶段 1 prompt。返回 [Future<String>]
/// 与 [PersonaReflector] 签名同形（装配层闭包绑定 llm/model 后传入服务）。
Future<String> reflectPersonaWithProvider({
  required LLMProvider llm,
  required String model,
  required String currentPersonality,
  required String charName,
  required List<String> personaFacts,
  List<String> similarClusters = const [],
}) {
  final messages = buildEvolutionMessages(
    currentPersonality: currentPersonality,
    charName: charName,
    personaFacts: personaFacts,
    similarClusters: similarClusters,
  );
  return llm.generate(messages: messages, model: model);
}

/// 装配 helper（VR-08）：包装 inner 反射器，把相似聚类摘要注入演化 prompt。
///
/// 调用链：`proposeEvolution` → 本 helper 返回的 [CharacterScopedReflector] 经
/// [EmbeddingService.buildClusterInput] 取该角色 persona_fact 相似分组（VR-06，
/// 组内成员为内容原文，组序稳定）→ 每组拼为一条摘要（成员以「；」连接）→
/// 非空时经 [similarClusters] 传给 [inner]。
///
/// 降级契约（复用 VR-06）：聚类不可用 / disabled / 组为空 → [inner] 收到空
/// 列表并原样走无聚类路径，不抛。
CharacterScopedReflector buildClusteredReflector({
  required EmbeddingService embeddingService,
  required Future<String> Function({
    required String currentPersonality,
    required String charName,
    required List<String> personaFacts,
    List<String> similarClusters,
  })
  inner,
}) {
  return ({
    required int characterId,
    required String currentPersonality,
    required String charName,
    required List<String> personaFacts,
  }) async {
    final groups = await embeddingService.buildClusterInput(characterId);
    final similarClusters = [
      for (final group in groups) group.map((entry) => entry.content).join('；'),
    ];
    return inner(
      currentPersonality: currentPersonality,
      charName: charName,
      personaFacts: personaFacts,
      similarClusters: similarClusters,
    );
  };
}

/// 人设演化服务 — LLM 反思 + 版本化快照 + 用户确认闸门。
class PersonaEvolutionService {
  /// 构造服务；[reflector] 为 LLM 反思 seam（测试注入 fake）。
  PersonaEvolutionService({
    required this._characterRepository,
    required this._memoryRepository,
    required this._reflector,
  });

  final CharacterRepository _characterRepository;
  final MemoryRepository _memoryRepository;
  final PersonaReflector _reflector;

  /// 提出一次人设演化：LLM 反思产出新人格 → 落 [PersonaRevisions] 快照。
  ///
  /// **不回写** `characters.personality`（等待用户确认）。新人格为空或与当前
  /// 人格相同 → 返回 null（无变化，不落快照）。角色不存在 → 抛
  /// [CharacterNotFoundError]。
  Future<PersonaRevision?> proposeEvolution(int characterId) async {
    final character = await _characterRepository.getCharacter(characterId);
    if (character == null) {
      throw CharacterNotFoundError(characterId);
    }
    final facts = await _memoryRepository.listPersonaFacts(characterId);
    final newPersonality = (await _reflector(
      currentPersonality: character.personality,
      charName: character.name,
      personaFacts: [for (final f in facts) f.content],
    )).trim();
    if (newPersonality.isEmpty || newPersonality == character.personality) {
      return null;
    }
    return _memoryRepository.addRevision(
      characterId: characterId,
      personalitySnapshot: newPersonality,
      reason: 'AI 反思演化',
    );
  }

  /// 应用（确认）一条人设演化：回写 `characters.personality` 为该版本快照。
  ///
  /// 版本不存在 → 返回 false（零副作用）；成功 → 返回 true。快照保留作历史。
  Future<bool> applyRevision(int revisionId) async {
    final revision = await _memoryRepository.getRevision(revisionId);
    if (revision == null) {
      return false;
    }
    await _characterRepository.updateCharacter(
      revision.characterId,
      CharactersCompanion(personality: Value(revision.personalitySnapshot)),
    );
    return true;
  }

  /// 拒绝（丢弃）一条人设演化：删除该版本快照，不回写 personality。
  ///
  /// 版本不存在 → 返回 false；成功 → 返回 true。
  Future<bool> discardRevision(int revisionId) {
    return _memoryRepository.deleteRevision(revisionId);
  }
}
