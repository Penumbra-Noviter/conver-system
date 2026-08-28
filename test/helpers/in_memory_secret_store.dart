/// SecretStore 的内存 fake — M1 全部凭证相关单测的共享替身（工单 T01）。
///
/// 行为逐条镜像 flutter_secure_storage 11.x 真通道的可观察契约
/// （键缺失读 null → SecretStore 层归一化空串、删除 no-op、写即覆盖），
/// 并与 FlutterSecretStore 共跑同一契约套件
/// （test/services/secure_store_test.dart）。真通道行为归 G6 模拟器冒烟。
library;

import 'package:conver_system_mobile/services/secure_store.dart';

/// 纯内存实现 — 无持久化，实例间不共享状态
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<String> read(String key) async => _values[key] ?? '';

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);
}
