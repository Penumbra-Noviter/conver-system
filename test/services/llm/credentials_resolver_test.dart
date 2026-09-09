/// CredentialsResolver 规则矩阵（AR-3 r3-credentials-resolver）——纯读者注入
/// 的 A1-A6 组合序契约（provider 覆盖/缺省 → apiKey 链 → 空抛 → base_url 空
/// 归一 → model 覆盖/缺省回退），零 flutter / drift 依赖（测试运行器惯例同
/// 既有纯 Dart 模块测试，用 flutter_test 壳）。
///
/// 语义锚点（只读权威源）：
/// - 桌面 `desktop/backend/app/services/llm/resolver.py::resolve_llm`（一般链
///   组合序的单点形态，本模块为移动端复刻）；
/// - 既有三消费点当前组合序（`chat_service._resolveProvider` /
///   `document_parse_service.parse` / `simulators_view._buildGenerator`）——本
///   矩阵锁定收编后解析器唯一持有该组合序，消费点只剩差异面（TD-66 / F-24 /
///   F5 漂移先例的反制）。
///
/// 测试 seam（公共接口边界）：四 reader（defaultProvider / defaultModel /
/// apiKey(provider) / baseUrl(provider)）注入 [CredentialsResolver]；Key 链
/// 协议回退语义以镜像 `settings_repository._slotValue`（provider 槽 → 同协议
/// 槽 → 跨协议兜底）的测试侧假 reader 承载——契约：解析器把解析后 provider
/// 传入 apiKey reader 并透传其返回（链规则本体仍单一归属数据层原语）。
library;

import 'package:conver_system_mobile/models/model_catalog.dart';
import 'package:conver_system_mobile/services/llm/credentials_resolver.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:flutter_test/flutter_test.dart';

