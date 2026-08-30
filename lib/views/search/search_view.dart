/// 搜索页（M3-04b 重写 20 行空壳）：防抖五态 + 结果列表 + 高亮第一处。
///
/// 语义锚点（桌面，逐字对齐）：
/// - `desktop/frontend/js/search-view.js`：防抖 300ms / Enter 立即查询 /
///   Escape 清空失焦 / 清空按钮；五态文案逐字（空输入 / 至少输入 2 个
///   字符 / 搜索中… / 未找到匹配的消息 / 搜索失败: <原因>）；结果头
///   「共找到 N 条匹配消息」；
/// - `desktop/frontend/js/format.js::searchResultItemHtml`：role 标签
///   （user →「你」，其余 → 角色名）+ 对话标题 + 预览（高亮第一处，
///   大小写不敏感，见顶层纯函数 [highlightFirst]）+ 时间。
///
/// 层级：呈现层。数据通路经 [SearchService]（缺省由注入的 [MessageRepository]
/// 构建，生产全内存库零平台通道）；结果点击经注入钩子 [onSelectResult]
/// （本票默认 no-op，M3-04c 在 home_shell 注入真实跳转定位）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/message_repository.dart';
import '../../services/search_service.dart';
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';

/// 高亮纯函数结果：原样文本 + 第一处命中区间（无命中 / 空 query 时
/// [start] / [end] 均为 null，文本原样返回——桌面 highlightText 语义）。
typedef HighlightRange = ({String text, int? start, int? end});

/// 预览高亮纯函数（桌面 `format.js::highlightText` 语义逐字）：
///
/// - 不区分大小写（`toLowerCase` 比对）定位**第一处**命中；
/// - 返回 [HighlightRange]：`text` 恒为原样 [content]；命中时 [start] /
///   [end] 为第一处区间，无命中 / 空 [query] 时为 null（原样文本）；
/// - 不做 trim（桌面调用方 search-view.js 已 trim keyword 后传入）。
HighlightRange highlightFirst(String content, String query) {
  if (query.isEmpty) {
    return (text: content, start: null, end: null);
  }
  final idx = content.toLowerCase().indexOf(query.toLowerCase());
  if (idx < 0) {
    return (text: content, start: null, end: null);
  }
  // 大小写折叠（如 'İ'.toLowerCase() 展开为 'i̇'）会使 lowerContent 长度
  // 与 content 不同，用 lower 偏移切原串可能越界——clamp 回原串安全区间。
  final start = idx < content.length ? idx : content.length;
  final end =
      (idx + query.length) < content.length ? idx + query.length : content.length;
  if (start >= end) {
    return (text: content, start: null, end: null);
  }
  return (text: content, start: start, end: end);
}

/// 结果预览高亮样式（amber 底，对齐桌面 `.search-highlight`）。
/// 视图层经 colorScheme 消费 accent token（F-7 契约：不直接引用色板常量）。
TextStyle _highlightStyle(BuildContext context) =>
    TextStyle(
      backgroundColor:
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.13),
    );

/// 搜索页状态机（仅本文件内部可见，外部通过渲染结果观察）。
enum _SearchPhase {
  /// 空输入：提示「输入关键词搜索所有对话中的消息」。
  empty,

  /// 查询少于 2 字符：「至少输入 2 个字符」。
  tooShort,

  /// 查询进行中：「搜索中…」。
  searching,

  /// 无命中：「未找到匹配的消息」。
  noResults,

  /// 查询失败：「搜索失败: <原因>」。
  error,

  /// 有结果：结果头 + 结果列表。
  results,
}

/// 搜索页（M3-04b）：输入防抖 300ms + 五态 + 结果列表 + 高亮第一处。
///
/// 构造约定：无参 `const SearchView()` 可由 home_shell 直接挂载（service
/// 缺省从 provider 读 [MessageRepository] 构建）；测试注入可控 service 与
/// [onSelectResult] 钩子。
class SearchView extends StatefulWidget {
  const SearchView({super.key, this.service, this.onSelectResult});

  /// 搜索服务（测试注入；缺省从 provider 读 [MessageRepository] 构建，
  /// 生产全内存库零平台通道）。
  final SearchService? service;

  /// 结果点击钩子 `(conversationId, messageId)`（本票默认 no-op；
  /// M3-04c 在 home_shell 注入真实跳转定位实现）。
  final void Function(int conversationId, int messageId)? onSelectResult;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  /// 防抖窗口（对齐桌面 search-view.js L67-96 的 300ms）。
  static const _debounceDelay = Duration(milliseconds: 300);

  late final SearchService _service;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  _SearchPhase _phase = _SearchPhase.empty;
  List<SearchResult> _results = const [];
  String _errorReason = '';
  String _query = '';

