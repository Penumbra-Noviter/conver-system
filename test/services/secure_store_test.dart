/// SecretStore 契约套件 — 同一组行为断言跑在两个实现上：
/// 1. InMemorySecretStore（内存 fake，M1 凭证相关单测的共享替身）
/// 2. FlutterSecretStore（经 flutter_secure_storage 官方测试平台 mock 转发，
///    验证薄实现的参数转发，非真通道）
///
/// 真通道（Android Keystore / iOS Keychain）不在宿主单测范围，归 G6 模拟器冒烟。
/// 槽位键名逐字锚定桌面 `backend/app/services/setting.py::ALLOWED_KEYS`。
library;

import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_secret_store.dart';

/// 契约（工单 T01-A4）：写→读回原值；覆盖写→读回新值；删→读空；未写→读空
void _contractSuite(String label, SecretStore Function() createStore) {
  group('$label 契约', () {
    late SecretStore store;

    setUp(() => store = createStore());

    test('未写 → 读空', () async {
      expect(await store.read(SecretStore.claudeApiKeySlot), '');
    });

    test('写 → 读回原值', () async {
      await store.write(key: SecretStore.claudeApiKeySlot, value: 'sk-ant-123');
      expect(await store.read(SecretStore.claudeApiKeySlot), 'sk-ant-123');
    });

    test('覆盖写 → 读回新值', () async {
      await store.write(key: SecretStore.openaiApiKeySlot, value: 'old-key');
      await store.write(key: SecretStore.openaiApiKeySlot, value: 'new-key');
      expect(await store.read(SecretStore.openaiApiKeySlot), 'new-key');
    });

    test('删 → 读空；containsKey 随之翻 false', () async {
      await store.write(key: SecretStore.claudeApiKeySlot, value: 'k');
      expect(await store.containsKey(SecretStore.claudeApiKeySlot), isTrue);

      await store.delete(SecretStore.claudeApiKeySlot);
      expect(await store.read(SecretStore.claudeApiKeySlot), '');
      expect(await store.containsKey(SecretStore.claudeApiKeySlot), isFalse);
    });

    test('删不存在的键 → no-op 不抛错', () async {
      await store.delete(SecretStore.claudeApiKeySlot);
      expect(await store.containsKey(SecretStore.claudeApiKeySlot), isFalse);
    });

    test('未写 → containsKey false；写后 true', () async {
      expect(await store.containsKey(SecretStore.openaiApiKeySlot), isFalse);
      await store.write(key: SecretStore.openaiApiKeySlot, value: 'k');
      expect(await store.containsKey(SecretStore.openaiApiKeySlot), isTrue);
    });

    test('两槽位互不影响', () async {
      await store.write(key: SecretStore.claudeApiKeySlot, value: 'claude-k');
      expect(await store.read(SecretStore.openaiApiKeySlot), '');
      expect(await store.containsKey(SecretStore.openaiApiKeySlot), isFalse);
    });

    test('空串写入 → 读回空串（空串 = 视同未配置，与桌面 get_value 语义一致）', () async {
      await store.write(key: SecretStore.claudeApiKeySlot, value: '');
      expect(await store.read(SecretStore.claudeApiKeySlot), '');
    });
  });
}

void main() {
  // FlutterSecretStore 转发验证所依赖的插件官方测试平台（内存实现）：
  // 每个用例前重置平台 mock 数据，保证用例间无残留。
  // 注意必须传可变 map —— mock 平台持有该 map 引用并原地读写
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  _contractSuite('InMemorySecretStore', InMemorySecretStore.new);
  _contractSuite('FlutterSecretStore（插件官方测试平台 mock）', FlutterSecretStore.new);

  group('槽位键名常量（A3：与桌面 ALLOWED_KEYS 逐字相同）', () {
    test('claude 槽位键逐字为 claude_api_key', () {
      expect(SecretStore.claudeApiKeySlot, 'claude_api_key');
    });

    test('openai 槽位键逐字为 openai_api_key', () {
      expect(SecretStore.openaiApiKeySlot, 'openai_api_key');
    });

    test('两槽位键名互异（防复制粘贴同键）', () {
      expect(SecretStore.claudeApiKeySlot, isNot(SecretStore.openaiApiKeySlot));
    });
  });
}
