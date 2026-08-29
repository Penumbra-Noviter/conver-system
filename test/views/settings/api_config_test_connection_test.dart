// T05 A6 test_connection widget 测试：每 provider「测试连接」按钮用表单当前
// Key / base_url 现值（不入库、独立于 _save）经工厂实例化后调 testConnection，
// 成功 / 失败 SnackBar + debugPrint（不静默吞错）。
//
// 文案锚（逐字对齐 `desktop/backend/app/api/routes/settings.py::test_connection`）：
// - 未提供 Key →「未提供 API Key，请在设置中填写后再测试」（settings.py 局部 400 语义）
// - LLM 族错误 → str(e) 逐字（LLMAuthError / LLMRateLimitError / LLMTimeoutError
//   消息模板锚 `errors.dart::translateSdkError` → LLMError.message）
// - 其他连接失败 →「连接失败: {error}」（settings.py `except Exception` 兜底）
// - 成功 → 成功 SnackBar + debugPrint
//
// 测试 seam（与 F-9 装配链一致的构造注入点）：[ApiConfigSection.providerFactory]
// 构造参数——生产走默认 LLMFactory（工单明确允许「或默认 LLMFactory」），测试
// 注入 fake factory。四锚：成功 / 失败（fake factory 抛错）/ 表单现值不入库 /
// 独立于 _save（F-10~F-13 不折入）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/settings/api_config_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_llm_provider.dart';
import '../../helpers/in_memory_secret_store.dart';

/// 记录 create 入参的工厂 fake——断言表单现值经工厂透传（不入库锚）。
class _RecordingFactory implements LLMProviderFactory {
  _RecordingFactory(this.provider);

  final LLMProvider provider;
  final List<({String provider, String apiKey, String? baseUrl})> calls = [];

  @override
  LLMProvider create({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) {
    calls.add((provider: provider, apiKey: apiKey, baseUrl: baseUrl));
    return this.provider;
  }
}

/// create 必抛的工厂 fake——命中「失败（fake factory 抛错）」锚。
class _ThrowingFactory implements LLMProviderFactory {
  _ThrowingFactory(this.error);

  final Object error;
  int createCount = 0;