  /// 请求序号：递增标记每次查询，仅应用最新一次的结果（防止较慢的旧查询
  /// 在较新的查询之后返回并覆盖新结果）。
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ?? SearchService(context.read<MessageRepository>());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 输入变更：重建防抖 timer（500ms 内连发只发一次，桌面 search-view.js）。
  void _onChanged(String value) {
    setState(() {}); // 刷新清空按钮可见性。
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => _performSearch(value));
  }

  /// Enter 立即查询（取消防抖，不等 300ms）。
  void _onSubmitted(String value) {
    _debounce?.cancel();
    _performSearch(value);
  }

  /// Escape 或清空按钮：清空输入 + 失焦 + 回空态（不触发查询）。
  void _clearAndReset() {
    _debounce?.cancel();
    // 递增请求序号使在途查询作废（W2 增量审核真缺回归：不递增时
    // 旧查询返回会把已清空的结果回填覆盖空态）。
    _requestSeq++;
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _phase = _SearchPhase.empty;
      _results = const [];
      _errorReason = '';
    });
  }

  /// 防抖 / Enter 共用入口（对齐桌面 performSearch）：五态转换。
  Future<void> _performSearch(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _phase = _SearchPhase.empty;
        _results = const [];
      });
      return;
    }
    if (query.length < 2) {
      setState(() {
        _phase = _SearchPhase.tooShort;
        _results = const [];
      });
      return;
    }
    final seq = ++_requestSeq;
    setState(() => _phase = _SearchPhase.searching);
    try {
      final results = await _service.search(query);
      if (!mounted || seq != _requestSeq) {
        return; // 卸载或已有更新的查询——丢弃过期结果。
      }
      setState(() {
        _results = results;
        _query = query;
        _phase =
            results.isEmpty ? _SearchPhase.noResults : _SearchPhase.results;
      });
    } catch (error) {
      if (!mounted || seq != _requestSeq) {
        return; // 卸载或已有更新的查询——丢弃过期错误。
      }
      setState(() {
        _errorReason = _errorMessage(error);
        _phase = _SearchPhase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ConverSpacing.space4,
              ConverSpacing.space1,
              ConverSpacing.space4,
              ConverSpacing.space2,
            ),
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _clearAndReset();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: _onSubmitted,
                decoration: InputDecoration(
                  hintText: '搜索消息内容',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          icon: const Icon(Icons.clear),
                          onPressed: _clearAndReset,
                        ),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 正文区按五态渲染（空 / 拦截 / 搜索中 / 未找到 / 失败 / 结果）。
  Widget _buildBody() {
    switch (_phase) {
      case _SearchPhase.empty:
        return _CenteredMessage('输入关键词搜索所有对话中的消息');
      case _SearchPhase.tooShort:
        return const _CenteredMessage('至少输入 2 个字符');
      case _SearchPhase.searching:
        return const _CenteredMessage('搜索中…');
      case _SearchPhase.noResults:
        return const _CenteredMessage('未找到匹配的消息');
      case _SearchPhase.error:
        return _CenteredMessage('搜索失败: $_errorReason');
      case _SearchPhase.results:
        return _buildResults();
    }
  }

  /// 结果头 + 结果列表。
  Widget _buildResults() {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ConverSpacing.space4,
            ConverSpacing.space1,
            ConverSpacing.space4,
            ConverSpacing.space1,
          ),
          child: Text(
            '共找到 ${_results.length} 条匹配消息',
            style: textTheme.labelLarge?.copyWith(color: palette.ink3),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final result = _results[index];
              return _SearchResultTile(
                result: result,
                query: _query,
onTap: () => widget.onSelectResult
                        ?.call(result.conversationId, result.messageId),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 从异常提取原因文案（对齐桌面 `err.message`：剥离 `Exception: ` 类型前缀）。
  static String _errorMessage(Object error) {
    final text = error.toString();
    final sep = text.indexOf(': ');
    return sep >= 0 ? text.substring(sep + 2) : text;
  }
}

/// 头部：标题「搜索」（对齐 characters_view._Header 结构）。
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ConverSpacing.space4,
        ConverSpacing.space5,
        ConverSpacing.space4,
        ConverSpacing.space2,
      ),
      child: Text(
        '搜索',
        style: textTheme.titleLarge?.copyWith(color: palette.ink1),
      ),
    );
  }
}

/// 居中状态文案（空 / 拦截 / 搜索中 / 未找到 / 失败共用）。
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ConverSpacing.space4),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: palette.ink3),
        ),
      ),
    );
  }
}

/// 单个搜索结果项：role 标签 + 对话标题 + 高亮预览 + 时间。
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.query,
    required this.onTap,
  });

  final SearchResult result;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final roleLabel = result.role == 'user' ? '你' : result.characterName;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ConverSpacing.space4,
          ConverSpacing.space2,
          ConverSpacing.space4,
          ConverSpacing.space2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RoleChip(label: roleLabel),
                const SizedBox(width: ConverSpacing.space2),
                Expanded(
                  child: Text(
                    result.conversationTitle,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium
                        ?.copyWith(color: palette.ink2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ConverSpacing.space1),
            Text.rich(
              TextSpan(children: _previewSpans(context)),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
            ),
            const SizedBox(height: ConverSpacing.space1),
            Text(
              _formatTime(result.createdAt),
              style: textTheme.labelSmall?.copyWith(color: palette.ink4),
            ),
            Divider(height: 24, color: palette.border),
          ],
        ),
      ),
    );
  }

  /// 预览 spans：`searchPreview` ±50 窗口后 [highlightFirst] 定位第一处命中。
  List<InlineSpan> _previewSpans(BuildContext context) {
    final preview = searchPreview(result.content, query);
    final range = highlightFirst(preview, query);
    if (range.start == null || range.end == null) {
      return [TextSpan(text: preview)];
    }
    return [
      TextSpan(text: preview.substring(0, range.start!)),
      TextSpan(
        text: preview.substring(range.start!, range.end!),
        style: _highlightStyle(context),
      ),
      TextSpan(text: preview.substring(range.end!)),
    ];
  }

  /// 时间展示（桌面 `toLocaleString('zh-CN')` 的移动端等价：yyyy-MM-dd HH:mm）。
  static String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

/// role 标签（user →「你」，其余 → 角色名）。
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primary
            .withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
