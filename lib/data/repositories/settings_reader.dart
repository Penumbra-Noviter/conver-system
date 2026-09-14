/// 会话仓储对设置的读取面 — 消费方定义的单薄 seam（SettingsReader）。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/setting.py`（get_value / default_provider /
/// default_model / user_name）
///
/// 并发拆分说明（工单 03）：
/// - 本接口由工单 03（会话仓储消费方）定义，使会话仓储与设置仓储可并行开发、
///   各自单测；
/// - 实现由工单 04 的设置仓储在装配期提供（implements 接线由工单 07 完成）；
/// - 工单 03 测试用内存假实现（见 test/data/repositories/
///   conversation_repository_test.dart），不等待工单 04。
///
/// 形态修正（M1-T07）：成员由方法改为 **getter** 形态——spec §数据仓储对
/// 本 seam 的定义即「三个类型化 getter」，工单 04 设置仓储的同名成员亦为
/// getter；工单 03 实现时的方法形态使 `implements` 无法接线，本票对齐为
/// 两票共同约定的 getter 契约。
library;

/// 三个类型化读取 getter — 键值语义与桌面 `get_value` 一致。
///
/// 契约（2026-09-07 F-24 收敛，对齐既有实现）：
/// - 实现方（[SettingsRepository]）对缺失或空串的键返回 [SettingsDefaults]
///   填充值（`claude` / `claude-sonnet-5` / `User`）——**兜底常量单一归属**，
///   本文件为唯一来源；
/// - 消费方无需自行回退；若消费方仍需兜底（如测试假实现按空串语义返回），
///   必须引用 [SettingsDefaults] 而非复制常量，杜绝「填充值与兜底值碰巧
///   相等」的静默破约。
abstract interface class SettingsReader {
  /// 设置键 `default_provider` 的值；缺失或空串返回 [SettingsDefaults.provider]。
  Future<String> get defaultProvider;

  /// 设置键 `default_model` 的值；缺失或空串返回 [SettingsDefaults.model]。
  Future<String> get defaultModel;

  /// 设置键 `user_name` 的值；缺失或空串返回 [SettingsDefaults.userName]。
  Future<String> get userName;

  /// 设置键 `template_vars` 的值（JSON `{"key":"value",...}` 反序列化）。
  ///
  /// 缺失 / 空串 / 非法 JSON / 非对象 JSON → 空 map；值非字符串的条目被过滤。
  /// 实现由工单 04 的设置仓储提供（mobile 先行，桌面无对应特性）。
  Future<Map<String, String>> get templateVars;
}

/// 设置缺省值——桌面 `config.py` 常量（DEFAULT_PROVIDER='claude' /
/// DEFAULT_MODEL='claude-sonnet-5' / user_name 默认 'User'）的移动端等价物，
/// **单一归属**（2026-09-07 F-24 收敛）。
///
/// [SettingsReader] 实现方（[SettingsRepository]）的缺省填充与消费方
/// （[ConversationRepository]）的兜底均引用本常量——任何一侧改动即全局生效，
/// 不再存在「两份字面量碰巧相等」的隐性契约。
abstract final class SettingsDefaults {
  static const String provider = 'claude';
  static const String model = 'claude-sonnet-5';
  static const String userName = 'User';
}
