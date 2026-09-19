/// EmbeddingService — 远端 embedding 编排深模块（VR-06）。
///
/// 协议表面小（构造 + 三个 public 入口），编排语义集中于此：
/// - [semanticSearch]：enabled + 配置齐 门 → 懒补嵌兜底 → 查询文本嵌入 →
///   同指纹向量余弦 ≥ [kSemanticRecallMinSimilarity]（VR-03 常量）→ 降序
///   top-k [kSemanticTopK] → 回读 `memory_entries.content` → 命中入
///   SemanticHits 队列（VR-05 CRUD 复用）；任一失败降级空（不抛，不阻断
///   主回复）。
/// - [backfillPending]：缺向量 / 脏 / 指纹过期的条目批量补嵌，单批 ≤
///   [kEmbeddingMaxBatch]（SR-18，超限拒绝且不部分出库）；指纹变更
///   （库中 model ≠ 当前配置）→ 先清旧指纹向量再补（spec D2，不混语义
///   空间）；幂等（重复调用不重复嵌入已有向量）。
/// - [buildClusterInput]：persona_fact 向量两两余弦 ≥
///   [kClusterSimilarityThreshold]（VR-03 常量）并查集分组 ≥2（引用
///   [clusterSimilar] 纯函数）；失败降级空列表。
///
/// 依赖注入：
/// - [resolveConfig]：装配层提供的配置解析闭包（VR-01 getter +
///   [validateEmbeddingBaseUrl] 组装语义，见 app.dart 装配腿）；
/// - [clientFactory]：EmbeddingClient 构造工厂（seam——生产注入
///   OpenAICompatibleEmbeddingClient，测试注入 fake）；
/// - [memoryRepository]：条目 + 向量 + 队列 CRUD。
///
/// 降级契约（SR-16/18）：embedding 域异常（[EmbeddingFailure] /
/// [EmbeddingConfigException]）与意外异常一律收敛为降级结果，debugPrint
/// 只打固定摘要，不含 API Key 与补嵌原文（>10 字符子串）。
library;

// ignore_for_file: prefer_initializing_formals — 构造为公开命名参数（装配
// 点横向一致性），字段私有下划线（项目多文件先例）。

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../data/database/app_database.dart';
import '../../data/database/tables.dart';
import '../../data/repositories/memory_repository.dart';
import '../vector/cluster.dart';
import '../vector/cosine_similarity.dart';
import '../../utils/float32_codec.dart';
import 'embedding_client.dart';
import 'embedding_config.dart';

/// 单批补嵌上限（SR-18：≤20 条；超限整批拒绝，不部分出库）。
const int kEmbeddingMaxBatch = 20;

/// 语义检索 top-k（spec D2：取余弦最高的前 5 条）。
const int kSemanticTopK = 5;

/// 远端 embedding 编排服务（懒补嵌 / 语义检索 / 聚类输入）。
///
/// 全部 public 方法不抛 embedding 域异常，统一收敛为降级结果；并发调用
/// 依赖 upsert 幂等兜底（不加密锁，见类 docstring）。
class EmbeddingService {
  /// 创建编排服务。
  ///
  /// - [memoryRepository]：条目 / 向量 / 队列 CRUD（VR-05）唯一数据入口；
  /// - [resolveConfig]：装配层注入的配置解析（enabled / apiKey / baseUrl /
  ///   model），每次操作解析（对齐「每请求读取」先例，设置变更即生效）；
  /// - [clientFactory]：按已解析配置构造 [EmbeddingClient]（seam）。
  EmbeddingService({
    required MemoryRepository memoryRepository,
    required Future<EmbeddingEndpointConfig> Function() resolveConfig,
    required EmbeddingClient Function(EmbeddingEndpointConfig config)
    clientFactory,
  }) : _memory = memoryRepository,
       _resolveConfig = resolveConfig,
       _clientFactory = clientFactory;

  final MemoryRepository _memory;
  final Future<EmbeddingEndpointConfig> Function() _resolveConfig;
  final EmbeddingClient Function(EmbeddingEndpointConfig) _clientFactory;

