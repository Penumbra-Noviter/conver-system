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
/// 阶段 2 关系区（PS2-10，spec P4 + 判定⑤⑧ + SR-10）：
/// - 关系状态经装配图 `CompanionRepository.listRelationships` 只读加载（本层
///   context.read 消费，不现造仓储；provider 缺位 → 静默降级不渲染，保既有
///   装配零回归）；
/// - 卡片显示五段中文 label（UI 层映射，业务枚举保持英文）+ affinity 进度条
///   （0-100）；无状态行角色不渲染关系区（判定⑧零噪音）；
/// - 升级提议经装配图 `StageUpgradeBroker`（ChangeNotifier）消费：proposal
///   归属角色卡展示「升级建议：目标阶段」+ 确认/拒绝（多选态隐藏防误触）；
///   确认/拒绝只调 `RelationshipService`（SR-10：UI 零直写 relationship_states；
///   F1 域校验拒绝 confirm=false → 不崩、刷新为现状）；拒绝后本会话同角色
///   不再重复弹（spec 判定⑤的 UI 侧拒绝记录，broker 只读不扩容）。
///
/// 层级：呈现层。经 [CharactersController] 注入 + 装配图 provider 消费，
/// 不触碰平台存储 / 不现造服务（layer_boundary_test 契约）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database/app_database.dart' show Character, RelationshipState;
import '../../data/database/tables.dart' show RelationshipStage;
import '../../data/repositories/character_repository.dart'
    show CharacterRepository, CharacterWithCount;
