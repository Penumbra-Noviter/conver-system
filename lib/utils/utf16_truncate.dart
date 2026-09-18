/// 文本快照长度工具（F-114/F-115 单源收敛）。
///
/// 全仓「快照内容截断上限」的单一权威定义与实现：人设演化快照
/// （[PersonaEvolutionService]）与 embedding 内容快照
/// （[MemoryRepository.upsertEmbedding]）共用本常量与本截断函数，防双源
/// 漂移；截断按 UTF-16 code unit 计数（与 Dart [String.length] 口径一致），
/// 并在边界处避免把代理对（surrogate pair）劈开产生尾部 U+FFFD。
library;

/// 快照截断上限（UTF-16 code unit 计数口径，与 [String.length] 一致）。
const int maxSnapshotLength = 2000;

/// 把 [text] 截断到不超过 [maxCodeUnits] 个 UTF-16 code unit，且不在代理对
/// 中间切断。
///
/// 若 `text.length <= maxCodeUnits` 原样返回（不复制）；否则取前
/// `maxCodeUnits` 个 code unit，若最后一个恰为高代理（high surrogate，
/// 0xD800..0xDBFF，其低代理在界外），则再多截 1 个，避免落库尾部出现
/// 无法解码的孤立代理 → U+FFFD。返回串长度 `<= maxCodeUnits`。
String truncateUtf16(String text, int maxCodeUnits) {
  if (maxCodeUnits <= 0) {
    return '';
  }
  if (text.length <= maxCodeUnits) {
    return text;
  }
  final cut = text.substring(0, maxCodeUnits);
  final last = cut.codeUnitAt(cut.length - 1);
  if (last >= 0xD800 && last <= 0xDBFF) {
    return text.substring(0, maxCodeUnits - 1);
  }
  return cut;
}
