/// Prompt Debug 只读面板（PD-04）— 展示组装核心逐条分段与来源标注。
///
/// 语义锚点（桌面 `prompt-polish-spec.md §PD-3` 六条锁的展示面）：
/// - 顶部元数据：角色名 / 模型（`provider/model`）/ prompt_mode；
/// - 每段：role 徽标 + 来源色标 + 等宽预排版 content（保留换行）；
/// - 来源 → 样式为**单一映射表**（[_promptSourceStylesOf]，不散落 if/else）；
///   未知来源取值回落默认样式不抛错（防御，验收 7）；
/// - 空 segments → 空态提示；关闭即弃、无编辑入口（只读见证）。
///
/// 层级：呈现层。接收已组装好的 [PromptDebugResult]（[ChatService.promptDebug]
/// 只读产出），零数据层 / 平台存储引用（layer_boundary_test 契约）；面板关闭
/// 即弃，无持久化 / 无编辑入口。视图层经 ConverPalette / Theme colorScheme
/// 取色（view_theme_tokens_test：视图不直接引用 design-token 色常量）。
library;

import 'package:flutter/material.dart';

import '../../services/chat_service.dart' show PromptDebugResult;
import '../../services/llm/prompt.dart';
import '../../theme/colors.dart' show ConverRadii, ConverSpacing;
import '../../theme/conver_palette.dart';

/// 来源 → 展示样式（标签 + 色标）的**单一映射表**。
///
/// 不许散落 if/else：新增来源只在表内登记；未知/非法来源经
/// [_promptSourceStyleOf] 回落默认（防御，验收 7）。色值全部派生自当前
/// theme 的 ConverPalette / colorScheme token（浅/深两套自动跟随）。
class _PromptSourceStyle {
  const _PromptSourceStyle({required this.label, required this.color});

  /// 来源中文标签（UI 层枚举，业务语义锚于 prompt.dart 来源常量）。
  final String label;

  /// 色标（theme token 派生，见 [_promptSourceStylesOf]）。
  final Color color;
}

/// 构建来源 → 样式单一映射表（每次 build 求值，token 随主题深浅切换）。
///
/// 色相分配（仅语义区分，不绑定业务含义）：
/// - 角色=primary（琥珀强调色）；记忆=tertiary；用户=secondary；
/// - 世界书 / 历史 = ink2/ink3 中性灰阶；叙述风格=error 色族（醒目）；
/// - Mod=danger 色族（占位）；未知默认=ink4 弱化。
Map<String, _PromptSourceStyle> _promptSourceStylesOf(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final palette = ConverPalette.of(context);
  return {
    sourceCharacter: _PromptSourceStyle(label: '角色', color: scheme.primary),
    sourceWorld: _PromptSourceStyle(label: '世界书', color: palette.ink3),
    sourceMemory: _PromptSourceStyle(label: '记忆', color: scheme.tertiary),
    sourceHistory: _PromptSourceStyle(label: '历史', color: palette.ink2),
    sourceUser: _PromptSourceStyle(label: '用户', color: scheme.secondary),
    sourceNarrative:
        _PromptSourceStyle(label: '叙述风格', color: scheme.error),
    sourceMod: _PromptSourceStyle(label: 'Mod', color: scheme.error),
  };
}

/// 非法 / 未知来源的默认样式（防御：不抛错，落灰色弱化）。
_PromptSourceStyle _unknownSourceStyle(BuildContext context) =>
    _PromptSourceStyle(label: '未知', color: ConverPalette.of(context).ink4);

/// 来源 → 样式单点查询：表内命中返回，否则回退默认（table lookup，
/// 无 if/else 链）。
_PromptSourceStyle _promptSourceStyleOf(
  BuildContext context,
  String source,
) =>
    _promptSourceStylesOf(context)[source] ?? _unknownSourceStyle(context);

/// Prompt Debug 只读面板组件（接受已组装结果，纯展示）。
///
/// 用法：经 showModalBottomSheet 弹出（`isScrollControlled: true`）；关闭即弃
/// （关闭按钮 + 下拉手柄），无编辑入口、无持久化。
class PromptDebugSheet extends StatelessWidget {
  const PromptDebugSheet({super.key, required this.result});

  /// 已组装好的 debug 结果（只读见证，零外发）。
  final PromptDebugResult result;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ConverSpacing.space4,
                ConverSpacing.space2,
                ConverSpacing.space2,
                ConverSpacing.space2,
              ),
              child: _SheetHeader(
                characterName: result.characterName,
                model: result.model,
                promptMode: result.promptMode,
              ),
            ),
            Divider(height: 1, color: palette.border),
            Expanded(
              child: result.segments.isEmpty
                  ? _EmptySegments(palette: palette)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        vertical: ConverSpacing.space2,
                      ),
                      itemCount: result.segments.length,
                      itemBuilder: (context, index) {
                        final segment = result.segments[index];
                        return _SegmentTile(
                          role: segment.role,
                          content: segment.content,
                          source: segment.source,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 面板头部：角色名（title）+ 模型 / prompt_mode（副行）。
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.characterName,
    required this.model,
    required this.promptMode,
  });

  final String characterName;
  final String model;
  final String promptMode;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                characterName.isEmpty ? '角色' : characterName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(color: palette.ink1),
              ),
              const SizedBox(height: ConverSpacing.space1),
              Text(
                '模型 $model · prompt_mode $promptMode',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: palette.ink4),
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('prompt-debug-close'),
          tooltip: '关闭',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// 单段展示：role 徽标 + 来源色标 + 等宽预排版 content（保留换行）。
class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.role,
    required this.content,
    required this.source,
  });

  final String role;
  final String content;
  final String source;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final sourceStyle = _promptSourceStyleOf(context, source);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space4,
        vertical: ConverSpacing.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RoleBadge(role: role),
              const SizedBox(width: ConverSpacing.space2),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: sourceStyle.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: ConverSpacing.space1),
              Text(
                sourceStyle.label,
                style: textTheme.bodySmall?.copyWith(color: palette.ink3),
              ),
            ],
          ),
          const SizedBox(height: ConverSpacing.space1),
          Text(
            content,
            // 等宽预排版：monospace + 保留换行（RawText 不折叠 \n）。
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.45,
              color: palette.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

/// role 徽标：system/user/assistant 三色调小圆角标签（未知角色回落中性）。
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final Color background;
    switch (role) {
      case 'system':
        background = palette.ink4.withValues(alpha: 0.25);
      case 'user':
        background = scheme.primary.withValues(alpha: 0.13);
      case 'assistant':
        background = scheme.tertiary.withValues(alpha: 0.15);
      default:
        background = scheme.surfaceContainerHigh;
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(ConverRadii.sm),
      ),
      child: Text(
        role,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: palette.ink2),
      ),
    );
  }
}

/// 空 segments 空态提示（防御：debug 结果不产出分段时不崩、给出指引）。
class _EmptySegments extends StatelessWidget {
  const _EmptySegments({required this.palette});

  final ConverPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '暂无分段可展示',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: palette.ink4),
      ),
    );
  }
}