import '../../data/repositories/companion_repository.dart';
import '../../data/repositories/memory_repository.dart';
import '../../services/companion/relationship_service.dart';
import '../../services/companion/stage_upgrade_broker.dart';
import '../../services/document_parse_service.dart';
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/notice_banner.dart';
import 'character_edit_view.dart';
import 'characters_controller.dart';
import 'memory_management_controller.dart';
import 'memory_management_view.dart';
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
  /// 关系状态行（characterId → 行）；无行角色不在 map（判定⑧零噪音）。
  Map<int, RelationshipState> _relationships = const {};

  /// 确认/拒绝进行中的角色 id 集（防重入：按钮忙碌禁用）。
  final Set<int> _busyCharacterIds = <int>{};

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
        unawaited(_loadRelationships());
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

  /// 从装配图（app.dart 单一落点）读取 [T]；provider 缺位（既有测试无
  /// stage2 装配）→ null，调用方降级不渲染（零回归契约）。
  T? _maybeProvider<T>(BuildContext context) {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// 订阅 [StageUpgradeBroker]（watch 语义：publish / clear 触发本视图重建，
  /// 升级提议行实时切换）；provider 缺位 → null 降级（既有装配零回归）。
  StageUpgradeBroker? _maybeBroker(BuildContext context) {
    try {
      return Provider.of<StageUpgradeBroker>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// 加载全部关系状态行（只读面；completion 后重建本地 map）。
  ///
  /// 刷新时机：切回 tab（post-frame）/ 下拉刷新 / 确认·拒绝后；失败仅日志，
  /// 保持既有 map 不闪烁。删除角色后残留 map entry 无害（无对应卡片即不
  /// 渲染，关系行本身已随 FK CASCADE 清理——PS2-01 实证）。
  Future<void> _loadRelationships() async {
    final repository = _maybeProvider<CompanionRepository>(context);
    if (repository == null) {
      return;
    }
    try {
      final rows = await repository.listRelationships();
      if (!mounted) {
        return;
      }
      setState(() {
        _relationships = {
          for (final row in rows) row.characterId: row,
        };
      });
    } catch (error) {
      debugPrint('关系状态加载失败，保持现状: $error');
    }
  }

  /// 确认升级（SR-10：只经 [RelationshipService.confirmStageUpgrade] 落库，
  /// 视图零直写 relationship_states）。
  ///
  /// 成功（true）→ 重载关系行展示新阶段 + broker 清除提议（验收 4）；F1
  /// 域校验拒绝 / 异常（false）→ 不崩，重载现状 + broker 清除（验收 6）。
  /// 防重入：同角色 busy 时忽略二次触发。
  Future<void> _confirmUpgrade(
    int characterId,
    StageUpgradeProposal proposal,
  ) async {
    if (!_busyCharacterIds.add(characterId)) {
      return;
    }
    setState(() {});
    try {
      await context.read<RelationshipService>().confirmStageUpgrade(
            characterId: characterId,
            targetStage: proposal.targetStage,
          );
    } catch (error) {
      debugPrint('升级确认失败: $error');
    }
    if (!mounted) {
      return;
    }
    _busyCharacterIds.remove(characterId);
    _maybeProvider<StageUpgradeBroker>(context)?.clear();
    // 成功 / F1 拒绝 / 异常统一重载为 DB 现状（F-82 观察：affinity 与 stage
    // 档可能短暂不一致，以落库值实时渲染，不做额外修正）。
    await _loadRelationships();
  }

  /// 拒绝升级（SR-10：零写库；spec 判定⑤「本会话不再重复提议」由
  /// StageUpgradeBroker.reject 承担——上提装配层，切 tab 重建仍生效）。
  Future<void> _rejectUpgrade(int characterId) async {
    if (!_busyCharacterIds.add(characterId)) {
      return;
    }
    setState(() {});
    try {
      await context
          .read<RelationshipService>()
          .rejectStageUpgrade(characterId: characterId);
    } catch (error) {
      debugPrint('拒绝升级失败: $error');
    }
    if (!mounted) {
      return;
    }
    _busyCharacterIds.remove(characterId);
    _maybeProvider<StageUpgradeBroker>(context)?.reject(characterId);
    _maybeProvider<StageUpgradeBroker>(context)?.clear();
    setState(() {});
  }

  /// 「新建角色」入口：push 6 步向导（M3-02a 接真导航，替换 M3-01 stub）。
  ///
  /// WizardController 经 [CharacterRepository]（provider 装配注入）构造；
  /// [DocumentParseService] 经装配图 provider 读取（C2 装配收敛：装配唯一落点
  /// app.dart，本层只 context.read 消费，不现造服务实例——layer_boundary_test
  /// 契约）。向导保存成功后回调 [CharactersController.refresh] 刷新列表，pop
  /// 回本页。
  Future<void> _openWizard() async {
    final repository = context.read<CharacterRepository>();
    final wizard = WizardController(
      characterRepository: repository,
      parseService: context.read<DocumentParseService>(),
    );
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
    final broker = _maybeBroker(context);
    final proposal = broker?.lastProposal;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 多选态：批量操作栏替换普通头部（M3-05）；否则普通头部。
          if (controller.selectionMode)
            _BatchBar(controller: controller)
          else
            _Header(
              onCreate: () => unawaited(_openWizard()),
              onImport: () => unawaited(controller.importCharacter()),
            ),
          // W5 B1：NoticeBanner 始终渲染（notice 可空），进出过渡 140ms 由
          // 组件自身 AnimatedOpacity 管理——dismiss 后播放出口 Fade，过渡
          // 完成才回调 dismissNotice（提示条不硬切卸载）。
          NoticeBanner(
            notice: controller.notice,
            // F-65④：notice 身份 seq 随文案同步传递（同文案新旧 notice 经
            // 身份区分，陈旧出口 dismiss 不误清新 notice）。
            noticeId: controller.noticeId,
            onDismiss: controller.dismissNotice,
          ),
          Expanded(
            child: RefreshIndicator(
              // 下拉刷新：角色列表 + 关系状态一并重拉（关系行随对话演进）。
              onRefresh: () async {
                await controller.refresh();
                await _loadRelationships();
              },
              child: controller.characters.isEmpty
                  ? _EmptyPane(loading: controller.loading)
                  : _CharacterList(
                      controller: controller,
                      relationships: _relationships,
                      proposal: proposal,
                      rejectedCharacterIds:
                          _maybeProvider<StageUpgradeBroker>(context)
                                  ?.rejectedCharacterIds ??
                          const <int>{},
                      busyCharacterIds: _busyCharacterIds,
                      onConfirm: _confirmUpgrade,
                      onReject: _rejectUpgrade,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 头部：标题「角色」+「导入角色卡」入口（M3-03）+「新建角色」入口
/// （push 向导；M3-02a 接真）。
class _Header extends StatelessWidget {
  const _Header({required this.onCreate, required this.onImport});

  /// 新建角色入口回调（由 state 层 push 向导）。
  final VoidCallback onCreate;

  /// 导入角色卡入口回调（由 state 层经 controller 调 seam）。
  final VoidCallback onImport;

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
          IconButton(
            tooltip: '导入角色卡',
            icon: Icon(Icons.file_open_outlined, size: 18, color: palette.ink3),
            onPressed: onImport,
          ),
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

/// 批量操作栏（M3-05 多选态）：实时选中数 + 批量删除（空选禁用）+ 退出。
///
/// 多选态下替换 [CharactersView] 普通头部；退出后恢复 [CharactersView]
/// 普通头部（[CharactersController.exitSelectionMode]）。
class _BatchBar extends StatelessWidget {
  const _BatchBar({required this.controller});

  /// 多选态状态持有者（选中数 / 批量删除 / 退出回调单一来源）。
  final CharactersController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final count = controller.selection.length;
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
            '已选 $count 个角色',
            style: textTheme.titleMedium?.copyWith(color: palette.ink1),
          ),
          const Spacer(),
          IconButton(
            tooltip: '批量删除',
            icon: Icon(
              Icons.delete_outline,
              color: count == 0
                  ? palette.ink4
                  : Theme.of(context).colorScheme.error,
            ),
            onPressed: count == 0 ? null : () => _confirmBatchDelete(context),
          ),
          IconButton(
            tooltip: '退出多选',
            icon: Icon(Icons.close, color: palette.ink3),
            onPressed: controller.exitSelectionMode,
          ),
        ],
      ),
    );
  }

  /// 批量删除确认：文案含选中数与级联说明（验收 3）；确认后经
  /// [CharactersController.deleteSelected] 逐角色级联删除 + 刷新 + 退多选。
  Future<void> _confirmBatchDelete(BuildContext context) async {
    final count = controller.selection.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除角色'),
        content: Text('删除将移除 $count 个角色及其对话与消息，此操作不可撤销。'),
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
      await controller.deleteSelected();
    }
  }
}

/// 空态容器：首次加载中显示 spinner；其余经共享 [EmptyState] 呈现
/// 「暂无角色」+ 创建引导；可下拉刷新（AlwaysScrollableScrollPhysics）。
class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.loading});

  /// 首次加载中（尚未完成过一次刷新）。
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: EmptyState(
              icon: Icons.person_outline,
              message: '暂无角色',
              hint: '点「新建角色」创建你的第一个角色',
            ),
          ),
        ),
      ),
    );
  }
}

