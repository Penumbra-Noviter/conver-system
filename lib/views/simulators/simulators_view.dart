/// 模拟器列表页（F-M5-03 占位重写 + F-M5-07 导入钩子接线）——四态列表 +
/// 类型筛选 + AppBar 三入口 + 下拉刷新 + 钩子派发。
///
/// 验收语义（工单验收语义契约逐条）：
/// - 四态：loading（进度指示）/ ready（卡片网格）/ error（文案 + 「重试」
///   按钮，端口占用文案含「端口被占用」语义）/ empty（「暂无游戏」文案）；
/// - 卡片：名称 / 描述 / 类型徽标〔AI 驱动·纯本地〕/ 导入·生成 badge
///   （source 判据）/ 点击打开（`hooks.onOpen(game)`，F-M5-04 接线点）；
/// - 类型筛选 chips 三档（全部 / AI 驱动 / 纯本地）；
/// - AppBar「存档 / 导入 / AI 生成」三入口：钩子未接线（缺省 null）→ 禁用态；
///   接线后点击 → 派发对应回调（F-M5-06/07/08b 接线点）；
/// - 下拉刷新 → [SimulatorsController.refresh]；视图 init 后帧触发
///   [ensureStarted]（懒启动仅首进发起；控制器 App 存续期常驻不随 tab 销毁）。
///
/// F-M5-07 接线（post-03 顺序追加，spec §4.3 波次安全 + app.dart 装配注释）：
/// 默认 hooks（onImportTap 未接线）时以 [importFlow] 填充导入入口——既有注入
/// 钩子（constructor 注入）优先保留，绝不覆盖非空槽位。
///
/// 层级：呈现层。经 [SimulatorsController] 注入，不触碰数据层 / 平台存储
/// （layer_boundary_test 契约）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/colors.dart' show ConverRadii, ConverSpacing;
import '../../theme/conver_palette.dart';
import '../../view_models/simulators_controller.dart';
import 'import_flow.dart' show SimulatorImportFlow;
import 'simulators_hooks.dart' show SimulatorsHooks, appendImportHook;

/// 模拟器列表页：AppBar（三入口）+ 四态正文。
class SimulatorsView extends StatefulWidget {
  const SimulatorsView({
    super.key,
    required this.controller,
    this.importFlow,
  });

  /// 模拟器 tab 状态持有者（装配注入，单一事实来源）。
  final SimulatorsController controller;

  /// 导入流程实现（测试注入 fake；缺省默认 seam）。F-M5-07 接线点消费——
  /// 未接线（onImportTap 已由外部注入）时不生效。
  final SimulatorImportFlow? importFlow;

  @override
  State<SimulatorsView> createState() => _SimulatorsViewState();
}

class _SimulatorsViewState extends State<SimulatorsView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // 懒启动（仅首进 tab 发起；控制器幂等，成功后重复触发短路）。
    // 推迟到本帧 build 之后触发（避免 initState 期间 markNeedsBuild during
    // build）；导入钩子接线同帧完成（registerHooks 内含 notifyListeners，
    // 亦须在 build 后调用）；失败仅日志（错误态由控制器状态机承载）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _wireImportHook();
        unawaited(_ensureStarted());
      }
    });
  }

  /// F-M5-07 导入钩子接线：既有注入钩子优先（非空槽位不覆盖）；否则以注入/
  /// 缺省导入流填充 onImportTap。
  void _wireImportHook() {
    final controller = widget.controller;
    if (controller.onImportTap != null) {
      return;
    }
    final flow = widget.importFlow ?? SimulatorImportFlow();
    controller.registerHooks(appendImportHook(
      SimulatorsHooks(
        onOpen: controller.onOpen,
        onSaveTap: controller.onSaveTap,
        onGenerateTap: controller.onGenerateTap,
      ),
      () => unawaited(flow.handleImport(context)),
    ));
  }

  void _onControllerChanged() => setState(() {});

  Future<void> _ensureStarted() async {
    try {
      await widget.controller.ensureStarted();
    } catch (error) {
      debugPrint('模拟器启动编排失败（错误态已呈现）: $error');
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('模拟器'),
        actions: [
          IconButton(
            tooltip: '存档管理',
            icon: const Icon(Icons.archive_outlined),
            onPressed: controller.onSaveTap == null
                ? null
                : () => controller.onSaveTap!(),
          ),
          IconButton(
            tooltip: '导入',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: controller.onImportTap == null
                ? null
                : () => controller.onImportTap!(),
          ),
          IconButton(
            tooltip: 'AI 生成',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: controller.onGenerateTap == null
                ? null
                : () => controller.onGenerateTap!(),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context, controller)),
    );
  }

  /// 四态正文。
  Widget _buildBody(BuildContext context, SimulatorsController controller) {
    switch (controller.state) {
      case SimulatorsState.loading:
        return const Center(child: CircularProgressIndicator());
      case SimulatorsState.error:
        return _ScrollablePane(
          child: _StatusColumn(
            icon: Icons.error_outline,
            message: controller.errorMessage ?? '模拟器启动失败',
            action: FilledButton(
              onPressed: () => unawaited(controller.retry()),
              child: const Text('重试'),
            ),
          ),
        );
      case SimulatorsState.empty:
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: _ScrollablePane(
            child: _StatusColumn(
              icon: Icons.sports_esports_outlined,
              message: '暂无游戏',
              hint: '下拉刷新试试',
            ),
          ),
        );
      case SimulatorsState.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterChips(
              filter: controller.filter,
              onSelected: controller.selectFilter,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.refresh,
                child: controller.games.isEmpty
                    ? _ScrollablePane(
                        child: _StatusColumn(
                          icon: Icons.filter_alt_outlined,
                          message: '该类型暂无可用的游戏',
                          hint: '切换筛选或下拉刷新',
                        ),
                      )
                    : _GameGrid(
                        games: controller.games,
                        onOpen: controller.onOpen,
                      ),
              ),
            ),
          ],
        );
    }
  }
}

