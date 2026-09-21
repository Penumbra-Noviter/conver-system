/// 设置仓储契约测试（M1-T04，验收门 G5 逐条）。
///
/// 全部在内存执行器（`AppDatabase(NativeDatabase.memory())`）上打真 schema；
/// SecretStore 用共享 fake（test/helpers/in_memory_secret_store.dart）。
/// 语义锚定桌面 `backend/app/services/setting.py`（ALLOWED_KEYS / get_value /
/// get_int / get_all / set_many / _slot_value / api_key / base_url）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/llm/credentials_resolver.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';

void main() {
  late AppDatabase db;
  late InMemorySecretStore secretStore;
  late SettingsRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    secretStore = InMemorySecretStore();
    repository = SettingsRepository(database: db, secretStore: secretStore);
  });

  tearDown(() async {
    await db.close();
  });

  /// 直查设置表全部行（key → value）— 用于「不落明文 Key」等落表断言
  Future<Map<String, String>> tableRows() async {
    final rows = await db.select(db.settings).get();
    return {for (final row in rows) row.key: row.value};
  }

  group('A1 白名单键集（G5 + 工单 03/04/05 + 人机恋 + VR-01）', () {
    test('与桌面 ALLOWED_KEYS 十键逐字相等 + mobile 先行键（含 embedding 四键）', () {
      expect(
        SettingsRepository.allowedKeys,
        equals(<String>{
          'claude_api_key',
          'claude_base_url',
          'openai_api_key',
          'openai_base_url',
          'default_provider',
          'default_provider_name',
          'default_model',
          'sliding_window_rounds',
          'theme_mode',
          'user_name',
          'temperature',
          'max_tokens',
          'template_vars',
          'onboarding_completed',
          'memory_prompt_mode',
          'memory_reflection_enabled',
          'proactive_message_enabled',
          'inner_thought_enabled',
          'embedding_enabled',
          'embedding_api_key',
          'embedding_base_url',
          'embedding_model',
          'memory_palace_enabled',
          'memory_palace_every_rounds',
          'narrative_style_enabled',
          'narrative_style_rules',
          'simulator_llm_description_enabled',
        }),
      );
    });

    test('embedding 四键经常量锚定（防字面量漂移）', () {
      expect(SettingsRepository.embeddingEnabledKey, 'embedding_enabled');
      expect(SecretStore.embeddingApiKeySlot, 'embedding_api_key');
      expect(SettingsRepository.embeddingBaseUrlKey, 'embedding_base_url');
      expect(SettingsRepository.embeddingModelKey, 'embedding_model');
      expect(
        SettingsRepository.defaultEmbeddingModel,
        'text-embedding-3-small',
      );
      expect(
        SettingsRepository.allowedKeys,
        contains(SettingsRepository.embeddingEnabledKey),
      );
      expect(
        SettingsRepository.allowedKeys,
        contains(SecretStore.embeddingApiKeySlot),
      );
      expect(
        SettingsRepository.allowedKeys,
        contains(SettingsRepository.embeddingBaseUrlKey),
      );
      expect(
        SettingsRepository.allowedKeys,
        contains(SettingsRepository.embeddingModelKey),
      );
      expect(
        SettingsRepository.allowedKeys,
        isNot(contains('${SecretStore.embeddingApiKeySlot}_extra')),
      );
    });

    test('模拟器简介精修键经常量锚定 + 默认关 + 往返', () async {
      expect(
        SettingsRepository.simulatorLlmDescriptionEnabledKey,
        'simulator_llm_description_enabled',
      );
      expect(
        SettingsRepository.allowedKeys,
        contains(SettingsRepository.simulatorLlmDescriptionEnabledKey),
      );
      // 默认关（成本敏感 opt-in）。
      expect(await repository.simulatorLlmDescriptionEnabled, isFalse);
      // 写入 'true' → 开；其他值 → 关。
      await repository.setMany({
        SettingsRepository.simulatorLlmDescriptionEnabledKey: 'true',
      });
      expect(await repository.simulatorLlmDescriptionEnabled, isTrue);
      await repository.setMany({
        SettingsRepository.simulatorLlmDescriptionEnabledKey: 'false',
      });
      expect(await repository.simulatorLlmDescriptionEnabled, isFalse);
      // 白名单外写入不落表。
      await repository.setMany({'simulator_llm_description_enabled_extra': '1'});
      expect(
        await tableRows().then((rows) => rows.keys),
        isNot(contains('simulator_llm_description_enabled_extra')),
      );
    });

    test('白名单外键写入被忽略（设置表与安全存储均无痕）', () async {
      await repository.setMany({
        'evil_key': 'boom',
        'deepseek_api_key': 'sk-ds', // 桌面读侧死路径，不采纳
        'user_name': '小明', // 白名单内对照
      });

      expect(await tableRows(), {'user_name': '小明'});
      expect(await secretStore.containsKey('evil_key'), isFalse);
      expect(await secretStore.containsKey('deepseek_api_key'), isFalse);
      expect(await repository.getAll(), {'user_name': '小明'});
    });
  });

  group('A2 set→get 往返 / upsert / getAll（G5）', () {
    test('set 后 get 往返原值', () async {
      await repository.setMany({'user_name': '旅人'});
      expect(await repository.getValue('user_name'), '旅人');
    });

    test('upsert：不存在创建、存在更新且行数不膨胀', () async {
      await repository.setMany({'user_name': '旧名', 'theme_mode': 'dark'});
      expect(await tableRows().then((rows) => rows.length), 2);

      await repository.setMany({'user_name': '新名'});
      expect(await repository.getValue('user_name'), '新名');
      expect(await tableRows().then((rows) => rows.length), 2);
      expect(await tableRows().then((rows) => rows['theme_mode']), 'dark');
    });

    test('getAll 只含白名单内已有行（含空串值行，不含未写键）', () async {
      expect(await repository.getAll(), isEmpty);

      await repository.setMany({'default_provider': 'openai', 'user_name': ''});
      expect(await repository.getAll(), {
        'default_provider': 'openai',
        'user_name': '',
      });
    });

    test('getValue 带显式 default：缺失返回 default（镜像桌面 get_value 参数）', () async {
      expect(
        await repository.getValue(
          'default_provider_name',
          defaultValue: 'Claude',
        ),
        'Claude',
      );
    });
  });

  group('A3 空串语义 / getInt 整型容错（G5）', () {
    test('缺失行读取返回空', () async {
      expect(await repository.getValue('user_name'), '');
    });

    test('空串值行读取返回空（不返回行存在性）', () async {
      await repository.setMany({'user_name': ''});
      expect(
        await tableRows().then((rows) => rows.containsKey('user_name')),
        isTrue,
      );
      expect(await repository.getValue('user_name'), '');
    });

    test('getInt：数字往返；非数字 / 缺失回退 default', () async {
      await repository.setMany({'sliding_window_rounds': '15'});
      expect(
        await repository.getInt('sliding_window_rounds', defaultValue: 30),
        15,
      );

      await repository.setMany({'sliding_window_rounds': 'abc'});
      expect(
        await repository.getInt('sliding_window_rounds', defaultValue: 30),
        30,
      );

      expect(await repository.getInt('no_such_key', defaultValue: 7), 7);
    });
  });

  group('A4 类型化便捷读取缺省（G5）', () {
    test('user_name 缺省 User', () async {
      expect(await repository.userName, 'User');
      await repository.setMany({'user_name': '小明'});
      expect(await repository.userName, '小明');
      await repository.setMany({'user_name': ''});
      expect(await repository.userName, 'User');
    });

    test('sliding_window_rounds 缺省 30，整型容错同 getInt', () async {
      expect(await repository.slidingWindowRounds, 30);
      await repository.setMany({'sliding_window_rounds': '12'});
      expect(await repository.slidingWindowRounds, 12);
      await repository.setMany({'sliding_window_rounds': '3.5'});
      expect(await repository.slidingWindowRounds, 30);
    });

    test(
      'default_provider / default_model 缺省 claude / claude-sonnet-5',
      () async {
        expect(await repository.defaultProvider, 'claude');
        expect(await repository.defaultModel, 'claude-sonnet-5');

        await repository.setMany({
          'default_provider': 'deepseek',
          'default_model': 'deepseek-v4-pro',
        });
        expect(await repository.defaultProvider, 'deepseek');
        expect(await repository.defaultModel, 'deepseek-v4-pro');
      },
    );
  });

  group('U-2 temperature / max_tokens 类型化读取（工单 03）', () {
    test('getTemperature 缺省 0.7；写入后读回；空串回退缺省', () async {
      expect(await repository.getTemperature(), 0.7);
      await repository.setMany({'temperature': '1.3'});
      expect(await repository.getTemperature(), 1.3);
      await repository.setMany({'temperature': ''});
      expect(await repository.getTemperature(), 0.7);
    });

    test('getTemperature 非数字回退缺省；越界 clamp 到 [0, 2]', () async {
      await repository.setMany({'temperature': 'abc'});
      expect(await repository.getTemperature(), 0.7);

      await repository.setMany({'temperature': '-1.5'});
      expect(await repository.getTemperature(), 0.0);

      await repository.setMany({'temperature': '9.9'});
      expect(await repository.getTemperature(), 2.0);
    });

    test('getMaxTokens 缺省 2048；数字往返；非数字回退缺省', () async {
      expect(await repository.getMaxTokens(), 2048);
      await repository.setMany({'max_tokens': '4096'});
      expect(await repository.getMaxTokens(), 4096);
      await repository.setMany({'max_tokens': 'xyz'});
      expect(await repository.getMaxTokens(), 2048);
    });

    test('temperature / max_tokens 白名单内：setMany 可写、getAll 可读', () async {
      await repository.setMany({'temperature': '1.2', 'max_tokens': '8192'});
      expect(await repository.getAll(), {
        'temperature': '1.2',
        'max_tokens': '8192',
      });
    });
  });

  group('U-3 templateVars JSON 读写（工单 04）', () {
    test('缺省空 map（无配置）', () async {
      expect(await repository.templateVars, isEmpty);
    });

    test('写入 JSON 后读回（往返一致）', () async {
      await repository.setMany({
        'template_vars': '{"city":"长安","place":"月牙泉"}',
      });
      expect(await repository.templateVars, {'city': '长安', 'place': '月牙泉'});
    });

    test('非法 JSON 回退空 map', () async {
      await repository.setMany({'template_vars': 'not-json{{{'});
      expect(await repository.templateVars, isEmpty);
    });

    test('JSON 非对象（数组）回退空 map', () async {
      await repository.setMany({'template_vars': '[1,2]'});
      expect(await repository.templateVars, isEmpty);
    });

    test('JSON 值非字符串的条目被过滤', () async {
      await repository.setMany({
        'template_vars': '{"city":"长安","count":3,"ok":true}',
      });
      expect(await repository.templateVars, {'city': '长安'});
    });

    test('template_vars 白名单内：setMany 可写、getAll 可读', () async {
      await repository.setMany({'template_vars': '{"a":"b"}'});
      expect(await repository.getAll(), {'template_vars': '{"a":"b"}'});
    });
  });

  group('U-4 onboarding_completed 读写（工单 05）', () {
    test('白名单内：setMany 可写、getValue 读回一致、getAll 可读', () async {
      await repository.setMany({'onboarding_completed': 'true'});
      expect(await repository.getValue('onboarding_completed'), 'true');
      expect(await repository.getAll(), {'onboarding_completed': 'true'});
    });

    test('缺失回退空串（isCompleted 判「未完成」的仓储侧契约）', () async {
      expect(await repository.getValue('onboarding_completed'), '');
    });

    test('空串值行读回空串（与缺失同判「未完成」）', () async {
      await repository.setMany({'onboarding_completed': ''});
      expect(await repository.getValue('onboarding_completed'), '');
    });
  });

  group('A5 apiKey 解析链三级回退（G5，InMemorySecretStore 实证）', () {
    test('第一级：provider 特定槽位（claude / openai 自身即槽位键）', () async {
      await secretStore.write(
        key: SecretStore.claudeApiKeySlot,
        value: 'sk-claude',
      );
      expect(await repository.apiKey('claude'), 'sk-claude');

      await secretStore.write(
        key: SecretStore.openaiApiKeySlot,
        value: 'sk-openai',
      );
      expect(await repository.apiKey('openai'), 'sk-openai');
    });

    test('第二级：同协议槽位（deepseek → openai 槽）', () async {
      await secretStore.write(
        key: SecretStore.openaiApiKeySlot,
        value: 'sk-openai',
      );
      expect(await repository.apiKey('deepseek'), 'sk-openai');
      expect(await repository.apiKey('qwen'), 'sk-openai');
    });

    test('第三级：跨协议兜底（仅 claude 槽有值时，openai 协议请求解析到 claude 槽值）', () async {
      await secretStore.write(
        key: SecretStore.claudeApiKeySlot,
        value: 'sk-claude',
      );
      expect(await repository.apiKey('openai'), 'sk-claude');
      expect(await repository.apiKey('deepseek'), 'sk-claude');
    });

    test('双槽位都有值：同协议槽位优先于跨协议兜底', () async {
      await secretStore.write(
        key: SecretStore.claudeApiKeySlot,
        value: 'sk-claude',
      );
      await secretStore.write(
        key: SecretStore.openaiApiKeySlot,
        value: 'sk-openai',
      );
      expect(await repository.apiKey('deepseek'), 'sk-openai');
      expect(await repository.apiKey('claude'), 'sk-claude');
      expect(await repository.apiKey('openai'), 'sk-openai');
    });

    test('全空返回空串；空串槽位视同未配置（链继续走）', () async {
      expect(await repository.apiKey('claude'), '');

      await secretStore.write(key: SecretStore.openaiApiKeySlot, value: '');
      await secretStore.write(
        key: SecretStore.claudeApiKeySlot,
        value: 'sk-claude',
      );
      expect(await repository.apiKey('openai'), 'sk-claude');
    });

    test('未知 provider 透传兜底两槽位（镜像桌面候选序）', () async {
      await secretStore.write(
        key: SecretStore.claudeApiKeySlot,
        value: 'sk-claude',
      );
      expect(await repository.apiKey('foo'), 'sk-claude');
    });
  });

  group('A6 baseUrl 同形链 + Key 写入重定向（G5）', () {
    test('baseUrl 同形链读设置表：provider 特定 → 同协议 → 跨协议', () async {
      await repository.setMany({
        'openai_base_url': 'https://openai.example/v1',
      });
      expect(await repository.baseUrl('deepseek'), 'https://openai.example/v1');
      expect(await repository.baseUrl('openai'), 'https://openai.example/v1');
      expect(await repository.baseUrl('claude'), 'https://openai.example/v1');

      await repository.setMany({'claude_base_url': 'https://claude.example'});
      expect(await repository.baseUrl('claude'), 'https://claude.example');
      expect(await repository.baseUrl('deepseek'), 'https://openai.example/v1');
    });

    test('baseUrl 全空返回空串', () async {
      expect(await repository.baseUrl('claude'), '');
    });

    test('写 Key 后设置表无明文 Key 行；槽位有值且读取重定向', () async {
      await repository.setMany({
        'claude_api_key': 'sk-ant-secret',
        'user_name': '小明',
      });

      final rows = await tableRows();
      expect(rows.containsKey('claude_api_key'), isFalse);
      expect(rows, {'user_name': '小明'});
      expect(await repository.getAll(), {'user_name': '小明'});

      expect(
        await secretStore.containsKey(SecretStore.claudeApiKeySlot),
        isTrue,
      );
      expect(
        await secretStore.read(SecretStore.claudeApiKeySlot),
        'sk-ant-secret',
      );
      // getValue 对 api_key 两键的读取同样重定向（与写入对称）
      expect(await repository.getValue('claude_api_key'), 'sk-ant-secret');
      expect(await repository.apiKey('claude'), 'sk-ant-secret');
    });

    test('重定向写入覆盖旧槽位值；写空串即清空（读回空串）', () async {
      await repository.setMany({'openai_api_key': 'sk-old'});
      await repository.setMany({'openai_api_key': 'sk-new'});
      expect(await secretStore.read(SecretStore.openaiApiKeySlot), 'sk-new');

      await repository.setMany({'openai_api_key': ''});
      expect(await secretStore.read(SecretStore.openaiApiKeySlot), '');
      expect(await repository.getValue('openai_api_key'), '');
    });
  });

  group('VR-01 embedding 设置域（阶段 3 装配腿）', () {
    test('embeddingEnabled 缺省 false（SR-19 默认关）；仅存 true 才开启', () async {
      expect(await repository.embeddingEnabled, isFalse);

      await repository.setMany({
        SettingsRepository.embeddingEnabledKey: 'true',
      });
      expect(await repository.embeddingEnabled, isTrue);

      // 其余值一律 false（'1' / 大写 / 空串）
      await repository.setMany({SettingsRepository.embeddingEnabledKey: '1'});
      expect(await repository.embeddingEnabled, isFalse);
      await repository.setMany({
        SettingsRepository.embeddingEnabledKey: 'TRUE',
      });
      expect(await repository.embeddingEnabled, isFalse);
      await repository.setMany({SettingsRepository.embeddingEnabledKey: ''});
      expect(await repository.embeddingEnabled, isFalse);
    });

    test('embedding_api_key 重定向 SecretStore：设置表无行、getAll 无明文', () async {
      await repository.setMany({
        SecretStore.embeddingApiKeySlot: 'sk-embed-secret',
        SettingsRepository.embeddingModelKey: 'text-embedding-3-small',
      });

      final rows = await tableRows();
      expect(rows.containsKey('embedding_api_key'), isFalse);
      expect(rows.containsKey('embedding_model'), isTrue);
      final all = await repository.getAll();
      expect(all.containsKey('embedding_api_key'), isFalse);
      expect(all, containsPair('embedding_model', 'text-embedding-3-small'));
      expect(all.values, isNot(contains('sk-embed-secret')));

      expect(
        await secretStore.containsKey(SecretStore.embeddingApiKeySlot),
        isTrue,
      );
      expect(
        await secretStore.read(SecretStore.embeddingApiKeySlot),
        'sk-embed-secret',
      );
      // getValue 对 embedding_api_key 的读取与写入对称重定向
      expect(
        await repository.getValue(SecretStore.embeddingApiKeySlot),
        'sk-embed-secret',
      );
    });

    test('embedding_api_key 写空串即清空槽位（读回空串，视同未配置）', () async {
      await repository.setMany({SecretStore.embeddingApiKeySlot: 'sk-old'});
      await repository.setMany({SecretStore.embeddingApiKeySlot: ''});
      expect(await secretStore.read(SecretStore.embeddingApiKeySlot), '');
      expect(await repository.getValue(SecretStore.embeddingApiKeySlot), '');
    });

    test('embeddingApiKey 槽链：embedding 槽优先，空则回退 openai 槽', () async {
      // 双槽皆空 → 空串
      expect(await repository.embeddingApiKey, '');

      // 仅 openai 槽 → 兜底
      await secretStore.write(
        key: SecretStore.openaiApiKeySlot,
        value: 'sk-openai',
      );
      expect(await repository.embeddingApiKey, 'sk-openai');

      // embedding 槽有值 → 优先于 openai 槽
      await secretStore.write(
        key: SecretStore.embeddingApiKeySlot,
        value: 'sk-embed',
      );
      expect(await repository.embeddingApiKey, 'sk-embed');

      // embedding 槽写空串视同未配置，回到 openai 兜底
      await repository.setMany({SecretStore.embeddingApiKeySlot: ''});
      expect(await repository.embeddingApiKey, 'sk-openai');
    });

    test('embeddingApiKey 专用槽链不并入 _slotValue（claude 槽不兜底）', () async {
      await secretStore.write(
        key: SecretStore.claudeApiKeySlot,
        value: 'sk-claude',
      );
      // 既有跨协议链对 openai 协议会兜到 claude 槽，但 embedding 链止于 openai
      expect(await repository.apiKey('openai'), 'sk-claude');
      expect(await repository.embeddingApiKey, '');
    });

    test('embeddingModel 缺省 text-embedding-3-small；写入后读回', () async {
      expect(await repository.embeddingModel, 'text-embedding-3-small');

      await repository.setMany({
        SettingsRepository.embeddingModelKey: 'text-embedding-3-large',
      });
      expect(await repository.embeddingModel, 'text-embedding-3-large');

      await repository.setMany({SettingsRepository.embeddingModelKey: ''});
      expect(await repository.embeddingModel, 'text-embedding-3-small');
    });

    test('embeddingBaseUrl 缺省空串；写入后读回', () async {
      expect(await repository.embeddingBaseUrl, '');

      await repository.setMany({
        SettingsRepository.embeddingBaseUrlKey: 'https://api.openai.com/v1',
      });
      expect(await repository.embeddingBaseUrl, 'https://api.openai.com/v1');

      await repository.setMany({SettingsRepository.embeddingBaseUrlKey: ''});
      expect(await repository.embeddingBaseUrl, '');
    });

    test('补漏锚：既有'
        "'true'"
        '判定 getter 与 memoryPromptMode 同族语义不回归', () async {
      // 与 embeddingEnabled 同族的 'true' 判定 getter（本票行覆盖补漏锚）
      expect(await repository.memoryReflectionEnabled, isFalse);
      expect(await repository.proactiveMessageEnabled, isFalse);
      expect(await repository.innerThoughtEnabled, isFalse);
      expect(await repository.memoryPromptMode, 'medium');

      await repository.setMany({
        SettingsRepository.memoryReflectionEnabledKey: 'true',
        SettingsRepository.proactiveMessageEnabledKey: 'true',
        SettingsRepository.innerThoughtEnabledKey: 'true',
        SettingsRepository.memoryPromptModeKey: 'strong',
      });
      expect(await repository.memoryReflectionEnabled, isTrue);
      expect(await repository.proactiveMessageEnabled, isTrue);
      expect(await repository.innerThoughtEnabled, isTrue);
      expect(await repository.memoryPromptMode, 'strong');
    });

    test('补漏锚：缺省 secretStore 走 FlutterSecretStore（默认构造路径）', () async {
      FlutterSecureStorage.setMockInitialValues(const {});
      final defaultRepository = SettingsRepository(database: db);
      expect(await defaultRepository.getValue('user_name'), '');
      expect(await defaultRepository.embeddingApiKey, '');
    });
  });

  group('落表行为（真 schema 契约）', () {
    test('settings 表主键为 key（TEXT 主键）', () async {
      final columns = await db
          .customSelect('PRAGMA table_info(settings)')
          .get();
      final keyColumn = columns
          .map((row) => row.data)
          .firstWhere((c) => c['name'] == 'key');
      expect(keyColumn['pk'], 1);
    });

    test('同键重复写入不产生重复行（upsert 落表实证）', () async {
      await repository.setMany({'theme_mode': 'dark'});
      await repository.setMany({'theme_mode': 'light'});
      final rows = await tableRows();
      expect(rows, {'theme_mode': 'light'});
    });
  });

  group('B1 wireCredentialsResolver 四键接线（C2 装配收敛）', () {
    /// 同一设置态下，[SettingsRepository.wireCredentialsResolver] 与手工四
    /// reader tear-off 装配的解析器 resolve() 结果字段全等（等价性契约：
    /// 装配收敛只搬接线不搬逻辑，两路径可观察行为逐位一致）。
    Future<void> expectEquivalentResolve({
      required bool hasKey,
      Map<String, String> settings = const {},
    }) async {
      await secretStore.write(
        key: SecretStore.claudeApiKeySlot,
        value: hasKey ? 'sk-claude' : '',
      );
      await repository.setMany(settings);

      final viaRepository = await repository
          .wireCredentialsResolver()
          .resolve();
      final manually = await CredentialsResolver(
        defaultProvider: () => repository.defaultProvider,
        defaultModel: () => repository.defaultModel,
        apiKey: repository.apiKey,
        baseUrl: repository.baseUrl,
      ).resolve();

      expect(viaRepository.provider, manually.provider);
      expect(viaRepository.apiKey, manually.apiKey);
      expect(viaRepository.model, manually.model);
      expect(viaRepository.baseUrl, manually.baseUrl);
    }

    test('缺省 provider/model + 已配置 key（含 base_url 归一）', () async {
      await expectEquivalentResolve(
        hasKey: true,
        settings: {'claude_base_url': 'https://claude.example'},
      );
    });

    test('显式 default_provider / default_model（覆盖缺省回退）', () async {
      await expectEquivalentResolve(
        hasKey: true,
        settings: {
          'default_provider': 'deepseek',
          'default_model': 'deepseek-v4-pro',
        },
      );
    });

    test('空 key 或空槽位 → 两路径同抛 ApiKeyMissingError（既有错误面不改写）', () async {
      await repository.setMany({'default_provider': 'claude'});

      Future<Object?> flat(Future<ResolvedCredentials> Function() run) async {
        try {
          await run();
          return null;
        } on ApiKeyMissingError catch (e) {
          return e;
        }
      }

      final viaRepository = await flat(
        repository.wireCredentialsResolver().resolve,
      );
      final manually = await flat(
        () => CredentialsResolver(
          defaultProvider: () => repository.defaultProvider,
          defaultModel: () => repository.defaultModel,
          apiKey: repository.apiKey,
          baseUrl: repository.baseUrl,
        ).resolve(),
      );

      expect(viaRepository, isA<ApiKeyMissingError>());
      expect(manually, isA<ApiKeyMissingError>());
      expect(
        (viaRepository! as ApiKeyMissingError).message,
        (manually! as ApiKeyMissingError).message,
        reason: '拆错路径文案与手工接线逐字一致',
      );
    });
  });

  group('WL-05 记忆宫殿设置键（白名单 + 类型化 getter）', () {
    test('allowedKeys 含两键常量（锚：memoryPalaceEnabledKey / memoryPalaceEveryRoundsKey）', () {
      expect(SettingsRepository.memoryPalaceEnabledKey, 'memory_palace_enabled');
      expect(
        SettingsRepository.memoryPalaceEveryRoundsKey,
        'memory_palace_every_rounds',
      );
      expect(
        SettingsRepository.allowedKeys,
        contains(SettingsRepository.memoryPalaceEnabledKey),
      );
      expect(
        SettingsRepository.allowedKeys,
        contains(SettingsRepository.memoryPalaceEveryRoundsKey),
      );
    });

    test('缺省常量：enabled 缺省 false、every_rounds 缺省 6（对齐 reflection 先例默认关）', () {
      expect(SettingsRepository.defaultMemoryPalaceEveryRounds, 6);
    });

    test('memoryPalaceEnabled 缺省 false（无键 / 空串 / 其他值）', () async {
      expect(await repository.memoryPalaceEnabled, isFalse);

      await repository.setMany({SettingsRepository.memoryPalaceEnabledKey: ''});
      expect(await repository.memoryPalaceEnabled, isFalse);

      await repository.setMany({SettingsRepository.memoryPalaceEnabledKey: '1'});
      expect(await repository.memoryPalaceEnabled, isFalse);

      await repository.setMany({SettingsRepository.memoryPalaceEnabledKey: 'TRUE'});
      expect(await repository.memoryPalaceEnabled, isFalse);
    });

    test('memoryPalaceEnabled 存储值 true 即开启；写空串恢复缺省', () async {
      expect(await repository.memoryPalaceEnabled, isFalse);
      await repository.setMany({SettingsRepository.memoryPalaceEnabledKey: 'true'});
      expect(await repository.memoryPalaceEnabled, isTrue);

      await repository.setMany({SettingsRepository.memoryPalaceEnabledKey: ''});
      expect(await repository.memoryPalaceEnabled, isFalse);
    });

    test('memoryPalaceEveryRounds 缺省 6；非法值回退缺省', () async {
      expect(await repository.memoryPalaceEveryRounds, 6);

      await repository.setMany({SettingsRepository.memoryPalaceEveryRoundsKey: 'abc'});
      expect(await repository.memoryPalaceEveryRounds, 6);

      await repository.setMany({SettingsRepository.memoryPalaceEveryRoundsKey: ''});
      expect(await repository.memoryPalaceEveryRounds, 6);
    });

    test('memoryPalaceEveryRounds 写入读回', () async {
      await repository.setMany({SettingsRepository.memoryPalaceEveryRoundsKey: '12'});
      expect(await repository.memoryPalaceEveryRounds, 12);
    });

    test('白名单外 memory_palace 附近键名仍被忽略（既有语义不回归）', () async {
      await repository.setMany({
        'memory_palace_enabled_extra': 'true',
        'memory_palace': '1',
      });
      expect(await repository.getAll(), isEmpty);
    });
  });

  group('NPD-01 叙述风格设置键（白名单 + 真值口径 + 回退）', () {
    /// 桌面 `setting.py::NARRATIVE_STYLE_DEFAULT_RULES`（278~290 行）逐字
    /// 迁移的期望值（独立来源：桌面文件 eval 值，含文末冲突从句）。
    const expectedDefaultRules =
        '叙述风格约束（降低 AI 生成痕迹）：\n'
        '1. 禁止总结式收尾，不以感慨、升华或归纳结束回复。\n'
        '2. 禁止「总之」「值得注意的是」「首先……其次……」等句式。\n'
        '3. 只输出角色台词、动作与内心活动，不输出说明性正文。\n'
        '4. 禁止括号外旁白与动机解释，想法只通过动作或内心呈现。\n'
        '5. 禁止复读用户输入，不机械重复对方刚说过的话。\n'
        '6. 禁止使用 emoji、markdown 标题或列表，行文以自然段落为主。\n'
        '7. 禁止机械对称的一问一答与堆砌式小作文。\n'
        '8. 保持人称与语气一致，与角色设定契合。\n'
        '9. 不确定如何回应时，用短句与动作推进场景。\n'
        '若与角色设定冲突，以角色设定为准。';

    test('allowedKeys 含两键常量（锚：narrativeStyleEnabledKey / narrativeStyleRulesKey）', () {
      expect(SettingsRepository.narrativeStyleEnabledKey, 'narrative_style_enabled');
      expect(SettingsRepository.narrativeStyleRulesKey, 'narrative_style_rules');
      expect(
        SettingsRepository.allowedKeys,
        contains(SettingsRepository.narrativeStyleEnabledKey),
      );
      expect(
        SettingsRepository.allowedKeys,
        contains(SettingsRepository.narrativeStyleRulesKey),
      );
    });

    test('默认规则常量逐字对齐桌面（含文末冲突从句，验收 3）', () {
      expect(SettingsRepository.narrativeStyleDefaultRules, expectedDefaultRules);
      expect(
        SettingsRepository.narrativeStyleDefaultRules,
        endsWith('若与角色设定冲突，以角色设定为准。'),
      );
    });

    test('可经 setMany/getValue 往返（白名单内可写，验收 1）', () async {
      await repository.setMany({
        SettingsRepository.narrativeStyleEnabledKey: '0',
        SettingsRepository.narrativeStyleRulesKey: '自定义规则',
      });
      expect(
        await repository.getValue(SettingsRepository.narrativeStyleEnabledKey),
        '0',
      );
      expect(
        await repository.getValue(SettingsRepository.narrativeStyleRulesKey),
        '自定义规则',
      );
    });

    test('narrativeStyleEnabled 缺省 true（无键视为开启，opt-out，验收 2）', () async {
      expect(await repository.narrativeStyleEnabled, isTrue);
    });

    test('真值口径矩阵：\'0\' 关闭；\'1\'/\'true\'/\'yes\' 大小写不敏感 → true（验收 2）', () async {
      await repository.setMany({SettingsRepository.narrativeStyleEnabledKey: '0'});
      expect(await repository.narrativeStyleEnabled, isFalse, reason: "'0' 显式关闭");

      for (final value in ['1', 'true', 'TRUE', 'True', 'yes', 'YES', 'Yes']) {
        await repository.setMany({SettingsRepository.narrativeStyleEnabledKey: value});
        expect(
          await repository.narrativeStyleEnabled,
          isTrue,
          reason: "存储值 '$value' 应视为开启",
        );
      }
    });

    test('真值口径：白名单外值视为关闭；空串回退缺省 default（对齐桌面 get_value）', () async {
      await repository.setMany({SettingsRepository.narrativeStyleEnabledKey: '2'});
      expect(await repository.narrativeStyleEnabled, isFalse);

      // 桌面 get_value(key, default="1")：空值行回退 default "1" → true。
      // （镜像 getValue defaultValue 语义——本票 getter 以 '1' 为缺省。）
      await repository.setMany({SettingsRepository.narrativeStyleEnabledKey: ''});
      expect(await repository.narrativeStyleEnabled, isTrue);
    });

    test('narrativeStyleRules 非空返回原值（验收 3）', () async {
      await repository.setMany({
        SettingsRepository.narrativeStyleRulesKey: '我的自定义叙述规则',
      });
      expect(
        await repository.narrativeStyleRules,
        '我的自定义叙述规则',
      );
    });

    test('narrativeStyleRules 空 / 缺省回退默认规则常量（验收 3）', () async {
      expect(await repository.narrativeStyleRules, expectedDefaultRules);

      await repository.setMany({SettingsRepository.narrativeStyleRulesKey: ''});
      expect(await repository.narrativeStyleRules, expectedDefaultRules);
    });

    test('narrativeStyleRules 纯空白原样返回（桌面 or 语义：\'   \' 为 truthy）', () async {
      await repository.setMany({SettingsRepository.narrativeStyleRulesKey: '   '});
      expect(await repository.narrativeStyleRules, '   ');
    });

    test('白名单外 narrative 附近键名仍被忽略（既有语义不回归）', () async {
      await repository.setMany({
        'narrative_style_enabled_extra': 'true',
        'narrative_style': '1',
      });
      expect(await repository.getAll(), isEmpty);
    });
  });
}
