/// 安全存储 seam — API Key 凭证槽位的抽象接口与 flutter_secure_storage 薄实现。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/setting.py`（ALLOWED_KEYS 两 api_key 键；
/// 解析链消费方见其 `_slot_value` / `api_key`）
///
/// 职责边界（M1-T01）：
/// - 本模块只负责两个固定槽位的写/读/删/含键，槽位键名与桌面白名单逐字相同；
///   provider → 槽位的三级解析回退链不在本层（工单 04，镜像桌面 setting 服务
///   消费 provider_registry 的分层）
/// - 真通道（Android Keystore / iOS Keychain）行为不在宿主单测验证，归 G6
///   模拟器冒烟；单测以内存 fake（test/helpers/in_memory_secret_store.dart）
///   承载契约，见 test/services/secure_store_test.dart
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 系统安全存储的凭证槽位接口 — M1 唯一新平台 seam。
///
/// 契约（与桌面 `get_value` 的空串语义一致）：
/// - [read]：缺失或已删返回空串 `''`，不做 null 区分（空串 = 视同未配置）
/// - [write]：同键重复写即覆盖；写入空串则读回空串
/// - [delete]：对不存在的键为无害 no-op（与 flutter_secure_storage 一致）
/// - [containsKey]：反映槽位是否存在（写入过且未删除），与空串语义独立
abstract interface class SecretStore {
  /// claude 协议凭证槽位键 — 与桌面 ALLOWED_KEYS 的 `claude_api_key` 逐字相同
  static const String claudeApiKeySlot = 'claude_api_key';

  /// openai 协议凭证槽位键 — 与桌面 ALLOWED_KEYS 的 `openai_api_key` 逐字相同
  static const String openaiApiKeySlot = 'openai_api_key';

  /// 写入（或覆盖）[key] 槽位的 [value]
  Future<void> write({required String key, required String value});

  /// 读取 [key] 槽位的值；缺失或已删返回空串
  Future<String> read(String key);

  /// 删除 [key] 槽位；键不存在时 no-op
  Future<void> delete(String key);

  /// 槽位 [key] 是否存在（写入过且未删除）
  Future<bool> containsKey(String key);
}

/// [SecretStore] 的 flutter_secure_storage 11.x 薄实现 — 仅参数转发，零业务逻辑。
///
/// 转发映射：[write] / [delete] / [containsKey] 同名直转；[read] 转发后将平台层
/// 的 null（键缺失）归一化为空串，使消费方拿到与桌面 `get_value` 一致的空串语义。
class FlutterSecretStore implements SecretStore {
  /// 创建实现；[storage] 仅供测试注入替身，缺省用默认平台配置
  FlutterSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<String> read(String key) async => await _storage.read(key: key) ?? '';

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);
}