  /// 语义检索（spec P3 / 票面验收 1~5）。
  ///
  /// 流程：enabled + key 齐 门 → 懒补嵌兜底（该角色缺向量条目，超限拒绝
  /// 不部分出库）→ 查询文本嵌入 → 与同指纹（model + dims）向量逐条余弦 →
  /// 仅 ≥ [kSemanticRecallMinSimilarity] 参与 → 降序取 [kSemanticTopK] →
  /// 回读 [MemoryEntry]（content 为 memory_entries 现值）→ 命中逐条入
  /// SemanticHits 队列（仓储级去重）。
  ///
  /// 降级：任意 [EmbeddingFailure] / 配置错误 → 返回空列表并 debugPrint
  /// 固定摘要（不含 key 与原文，SR-16），不抛、不阻断主回复。
  Future<List<MemoryEntry>> semanticSearch(
    int characterId,
    String queryText,
  ) async {
    final config = await _resolveConfigSafely();
    if (!_usable(config)) {
      return const <MemoryEntry>[];
    }
    await _backfill(characterId: characterId, limit: kEmbeddingMaxBatch);
    final queryVectors = await _embedSafely(config!, [queryText]);
    if (queryVectors == null || queryVectors.isEmpty) {
      return const <MemoryEntry>[];
    }
    final query = queryVectors.first;
    final rows = await _memory.listEmbeddingsByCharacter(
      characterId,
      model: config.model,
      dims: query.dims,
    );
    if (rows.isEmpty) {
      return const <MemoryEntry>[];
    }
    final entryById = <int, MemoryEntry>{
      for (final entry in await _memory.listEntries(characterId))
        entry.id: entry,
    };
    final scored = <(double, EmbeddingEntry)>[];
    for (final row in rows) {
      final vector = _tryUnpack(row.vector);
      if (vector == null) {
        continue;
      }
      final similarity = cosineSimilarity(query.values, vector);
      if (similarity == null || similarity < kSemanticRecallMinSimilarity) {
        continue;
      }
      scored.add((similarity, row));
    }
    scored.sort((a, b) {
      final bySimilarity = b.$1.compareTo(a.$1);
      // 同余弦按入嵌序（id 升序）稳定输出。
      return bySimilarity != 0 ? bySimilarity : a.$2.id.compareTo(b.$2.id);
    });
    final results = <MemoryEntry>[];
    for (final (_, row) in scored.take(kSemanticTopK)) {
      final entry = entryById[row.entryId];
      if (entry == null) {
        continue; // 条目已删而向量残留 → 跳过（向量级联由仓储自管）。
      }
      results.add(entry);
      await _enqueueSafely(
        characterId: characterId,
        entry: entry,
        query: queryText,
      );
    }
    return results;
  }

  /// 批量补嵌（spec D4 / 票面验收 2/4/6）：该角色缺向量 / 指纹过期的条目。
  ///
  /// - [limit] 缺省 [kEmbeddingMaxBatch]；[limit] > 上限 → 整批拒绝返回 0；
  /// - 待补量 > [limit] → 整批拒绝返回 0（SR-18 不部分出库）；
  /// - 指纹变更（库中该角色向量行 model ≠ 当前配置 model）→ 先清范围内
  ///   旧指纹向量再补（spec D2）；
  /// - 幂等：已有向量条目不重复嵌入；重复调用待补为 0 → 返回 0 零请求；
  /// - 失败：任何 [EmbeddingFailure] → 返回 0（计数 0），不抛。
  /// 返回成功补嵌的条数。
  Future<int> backfillPending(
    int characterId, {
    int limit = kEmbeddingMaxBatch,
  }) {
    return _backfill(characterId: characterId, limit: limit);
  }

  /// 人格演化聚类输入（spec D5 / 票面验收 7）。
  ///
  /// 流程：enabled 门 → 懒补嵌（scope = persona_fact）→ 取该角色
  /// persona_fact 的当前指纹向量 → 两两余弦 ≥ [kClusterSimilarityThreshold]
  /// 并查集分组（引用 [clusterSimilar]，VR-03）→ 仅输出成员 ≥2 的分组，
  /// 回读为 [MemoryEntry]。
  ///
  /// 降级：disabled / 任一 persona_fact 缺向量 / 补嵌失败 / 配置错误 →
  /// 空列表（不抛）。
  Future<List<List<MemoryEntry>>> buildClusterInput(int characterId) async {
    final config = await _resolveConfigSafely();
    if (!_usable(config)) {
      return const <List<MemoryEntry>>[];
    }
    await _backfill(
      characterId: characterId,
      limit: kEmbeddingMaxBatch,
      kind: MemoryKind.personaFact,
    );
    final facts = await _memory.listPersonaFacts(characterId);
    if (facts.isEmpty) {
      return const <List<MemoryEntry>>[];
    }
    final rows = await _memory.listEmbeddingsByCharacter(
      characterId,
      model: config!.model,
    );
    final vectorByEntryId = <int, List<double>>{};
    for (final row in rows) {
      final vector = _tryUnpack(row.vector);
      if (vector != null) {
        vectorByEntryId[row.entryId] = vector;
      }
    }
    final texts = <String>[];
    final vectors = <List<double>>[];
    for (final fact in facts) {
      final vector = vectorByEntryId[fact.id];
      if (vector == null) {
        return const <List<MemoryEntry>>[]; // 缺向量 → 降级空（验收 7）。
      }
      texts.add(fact.content);
      vectors.add(vector);
    }
    final groups = clusterSimilar(
      texts: texts,
      vectors: vectors,
      threshold: kClusterSimilarityThreshold,
    );
    if (groups.isEmpty) {
      return const <List<MemoryEntry>>[];
    }
    // persona_fact content 由反思链精确字符串去重（spec 锚点），此处按
    // content 回引用同序分组；重复 content（违背前置）时映射到任一语义
    // 等价的同内容条目，可接受。
    final entryByContent = <String, MemoryEntry>{
      for (final fact in facts) fact.content: fact,
    };
    return [
      for (final group in groups)
        [for (final content in group) entryByContent[content]!],
    ];
  }

