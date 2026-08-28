/// 会话仓储对设置的读取面 — 消费方定义的单薄 seam（SettingsReader）。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/setting.py`（get_value / default_provider /
/// default_model / user_name）
///
/// 并发拆分说明（工单 03）：
/// - 本接口由工单 03（会话仓储消费方）定义，使会话仓储与设置仓储可并行开发、
///   各自单测；
/// - 实现由工单 04 的设置仓储在装配期提供（implements 接线归工单 07）；
/// - 工单 03 测试用内存假实现（见 test/data/repositories/
///   conversation_repository_test.dart），不等待工单 04。
library;

/// 三个类型化读取方法 — 键值语义与桌面 `get_value` 一致。
///
/// 契约：对应设置键缺失或为空串时返回空串 `''`（空串 = 视同未配置）；
/// 缺省值兜底腿（`claude` / `claude-sonnet-5` / `User`）由消费方
/// （会话仓储）回退，本接口不做缺省填充。
abstract interface class SettingsReader {
  /// 设置键 `default_provider` 的原始值；缺失或空串返回 `''`。
  Future<String> defaultProvider();

  /// 设置键 `default_model` 的原始值；缺失或空串返回 `''`。
  Future<String> defaultModel();

  /// 设置键 `user_name` 的原始值；缺失或空串返回 `''`。
  Future<String> userName();
}
