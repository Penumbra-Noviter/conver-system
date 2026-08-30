/// 角色 tab 真实 UI（M3-01 重写 21 行空壳）：单列角色卡片列表。
///
/// 语义锚点（spec §Implementation Decisions 角色列表面 + 工单 01 验收）：
/// - 卡片语义对齐桌面 `characterCardHtml`：头像（缺省首字占位）/ 名称 /
///   描述（空 → personality 前 60 字）/ 开场白前 60 字（超长「…」）/ 标签 /
///   温度（一位小数）/ 对话数徽标；排序 updated_at 倒序由仓储契约保证；
/// - 下拉刷新（[RefreshIndicator]，空态亦可下拉）+ 切回 tab 自动刷新
///   （本层 initState 后帧回调触发 [CharactersController.refresh]，控制器
///   幂等——加载中合并，已有数据不闪烁）；
/// - 卡片四按钮：开始对话（切聊天 tab + [ChatController.createConversationFor]
///   直达新会话）/ 编辑（push 编辑表单）/ 导出（经 seam，Stub 占位提示）/
///   删除（确认文案含对话数 → 级联删除 + 列表刷新）；
/// - 空态「暂无角色」+ 创建引导；「新建角色」入口 push 6 步向导
///   （M3-01 留 stub，M3-02a 接真导航；[CharacterWizardView]）。
///
/// 层级：呈现层。经 [CharactersController] 注入，不触碰数据层 / 平台存储
/// （layer_boundary_test 契约）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database/app_database.dart' show Character;
import '../../data/repositories/character_repository.dart'
    show CharacterRepository, CharacterWithCount;
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import 'character_edit_view.dart';
import 'characters_controller.dart';
import 'wizard/character_wizard_controller.dart';
import 'wizard/character_wizard_view.dart';

/// 角色列表页：头部 + 提示条 + 卡片列表（RefreshIndicator 包裹）。
class CharactersView extends StatefulWidget {
  const CharactersView({super.key, required this.controller});

  /// 角色 tab 状态持有者（装配注入，单一事实来源）。
  final CharactersController controller;

  @override
  State<CharactersView> createState() => _CharactersViewState();
}

class _CharactersViewState extends State<CharactersView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // 切回角色 tab 自动刷新（HomeShell 重建本视图 → 重新 initState）：
    // 推迟到本帧 build 之后触发（避免 initState 期间 markNeedsBuild during
    // build）；controller refresh 幂等，已有数据不闪烁。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureLoaded();
      }
    });
  }

  void _onControllerChanged() => setState(() {});

  /// 幂等触发 [CharactersController.refresh]（对齐 ChatView._ensureEntryLoaded
  /// 模式：失败仅日志，保持缺省空列表）。
  Future<void> _ensureLoaded() async {
    try {
      await widget.controller.refresh();
    } catch (error) {
      debugPrint('角色列表刷新失败，保持缺省空列表: $error');
    }
  }

  /// 「新建角色」入口：push 6 步向导（M3-02a 接真导航，替换 M3-01 stub）。
  ///
  /// WizardController 经 [CharacterRepository]（provider 装配注入）构造；
  /// 向导保存成功后回调 [CharactersController.refresh] 刷新列表，pop 回本页。
  Future<void> _openWizard() async {
    final repository = context.read<CharacterRepository>();
    final wizard = WizardController(characterRepository: repository);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CharacterWizardView(
          controller: wizard,
          onSaved: () => unawaited(widget.controller.refresh()),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onCreate: () => unawaited(_openWizard())),
          if (controller.notice != null)
            _NoticeBanner(
              notice: controller.notice!,
              onDismiss: controller.dismissNotice,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: controller.characters.isEmpty
                  ? _EmptyState(loading: controller.loading)
                  : _CharacterList(controller: controller),
            ),
          ),
        ],
      ),
    );
  }
}

/// 头部：标题「角色」+「新建角色」入口（push 向导；M3-02a 接真）。
class _Header extends StatelessWidget {
  const _Header({required this.onCreate});

  /// 新建角色入口回调（由 state 层 push 向导）。
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ConverSpacing.space4,
        ConverSpacing.space5,
        ConverSpacing.space2,
        0,
      ),
      child: Row(
        children: [
          Text(
            '角色',
            style: textTheme.titleLarge?.copyWith(color: palette.ink1),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建角色'),
          ),
        ],
      ),
    );
  }
}

/// 非阻塞提示条（导出占位 / 加载失败 / 删除反馈），可
/// [CharactersController.dismissNotice]。
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.notice, required this.onDismiss});

  final String notice;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ConverSpacing.space4,
          ConverSpacing.space1,
          ConverSpacing.space1,
          ConverSpacing.space1,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                notice,
                style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
              ),
            ),
            IconButton(
              tooltip: '关闭提示',
              icon: Icon(Icons.close, size: 18, color: palette.ink4),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// 空态「暂无角色」+ 创建引导；首次加载中显示 spinner；可下拉刷新
/// （AlwaysScrollableScrollPhysics）。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.loading});

  /// 首次加载中（尚未完成过一次刷新）。
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline, size: 40, color: palette.ink4),
                const SizedBox(height: ConverSpacing.space2),
                Text(
                  '暂无角色',
                  style: textTheme.bodyMedium?.copyWith(color: palette.ink3),
                ),
                const SizedBox(height: ConverSpacing.space1),
                Text(
                  '点「新建角色」创建你的第一个角色',
                  style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单列角色卡片列表。
class _CharacterList extends StatelessWidget {
  const _CharacterList({required this.controller});

  final CharactersController controller;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        ConverSpacing.space4,
        ConverSpacing.space2,
        ConverSpacing.space4,
        ConverSpacing.space4,
      ),
      itemCount: controller.characters.length,
      itemBuilder: (context, index) {
        final row = controller.characters[index];
        return _CharacterCard(row: row, controller: controller);
      },
    );
  }
}

