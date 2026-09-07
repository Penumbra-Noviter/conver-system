/// 存档读写层测试假件：localStorage 访问抽象 [LocalStorageAccess]（F-M5-06
/// 本票自建测试辅助，不进 helpers —— helpers 无同型 async storage 先例）。
///
/// 语义与 `save_contract_test.dart` 的 [FakeSaveStorage] 同构（Map 背衬、插入序
/// 枚举、读写删除、`__proto__` 键为普通键），但面向 F-M5-06 读写层 seam：
/// `enumerate()` 返回副本 / `setItem` `removeItem` 为 async 且可注入抛错
/// （对拍生产 runJavaScript 写失败路径与回滚用例 TD-63 / TD-73）。
library;

import 'package:conver_system_mobile/services/simulator/save_bridge.dart'
    show LocalStorageAccess;

/// 可控 mock：enumerate 返回当前内容副本，setItem 覆盖写，removeItem 不存在
/// 时 no-op。
class FakeLocalStorageAccess implements LocalStorageAccess {
  /// 以 [seed] 初值构建（seed 含 `__proto__` 键即覆盖普通键语义）。
  FakeLocalStorageAccess([Map<String, String>? seed]) {
    if (seed != null) _store.addAll(seed);
  }

  final Map<String, String> _store = {};

  /// setItem 抛错注入：键 → 命中时 throw 该对象（验证写失败路径与回滚）。
  final Map<String, Object> setItemThrows = {};

  /// removeItem 抛错注入：键 → 命中时 throw 该对象（验证尽力而为回滚）。
  final Map<String, Object> removeItemThrows = {};

  @override
  Future<Map<String, String>> enumerate() async => Map.of(_store);

  @override
  Future<void> setItem(String key, String value) async {
    final throwable = setItemThrows[key];
    if (throwable != null) {
      throw throwable;
    }
    _store[key] = value;
  }

  @override
  Future<void> removeItem(String key) async {
    final throwable = removeItemThrows[key];
    if (throwable != null) {
      throw throwable;
    }
    _store.remove(key);
  }

  /// 便捷读（测试断言）。
  String? operator [](String key) => _store[key];

  /// 当前内容快照（不可变副本，断言存储终态）。
  Map<String, String> get snapshot => Map.unmodifiable(_store);
}