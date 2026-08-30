/// DocumentParseService 单元测试（工单 M4-04 验收逐条：语义契约）。
///
/// 语义锚点（spec §B 文档解析 + 桌面 document_parser.py 权威源）：
/// - `parseSystemPrompt` 常量 = 桌面 `_PARSE_SYSTEM_PROMPT` 原文逐字（差分锚定）；
/// - `parseFields` 白名单 10 项 = 桌面 `PARSE_FIELDS`；
/// - `extractJsonFromLlm` 三级提取（直接 dict → ```json 代码块 → {…} 范围）；
/// - `parse` 按默认 provider/model + apiKey 链 + baseUrl 装配，消息 [system, user]，
///   generate(maxTokens: 4096, model) 且**不传 temperature**（R8 定案：
///   `LLMProvider.generate` 签名无 temperature 参数，结构性保证）；
/// - 白名单过滤 / 默认值 / parsedFields；四级错误文案全部折叠 [DocParseError]。
///
/// 测试 seam（spec Testing Decisions）：真实「内存 drift 库 + InMemorySecretStore
/// + SettingsRepository + 假 LLM provider（FixedLLMProviderFactory）」；只断言外部
/// 行为与输出契约，不测实现细节。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/document_parse_service.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_llm_provider.dart';
import '../helpers/in_memory_secret_store.dart';

/// 桌面 `_PARSE_SYSTEM_PROMPT` 原文逐字（来自
/// `desktop/backend/app/services/document_parser.py`，522 字符、无首尾换行）。
///
/// 注意：Dart 三引号字符串紧跟首行内容书写（`'''你…`），首行前无换行，
/// 与桌面 Python 三引号 `"""` 紧跟内容的语义一致。
const String _desktopParseSystemPrompt = '''你是一个角色卡解析器。用户会提供一段关于角色的文字描述（可能是小说片段、设定文档、角色简介等），请从中提取以下字段并以 JSON 格式返回：

{
  "name": "角色名称",
  "description": "简短描述（一句话）",
  "personality": "人格设定、性格特征、说话方式、行为模式等核心设定",
  "scenario": "场景设定（对话发生的背景/世界）",
  "first_mes": "开场白（角色首次见面说的话）",
  "mes_example": "对话范例（展示角色说话风格的示例对话）",
  "system_prompt": "系统提示词（如果有明确的指令性内容）",
  "tags": ["标签1", "标签2"],
  "creator": "作者/来源"
}

规则：
1. name 必须提取，无法确定则留空字符串
2. 不要编造文档中没有的信息
3. personality 是核心字段，尽量详细
4. 对话范例用 <START> 标记开头，{{user}} 表示用户，{{char}} 表示角色
5. 不确定的字段留空字符串或空数组
6. 只返回 JSON，不要其他文字''';

/// 记录 `create` 入参的工厂（断言 Key 链 / baseUrl 装配用）。
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

/// 恒抛 [ProviderNotSupportedError] 的工厂（未知 Provider 错误面用）。
class _ThrowingFactory implements LLMProviderFactory {
  @override
  LLMProvider create({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) {
    throw ProviderNotSupportedError(provider);
  }
}

/// 内存 drift 库 + SettingsRepository + InMemorySecretStore 装配基座。
class _ParseEnv {
  _ParseEnv({required this.db, required this.settings, required this.secretStore});

  final AppDatabase db;
  final SettingsRepository settings;
  final InMemorySecretStore secretStore;

  static Future<_ParseEnv> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    final secretStore = InMemorySecretStore();
    final settings = SettingsRepository(database: db, secretStore: secretStore);
    return _ParseEnv(db: db, settings: settings, secretStore: secretStore);
  }

  /// 用 [provider] 装配 [DocumentParseService]（固定工厂注入）。
  DocumentParseService service(LLMProvider provider) => DocumentParseService(
        settings: settings,
        providerFactory: FixedLLMProviderFactory(provider),
      );

  Future<void> close() => db.close();
}

