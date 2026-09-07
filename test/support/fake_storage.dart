/// 存档契约层测试假件：localStorage 兼容 [SaveStorage]（本票自建测试辅助，
/// 不进 helpers —— helpers 无同型 storage 先例）。
///
/// 语义与桌面 save-manager.test.js `makeStorage` 假件一致：`Map<String,String>`
/// 背衬、插入序枚举（key(i)）、读写删除、`__proto__` 键为普通键（Dart Map
/// 无原型污染问题）。另支持按键注入 setItem / removeItem 抛错（对拍桌面
/// 回滚用例 TD-63 / TD-73 的配额失败与回滚失败注入）。
library;

import 'package:conver_system_mobile/services/simulator/save_contract.dart';

/// 可控 mock：key(i) 越界返回 null，setItem 覆盖写，removeItem 不存在时 no-op。
class FakeSaveStorage implements SaveStorage {
  /// 以 [seed] 初值构建（seed 含 `__proto__` 键即覆盖普通键语义）。
  FakeSaveStorage([Map<String, String>? seed]) {
    if (seed != null) _store.addAll(seed);
  }

  final Map<String, String> _store = {};

  /// setItem 抛错注入：键 → 命中时 throw 该对象（验证写失败路径与回滚）。
  final Map<String, Object> setItemThrows = {};

  /// removeItem 抛错注入：键 → 命中时 throw 该对象（验证尽力而为回滚）。
  final Map<String, Object> removeItemThrows = {};

  @override
  int get length => _store.length;

  @override
  String? key(int index) {
    if (index < 0 || index >= _store.length) return null;
    return _store.keys.elementAt(index);
  }

  @override
  String? getItem(String key) => _store[key];

  @override
  void setItem(String key, String value) {
    final throwable = setItemThrows[key];
    if (throwable != null) {
      throw throwable;
    }
    _store[key] = value;
  }

  @override
  void removeItem(String key) {
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