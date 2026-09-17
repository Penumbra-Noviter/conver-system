/// VR-06 EmbeddingService 编排验收测试。
///
/// seam = [EmbeddingService] 构造三参（resolveConfig / clientFactory /
/// memoryRepository）+ 三个 public 编排入口。fake [EmbeddingClient] 记录
/// embed 调用并返回预设向量（缺失文本 → StateError，防静默遗漏）；配置
/// 来自真实 SettingsRepository 内存形态（InMemorySecretStore），enabled /
/// key / base_url / model 判定走真实 getter 与 validateEmbeddingBaseUrl。
///
/// 验收映射（票面验收 1~7 逐条；验收 8 集成动作无 key，见文件尾注释）：
/// 1  disabled / key 空 → 空 + 零 API 调用（用例 1/2）
/// 2  缺向量 → 懒补嵌触发；超限拒绝且不部分出库（用例 3/6）
/// 3  余弦降序 top-k 5 + 均 ≥0.5 + dims 指纹过滤（用例 3/4）
/// 4  指纹变更（model 不同）→ 旧向量清空后重嵌（用例 5）
/// 5  EmbeddingFailure → 不抛、空结果/计数 0、日志不含 key/原文（用例 7/8）
/// 6  单批 ≤20；重复调用幂等（用例 6）
/// 7  聚类 ≥2 分组；缺向量/API 失败 → 空（用例 9/10）
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/memory_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/embedding/embedding_client.dart';
import 'package:conver_system_mobile/services/embedding/embedding_config.dart';
import 'package:conver_system_mobile/services/embedding/embedding_service.dart';
import 'package:conver_system_mobile/services/vector/cosine_similarity.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';

/// 记录调用并返回预设向量的 fake [EmbeddingClient]（seam 注入）。
class _FakeEmbeddingClient implements EmbeddingClient {
  int embedCalls = 0;
  final List<List<String>> calls = [];

  /// 置位后每次 embed 抛该失败（模拟 API 失败）。
  EmbeddingFailure? failure;

  /// 从第几次调用起抛 [failure]（1-based；null = 不按次数触发）。
  int? failOnCall;

  /// 文本 → 向量预设；缺失文本抛 StateError（防测试静默遗漏预设）。
  final Map<String, List<double>> vectorsByText = {};

  @override
  Future<List<EmbeddingVector>> embed(List<String> texts) async {
    embedCalls += 1;
    calls.add(List<String>.unmodifiable(texts));
    if (failOnCall != null && embedCalls >= failOnCall!) {
      throw failure ??
          const EmbeddingFailure(
            EmbeddingFailureKind.network,
            'embedding 网络失败（测试注入）',
          );
    }
    if (failure != null) {
      throw failure!;
    }
    return [
      for (final text in texts)
        EmbeddingVector(
          vectorsByText[text] ?? (throw StateError('测试未预设文本向量: $text')),
        ),
    ];
  }
}

