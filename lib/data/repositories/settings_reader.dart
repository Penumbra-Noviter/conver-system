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
/// 契约：对应设置键缺失或为空串时返回空串 `''`（空串 = 视同未配置）；
/// 缺省值兜底腿（`claude` / `claude-sonnet-5` / `User`）由消费方
/// （会话仓储）回退，本接口不做缺省填充。
abstract interface class SettingsReader {
  /// 设置键 `default_provider` 的原始值；缺失或空串返回 `''`。
  Future<String> get defaultProvider;

  /// 设置键 `default_model` 的原始值；缺失或空串返回 `''`。
  Future<String> get defaultModel;

  /// 设置键 `user_name` 的原始值；缺失或空串返回 `''`。
  Future<String> get userName;
}