/// 单列角色卡片列表（PS2-10 追加关系区数据与升级提议分发）。
class _CharacterList extends StatelessWidget {
  const _CharacterList({
    required this.controller,
    required this.relationships,
    required this.proposal,
    required this.rejectedCharacterIds,
    required this.busyCharacterIds,
    required this.onConfirm,
    required this.onReject,
  });

  final CharactersController controller;

  /// 关系状态行（characterId → 行）；缺席即无行（判定⑧）。
  final Map<int, RelationshipState> relationships;

  /// 当前升级提议（broker 广播；归属按 [StageUpgradeProposal.characterId]）。
  final StageUpgradeProposal? proposal;

  /// 本会话拒绝过提议的角色 id 集（判定⑤ UI 侧记录）。
  final Set<int> rejectedCharacterIds;

  /// 确认/拒绝进行中的角色 id 集（防重入禁用）。
  final Set<int> busyCharacterIds;

  /// 确认升级回调（上行至 state 层经 RelationshipService 落库）。
  final void Function(int characterId, StageUpgradeProposal proposal) onConfirm;

  /// 拒绝升级回调（不写库，记拒绝语义）。
  final void Function(int characterId) onReject;

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
        final relationship = relationships[row.character.id];
        final matchesProposal =
            proposal != null && proposal!.characterId == row.character.id;
        return _CharacterCard(
          row: row,
          controller: controller,
          relationship: relationship,
          proposal: matchesProposal ? proposal : null,
          rejected: rejectedCharacterIds.contains(row.character.id),
          busy: busyCharacterIds.contains(row.character.id),
          onConfirm: onConfirm,
          onReject: onReject,
        );
      },
    );
  }
}