void main() {
  late AppDatabase db;
  late MemoryRepository memory;
  late SettingsRepository settings;
  late _FakeEmbeddingClient fake;
  late EmbeddingService service;

  /// 真实 SettingsRepository 内存形态的配置解析（复刻装配腿组装语义：
  /// enabled 门 → key → base_url 校验 → model）。
  Future<EmbeddingEndpointConfig> resolveConfig() async {
    final enabled = await settings.embeddingEnabled;
    if (!enabled) {
      return EmbeddingEndpointConfig(
        enabled: false,
        apiKey: '',
        baseUrl: null,
        model: SettingsRepository.defaultEmbeddingModel,
      );
    }
    return EmbeddingEndpointConfig(
      enabled: true,
      apiKey: await settings.embeddingApiKey,
      baseUrl: validateEmbeddingBaseUrl(await settings.embeddingBaseUrl),
      model: await settings.embeddingModel,
    );
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    memory = MemoryRepository(db);
    settings = SettingsRepository(
      database: db,
      secretStore: InMemorySecretStore(),
    );
    fake = _FakeEmbeddingClient();
    service = EmbeddingService(
      memoryRepository: memory,
      resolveConfig: resolveConfig,
      clientFactory: (_) => fake,
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 建角色并返回 id（EmbeddingEntries/SemanticHits 均 FK → characters）。
  Future<int> seedCharacter({String name = '艾莉亚'}) async {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return character.id;
  }

  /// 建 n 条记忆条目（kind 可指定），返回按创建序的条目 id 列表。
  Future<List<int>> seedEntries(
    int characterId,
    int count, {
    MemoryKind kind = MemoryKind.episodic,
  }) async {
    final ids = <int>[];
    for (var i = 0; i < count; i++) {
      final entry = await memory.createEntry(
        characterId: characterId,
        kind: kind,
        content: '记忆内容$i',
      );
      ids.add(entry.id);
    }
    return ids;
  }

  /// 启用 embedding 并注入 key（真实 settings 内存形态）。
  Future<void> enableEmbedding({String key = 'sk-test-secret-1234'}) async {
    await settings.setMany({'embedding_enabled': 'true'});
    await settings.setMany({'embedding_api_key': key});
  }

  /// 检索语义预设：query 与六条条目向量（按 `记忆内容$i` 建条目的 content
  /// 对齐）。向量取单位圆二维方向 + 两个零维（dims=4）——余弦只由 x
  /// 分量决定（点积 = x，范数 = 1），故 cos(i=0)=1.0、i=1≈0.707、
  /// i=2=0.4、i=3=0.5、i=4=0.6、i=5≈0.55 精确可控。
  void seedRecallVectors(List<int> entryIds) {
    fake.vectorsByText['今天心情如何'] = const [1.0, 0.0, 0.0, 0.0];
    const presets = <List<double>>[
      [1.0, 0.0, 0.0, 0.0],
      [0.7071, 0.7071, 0.0, 0.0],
      [0.4, 0.9165, 0.0, 0.0],
      [0.5, 0.866, 0.0, 0.0],
      [0.6, 0.8, 0.0, 0.0],
      [0.55, 0.835, 0.0, 0.0],
    ];
    for (var i = 0; i < entryIds.length; i++) {
      fake.vectorsByText['记忆内容$i'] = presets[i];
    }
  }

  group('语义检索（验收 1/2/3/5）', () {
    test('验收 1：embedding_enabled=false → 直接返回空，零 API 调用', () async {
      final characterId = await seedCharacter();
      await seedEntries(characterId, 3);

      final results = await service.semanticSearch(characterId, '任意查询');

      expect(results, isEmpty);
      expect(fake.embedCalls, 0, reason: 'disabled 时不得发起任何 embedding 请求');
    });

    test('验收 1：enabled 但 key 空 → 直接返回空，零 API 调用', () async {
      final characterId = await seedCharacter();
      await seedEntries(characterId, 2);
      await settings.setMany({'embedding_enabled': 'true'});
      // 不写 key：SecretStore 槽链为空。

      final results = await service.semanticSearch(characterId, '任意查询');

      expect(results, isEmpty);
      expect(fake.embedCalls, 0, reason: 'key 未配置时不得发起任何 embedding 请求');
    });

    test('验收 2+3：缺向量先懒补嵌；命中按余弦降序 top-5 且均 ≥0.5，结果入队', () async {
      final characterId = await seedCharacter();
      final entryIds = await seedEntries(characterId, 6);
      await enableEmbedding();
      seedRecallVectors(entryIds);

      final results = await service.semanticSearch(characterId, '今天心情如何');

      // 余弦降序：A(1.0) B(0.707) E(0.6) F(0.55) D(0.5)；C(0.4) 被阈值排除。
      expect(results.map((e) => e.id).toList(), [
        entryIds[0],
        entryIds[1],
        entryIds[4],
        entryIds[5],
        entryIds[3],
      ]);
      for (final entry in results) {
        expect(
          entry.content,
          isNotEmpty,
          reason: '结果必须回读 memory_entries.content（非向量快照）',
        );
      }
      // 补嵌 1 批（6 条）+ 查询文本 1 次 = 2 次调用。
      expect(fake.embedCalls, 2);
      // 命中全部入 SemanticHits 队列（VR-05 CRUD 复用）。
      final pending = await memory.listPendingSemanticHits(
        characterId,
        limit: 10,
      );
      expect(
        pending.map((h) => h.entryId).toSet(),
        results.map((e) => e.id).toSet(),
      );
      expect(pending.every((h) => h.query == '今天心情如何'), isTrue);
    });

    test('验收 3：检索再次执行不重复补嵌（幂等）且结果稳定', () async {
      final characterId = await seedCharacter();
      final entryIds = await seedEntries(characterId, 3);
      await enableEmbedding();
      seedRecallVectors(entryIds);

      final first = await service.semanticSearch(characterId, '今天心情如何');
      final second = await service.semanticSearch(characterId, '今天心情如何');

      expect(first.map((e) => e.id), second.map((e) => e.id));
      // 首次 = 补嵌 1 + query 1；二次 = 补嵌 0（已有向量）+ query 1。
      expect(fake.embedCalls, 3);
      // 入队去重：同一 (characterId, entryId) 不重复入队（VR-05 仓储级）；
      // 3 条条目中 A/B 命中（C 余弦 0.4 被阈值排除）→ 队列恒 2 行。
      final pending = await memory.listPendingSemanticHits(
        characterId,
        limit: 10,
      );
      expect(pending.length, 2);
    });

    test('验收 3：data[].embedding 维度与指纹不符的向量不参与比较', () async {
      final characterId = await seedCharacter();
      final entryIds = await seedEntries(characterId, 3);
      await enableEmbedding();
      // 预置一条旧 dims（=3）向量，指纹与 query（dims=4）不符。
      final staleEntry = await memory.createEntry(
        characterId: characterId,
        kind: MemoryKind.episodic,
        content: '旧维度条目',
      );
      await memory.upsertEmbedding(
        characterId: characterId,
        entryId: staleEntry.id,
        content: staleEntry.content,
        vector: const [1.0, 0.0, 0.0],
        model: 'text-embedding-3-small',
        dims: 3,
      );
      // 三条正常条目走懒补嵌（dims=4）。
      fake.vectorsByText
        ..['今天心情如何'] = const [1.0, 0.0, 0.0, 0.0]
        ..['记忆内容0'] = const [1.0, 0.0, 0.0, 0.0]
        ..['记忆内容1'] = const [0.7071, 0.7071, 0.0, 0.0]
        ..['记忆内容2'] = const [0.4, 0.9165, 0.0, 0.0];

      final results = await service.semanticSearch(characterId, '今天心情如何');

      expect(results.map((e) => e.id).toList(), [
        entryIds[0],
        entryIds[1],
      ], reason: 'dims=3 的旧向量行被指纹过滤，不得进入比较');
      expect(fake.calls.singleWhere((c) => c.length == 1).single, '今天心情如何');
    });

    test('验收 5：EmbeddingFailure（rateLimit）→ 不抛、空结果、日志不含 key/原文', () async {
      final characterId = await seedCharacter();
      await seedEntries(characterId, 2);
      await enableEmbedding();
      const longText = '这是一个超过十个字符的补嵌原文内容用于断言不外泄';
      fake.vectorsByText['今天心情如何'] = const [1.0, 0.0, 0.0, 0.0];
      // 补嵌的原文（记忆内容）也属于 SR-16 保护范围，这里显式断言。
      fake.failure = const EmbeddingFailure(
        EmbeddingFailureKind.rateLimit,
        'embedding 触发限流（测试注入）',
      );
      final captured = <String>[];
      final original = debugPrint;
      debugPrint = (message, {int? wrapWidth}) {
        captured.add(message ?? '');
      };
      addTearDown(() => debugPrint = original);

      final results = await service.semanticSearch(characterId, '今天心情如何');

      expect(results, isEmpty);
      final logs = captured.join('\n');
      expect(
        logs,
        isNot(contains('sk-test-secret-1234')),
        reason: 'SR-16：日志不得含 key',
      );
      expect(
        logs,
        isNot(contains(longText)),
        reason: 'SR-16：日志不得含补嵌原文（>10 字符子串）',
      );
    });
  });

  group('懒补嵌（验收 2/4/6）', () {
    test('验收 2+6：backfillPending 待补超限拒绝，不部分出库', () async {
      final characterId = await seedCharacter();
      final entryIds = await seedEntries(characterId, 25);
      await enableEmbedding();
      for (var i = 0; i < entryIds.length; i++) {
        fake.vectorsByText['记忆内容$i'] = [1.0, 0.0, 0.0, 0.0];
      }

      final count = await service.backfillPending(characterId);

      expect(count, 0, reason: '25 > 20 上限 → 整批拒绝');
      expect(fake.embedCalls, 0, reason: '超限拒绝不得发起任何 embedding 请求');
      final rows = await memory.listEmbeddingsByCharacter(characterId);
      expect(rows, isEmpty, reason: '超限拒绝不得部分出库（前 20 条也不得嵌入）');
    });

    test('验收 2+6：显式 limit 超上限（>20）拒绝；20 条内正常补嵌且幂等', () async {
      final characterId = await seedCharacter();
      final entryIds = await seedEntries(characterId, 20);
      await enableEmbedding();
      for (var i = 0; i < entryIds.length; i++) {
        fake.vectorsByText['记忆内容$i'] = [1.0, 0.0, 0.0, 0.0];
      }

      expect(await service.backfillPending(characterId, limit: 21), 0);
      expect(fake.embedCalls, 0);

      final first = await service.backfillPending(characterId);
      expect(first, 20);
      expect(fake.embedCalls, 1);

      final second = await service.backfillPending(characterId);
      expect(second, 0, reason: '幂等：已有向量不重复嵌入');
      expect(fake.embedCalls, 1, reason: '幂等：重复调用零 embed 请求');
      final rows = await memory.listEmbeddingsByCharacter(characterId);
      expect(rows.length, 20);
      expect(rows.every((r) => r.dims == 4 && r.vector.isNotEmpty), isTrue);
    });

    test('验收 4：指纹变更（model 不同）→ 旧向量清空后按新指纹重嵌', () async {
      final characterId = await seedCharacter();
      final entryIds = await seedEntries(characterId, 2);
      await enableEmbedding();
      // 预置旧 model 向量（内容 hash 与条目相同，模拟旧指纹残留）。
      await memory.upsertEmbedding(
        characterId: characterId,
        entryId: entryIds[0],
        content: '记忆内容0',
        vector: const [1.0, 0.0, 0.0, 0.0],
        model: 'old-model',
        dims: 4,
      );
      await memory.upsertEmbedding(
        characterId: characterId,
        entryId: entryIds[1],
        content: '记忆内容1',
        vector: const [1.0, 0.0, 0.0, 0.0],
        model: 'old-model',
        dims: 4,
      );
      fake.vectorsByText['记忆内容0'] = const [1.0, 0.0, 0.0, 0.0];
      fake.vectorsByText['记忆内容1'] = const [0.5, 0.5, 0.0, 0.0];

      await service.backfillPending(characterId);

      final rows = await memory.listEmbeddingsByCharacter(characterId);
      expect(rows, hasLength(2));
      expect(
        rows.every((r) => r.model == 'text-embedding-3-small'),
        isTrue,
        reason: '旧指纹向量被清空，全部按当前指纹重嵌',
      );
    });

    test('验收 5：backfillPending API 失败 → 计数 0、不抛、日志无原文', () async {
      final characterId = await seedCharacter();
      await seedEntries(characterId, 2);
      await enableEmbedding();
      fake.failure = const EmbeddingFailure(
        EmbeddingFailureKind.timeout,
        'embedding 请求超时（测试注入）',
      );
      final captured = <String>[];
      final original = debugPrint;
      debugPrint = (message, {int? wrapWidth}) {
        captured.add(message ?? '');
      };
      addTearDown(() => debugPrint = original);

      final count = await service.backfillPending(characterId);

      expect(count, 0);
      expect(captured.join('\n'), isNot(contains('记忆内容')));
    });
  });

  group('聚类输入（验收 7）', () {
    test('两两余弦 ≥0.75 并查集分组，仅输出 ≥2 条分组（回读 MemoryEntry）', () async {
      final characterId = await seedCharacter();
      final f1 = await memory.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '喜欢在河边散步',
      );
      final f2 = await memory.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '常去河边看日落',
      );
      final f3 = await memory.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '不爱吃香菜',
      );
      await enableEmbedding();
      fake.vectorsByText
        ..['喜欢在河边散步'] = const [1.0, 0.0, 0.0, 0.0]
        ..['常去河边看日落'] = const [0.8, 0.6, 0.0, 0.0]
        ..['不爱吃香菜'] = const [0.0, 1.0, 0.0, 0.0];

      final groups = await service.buildClusterInput(characterId);

      expect(groups, hasLength(1));
      expect(groups.single.map((e) => e.id).toSet(), {
        f1.id,
        f2.id,
      }, reason: 'cos(f1,f2)=0.8 ≥0.75 同组；f3 孤立不输出');
      expect(
        groups.single.any((e) => e.id == f3.id),
        isFalse,
        reason: '孤立条目（与任何成员余弦 <0.75）不进入分组',
      );
      expect(
        groups.single.every((e) => e.kind == MemoryKind.personaFact),
        isTrue,
      );
      // 0.75 常量单处引用（不重复定义）：阈值语义与 VR-03 一致。
      expect(kClusterSimilarityThreshold, 0.75);
    });

    test('补嵌失败（缺向量）→ 空列表降级', () async {
      final characterId = await seedCharacter();
      await memory.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '喜欢在河边散步',
      );
      await enableEmbedding();
      fake.failure = const EmbeddingFailure(
        EmbeddingFailureKind.network,
        'embedding 网络失败（测试注入）',
      );

      final groups = await service.buildClusterInput(characterId);

      expect(groups, isEmpty);
    });

    test('disabled → 空列表，零 API 调用', () async {
      final characterId = await seedCharacter();
      await memory.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: '喜欢在河边散步',
      );

      final groups = await service.buildClusterInput(characterId);

      expect(groups, isEmpty);
      expect(fake.embedCalls, 0);
    });
  });

  group('配置与降级边界（SR-20）', () {
    test('enabled 但 base_url 为 http → 配置错误收敛为降级空，零调用', () async {
      final characterId = await seedCharacter();
      await seedEntries(characterId, 1);
      await enableEmbedding();
      await settings.setMany({'embedding_base_url': 'http://api.example.com'});

      final results = await service.semanticSearch(characterId, '查询');

      expect(results, isEmpty);
      expect(fake.embedCalls, 0, reason: '非法 base_url 在配置解析期降级，不发起请求');
    });
  });

  test('验收 8 标定口径：阈值 0.5/0.75 为经验初值，真实响应待 key 补充', () async {
    // D6 标定动作：本机无 key，fixture 基于 OpenAI 官方公开文档合成样例
    // （见 test/services/embedding/fixtures/），0.5/0.75 仅名义生效。
    // 有真实 key 的集成会话须抓真实响应补 fixture、用真实记忆样条重标
    // 两常量（cosine_similarity.dart 单处定义），并断言语义相关性而非
    // 关键词同形。本用例钉住「常量单处定义、服务引用不重复定义」契约。
    expect(kSemanticRecallMinSimilarity, 0.5);
    expect(kClusterSimilarityThreshold, 0.75);
    // 检索实现引用 VR-03 常量而非字面量（防标定后双源漂移）。
    const thresholdUsed = kSemanticRecallMinSimilarity;
    expect(thresholdUsed, 0.5);
  });
}
