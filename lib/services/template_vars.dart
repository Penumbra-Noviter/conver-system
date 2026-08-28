/// {{user}}/{{char}} 模板变量替换 — 纯函数，无任何 I/O 依赖。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/llm/prompt.py::apply_template_vars`
///
/// M2 复用点：prompt 组装（build_messages 对应物）与 mes_example 解析
/// 将复用本函数，不另写第二份替换逻辑。
library;

/// 替换文本中的模板变量：`{{user}}` → [userName]，`{{char}}` → [charName]。
///
/// 行为与桌面 `apply_template_vars` 逐条对齐：
/// - 空文本原样返回（不做任何替换）；
/// - 不含占位符的文本原样返回；
/// - 先替换 `{{user}}` 再替换 `{{char}}`（与桌面 replace 链同序）；
/// - 不做递归替换（替换值中若含占位符文本，按同序一次性处理）。
String applyTemplateVars(
  String text, {
  String userName = 'User',
  String charName = 'Character',
}) {
  if (text.isEmpty) {
    return text;
  }
  return text.replaceAll('{{user}}', userName).replaceAll('{{char}}', charName);
}