/// api_key 槽链假 reader——镜像 `settings_repository._slotValue('api_key')`：
/// provider 特定槽（claude/openai 自身即槽位键）→ 同协议槽 → 跨协议兜底 →
/// 空串。仅承载「链」语义供解析器组合序验证，不属被测实现。
Future<String> slotApiKey(String provider, Map<String, String> slots) async {
  final proto = ModelCatalog.resolveApiProvider(provider);
  const allSlots = ['claude', 'openai'];
  final candidates = [proto, ...allSlots.where((slot) => slot != proto)];
  for (final slot in candidates) {
    final value = slots['${slot}_api_key'];
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

/// 可计数解析器装配基座（断言 A6 组合序「四 reader 各一次」与覆盖序入参）。
class _Harness {
  _Harness({
    required this.defaultProvider,
    required this.defaultModel,
    required this.apiKeyFor,
    required this.baseUrlFor,
  });

  final String defaultProvider;
  final String defaultModel;
  final Future<String> Function(String provider) apiKeyFor;
  final Future<String> Function(String provider) baseUrlFor;

  int defaultProviderCalls = 0;
  int defaultModelCalls = 0;
  int apiKeyCalls = 0;
  int baseUrlCalls = 0;
  final List<String> apiKeyProviders = [];
  final List<String> baseUrlProviders = [];

  CredentialsResolver resolver() => CredentialsResolver(
        defaultProvider: () async {
          defaultProviderCalls++;
          return defaultProvider;
        },
        defaultModel: () async {
          defaultModelCalls++;
          return defaultModel;
        },
        apiKey: (provider) async {
          apiKeyCalls++;
          apiKeyProviders.add(provider);
          return apiKeyFor(provider);
        },
        baseUrl: (provider) async {
          baseUrlCalls++;
          baseUrlProviders.add(provider);
          return baseUrlFor(provider);
        },
      );
}

void main() {
  // 三消费点既有语义的逐字锚（当前实现 A2 路径 / doc-parse / 生成组合点共享）。
  const claudeSlots = {'claude_api_key': 'sk-claude'};
  const openaiSlots = {'openai_api_key': 'sk-openai'};

  group('A1 · provider 选择（override 优先，空/缺省回退 defaultProvider）', () {
    test('override 非空优先于 defaultProvider', () async {
      final h = _Harness(
        defaultProvider: 'claude',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (p) async => p == 'deepseek' ? 'sk-deepseek' : '',
        baseUrlFor: (_) async => '',
      );

      final resolved =
          await h.resolver().resolve(providerOverride: 'deepseek');

      expect(resolved.provider, 'deepseek');
      expect(h.apiKeyProviders, ['deepseek'],
          reason: 'apiKey reader 收到解析后的 provider（覆盖值）');
    });

    test('空 override → defaultProvider 回退', () async {
      final h = _Harness(
        defaultProvider: 'claude',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (p) async => p == 'claude' ? 'sk-claude' : '',
        baseUrlFor: (_) async => '',
      );

      final resolved = await h.resolver().resolve();

      expect(resolved.provider, 'claude');
      expect(h.apiKeyProviders, ['claude'],
          reason: 'apiKey reader 收到解析后的 provider（缺省回退值）');
    });
  });

  group('A2 · key 链（provider → 槽位链 → 跨协议兜底，reader 承载链语义）', () {
    test('provider=claude → claude 槽位 key', () async {
      final h = _Harness(
        defaultProvider: 'claude',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (p) => slotApiKey(p, claudeSlots),
        baseUrlFor: (_) async => '',
      );

      final resolved = await h.resolver().resolve();

      expect(resolved.apiKey, 'sk-claude');
    });

    test('provider=openai → openai 槽位 key', () async {
      final h = _Harness(
        defaultProvider: 'openai',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (p) => slotApiKey(p, openaiSlots),
        baseUrlFor: (_) async => '',
      );

      final resolved = await h.resolver().resolve();

      expect(resolved.apiKey, 'sk-openai');
    });

    test('provider=deepseek（同协议 openai）→ openai 槽位 key', () async {
      final h = _Harness(
        defaultProvider: 'deepseek',
        defaultModel: 'deepseek-v3',
        apiKeyFor: (p) => slotApiKey(p, openaiSlots),
        baseUrlFor: (_) async => '',
      );

      final resolved = await h.resolver().resolve();

      expect(resolved.apiKey, 'sk-openai',
          reason: '同协议槽位命中（deepseek → openai 协议）');
    });

    test('仅 claude 槽有值且 provider=openai → 跨协议兜底返回 claude key', () async {
      final h = _Harness(
        defaultProvider: 'openai',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (p) => slotApiKey(p, claudeSlots),
        baseUrlFor: (_) async => '',
      );

      final resolved = await h.resolver().resolve();

      expect(resolved.apiKey, 'sk-claude',
          reason: '跨协议兜底（openai 槽空 → claude 槽）');
    });
  });

  group('A3 · 全槽空 → 抛 ApiKeyMissingError（文案逐字）', () {
    test('抛出 ApiKeyMissingError，消息「未配置 {provider} API Key，请在设置中填写」',
        () async {
      final h = _Harness(
        defaultProvider: 'claude',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (_) async => '',
        baseUrlFor: (_) async => '',
      );

      await expectLater(
        h.resolver().resolve(),
        throwsA(isA<ApiKeyMissingError>().having(
          (e) => e.message,
          'message',
          '未配置 claude API Key，请在设置中填写',
        )),
      );
    });

    test('override provider 空 key → 抛点消息含覆盖 provider', () async {
      final h = _Harness(
        defaultProvider: 'claude',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (_) async => '',
        baseUrlFor: (_) async => '',
      );

      await expectLater(
        h.resolver().resolve(providerOverride: 'deepseek'),
        throwsA(isA<ApiKeyMissingError>().having(
          (e) => e.message,
          'message',
          '未配置 deepseek API Key，请在设置中填写',
        )),
      );
    });
  });

  group('A4 · base_url（非空透传，空 → null 归一）', () {
    test('非空 base_url 原样透传', () async {
      final h = _Harness(
        defaultProvider: 'openai',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (p) => slotApiKey(p, openaiSlots),
        baseUrlFor: (_) async => 'https://relay.example.com/v1',
      );

      final resolved = await h.resolver().resolve();

      expect(resolved.baseUrl, 'https://relay.example.com/v1');
    });

    test('空 base_url → null（归一；工厂收到 null = 官方端点）', () async {
      final h = _Harness(
        defaultProvider: 'openai',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (p) => slotApiKey(p, openaiSlots),
        baseUrlFor: (_) async => '',
      );

      final resolved = await h.resolver().resolve();

      expect(resolved.baseUrl, isNull);
    });
  });

  group('A5 · model（override 优先，空/缺省回退 defaultModel）', () {
    test('override 非空优先于 defaultModel', () async {
      final h = _Harness(
        defaultProvider: 'deepseek',
        defaultModel: 'deepseek-v3',
        apiKeyFor: (p) => slotApiKey(p, openaiSlots),
        baseUrlFor: (_) async => '',
      );

      final resolved =
          await h.resolver().resolve(modelOverride: 'deepseek-r1');

      expect(resolved.model, 'deepseek-r1');
    });

    test('空 override → defaultModel 回退', () async {
      final h = _Harness(
        defaultProvider: 'claude',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (p) => slotApiKey(p, claudeSlots),
        baseUrlFor: (_) async => '',
      );

      final resolved = await h.resolver().resolve();

      expect(resolved.model, 'claude-sonnet-5');
    });
  });

  group('A6 · 组合序（四 reader 各一次，无重复读；字段齐全）', () {
    test('happy path：defaultProvider / apiKey / defaultModel / baseUrl 各调一次',
        () async {
      final h = _Harness(
        defaultProvider: 'openai',
        defaultModel: 'gpt-4o',
        apiKeyFor: (p) => slotApiKey(p, openaiSlots),
        baseUrlFor: (_) async => 'https://relay.example.com/v1',
      );

      final resolved = await h.resolver().resolve();

      expect(h.defaultProviderCalls, 1);
      expect(h.apiKeyCalls, 1);
      expect(h.defaultModelCalls, 1);
      expect(h.baseUrlCalls, 1);
      expect(h.baseUrlProviders, ['openai'],
          reason: 'baseUrl reader 收到解析后的 provider');
      expect(resolved.provider, 'openai');
      expect(resolved.apiKey, 'sk-openai');
      expect(resolved.model, 'gpt-4o');
      expect(resolved.baseUrl, 'https://relay.example.com/v1');
    });

    test('Falsify 边界：空 key 抛点路径只读 provider 与 apiKey（不读 model/baseUrl）',
        () async {
      final h = _Harness(
        defaultProvider: 'claude',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (_) async => '',
        baseUrlFor: (_) async => '',
      );

      await expectLater(h.resolver().resolve(), throwsA(isA<ApiKeyMissingError>()));

      expect(h.defaultProviderCalls, 1, reason: 'provider 先解析');
      expect(h.apiKeyCalls, 1, reason: 'key 链随后读取');
      expect(h.defaultModelCalls, 0,
          reason: '空 key 抛点在 model 读取之前（对齐既有 chat/生成路径）');
      expect(h.baseUrlCalls, 0,
          reason: '空 key 抛点在 base_url 读取之前');
    });

    test('Falsify 边界：override 同时提供 provider+model → 两缺省 reader 均不读',
        () async {
      final h = _Harness(
        defaultProvider: 'claude',
        defaultModel: 'claude-sonnet-5',
        apiKeyFor: (p) => slotApiKey(p, openaiSlots),
        baseUrlFor: (_) async => '',
      );

      final resolved = await h
          .resolver()
          .resolve(providerOverride: 'deepseek', modelOverride: 'deepseek-v3');

      expect(h.defaultProviderCalls, 0);
      expect(h.defaultModelCalls, 0);
      expect(resolved.provider, 'deepseek');
      expect(resolved.model, 'deepseek-v3');
      expect(resolved.apiKey, 'sk-openai',
          reason: 'key 链按覆盖 provider 走 openai 协议槽');
    });
  });
}