/// 单张角色卡片：头像 / 名称 / 描述（空 → personality 前 60 字）/ 开场白
/// 预览 / 标签 / 温度 / 对话数徽标 + 四按钮；PS2-10 追加关系区（五段
/// label + affinity 进度条 + 升级提议确认/拒绝）。
///
/// M3-05 多选层追加：长按任意卡片进入多选态并勾选该卡；多选态下卡片前置
/// 勾选框、tap 切换选中，隐藏四按钮与升级操作（防批量勾选时误触单删 /
/// 开始对话 / 升级确认）——关系 label 与进度条为被动展示，保留。
class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.row,
    required this.controller,
    required this.relationship,
    required this.proposal,
    required this.rejected,
    required this.busy,
    required this.onConfirm,
    required this.onReject,
  });

  final CharacterWithCount row;
  final CharactersController controller;

  /// 该角色关系状态行；null = 无行（不渲染关系区，判定⑧）。
  final RelationshipState? relationship;

  /// 归属该角色的升级提议；null = 无（含拒绝过后的抑制态）。
  final StageUpgradeProposal? proposal;

  /// 本会话已拒绝（不弹确认/拒绝操作）。
  final bool rejected;

  /// 确认/拒绝进行中（禁用防重入）。
  final bool busy;

  /// 确认升级回调。
  final void Function(int characterId, StageUpgradeProposal proposal) onConfirm;

  /// 拒绝升级回调。
  final void Function(int characterId) onReject;

  @override
  Widget build(BuildContext context) {
    final character = row.character;
    final selectionMode = controller.selectionMode;
    final selected =
        selectionMode && controller.selection.contains(character.id);
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final greeting = _preview(character.firstMes.trim(), 60);
    return Semantics(
      // 可点卡片 button 语义 + 长按多选 hint（spec §4.4 覆盖清单 ③）。
      // F-59 守卫对齐游戏卡（simulators_view.dart _GameCard：button: onOpen != null）：
      // tap 有效才宣告 button——常态（非多选）onTap 为 null 不宣告，
      // 长按进多选由 hint「长按可多选」描述。
      button: selectionMode,
      hint: '长按可多选',
      child: GestureDetector(
        onTap: selectionMode
            ? () => controller.toggleSelection(character.id)
            : null,
        onLongPress: () {
          controller.enterSelectionMode();
          controller.toggleSelection(character.id);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: ConverSpacing.space2),
          padding: const EdgeInsets.fromLTRB(
            ConverSpacing.space3,
            ConverSpacing.space3,
            ConverSpacing.space3,
            ConverSpacing.space1,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : palette.border,
            ),
            borderRadius: BorderRadius.circular(ConverRadii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectionMode)
                    Checkbox(
                      value: selected,
                      onChanged: (_) =>
                          controller.toggleSelection(character.id),
                    ),
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
                          style: textTheme.titleMedium?.copyWith(
                            color: palette.ink1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _cardDescription(character),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: palette.ink2,
                          ),
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
                            style: textTheme.labelSmall?.copyWith(
                              color: palette.ink3,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    _temperatureLabel(character.temperature),
                    style: textTheme.labelSmall?.copyWith(color: palette.ink3),
                  ),
                  const SizedBox(width: ConverSpacing.space3),
                  _ConversationCountBadge(count: row.conversationCount),
                ],
              ),
              // PS2-10 关系区：无状态行角色不渲染（判定⑧零噪音）；有行 →
              // 五段中文 label + affinity 进度条；proposal 归属且未拒绝且
              // 非多选态 → 追加确认/拒绝操作行（验收 3）。
              if (relationship != null) ...[
                const SizedBox(height: ConverSpacing.space2),
                _RelationshipSection(
                  relationship: relationship!,
                  proposal:
                      proposal != null && !rejected ? proposal : null,
                  showActions: !selectionMode,
                  busy: busy,
                  onConfirm: () =>
                      onConfirm(character.id, proposal!),
                  onReject: () => onReject(character.id),
                ),
              ],
              // 多选态下隐藏四按钮（防误触；勾选交互经卡片 tap）。
              if (!selectionMode) ...[
                const SizedBox(height: ConverSpacing.space2),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => unawaited(
                          controller.startConversation(character.id),
                        ),
                        icon: const Icon(Icons.forum_outlined, size: 18),
                        label: const Text('开始对话'),
                      ),
                    ),
                    IconButton(
                      tooltip: '记忆',
                      icon: Icon(
                        Icons.psychology_outlined,
                        color: palette.ink3,
                      ),
                      onPressed: () => _openMemory(context),
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
            ],
          ),
        ),
      ),
    );
  }

  /// 打开编辑表单（push）。
  void _openEdit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CharacterEditView(controller: controller, character: row.character),
      ),
    );
  }

  /// 打开记忆管理页（AC-05）：经 provider 装配 [MemoryRepository]（装配单源
  /// app.dart，本层只 context.read 消费，不再现造服务），push
  /// [MemoryManagementView]。
  void _openMemory(BuildContext context) {
    final repository = context.read<MemoryRepository>();
    final memoryController = MemoryManagementController(
      memoryRepository: repository,
      characterId: row.character.id,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoryManagementView(controller: memoryController),
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
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: palette.ink3),
      ),
    );
  }
}

