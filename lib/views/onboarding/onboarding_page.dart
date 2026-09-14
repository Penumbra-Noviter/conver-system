/// 首启分页新手指引页（工单 05 / spec §U-4）。
///
/// 全屏 `PageView` 3–5 页 + 每页顶部「跳过」+ 末页「开始使用」。零第三方动画
/// 库（只消费 `PageController.nextPage` + [ConverDurations] token），视觉对齐
/// Warm Stone token（[ConverPalette] / [ConverSpacing] / [ConverRadii]）。
///
/// 层级：呈现层。只经 [onFinished] 回调交还「完成/跳过」事件，不触碰数据层 /
/// 平台存储（标记落库由装配层 `app.dart` 完成，spec §U-4 高不确定点取
/// 「状态翻转」方案而非 `Navigator.pushReplacement`）。
library;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import '../../theme/motion.dart';

/// 单页指引内容（icon / title / description）。
class _SlideData {
  const _SlideData({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

/// 指引页内容（4 页，线性图标无 emoji，文案对齐应用核心使用路径）。
const List<_SlideData> _slides = <_SlideData>[
  _SlideData(
    icon: Icons.auto_awesome_outlined,
    title: '欢迎使用汇流',
    description: 'AI 角色扮演助手，对话、角色、搜索、模拟器一应俱全。',
  ),
  _SlideData(
    icon: Icons.person_add_alt_1_outlined,
    title: '创建你的角色',
    description: '手动创建、从模板开始，或粘贴设定文档让 AI 智能导入。',
  ),
  _SlideData(
    icon: Icons.chat_bubble_outline,
    title: '与角色对话',
    description: '直连 LLM 流式回复，滑动窗口上下文与重生成随时可用。',
  ),
  _SlideData(
    icon: Icons.explore_outlined,
    title: '探索更多',
    description: '搜索历史对话、解析文档，运行内置的模拟器游戏。',
  ),
];

/// 首次启动的分页新手指引页。
class OnboardingPage extends StatefulWidget {
  /// 构造指引页；[onFinished] 在「跳过」或「开始使用」时被调用（异步完成）。
  const OnboardingPage({super.key, required this.onFinished});

  /// 完成/跳过回调——由装配层标记落库并切回主界面。
  final Future<void> Function() onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 「跳过」/「开始使用」统一落点：幂等防连点，await 装配层回调。
  Future<void> _finish() async {
    if (_finishing) {
      return;
    }
    _finishing = true;
    try {
      await widget.onFinished();
    } finally {
      _finishing = false;
    }
  }

  /// 非末页「下一步」：翻到下一页（消费 ConverDurations.mid）。
  void _next() {
    _controller.nextPage(
      duration: ConverDurations.mid,
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  ConverSpacing.space4,
                  ConverSpacing.space2,
                  ConverSpacing.space2,
                  0,
                ),
                child: TextButton(
                  onPressed: () => _finish(),
                  child: Text(
                    '跳过',
                    style: TextStyle(color: palette.ink3),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (index) => setState(() => _page = index),
                children: [
                  for (final slide in _slides) _Slide(data: slide),
                ],
              ),
            ),
            _PageDots(count: _slides.length, current: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ConverSpacing.space4,
                ConverSpacing.space2,
                ConverSpacing.space4,
                ConverSpacing.space4,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLast ? () => _finish() : _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  child: Text(isLast ? '开始使用' : '下一步'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单页内容：圆底线性图标 + 标题 + 说明。
class _Slide extends StatelessWidget {
  const _Slide({required this.data});

  final _SlideData data;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ConverSpacing.space8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              shape: BoxShape.circle,
              border: Border.all(color: palette.border),
            ),
            child: Icon(data.icon, size: 44, color: colorScheme.primary),
          ),
          const SizedBox(height: ConverSpacing.space8),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(color: palette.ink1),
          ),
          const SizedBox(height: ConverSpacing.space3),
          Text(
            data.description,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
          ),
        ],
      ),
    );
  }
}

/// 分页指示点（当前页 accent 高亮）。
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ConverSpacing.space3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: ConverDurations.fast,
              margin: const EdgeInsets.symmetric(
                horizontal: ConverSpacing.space1,
              ),
              width: i == current ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == current
                    ? colorScheme.primary
                    : palette.border,
                borderRadius: BorderRadius.circular(ConverRadii.md),
              ),
            ),
        ],
      ),
    );
  }
}
