/// 最近对话窗口单源纯 builder（F-148，波 2 C3）。
///
/// 回合末伴生服务（反思 / 主动消息 / 记忆宫殿）的「全量拉取 → sublist(20) →
/// 署名行」同构管道收敛于此：仓库侧 [MessageRepository.recentMessages] 定位读
/// 取尾 N，本 builder 对已有序消息片段收窗口（尾 N + 可选字符预算从后截断），
/// 返回窗口消息列表（排序不变）。署名差异化由各服务在调用点显式传入
/// （三套语义逐字保持：reflection 角色名 / proactive 原文直给 / palace
/// `role.value`），本模块不代签。
///
/// 预算口径：从窗口最末（最近）条目起向前累加 `content.length`，累计遇到
/// **首个超预算**条目即停——该条与其前全部排除（保留最近内容）。累计恰好
/// 等于预算的条目保留（> 才截断，与旧行字符预算同口径）。
library;

import '../../data/database/app_database.dart' show Message;

/// 取最近 [limit] 条消息作为对话窗口，返回升序（与输入序一致）。
///
/// - [messages] 为有序消息片段（通常为
///   [MessageRepository.recentMessages] 结果，已取尾 N）；[limit] 是窗口
///   语义上限，重复作用于输入幂等（输入已 ≤ limit 则原样）；
/// - [charBudget] 非空 → 额外从后往前按 `content.length` 累加截断（见文件
///   docstring 口径）；null → 仅限长；
/// - [limit] ≤ 0 → 空窗口；[charBudget] 小于单条内容长度时该条连同更早
///   条目一并排除（可导致空窗口）。
///
/// 返回新列表，不修改输入。
List<Message> recentDialogueWindow(
  List<Message> messages, {
  required int limit,
  int? charBudget,
}) {
  if (limit <= 0) {
    return const <Message>[];
  }
  final tailLength = messages.length > limit ? limit : messages.length;
  final tail = messages.sublist(messages.length - tailLength);
  if (charBudget == null) {
    return tail;
  }
  var budget = 0;
  final kept = <Message>[];
  for (final m in tail.reversed) {
    budget += m.content.length;
    if (budget > charBudget) {
      break;
    }
    kept.add(m);
  }
  return kept.reversed.toList();
}