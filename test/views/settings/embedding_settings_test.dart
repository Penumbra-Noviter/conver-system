/// VR-09「对话」设置子页 embedding 配置区 widget 契约——开关（默认关 +
/// SR-19 外发告知副标题）/ base_url 校验（SR-20）/ key 经 setMany 白名单
/// 重定向 SecretStore（SR-16）/ model 回显 / 测试连接（三权表单现值透传、
/// 失败分类文案不含 key 与原文、只读不落库）。
///
/// seam：ConversationSettingsPage 公开构造（仓储注入 + 可空
/// `embeddingClientFactory`——生产缺省构造 OpenAICompatibleEmbeddingClient，
/// 测试注入 fake client factory 不触真实网络）；读写经真实
/// SettingsRepository（内存 drift 真 schema + InMemorySecretStore），断言
/// 落在仓储 / 槽位可观察值上，不锁内部实现（对齐既有设置页测试基建）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/embedding/embedding_client.dart';
import 'package:conver_system_mobile/services/embedding/embedding_config.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/settings/conversation_settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';
import '../../helpers/save_fail_repo.dart';

/// 可控 embed 结果的 fake client——成功返回 [dims] 维向量，或抛 [failure]，
/// 可选 [delay] 供防重入在途断言。
class _FakeEmbeddingClient implements EmbeddingClient {
  _FakeEmbeddingClient({
    this.dims = 1536,
    this.failure,
    this.delay,
  });

  final int dims;
  final EmbeddingFailure? failure;
  final Duration? delay;
  int embedCalls = 0;
  List<String>? lastTexts;

  @override
  Future<List<EmbeddingVector>> embed(List<String> texts) async {
    embedCalls++;
    lastTexts = texts;
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    if (failure != null) {
      throw failure!;
    }
    return <EmbeddingVector>[
      EmbeddingVector(List<double>.filled(dims, 0.1)),
    ];
  }
}

/// 记录 create 入参的 client 工厂 fake——断言表单现值经工厂透传（不入库锚）。
class _RecordingClientFactory {
  _RecordingClientFactory(this.client);

  final EmbeddingClient client;
  final List<EmbeddingEndpointConfig> calls = [];

  EmbeddingClient call(EmbeddingEndpointConfig config) {
    calls.add(config);
    return client;
  }
}

