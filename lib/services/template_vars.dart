/// {{user}}/{{char}} 模板变量替换 — 纯函数，无任何 I/O 依赖。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/llm/prompt.py::apply_template_vars`
///
/// M2 复用点：prompt 组装（build_messages 对应物）与 mes_example 解析
/// 将复用本函数，不另写第二份替换逻辑。
library;

/// 替换文本中的模板变量：`{{user}}` → [userName]，`{{char}}` → [charName]，
/// 以及 [extraVars] 中的用户自定义 `{{key}}`（工单 04 / spec §U-3，mobile
/// 新增——桌面 `apply_template_vars` 仅 user/char，无 extraVars）。
///
/// 行为与桌面 `apply_template_vars` 逐条对齐，并扩展 extraVars：
/// - 空文本原样返回（不做任何替换）；
/// - 不含占位符的文本原样返回；
/// - 替换顺序：先 `{{user}}` → `{{char}}` → 再逐 key 替换 [extraVars]
///   （与桌面 replace 链同序，extraVars 追加于其后）；
/// - [extraVars] 按 key 长度**降序**替换（防 `{{a}}` 与 `{{ab}}` 前缀误替换）；
/// - 保留 key（`user` / `char`）优先：[extraVars] 中的同名 key 被跳过，
///   用户自定义 key 不覆盖内置两变量；
/// - 不做递归替换（替换值中若含占位符文本，按同序一次性处理）。
String applyTemplateVars(
  String text, {
  String userName = 'User',
  String charName = 'Character',
  Map<String, String> extraVars = const {},
}) {
  if (text.isEmpty) {
    return text;
  }
  var result =
      text.replaceAll('{{user}}', userName).replaceAll('{{char}}', charName);
  final keys = extraVars.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    if (key == 'user' || key == 'char') {
      continue;
    }
    result = result.replaceAll('{{$key}}', extraVars[key]!);
  }
  return result;
}