/// 单张角色卡片：头像 / 名称 / 描述（空 → personality 前 60 字）/ 开场白
/// 预览 / 标签 / 温度 / 对话数徽标 + 四按钮。
class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.row, required this.controller});

  final CharacterWithCount row;
  final CharactersController controller;

  @override
  Widget build(BuildContext context) {
    final character = row.character;
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final greeting = _preview(character.firstMes.trim(), 60);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: ConverSpacing.space2),
      padding: const EdgeInsets.fromLTRB(
        ConverSpacing.space3,
        ConverSpacing.space3,
        ConverSpacing.space3,
        ConverSpacing.space1,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(ConverRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(character: character),
              const SizedBox(width: ConverSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          textTheme.titleMedium?.copyWith(color: palette.ink1),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _cardDescription(character),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          textTheme.bodySmall?.copyWith(color: palette.ink2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (greeting.isNotEmpty) ...[
            const SizedBox(height: ConverSpacing.space2),
            Text(
              greeting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: palette.ink4),
            ),
          ],
          const SizedBox(height: ConverSpacing.space2),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: ConverSpacing.space2,
                  runSpacing: 2,
                  children: [
                    for (final tag in character.tags)
                      Text(
                        '#$tag',
                        style:
                            textTheme.labelSmall?.copyWith(color: palette.ink3),
                      ),
                  ],
                ),
              ),
              Text(
                _temperatureLabel(character.temperature),
                style:
                    textTheme.labelSmall?.copyWith(color: palette.ink3),
              ),
              const SizedBox(width: ConverSpacing.space3),
              _ConversationCountBadge(count: row.conversationCount),
            ],
          ),
          const SizedBox(height: ConverSpacing.space2),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      unawaited(controller.startConversation(character.id)),
                  icon: const Icon(Icons.forum_outlined, size: 18),
                  label: const Text('开始对话'),
                ),
              ),
              IconButton(
                tooltip: '编辑',
                icon: Icon(Icons.edit_outlined, color: palette.ink3),
                onPressed: () => _openEdit(context),
              ),
              IconButton(
                tooltip: '导出',
                icon: Icon(
                  Icons.file_download_outlined,
                  color: palette.ink3,
                ),
                onPressed: () =>
                    unawaited(controller.exportCharacter(character)),
              ),
              IconButton(
                tooltip: '删除',
                icon: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 打开编辑表单（push）。
  void _openEdit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CharacterEditView(
          controller: controller,
          character: row.character,
        ),
      ),
    );
  }

  /// 删除确认：文案含角色对话数（验收 5）；确认后经
  /// [CharactersController.deleteCharacter] 级联删除并刷新列表。
  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除角色'),
        content: Text(
          '删除角色「${row.character.name}」？'
          '删除后其 ${row.conversationCount} 个对话与消息将一并删除，'
          '此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteCharacter(row.character.id);
    }
  }
}

/// 头像：缺省首字占位（avatar 位图渲染随 M3-03 角色卡面处理，本票不触
/// 网络图片 / base64 解码通道）。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.character});

  final Character character;

  @override
  Widget build(BuildContext context) {
    final name = character.name.trim();
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 20,
      backgroundColor: colorScheme.surfaceContainerHighest,
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(color: colorScheme.primary, fontSize: 18),
      ),
    );
  }
}

/// 对话数徽标（桌面角色卡角标语义；「N 对话」）。
class _ConversationCountBadge extends StatelessWidget {
  const _ConversationCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(ConverRadii.xs),
      ),
      child: Text(
        '$count 对话',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: palette.ink3),
      ),
    );
  }
}

/// 卡片描述：非空直接预览；空 → personality 前 60 字（验收 1 兜底语义）。
String _cardDescription(Character character) {
  final description = character.description.trim();
  if (description.isNotEmpty) {
    return _preview(description, 60);
  }
  return _preview(character.personality.trim(), 60);
}

/// 温度标签：一位小数显示（缺省 0.7）。
String _temperatureLabel(double temperature) =>
    '温度 ${temperature.toStringAsFixed(1)}';

/// 前 [maxLen] 字预览：超长截断加「…」（与 truncateTitle 同按 Unicode
/// 码点切分，避免代理对被劈开）。
String _preview(String text, int maxLen) {
  final runes = text.runes;
  if (runes.length <= maxLen) {
    return text;
  }
  return '${String.fromCharCodes(runes.take(maxLen))}…';
}