void main() {
  late AppDatabase db;
  late SettingsRepository repo;
  late InMemorySecretStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = InMemorySecretStore();
    repo = SettingsRepository(database: db, secretStore: store);
  });

  tearDown(() async {
    await db.close();
  });

  /// 高视口 + 深色暖灰主题包一层 MaterialApp，直接挂载子页；
  /// [clientFactory] 注入测试连接 seam。
  Future<void> pumpPage(
    WidgetTester tester, {
    EmbeddingClient Function(EmbeddingEndpointConfig)? clientFactory,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: ConversationSettingsPage(
          settingsRepository: repo,
          embeddingClientFactory: clientFactory,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 重建子页（强制重新 `_load`）→ 回显存储中的最新值。
  Future<void> rebuildPage(
    WidgetTester tester, {
    EmbeddingClient Function(EmbeddingEndpointConfig)? clientFactory,
  }) async {
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester, clientFactory: clientFactory);
  }

  /// 读取指定开关的当前 UI 值。
  bool switchValue(WidgetTester tester, String title) => tester
      .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title))
      .value;

  /// 开启「启用语义检索」开关（默认关 → 开，输入区随之可用）。
  Future<void> enableEmbedding(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(SwitchListTile, '启用语义检索'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
  }

  Future<void> tapTestConnection(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('test-connection-embedding')));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  group('开关语义（验收 1/2 + SR-19）', () {
    testWidgets('初始默认关：外发告知副标题存在、输入区与测试连接禁用', (tester) async {
      await pumpPage(tester);

      expect(switchValue(tester, '启用语义检索'), isFalse,
          reason: 'SR-19 开关默认关（对话内容不默认外发）');
      expect(find.text('对话内容将发送至所选 Embedding 服务'), findsOneWidget,
          reason: 'SR-19 外发告知副标题必须逐字存在');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('embedding-api-key')))
            .enabled,
        isFalse,
        reason: '关闭时输入区禁用',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('embedding-base-url')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('embedding-model')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('test-connection-embedding')),
            )
            .onPressed,
        isNull,
        reason: '关闭时测试连接按钮禁用',
      );
    });

    testWidgets('存储 embedding_enabled=true → 回显开 + 输入区启用', (tester) async {
      await repo.setMany({
        SettingsRepository.embeddingEnabledKey: 'true',
      });
      await pumpPage(tester);

      expect(switchValue(tester, '启用语义检索'), isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('embedding-api-key')))
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('test-connection-embedding')),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('切换「启用语义检索」→ 写 embeddingEnabledKey 且重建回显一致', (tester) async {
      await pumpPage(tester);
      expect(switchValue(tester, '启用语义检索'), isFalse);

      await enableEmbedding(tester);
      expect(
        await repo.getValue(SettingsRepository.embeddingEnabledKey),
        'true',
      );
      expect(switchValue(tester, '启用语义检索'), isTrue);

      await rebuildPage(tester);
      expect(switchValue(tester, '启用语义检索'), isTrue);
    });

    testWidgets('embedding 开关写失败 → UI 回滚 + SnackBar「保存失败」', (tester) async {
      final failing = SaveFailRepo(db);
      repo = failing;
      await pumpPage(tester);
      expect(switchValue(tester, '启用语义检索'), isFalse);

      await tester.tap(find.widgetWithText(SwitchListTile, '启用语义检索'));
      await tester.pumpAndSettle();

      expect(switchValue(tester, '启用语义检索'), isFalse,
          reason: '写失败应回滚 UI');
      expect(find.text('保存失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('重复切换 → 值在 true/false 间往返且落库一致', (tester) async {
      await pumpPage(tester);

      final tile = find.widgetWithText(SwitchListTile, '启用语义检索');
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(
        await repo.getValue(SettingsRepository.embeddingEnabledKey),
        'true',
      );
      expect(switchValue(tester, '启用语义检索'), isTrue);
    });
  });

  group('保存语义（验收 3/4/5 + SR-16/20）', () {
    testWidgets('base_url http → SnackBar 拒绝 + 不保存（SR-20）', (tester) async {
      await pumpPage(tester);
      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-base-url')),
        'http://c.example',
      );
      await save(tester);

      expect(find.text('API 地址必须以 https:// 开头'), findsOneWidget,
          reason: 'SR-20 http 拒绝并提示');
      expect(find.text('已保存'), findsNothing);
      expect(await repo.getValue(SettingsRepository.embeddingBaseUrlKey), '',
          reason: '非法 base_url 不落库');
    });

    testWidgets('base_url https 保存 → 归一值落库 + 重建回显（SR-20 放行）', (tester) async {
      await pumpPage(tester);
      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-base-url')),
        'https://c.example/',
      );
      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        'sk-emb-test',
      );
      await save(tester);

      expect(find.text('已保存'), findsOneWidget);
      expect(
        await repo.getValue(SettingsRepository.embeddingBaseUrlKey),
        'https://c.example',
        reason: '保存归一后值（trim + 去尾部斜杠）',
      );
      await rebuildPage(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('embedding-base-url')))
            .controller
            ?.text,
        'https://c.example',
      );
    });

    testWidgets('base_url 留空保存 → 不落行（官方默认端点）', (tester) async {
      await pumpPage(tester);
      await enableEmbedding(tester);
      await save(tester);

      final all = await repo.getAll();
      expect(all.containsKey(SettingsRepository.embeddingBaseUrlKey), isFalse,
          reason: '空 base_url 不落设置表行');
      expect(await repo.embeddingBaseUrl, '');
    });

    testWidgets('key 保存 → SecretStore 槽位落值、设置表无明文 Key 行（SR-16）', (tester) async {
      await pumpPage(tester);
      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        'sk-emb-secret',
      );
      await save(tester);

      expect(await store.read(SecretStore.embeddingApiKeySlot), 'sk-emb-secret',
          reason: 'key 经白名单重定向写入 SecretStore 槽位');
      final all = await repo.getAll();
      expect(all.containsKey(SecretStore.embeddingApiKeySlot), isFalse,
          reason: 'SR-16 设置表无 embedding_api_key 明文行');
      // 仓储侧读回与槽位一致（写入重定向的对称读取）。
      expect(await repo.getValue(SecretStore.embeddingApiKeySlot), 'sk-emb-secret');
    });

    testWidgets('key 清空保存 → 槽位清空（读回空串 = 未配置）', (tester) async {
      await pumpPage(tester);
      await store.write(key: SecretStore.embeddingApiKeySlot, value: 'old-key');
      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        '',
      );
      await save(tester);

      expect(await store.read(SecretStore.embeddingApiKeySlot), '');
    });

    testWidgets('model 缺省回显 text-embedding-3-small；自定义保存后回显保存值', (tester) async {
      await pumpPage(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('embedding-model')))
            .controller
            ?.text,
        SettingsRepository.defaultEmbeddingModel,
        reason: '验收 5：缺省回显 text-embedding-3-small',
      );

      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-model')),
        'custom-embed-model',
      );
      await save(tester);
      expect(await repo.getValue(SettingsRepository.embeddingModelKey),
          'custom-embed-model');

      await rebuildPage(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('embedding-model')))
            .controller
            ?.text,
        'custom-embed-model',
        reason: '验收 5：保存后回显保存值',
      );
    });
  });

  group('测试连接（验收 6/7 + 不硬编码模型）', () {
    testWidgets('三权齐备 → 成功 SnackBar 含 dims + 表单现值经工厂透传', (tester) async {
      final client = _FakeEmbeddingClient(dims: 1536);
      final factory = _RecordingClientFactory(client);
      await pumpPage(tester, clientFactory: factory.call);
      await enableEmbedding(tester);

      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        'sk-emb-form',
      );
      await tester.enterText(
        find.byKey(const ValueKey('embedding-base-url')),
        'https://c.example',
      );
      await tester.enterText(
        find.byKey(const ValueKey('embedding-model')),
        'form-model',
      );
      await tapTestConnection(tester);

      expect(find.text('连接成功（1536 维）'), findsOneWidget,
          reason: '成功 SnackBar 含 dims 摘要');
      expect(client.embedCalls, 1);
      expect(client.lastTexts, <String>['ping'],
          reason: '连接测试固定单条 ping 探测文本');
      expect(factory.calls, hasLength(1));
      expect(factory.calls.single.apiKey, 'sk-emb-form',
          reason: 'key 取表单现值，不读已保存值');
      expect(factory.calls.single.baseUrl, 'https://c.example');
      expect(factory.calls.single.model, 'form-model',
          reason: '不硬编码模型——测用户实际配置的表单模型');
    });

    testWidgets('未配置自定义模型 → 传到缺省 text-embedding-3-small（非硬编码）', (tester) async {
      final client = _FakeEmbeddingClient();
      final factory = _RecordingClientFactory(client);
      await pumpPage(tester, clientFactory: factory.call);
      await enableEmbedding(tester);
      // 表单回显即缺省模型，不额外输入。
      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        'sk-emb-form',
      );
      await tapTestConnection(tester);

      expect(find.text('连接成功（1536 维）'), findsOneWidget);
      expect(factory.calls.single.model,
          SettingsRepository.defaultEmbeddingModel);
    });

    testWidgets('base_url 留空 → 工厂收到 null（官方默认端点）', (tester) async {
      final client = _FakeEmbeddingClient();
      final factory = _RecordingClientFactory(client);
      await pumpPage(tester, clientFactory: factory.call);
      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        'sk-emb-form',
      );
      await tapTestConnection(tester);

      expect(find.text('连接成功（1536 维）'), findsOneWidget);
      expect(factory.calls.single.baseUrl, isNull);
    });

    testWidgets('未提供 Key → 提示先配置 + 工厂不触发（零请求）', (tester) async {
      final client = _FakeEmbeddingClient();
      final factory = _RecordingClientFactory(client);
      await pumpPage(tester, clientFactory: factory.call);
      await enableEmbedding(tester);

      await tapTestConnection(tester);

      expect(find.text('未提供 API Key，请在设置中填写后再测试'), findsOneWidget);
      expect(factory.calls, isEmpty);
      expect(client.embedCalls, 0);
    });

    testWidgets('base_url http → 提示非法端点 + 工厂不触发（SR-20）', (tester) async {
      final client = _FakeEmbeddingClient();
      final factory = _RecordingClientFactory(client);
      await pumpPage(tester, clientFactory: factory.call);
      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        'sk-emb-form',
      );
      await tester.enterText(
        find.byKey(const ValueKey('embedding-base-url')),
        'http://c.example',
      );
      await tapTestConnection(tester);

      expect(find.text('API 地址必须以 https:// 开头'), findsOneWidget);
      expect(factory.calls, isEmpty);
      expect(client.embedCalls, 0);
    });

    for (final (failure, expected) in [
      (
        const EmbeddingFailure(
          EmbeddingFailureKind.auth,
          'embedding 鉴权失败（HTTP 401）',
        ),
        'embedding 鉴权失败（HTTP 401）',
      ),
      (
        const EmbeddingFailure(
          EmbeddingFailureKind.rateLimit,
          'embedding 触发限流（HTTP 429，调用方降级）',
        ),
        'embedding 触发限流（HTTP 429，调用方降级）',
      ),
      (
        const EmbeddingFailure(
          EmbeddingFailureKind.timeout,
          'embedding 请求超时（对齐 LLM 链 60s，SR-18）',
        ),
        'embedding 请求超时（对齐 LLM 链 60s，SR-18）',
      ),
      (
        const EmbeddingFailure(
          EmbeddingFailureKind.parse,
          'embedding 响应解析失败（SR-17）：响应不是合法 JSON',
        ),
        'embedding 响应解析失败（SR-17）：响应不是合法 JSON',
      ),
      (
        const EmbeddingFailure(
          EmbeddingFailureKind.network,
          'embedding 网络失败（连接失败或响应取消）',
        ),
        'embedding 网络失败（连接失败或响应取消）',
      ),
    ]) {
      testWidgets('EmbeddingFailure(${failure.kind.name}) → SnackBar 分类摘要', (tester) async {
        final client = _FakeEmbeddingClient(failure: failure);
        final factory = _RecordingClientFactory(client);
        await pumpPage(tester, clientFactory: factory.call);
        await enableEmbedding(tester);
        await tester.enterText(
          find.byKey(const ValueKey('embedding-api-key')),
          'sk-emb-form',
        );
        await tapTestConnection(tester);

        expect(find.text(expected), findsOneWidget,
            reason: '失败分类文案 = EmbeddingFailure.message（SR-16 固定摘要）');
        expect(client.embedCalls, 1);
      });
    }

    testWidgets('SR-16：失败 SnackBar 不含 key 子串与探测原文', (tester) async {
      const key = 'sk-emb-supersecret';
      const failure = EmbeddingFailure(
        EmbeddingFailureKind.auth,
        'embedding 鉴权失败（HTTP 401）',
      );
      final client = _FakeEmbeddingClient(failure: failure);
      final factory = _RecordingClientFactory(client);
      await pumpPage(tester, clientFactory: factory.call);
      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        key,
      );
      await tapTestConnection(tester);

      final snackBarText = tester
          .widget<SnackBar>(find.byType(SnackBar))
          .content
          .toString();
      expect(snackBarText.contains(key), isFalse, reason: 'SR-16 不含 key');
      expect(snackBarText.contains('ping'), isFalse,
          reason: 'SR-16 不含探测原文 >10 字符子串（此处全量防护）');
    });

    testWidgets('非 EmbeddingFailure 兜底 → 固定文案（不含异常内容，SR-16）', (tester) async {
      final client = _FakeEmbeddingClient(failure: null);
      final throwing = _ThrowingClientFactory(client);
      await pumpPage(tester, clientFactory: throwing.call);
      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        'sk-emb-form',
      );
      await tapTestConnection(tester);

      expect(find.text('连接失败，请稍后重试'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing,
          reason: '兜底文案不拼接异常内容（防 key/原文外泄）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('测试连接只读验证：失败后 SecretStore 与设置表零写入（验收 7）', (tester) async {
      const failure = EmbeddingFailure(
        EmbeddingFailureKind.timeout,
        'embedding 请求超时（对齐 LLM 链 60s，SR-18）',
      );
      final client = _FakeEmbeddingClient(failure: failure);
      final factory = _RecordingClientFactory(client);
      await pumpPage(tester, clientFactory: factory.call);
      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        'sk-emb-form',
      );
      await tester.enterText(
        find.byKey(const ValueKey('embedding-base-url')),
        'https://c.example',
      );
      await tapTestConnection(tester);

      expect(find.text('embedding 请求超时（对齐 LLM 链 60s，SR-18）'),
          findsOneWidget);
      expect(await store.read(SecretStore.embeddingApiKeySlot), '',
          reason: '验收 7：测试连接不写 SecretStore');
      expect(await repo.getValue(SettingsRepository.embeddingBaseUrlKey), '',
          reason: '验收 7：测试连接不写设置表');
      expect(find.text('已保存'), findsNothing);
    });

    testWidgets('在途禁用「测试连接」按钮防重入；结束后复位', (tester) async {
      final client = _FakeEmbeddingClient(
        delay: const Duration(milliseconds: 100),
      );
      final factory = _RecordingClientFactory(client);
      await pumpPage(tester, clientFactory: factory.call);
      await enableEmbedding(tester);
      await tester.enterText(
        find.byKey(const ValueKey('embedding-api-key')),
        'sk-emb-form',
      );

      await tester.tap(find.byKey(const ValueKey('test-connection-embedding')));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('test-connection-embedding')),
            )
            .onPressed,
        isNull,
        reason: 'embed 在途期间禁用按钮防重入',
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('test-connection-embedding')),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('连接成功（1536 维）'), findsOneWidget);
    });
  });
}

/// create 必抛非 EmbeddingFailure 异常的工厂 fake——命中「兜底固定文案」锚。
class _ThrowingClientFactory {
  _ThrowingClientFactory(this.client);

  final EmbeddingClient client;

  EmbeddingClient call(EmbeddingEndpointConfig config) {
    throw StateError('boom-with-secret-ish');
  }
}