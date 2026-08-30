/// 搜索服务 — 跨全部对话的消息 content 模糊检索编排 + 预览纯函数。
///
/// 桌面权威源（只读，语义锚点，逐字对齐）：
/// `desktop/backend/app/services/message.py::search_messages`（189–244 行）
/// 与 `desktop/backend/app/schemas/message.py::SearchResult`。
///
/// 对齐要点：
/// - 搜索范围 = 消息 `content` only（跨全部对话；不搜角色名 / 对话标题 /
///   开场白），结果排序 createdAt 倒序、同秒 id 倒序兜底、limit 50——
///   数据面全部委托 [MessageRepository.searchMessages]，本层零查询；
/// - `search` 编排：trim 后转交仓储；空串 / 纯空白短路空列表（零查询）；
///   仓储异常原样上抛（UI 层五态「搜索失败」消费契约，本票不做 UI）；
/// - `<2 字符拦截` 阈值归 UI 层五态（「至少输入 2 个字符」），服务层不设
///   阈值（工单验收 6 只要求空查询短路；分工以工单为准）；
/// - `SearchResult.role` 取 `Role.value`（user/assistant/system 字符串，
///   桌面 `msg.role.value` 语义）；`content` 为全文，预览由顶层纯函数
///   [searchPreview] 单独计算供 UI 直接消费。
library;

import '../data/repositories/message_repository.dart';

/// 消息搜索结果条目（对齐桌面 `SearchResult` 字段契约）。
///
/// `content` 为命中消息全文；预览窗口由顶层纯函数 [searchPreview] 计算
/// （UI 层直接消费，含高亮第一处）。
class SearchResult {
  const SearchResult({
    required this.messageId,
    required this.conversationId,
    required this.conversationTitle,
    required this.characterId,
    required this.characterName,
    required this.characterAvatar,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  /// 命中消息 id。
  final int messageId;

  /// 所属对话 id。
  final int conversationId;

  /// 对话标题。
  final String conversationTitle;

  /// 对话所属角色 id。
  final int characterId;

  /// 角色名。
  final String characterName;

  /// 角色头像（可空）。
  final String? characterAvatar;

  /// 消息角色值（`Role.value` 语义：user / assistant / system）。
  final String role;

  /// 命中消息全文。
  final String content;

  /// 消息时间戳。
  final DateTime createdAt;
}

/// 搜索预览纯函数（桌面 `search_messages` 内联预览逐字）：
///
/// - 命中（大小写不敏感，仅第一处）：`max(0, idx-50)` 起、
///   `min(len, idx+len(query)+50)` 止的窗口；窗口前被截断加「…」、
///   窗口后同理（桌面 `ctx_start / ctx_end` 公式）；
/// - 无命中：content 前 120 字，超长加「…」（桌面回退语义逐字；
///   恰好 120 字不加省略号）。
String searchPreview(String content, String query) {
  final lowerContent = content.toLowerCase();
  final lowerQuery = query.trim().toLowerCase();
  final idx = lowerContent.indexOf(lowerQuery);
  if (idx < 0) {
    return content.length <= 120 ? content : '${content.substring(0, 120)}…';
  }
  final ctxStart = idx - 50 > 0 ? idx - 50 : 0;
  final ctxEnd = idx + query.length + 50 < content.length
      ? idx + query.length + 50
      : content.length;
  final prefix = ctxStart > 0 ? '…' : '';
  final suffix = ctxEnd < content.length ? '…' : '';
  return '$prefix${content.substring(ctxStart, ctxEnd)}$suffix';
}

/// 搜索编排服务 — 纯数据通路，无平台 / 视图依赖。
class SearchService {
  /// [messageRepository] 为搜索数据源（三表 join 查询面）。
  SearchService(this._messageRepository);

  final MessageRepository _messageRepository;

  /// 跨全部对话的消息 content 检索（桌面 `search_messages` 语义）。
  ///
  /// - [query] 首尾空白先行 trim 再转交仓储；
  /// - 空串 / 纯空白 → 空列表（短路，不触仓储）；
  /// - 仓储异常原样上抛（UI 五态「搜索失败」消费契约）。
  Future<List<SearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final hits = await _messageRepository.searchMessages(trimmed);
    return [
      for (final hit in hits)
        SearchResult(
          messageId: hit.message.id,
          conversationId: hit.message.conversationId,
          conversationTitle: hit.conversation.title,
          characterId: hit.character.id,
          characterName: hit.character.name,
          characterAvatar: hit.character.avatar,
          role: hit.message.role.value,
          content: hit.message.content,
          createdAt: hit.message.createdAt,
        ),
    ];
  }
}