void main() {
  group('parseSystemPrompt 常量 · 锚桌面 _PARSE_SYSTEM_PROMPT 原文（验收 2）', () {
    test('逐字相等（522 字符、无尾随换行）', () {
      expect(parseSystemPrompt, _desktopParseSystemPrompt);
      expect(parseSystemPrompt.length, 522);
      expect(parseSystemPrompt.endsWith('\n'), isFalse, reason: '无尾随换行');
    });
  });

  group('parseFields 白名单 · 锚桌面 PARSE_FIELDS（验收 2）', () {
    test('10 项逐字', () {
      expect(parseFields, [
        'name',
        'description',
        'personality',
        'scenario',
        'first_mes',
        'mes_example',
        'system_prompt',
        'post_history_instructions',
        'tags',
        'creator',
      ]);
    });
  });

  group('extractJsonFromLlm · 三级提取（验收 3）', () {
    test('第一级：直接 jsonDecode dict', () {
      expect(extractJsonFromLlm('{"name": "艾莉亚"}'), {'name': '艾莉亚'});
      // 容忍首尾空白。
      expect(extractJsonFromLlm('  {"name": "艾莉亚"}  '), {'name': '艾莉亚'});
    });

    test('直接解析非 dict（list）→ 不返回，走下一级', () {
      // 直接解析得到 List 非 dict → 跳过；无代码块/花括号 → null。
      expect(extractJsonFromLlm('[1, 2, 3]'), isNull);
    });

    test('第二级：```json 代码块提取', () {
      const raw = '这是开头\n```json\n{"name": "艾莉亚", "tags": ["冒险"]}\n```\n结尾';
      expect(extractJsonFromLlm(raw), {'name': '艾莉亚', 'tags': ['冒险']});
    });

    test('第二级：无 json 标记的 ``` 代码块（```\\n 与裸 ```）', () {
      const raw = '```\n{"name": "艾莉亚"}\n```';
      expect(extractJsonFromLlm(raw), {'name': '艾莉亚'});
    });

    test('第三级：首 { 到末 } 范围提取', () {
      const raw = '前缀 {"name": "艾莉亚"} 后缀';
      expect(extractJsonFromLlm(raw), {'name': '艾莉亚'});
    });

    test('三级全失败 → null', () {
      for (final bad in ['', '不是 JSON', '纯文本', '12345', 'true', 'null']) {
        expect(extractJsonFromLlm(bad), isNull, reason: '输入 "$bad"');
      }
    });
  });

  group('truncateError · 截断辅助（验收 5 _truncate 语义）', () {
    test('≤200 原样返回；>200 截断到 200 + …', () {
      expect(truncateError('短错误'), '短错误');
      expect(truncateError('x' * 200), 'x' * 200, reason: '恰好 200 不截断');
      expect(truncateError('x' * 201), '${'x' * 200}…', reason: '>200 加省略号');
    });
  });

  group('parse · 消息组装 / 调用契约（验收 1）', () {
    test('system+user 消息、maxTokens=4096、model=默认、不传 temperature', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final provider = FakeLLMProvider(tokens: ['{"name": "艾莉亚"}']);
      final service = env.service(provider);

      final result = await service.parse('设定文档内容……');

      // 调用记录：消息 [system, user]；maxTokens 4096；model 默认值。
      expect(provider.lastMessages, [
        LlmMessage(role: 'system', content: parseSystemPrompt),
        LlmMessage(role: 'user', content: '设定文档内容……'),
      ]);
      expect(provider.lastMaxTokens, 4096, reason: '照搬桌面 max_tokens=4096');
      expect(provider.lastModel, 'claude-sonnet-5', reason: '默认模型');
      // 不传 temperature：LLMProvider.generate 抽象签名无 temperature 参数
      // （R8 定案，结构性保证——调用记录形状即验证，不存在可传通道）。
      expect(result.name, '艾莉亚');
      await env.close();
    });

    test('默认 provider/model + apiKey 链 + baseUrl 装配（RecordingFactory）', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final provider = FakeLLMProvider(tokens: ['{"name": "艾莉亚"}']);
      final factory = _RecordingFactory(provider);
      final service = DocumentParseService(
        settings: env.settings,
        providerFactory: factory,
      );

      await service.parse('文档');

      expect(factory.calls, hasLength(1));
      expect(factory.calls.single.provider, 'claude', reason: '默认 provider');
      expect(factory.calls.single.apiKey, 'sk-test', reason: 'Key 链命中 claude 槽位');
      expect(factory.calls.single.baseUrl, isNull, reason: 'baseUrl 空 → null');
      await env.close();
    });

    test('设置指定 provider/model + baseUrl 透传', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.openaiApiKeySlot, value: 'sk-openai');
      await env.settings.setMany({
        'default_provider': 'openai',
        'default_model': 'gpt-4o',
        'openai_base_url': 'https://custom.example/v1',
      });
      final provider = FakeLLMProvider(tokens: ['{"name": "艾莉亚"}']);
      final factory = _RecordingFactory(provider);
      final service = DocumentParseService(
        settings: env.settings,
        providerFactory: factory,
      );

      await service.parse('文档');

      expect(factory.calls.single.provider, 'openai');
      expect(factory.calls.single.apiKey, 'sk-openai');
      expect(factory.calls.single.baseUrl, 'https://custom.example/v1');
      expect(provider.lastModel, 'gpt-4o');
      await env.close();
    });
  });

  group('parse · 白名单过滤 / 默认值 / parsedFields（验收 4）', () {
    test('只取白名单字段，额外字段丢弃', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final service = env.service(FakeLLMProvider(tokens: [
        '{"name": "艾莉亚", "extra_field": "丢弃", "temperature": 0.9, "tags": ["冒险"]}',
      ]));

      final result = await service.parse('文档');

      expect(result.name, '艾莉亚');
      expect(result.tags, ['冒险']);
      expect(result.description, '', reason: '未提供字段为默认空串');
      expect(result.parsedFields, containsAll(['name', 'tags']));
      await env.close();
    });

    test('空值/null/空串/空数组 → 默认（tags 空列表、其余空串）', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final service = env.service(FakeLLMProvider(tokens: [
        '{"name": "", "description": null, "tags": [], "personality": "", "scenario": null}',
      ]));

      final result = await service.parse('文档');

      expect(result.name, '', reason: '空串 → 默认空串');
      expect(result.description, '', reason: 'null → 默认空串');
      expect(result.personality, '', reason: '空串 → 默认空串');
      expect(result.scenario, '', reason: 'null → 默认空串');
      expect(result.tags, isEmpty, reason: '空数组 → 默认空列表');
      expect(result.parsedFields, isEmpty, reason: '全空无成功提取字段');
      await env.close();
    });

    test('tags 必须 list 且元素转 str、过滤空；非 list → 空列表', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final service = env.service(FakeLLMProvider(tokens: [
        '{"tags": ["冒险", "", " 奇幻 ", null, 42], "name": "艾莉亚"}',
      ]));

      final result = await service.parse('文档');

      expect(result.tags, ['冒险', ' 奇幻 ', '42'], reason: '元素转 str、空与 null 过滤');
      await env.close();
    });

    test('tags 非 list（字符串/数字）→ 空列表', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final service = env.service(FakeLLMProvider(tokens: [
        '{"tags": "冒险", "name": "艾莉亚"}',
      ]));

      final result = await service.parse('文档');

      expect(result.tags, isEmpty, reason: '非 list → 空列表');
      await env.close();
    });

    test('str 字段 strip；非 str 转 str', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final service = env.service(FakeLLMProvider(tokens: [
        '{"name": "  艾莉亚  ", "creator": 123, "description": " 简介 ", "system_prompt": true}',
      ]));

      final result = await service.parse('文档');

      expect(result.name, '艾莉亚', reason: 'str strip');
      expect(result.description, '简介', reason: 'str strip');
      expect(result.creator, '123', reason: '非 str → str');
      expect(result.systemPrompt, 'true', reason: '非 str（bool）→ str');
      await env.close();
    });

    test('成功提取字段记录 parsedFields（10 项全命中）', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final service = env.service(FakeLLMProvider(tokens: [
        '{"name": "艾莉亚", "description": "d", "personality": "p", "scenario": "s", '
        '"first_mes": "f", "mes_example": "m", "system_prompt": "sp", '
        '"post_history_instructions": "ph", "tags": ["t"], "creator": "c"}',
      ]));

      final result = await service.parse('文档');

      expect(result.parsedFields, parseFields, reason: '10 项全部成功提取');
      expect(result.firstMes, 'f');
      expect(result.mesExample, 'm');
      expect(result.systemPrompt, 'sp');
      expect(result.postHistoryInstructions, 'ph');
      await env.close();
    });
  });

  group('parse · 四级错误文案（验收 6）', () {
    test('未配置 API Key → DocParseError「未配置 API Key，请先在设置中填写」', () async {
      final env = await _ParseEnv.create();
      // 不写任何 Key。
      final service = env.service(FakeLLMProvider(tokens: ['{"name": "艾莉亚"}']));

      await expectLater(
        service.parse('文档'),
        throwsA(isA<DocParseError>().having(
          (e) => e.message,
          'message',
          '未配置 API Key，请先在设置中填写',
        )),
      );
      await env.close();
    });

    test('未知 Provider → DocParseError「不支持的 Provider: {provider}」', () async {
      final env = await _ParseEnv.create();
      // 任意 Key 可用即可——错误来自工厂派生。
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      await env.settings.setMany({'default_provider': 'unknown-provider'});
      final service = DocumentParseService(
        settings: env.settings,
        providerFactory: _ThrowingFactory(),
      );

      await expectLater(
        service.parse('文档'),
        throwsA(isA<DocParseError>().having(
          (e) => e.message,
          'message',
          '不支持的 Provider: unknown-provider',
        )),
      );
      await env.close();
    });

    test('LLM 任意异常 → DocParseError「LLM 调用失败：{截断200}」', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final service =
          env.service(FakeLLMProvider(error: StateError('boom'), tokens: const []));

      await expectLater(
        service.parse('文档'),
        throwsA(isA<DocParseError>().having(
          (e) => e.message,
          'message',
          'LLM 调用失败：Bad state: boom',
        )),
      );
      await env.close();
    });

    test('LLM 异常超长消息 → 截断 200 + …', () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final longMsg = 'e' * 300;
      final service = env.service(FakeLLMProvider(error: StateError(longMsg), tokens: const []));

      await expectLater(
        service.parse('文档'),
        throwsA(isA<DocParseError>().having(
          (e) => e.message,
          'message',
          'LLM 调用失败：${truncateError('Bad state: $longMsg')}',
        )),
      );
      await env.close();
    });

    test('返回不可解析 → DocParseError「LLM 返回了无法解析的响应，请重试或手动创建」',
        () async {
      final env = await _ParseEnv.create();
      await env.secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
      final service = env.service(FakeLLMProvider(tokens: ['这不是 JSON']));

      await expectLater(
        service.parse('文档'),
        throwsA(isA<DocParseError>().having(
          (e) => e.message,
          'message',
          'LLM 返回了无法解析的响应，请重试或手动创建',
        )),
      );
      await env.close();
    });
  });
}
