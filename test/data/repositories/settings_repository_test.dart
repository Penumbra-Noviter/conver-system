/// 设置仓储契约测试（M1-T04，验收门 G5 逐条）。
///
/// 全部在内存执行器（`AppDatabase(NativeDatabase.memory())`）上打真 schema；
/// SecretStore 用共享 fake（test/helpers/in_memory_secret_store.dart）。
/// 语义锚定桌面 `backend/app/services/setting.py`（ALLOWED_KEYS / get_value /
/// get_int / get_all / set_many / _slot_value / api_key / base_url）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:drift/native.dart';
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

  group('A1 白名单键集（G5）', () {
    test('与桌面 ALLOWED_KEYS 十键逐字相等', () {
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
        }),
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
        await repository.getValue('default_provider_name', defaultValue: 'Claude'),
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
      expect(await tableRows().then((rows) => rows.containsKey('user_name')),
          isTrue);
      expect(await repository.getValue('user_name'), '');
    });

    test('getInt：数字往返；非数字 / 缺失回退 default', () async {
      await repository.setMany({'sliding_window_rounds': '15'});
      expect(await repository.getInt('sliding_window_rounds', defaultValue: 30),
          15);

      await repository.setMany({'sliding_window_rounds': 'abc'});
      expect(await repository.getInt('sliding_window_rounds', defaultValue: 30),
          30);

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

    test('default_provider / default_model 缺省 claude / claude-sonnet-5',
        () async {
      expect(await repository.defaultProvider, 'claude');
      expect(await repository.defaultModel, 'claude-sonnet-5');

      await repository.setMany({
        'default_provider': 'deepseek',
        'default_model': 'deepseek-v4-pro',
      });
      expect(await repository.defaultProvider, 'deepseek');
      expect(await repository.defaultModel, 'deepseek-v4-pro');
    });
  });

  group('A5 apiKey 解析链三级回退（G5，InMemorySecretStore 实证）', () {
    test('第一级：provider 特定槽位（claude / openai 自身即槽位键）', () async {
      await secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-claude');
      expect(await repository.apiKey('claude'), 'sk-claude');

      await secretStore.write(key: SecretStore.openaiApiKeySlot, value: 'sk-openai');
      expect(await repository.apiKey('openai'), 'sk-openai');
    });

    test('第二级：同协议槽位（deepseek → openai 槽）', () async {
      await secretStore.write(key: SecretStore.openaiApiKeySlot, value: 'sk-openai');
      expect(await repository.apiKey('deepseek'), 'sk-openai');
      expect(await repository.apiKey('qwen'), 'sk-openai');
    });

    test('第三级：跨协议兜底（仅 claude 槽有值时，openai 协议请求解析到 claude 槽值）',
        () async {
      await secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-claude');
      expect(await repository.apiKey('openai'), 'sk-claude');
      expect(await repository.apiKey('deepseek'), 'sk-claude');
    });

    test('双槽位都有值：同协议槽位优先于跨协议兜底', () async {
      await secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-claude');
      await secretStore.write(key: SecretStore.openaiApiKeySlot, value: 'sk-openai');
      expect(await repository.apiKey('deepseek'), 'sk-openai');
      expect(await repository.apiKey('claude'), 'sk-claude');
      expect(await repository.apiKey('openai'), 'sk-openai');
    });

    test('全空返回空串；空串槽位视同未配置（链继续走）', () async {
      expect(await repository.apiKey('claude'), '');

      await secretStore.write(key: SecretStore.openaiApiKeySlot, value: '');
      await secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-claude');
      expect(await repository.apiKey('openai'), 'sk-claude');
    });

    test('未知 provider 透传兜底两槽位（镜像桌面候选序）', () async {
      await secretStore.write(key: SecretStore.claudeApiKeySlot, value: 'sk-claude');
      expect(await repository.apiKey('foo'), 'sk-claude');
    });
  });

  group('A6 baseUrl 同形链 + Key 写入重定向（G5）', () {
    test('baseUrl 同形链读设置表：provider 特定 → 同协议 → 跨协议', () async {
      await repository.setMany({'openai_base_url': 'https://openai.example/v1'});
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
      expect(
        await secretStore.read(SecretStore.openaiApiKeySlot),
        'sk-new',
      );

      await repository.setMany({'openai_api_key': ''});
      expect(await secretStore.read(SecretStore.openaiApiKeySlot), '');
      expect(await repository.getValue('openai_api_key'), '');
    });
  });

  group('落表行为（真 schema 契约）', () {
    test('settings 表主键为 key（TEXT 主键）', () async {
      final columns = await db.customSelect(
        'PRAGMA table_info(settings)',
      ).get();
      final keyColumn =
          columns.map((row) => row.data).firstWhere((c) => c['name'] == 'key');
      expect(keyColumn['pk'], 1);
    });

    test('同键重复写入不产生重复行（upsert 落表实证）', () async {
      await repository.setMany({'theme_mode': 'dark'});
      await repository.setMany({'theme_mode': 'light'});
      final rows = await tableRows();
      expect(rows, {'theme_mode': 'light'});
    });
  });
}