  // ── 私有编排核心 ──

  /// 补嵌核心：配置门 → 上限校验 → 指纹变更清理 → 待补计算 → 批量嵌入。
  ///
  /// [kind] 非空时只补该类型条目（聚类 scope = persona_fact），指纹变更
  /// 清理也只作用于该 scope 的向量行（检索全量路径会自愈清全量）。
  Future<int> _backfill({
    required int characterId,
    required int limit,
    MemoryKind? kind,
  }) async {
    final config = await _resolveConfigSafely();
    if (!_usable(config)) {
      return 0;
    }
    if (limit > kEmbeddingMaxBatch) {
      debugPrint(
        'embedding 补嵌上限违规拒绝（单批 ≤$kEmbeddingMaxBatch，SR-18）: '
        'limit=$limit',
      );
      return 0;
    }
    final entries = await _memory.listEntries(characterId, kind: kind);
    if (entries.isEmpty) {
      return 0;
    }
    final entriesInScope = entries.map((entry) => entry.id).toSet();
    var existing = await _memory.listEmbeddingsByCharacter(characterId);
    final staleRows = existing
        .where(
          (row) =>
              row.model != config!.model &&
              entriesInScope.contains(row.entryId),
        )
        .toList();
    if (staleRows.isNotEmpty) {
      // 指纹变更：清该角色旧指纹向量再补，不混语义空间（spec D2）。
      for (final row in staleRows) {
        await _memory.deleteEmbeddingByEntryId(row.entryId);
      }
      existing = await _memory.listEmbeddingsByCharacter(characterId);
    }
    final embeddedEntryIds = existing.map((row) => row.entryId).toSet();
    final pending = entries
        .where((entry) => !embeddedEntryIds.contains(entry.id))
        .toList();
    if (pending.isEmpty) {
      return 0; // 幂等：无待补。
    }
    if (pending.length > limit) {
      debugPrint(
        'embedding 补嵌待补超限拒绝（单批 ≤$limit，SR-18 不部分出库）: '
        '${pending.length} 条待补',
      );
      return 0;
    }
    final vectors = await _embedSafely(config!, [
      for (final entry in pending) entry.content,
    ]);
    if (vectors == null) {
      return 0; // 失败降级已记录摘要日志。
    }
    for (var i = 0; i < pending.length; i++) {
      await _memory.upsertEmbedding(
        characterId: characterId,
        entryId: pending[i].id,
        content: pending[i].content,
        vector: vectors[i].values,
        model: config.model,
        dims: vectors[i].dims,
      );
    }
    return pending.length;
  }

  /// 配置解析 + 降级收敛：异常（含 VR-01 [EmbeddingConfigException]）→
  /// null + debugPrint 固定摘要（不含 key/原文，SR-16）。
  Future<EmbeddingEndpointConfig?> _resolveConfigSafely() async {
    try {
      return await _resolveConfig();
    } catch (e) {
      debugPrint('embedding 配置解析失败（${e.runtimeType}），本次降级');
      return null;
    }
  }

  /// 嵌入请求 + 降级收敛：失败 → null（debugPrint 固定摘要，不含 key/原文）。
  Future<List<EmbeddingVector>?> _embedSafely(
    EmbeddingEndpointConfig config,
    List<String> texts,
  ) async {
    if (texts.isEmpty) {
      return const <EmbeddingVector>[];
    }
    final client = _clientFactory(config);
    try {
      return await client.embed(texts);
    } on EmbeddingFailure catch (e) {
      debugPrint('embedding 请求降级（SR-16 摘要）：$e');
      return null;
    } catch (e) {
      debugPrint('embedding 请求意外失败（${e.runtimeType}），本次降级');
      return null;
    }
  }

  /// 语义命中入队 + 降级收敛（队列写失败不阻断检索结果）。
  Future<void> _enqueueSafely({
    required int characterId,
    required MemoryEntry entry,
    required String query,
  }) async {
    try {
      await _memory.enqueueSemanticHit(
        characterId: characterId,
        entryId: entry.id,
        query: query,
      );
    } catch (e) {
      debugPrint('embedding 命中入队失败（${e.runtimeType}），不阻断检索');
    }
  }

  /// blob 解包 + 长度守卫降级（非法长度 → null，跳过该行不参与比较）。
  List<double>? _tryUnpack(Uint8List bytes) {
    try {
      return unpackFloat32(bytes);
    } on FormatException {
      return null;
    }
  }

  /// 可用性门：配置非空且 enabled + key 非空（SR-19 默认关 / 验收 1）。
  bool _usable(EmbeddingEndpointConfig? config) =>
      config != null && config.enabled && config.apiKey.isNotEmpty;
}