/// 类型筛选 chips（三档：全部 / AI 驱动 / 纯本地）。
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.filter, required this.onSelected});

  final SimulatorFilter filter;
  final void Function(SimulatorFilter) onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ConverSpacing.space4,
        ConverSpacing.space3,
        ConverSpacing.space4,
        0,
      ),
      child: Row(
        children: [
          for (final option in SimulatorFilter.values) ...[
            ChoiceChip(
              label: Text(_filterLabel(option)),
              selected: filter == option,
              onSelected: (_) => onSelected(option),
            ),
            const SizedBox(width: ConverSpacing.space2),
          ],
        ],
      ),
    );
  }

  /// chips 文案（与卡片类型徽标同词汇，语义一致）。
  static String _filterLabel(SimulatorFilter filter) => switch (filter) {
        SimulatorFilter.all => '全部',
        SimulatorFilter.ai => 'AI 驱动',
        SimulatorFilter.local => '纯本地',
      };
}

/// 游戏卡片网格（两列）。
class _GameGrid extends StatelessWidget {
  const _GameGrid({required this.games, required this.onOpen});

  final List<SimulatorGame> games;
  final void Function(SimulatorGame game)? onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        ConverSpacing.space4,
        ConverSpacing.space3,
        ConverSpacing.space4,
        ConverSpacing.space4,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: ConverSpacing.space3,
        crossAxisSpacing: ConverSpacing.space3,
        childAspectRatio: 1.05,
      ),
      itemCount: games.length,
      itemBuilder: (context, index) => _GameCard(
        game: games[index],
        onOpen: onOpen,
      ),
    );
  }
}

/// 单张游戏卡片：名称 / 描述 / 类型徽标 / 导入·生成 badge / 点击打开。
class _GameCard extends StatelessWidget {
  const _GameCard({required this.game, required this.onOpen});

  final SimulatorGame game;
  final void Function(SimulatorGame game)? onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onOpen == null ? null : () => onOpen!(game),
      borderRadius: BorderRadius.circular(ConverRadii.md),
      child: Container(
        padding: const EdgeInsets.all(ConverSpacing.space3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(ConverRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              game.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(color: palette.ink1),
            ),
            const SizedBox(height: ConverSpacing.space1),
            Expanded(
              child: Text(
                game.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: palette.ink2),
              ),
            ),
            const SizedBox(height: ConverSpacing.space2),
            Wrap(
              spacing: ConverSpacing.space2,
              runSpacing: 2,
              children: [
                _Badge(
                  label: game.type == SimulatorGameType.ai ? 'AI 驱动' : '纯本地',
                  color: colorScheme.surfaceContainerHigh,
                  foreground: game.type == SimulatorGameType.ai
                      ? colorScheme.primary
                      : palette.ink3,
                ),
                if (game.source == SimulatorGameSource.imported)
                  _Badge(
                    label: '导入',
                    color: colorScheme.surfaceContainerHigh,
                    foreground: palette.ink3,
                  ),
                if (game.source == SimulatorGameSource.generated)
                  _Badge(
                    label: '生成',
                    color: colorScheme.surfaceContainerHigh,
                    foreground: palette.ink3,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片徽标（类型 / 导入 / 生成）。
class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(ConverRadii.xs),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground),
      ),
    );
  }
}

/// 单态信息列（错误文案 + 重试 / 空态提示），居中展示。
class _StatusColumn extends StatelessWidget {
  const _StatusColumn({
    required this.icon,
    required this.message,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String message;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: palette.ink4),
        const SizedBox(height: ConverSpacing.space2),
        Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
        ),
        if (hint != null) ...[
          const SizedBox(height: ConverSpacing.space1),
          Text(
            hint!,
            style: textTheme.bodySmall?.copyWith(color: palette.ink4),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: ConverSpacing.space3),
          action!,
        ],
      ],
    );
  }
}

/// 下拉刷新的滚动容器：占满可用高度并允许始终滚动（空/错误态亦可下拉）。
class _ScrollablePane extends StatelessWidget {
  const _ScrollablePane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(child: child),
        ),
      ),
    );
  }
}