  @override
  LLMProvider create({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) {
    createCount++;
    throw error;
  }
}

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(database: db, secretStore: InMemorySecretStore());
  });

  tearDown(() async {
    await db.close();
  });

  /// 包一层 MaterialApp + Scaffold，使 SnackBar（ScaffoldMessenger）可呈现。
  Future<void> pumpSection(WidgetTester tester, Widget section) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: section),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 填入 claude 槽的 Key 现值并点「测试连接」。
  Future<void> tapClaudeTest(WidgetTester tester, {String key = 'sk-ant-test'}) async {
    await tester.enterText(
      find.byKey(const ValueKey('api-key-claude')),
      key,
    );
    await tester.tap(find.byKey(const ValueKey('test-connection-claude')));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  group('成功路径', () {
    testWidgets('测试连接成功 → SnackBar「连接成功」+ 表单现值经工厂透传', (tester) async {
      final provider = FakeLLMProvider();
      final factory = _RecordingFactory(provider);
      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: InMemorySecretStore(),
          providerFactory: factory,
          initialValues: const <String, String>{},
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('api-key-claude')),
        'sk-ant-test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('base-url-claude')),
        'https://c.example',
      );
      await tester.tap(find.byKey(const ValueKey('test-connection-claude')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('连接成功'), findsOneWidget);
      expect(provider.testConnectionCallCount, 1);
      // 表单现值透传（Key + base_url 均来自表单，非入库值）。
      expect(factory.calls, hasLength(1));
      expect(factory.calls.single.provider, 'claude');
      expect(factory.calls.single.apiKey, 'sk-ant-test');
      expect(factory.calls.single.baseUrl, 'https://c.example');
    });

    testWidgets('base_url 留空 → 工厂收到 null（官方默认端点）', (tester) async {
      final factory = _RecordingFactory(FakeLLMProvider());
      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: InMemorySecretStore(),
          providerFactory: factory,
          initialValues: const <String, String>{},
        ),
      );

      await tapClaudeTest(tester);

      expect(find.text('连接成功'), findsOneWidget);
      expect(factory.calls.single.baseUrl, isNull,
          reason: 'base_url 空 = 未配置自定义端点 → null（官方默认）');
    });
  });

  group('失败路径（fake factory 抛错）', () {
    testWidgets('未提供 Key →「未提供 API Key，请在设置中填写后再测试」且工厂不触发', (tester) async {
      final factory = _RecordingFactory(FakeLLMProvider());
      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: InMemorySecretStore(),
          providerFactory: factory,
          initialValues: const <String, String>{},
        ),
      );

      await tester.tap(find.byKey(const ValueKey('test-connection-claude')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.text('未提供 API Key，请在设置中填写后再测试'),
        findsOneWidget,
      );
      expect(factory.calls, isEmpty,
          reason: '未配置 Key 按未配置处理，不发任何请求');
    });

    for (final (error, expected) in [
      (LLMAuthError('Claude'), 'Claude API Key 无效或未配置'),
      (LLMRateLimitError('Claude'), 'Claude API 请求频率超限'),
      (LLMTimeoutError('Claude'), 'Claude API 请求超时'),
    ]) {
      testWidgets('factory 抛 $error → SnackBar「$expected」', (tester) async {
        final factory = _ThrowingFactory(error);
        await pumpSection(
          tester,
          ApiConfigSection(
            settingsRepository: repo,
            secretStore: InMemorySecretStore(),
            providerFactory: factory,
            initialValues: const <String, String>{},
          ),
        );

        await tapClaudeTest(tester);

        expect(find.text(expected), findsOneWidget,
            reason: 'LLM 族错误 str(e) 逐字对齐 translate_sdk_error 消息模板');
        expect(factory.createCount, 1);
      });
    }

    testWidgets('factory 抛非 LLM 异常 → SnackBar「连接失败: {error}」', (tester) async {
      final factory = _ThrowingFactory(Exception('boom'));
      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: InMemorySecretStore(),
          providerFactory: factory,
          initialValues: const <String, String>{},
        ),
      );

      await tapClaudeTest(tester);

      expect(find.text('连接失败: Exception: boom'), findsOneWidget,
          reason: '非 LLM 族兜底「连接失败: {error}」对齐 settings.py');
      expect(factory.createCount, 1);
    });
  });

  group('表单现值不入库（F-10 边界）', () {
    testWidgets('测试连接后 SecretStore 零写入、设置表 base_url 零写入', (tester) async {
      final store = InMemorySecretStore();
      final factory = _RecordingFactory(FakeLLMProvider());
      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: store,
          providerFactory: factory,
          initialValues: const <String, String>{},
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('api-key-claude')),
        'sk-ant-test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('base-url-claude')),
        'https://c.example',
      );
      await tester.tap(find.byKey(const ValueKey('test-connection-claude')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('连接成功'), findsOneWidget);
      // 表单现值透传但绝不停留：安全存储零写入。
      expect(await store.read(SecretStore.claudeApiKeySlot), '');
      expect(await store.read(SecretStore.openaiApiKeySlot), '');
      // 设置表零写入。
      expect(await repo.getValue('claude_base_url'), '');
      expect(await repo.getValue('openai_base_url'), '');
      // 未触发 _save 的成功文案（独立于 _save）。
      expect(find.text('API 配置已保存'), findsNothing);
    });
  });

  group('防重入（在途禁用按钮）', () {
    testWidgets('测试连接在途 → claude 按钮禁用；结束后复位', (tester) async {
      final provider = FakeLLMProvider(
        generateDelay: const Duration(milliseconds: 100),
      );
      final factory = _RecordingFactory(provider);
      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: InMemorySecretStore(),
          providerFactory: factory,
          initialValues: const <String, String>{},
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('api-key-claude')),
        'sk-ant-test',
      );
      // 在途：不 settle，直接看按钮 onPressed 是否被禁用。
      await tester.tap(find.byKey(const ValueKey('test-connection-claude')));
      await tester.pump();
      final inFlightButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('test-connection-claude')),
      );
      expect(inFlightButton.onPressed, isNull,
          reason: 'testConnection 在途期间禁用对应「测试连接」按钮防重入');

      // 结束后复位：等 generateDelay 走完再 settle。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      final settledButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('test-connection-claude')),
      );
      expect(settledButton.onPressed, isNotNull,
          reason: '测试连接结束后按钮恢复可点');
      expect(find.text('连接成功'), findsOneWidget);
    });
  });

  group('独立于 _save（F-10~F-13 不折入）', () {
    testWidgets('测试连接不组合保存链；随后保存仍独立可用', (tester) async {
      final store = InMemorySecretStore();
      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: store,
          providerFactory: FixedLLMProviderFactory(FakeLLMProvider()),
          initialValues: const <String, String>{},
        ),
      );

      // 1) 只点「测试连接」→ 成功文案出现，但无保存文案、无任何落库。
      await tapClaudeTest(tester);
      expect(find.text('连接成功'), findsOneWidget);
      expect(find.text('API 配置已保存'), findsNothing);
      expect(await store.read(SecretStore.claudeApiKeySlot), '');

      // 2) 随后点「保存 API 配置」→ 保存链路独立可用（互不干扰）。
      await tester.tap(find.text('保存 API 配置'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('API 配置已保存'), findsOneWidget);
      expect(await store.read(SecretStore.claudeApiKeySlot), 'sk-ant-test');
    });
  });
}