/// 关系区（PS2-10）：五段中文 label + affinity 进度条（0-100 映射），
/// 归属升级提议存在且 [showActions] 时追加「升级建议：目标阶段」+
/// 确认/拒绝操作行。
///
/// 配色全走 Warm Stone token：label/文案 ink2/ink3，进度条前景走
/// colorScheme.primary（= accent，ConverPalette 映射说明），容器即卡片底。
class _RelationshipSection extends StatelessWidget {
  const _RelationshipSection({
    required this.relationship,
    required this.proposal,
    required this.showActions,
    required this.busy,
    required this.onConfirm,
    required this.onReject,
  });

  /// 该角色关系状态行（调用方已保证非空）。
  final RelationshipState relationship;

  /// 归属该角色的升级提议（null = 无/已拒绝/非本卡）。
  final StageUpgradeProposal? proposal;

  /// 是否展示确认/拒绝操作（多选态 false 防误触）。
  final bool showActions;

  /// 确认/拒绝进行中（禁用）。
  final bool busy;

  /// 确认回调。
  final VoidCallback onConfirm;

  /// 拒绝回调。
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final progress = (relationship.affinity /
            RelationshipThresholds.affinityMax)
        .clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _stageLabel(relationship.stage),
              style: textTheme.labelMedium?.copyWith(color: palette.ink2),
            ),
            const SizedBox(width: ConverSpacing.space3),
            Expanded(
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                borderRadius: BorderRadius.circular(ConverRadii.xs),
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
            ),
          ],
        ),
        if (proposal != null && showActions) ...[
          const SizedBox(height: ConverSpacing.space1),
          Row(
            children: [
              Expanded(
                child: Text(
                  '升级建议：${_stageLabel(proposal!.targetStage)}',
                  style: textTheme.labelMedium?.copyWith(color: palette.ink3),
                ),
              ),
              TextButton(
                onPressed: busy ? null : onConfirm,
                child: const Text('确认'),
              ),
              TextButton(
                onPressed: busy ? null : onReject,
                child: const Text('拒绝'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 关系阶段 → 中文 label（UI 层映射，业务枚举保持英文；spec 五段全覆盖：
/// 陌生/相识/熟悉/亲密/挚爱）。
String _stageLabel(RelationshipStage stage) => switch (stage) {
      RelationshipStage.stranger => '陌生',
      RelationshipStage.acquainted => '相识',
      RelationshipStage.familiar => '熟悉',
      RelationshipStage.intimate => '亲密',
      RelationshipStage.soulmate => '挚爱',
    };

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
