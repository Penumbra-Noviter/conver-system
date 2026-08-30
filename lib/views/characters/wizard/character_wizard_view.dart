/// 6 步角色创建向导全屏页（M3-02a 切片：手动创建路径 + 状态机；M3-02b
/// 追加步骤②真 UI：模板网格 / import 占位 + 视图层校验）。
///
/// 语义锚点（spec §Implementation Decisions 6 步向导 + 桌面
/// character-wizard.js renderStep / validateStep / handleSave）：
/// - 全屏 Scaffold + AppBar（标题随步骤；返回 = 上一步，step1 返回 = 退出）
///   + 步骤指示器（进度条 + 6 点）;
/// - 步骤①三卡片（智能导入 / 从模板开始 / 手动创建），手动选中直接跳③；
///   步骤②（M3-02b）：template → 5 模板卡（name/description/tags 逐字来自
///   `characterTemplates.dart`，点击 [WizardController.selectTemplate] 填充 +
///   选中高亮，再次进入保持选中态）；import → 多行 textarea（占位含「粘贴
///   角色设定文档」语义）+ 「AI 智能解析」按钮 disabled + 逐字文案「文档
///   AI 解析随 M4 交付」（不调任何 parse 接口）；步骤②视图层校验：template
///   未选下一步 → 「请选择一个模板」拦截（controller 只读既有状态机，
///   本层拦截不越权）；import 模式放行（不受内容影响）；
///   步骤③基本信息（name maxLength=100 / description maxLength=200 / avatar
///   / tags splitTags），字段 initialValue 绑定 controller 回显模板/已填值；
///   步骤④人格设定；步骤⑤对话风格；步骤⑥四段摘要 + 温度滑块；
/// - 校验门文案（「请选择一种创建方式」/「角色名称不能为空」）由
///   [WizardController.error] 提供；「请选择一个模板」由本层步骤②校验
///   提供；均经 _ErrorBanner 展示；
/// - 保存：⑥「保存角色」→ [WizardController.save] 成功 → 触发 [onSaved]
///   回调（列表刷新）→ pop 返回。
///
/// 层级：呈现层。经 [WizardController] 注入，不触碰数据层 / 平台存储
/// （layer_boundary_test 契约）。
library;

import 'package:flutter/material.dart';

import '../../../data/character_templates.dart';
import '../../../theme/colors.dart';
import '../../../theme/conver_palette.dart';
import 'character_wizard_controller.dart';
/// 向导页标题（对齐桌面 STEP_TITLES）。
const List<String> _stepTitles = <String>[
  '选择创建方式',
  '导入文档 / 选择模板',
  '基本信息',
  '人格设定',
  '对话风格',
  '预览保存',
];

/// 全屏 6 步向导。
class CharacterWizardView extends StatefulWidget {
  const CharacterWizardView({
    super.key,
    required this.controller,
    this.onSaved,
  });

  /// 向导状态机（入口装配注入）。
  final WizardController controller;

  /// 保存成功回调（列表刷新；由入口传入）。
  final VoidCallback? onSaved;

  @override
  State<CharacterWizardView> createState() => _CharacterWizardViewState();
}

class _CharacterWizardViewState extends State<CharacterWizardView> {
  /// 步骤②视图层校验错误（template 未选拦截）。controller 为只读共享件，
  /// 本错误状态由本层持有并在步骤切换时清除，不越权写 controller。
  String? _step2Error;

  /// 向导控制器由入口（characters_view._openWizard）内联创建、本视图拥有
  /// 生命周期——pop 时 dispose（ChangeNotifier 惯例）。
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final stepTitle =
            _stepTitles[(controller.step - 1).clamp(0, _stepTitles.length - 1)];
        final error = controller.error ?? _step2Error;
        return Scaffold(
          appBar: AppBar(
            title: Text(stepTitle),
            leading: IconButton(
              tooltip: controller.step > 1 ? '上一步' : '退出',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _handleBack(context),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  controller.cancel();
                  Navigator.of(context).pop();
                },
                child: const Text('取消'),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _StepIndicator(step: controller.step),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      ConverSpacing.space4,
                      ConverSpacing.space2,
                      ConverSpacing.space4,
                      ConverSpacing.space4,
                    ),
                    child: _buildStep(context, controller),
                  ),
                ),
                if (error != null) _ErrorBanner(message: error),
              ],
            ),
          ),
          bottomNavigationBar: _BottomBar(
            controller: controller,
            onBack: () => _handleBack(context),
            onNext: () => _handleNext(context),
          ),
        );
      },
    );
  }

  /// AppBar / 系统返回：step>1 → 上一步；step1 → 退出（零副作用）。
  void _handleBack(BuildContext context) {
    setState(() => _step2Error = null);
    if (widget.controller.step > 1) {
      widget.controller.prev();
      return;
    }
    widget.controller.cancel();
    Navigator.of(context).pop();
  }

  /// 下一步：⑥保存角色；其余 next（校验失败错误由 controller.error 或本层
  /// _step2Error 展示）。步骤②视图层校验：template 未选 → 「请选择一个模板」
  /// 拦截；import 模式放行（不受内容影响）。
  Future<void> _handleNext(BuildContext context) async {
    final controller = widget.controller;
    if (controller.step == 6) {
      final ok = await controller.save();
      if (ok) {
        widget.onSaved?.call();
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      }
      return;
    }
    if (controller.step == 2 &&
        controller.mode == WizardCreationMode.template &&
        controller.selectedTemplateId == null) {
      setState(() => _step2Error = '请选择一个模板');
      return;
    }
    setState(() => _step2Error = null);
    controller.next();
  }

  /// 按当前步渲染步骤内容。
  Widget _buildStep(BuildContext context, WizardController controller) {
    return switch (controller.step) {
      1 => _Step1(mode: controller.mode, onSelect: controller.selectMode),
      2 => _Step2(
          controller: controller,
          onSelectTemplate: (String id) {
            setState(() => _step2Error = null);
            controller.selectTemplate(id);
          },
        ),
      3 => _Step3(controller: controller),
      4 => _Step4(controller: controller),
      5 => _Step5(controller: controller),
      6 => _Step6(controller: controller),
      _ => const SizedBox.shrink(),
    };
  }
}

/// 步骤指示器：进度条 + 6 点（已到步高亮）。
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ConverSpacing.space4,
        ConverSpacing.space2,
        ConverSpacing.space4,
        ConverSpacing.space2,
      ),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: ((step - 1) / 5).clamp(0.0, 1.0),
            backgroundColor: palette.border,
          ),
          const SizedBox(height: ConverSpacing.space2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 1; i <= 6; i++) _StepDot(index: i, step: step),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单点步骤指示器（当前/已完成步高亮）。
class _StepDot extends StatelessWidget {
  const _StepDot({required this.index, required this.step});

  final int index;
  final int step;

  @override
  Widget build(BuildContext context) {
    final active = index <= step;
    final palette = ConverPalette.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            active ? colorScheme.primary : colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        '$index',
        style: TextStyle(
          fontSize: 11,
          color: active ? colorScheme.onPrimary : palette.ink3,
        ),
      ),
    );
  }
}

/// 步骤①：三张创建方式卡片（对齐桌面 renderStep1）。
class _Step1 extends StatelessWidget {
  const _Step1({required this.mode, required this.onSelect});

  final WizardCreationMode? mode;
  final ValueChanged<WizardCreationMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择一种方式开始创建你的角色：',
          style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
        ),
        const SizedBox(height: ConverSpacing.space3),
        _ModeCard(
          icon: Icons.upload_file_outlined,
          title: '智能导入',
          description: '粘贴角色设定文档，AI 自动提取角色信息',
          selected: mode == WizardCreationMode.import,
          onTap: () => onSelect(WizardCreationMode.import),
        ),
        const SizedBox(height: ConverSpacing.space2),
        _ModeCard(
          icon: Icons.style_outlined,
          title: '从模板开始',
          description: '从预设角色模板中选择，快速入门',
          selected: mode == WizardCreationMode.template,
          onTap: () => onSelect(WizardCreationMode.template),
        ),
        const SizedBox(height: ConverSpacing.space2),
        _ModeCard(
          icon: Icons.edit_outlined,
          title: '手动创建',
          description: '从零开始，逐项填写角色信息',
          selected: mode == WizardCreationMode.manual,
          onTap: () => onSelect(WizardCreationMode.manual),
        ),
      ],
    );
  }
}

/// 创建方式卡片（选中态描边高亮）。
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ConverRadii.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(ConverSpacing.space3),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surfaceContainerLow,
          border: Border.all(
            color: selected ? colorScheme.primary : palette.border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(ConverRadii.md),
        ),
        child: Row(
          children: [
            Icon(icon, color: colorScheme.primary),
            const SizedBox(width: ConverSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: textTheme.bodySmall?.copyWith(color: palette.ink3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 步骤②（M3-02b 真 UI）：template → 5 模板网格；import → textarea 占位 +
/// disabled 解析按钮 + M4 文案。按 [WizardController.mode] 分派。
class _Step2 extends StatelessWidget {
  const _Step2({required this.controller, required this.onSelectTemplate});

  final WizardController controller;
  final ValueChanged<String> onSelectTemplate;

  @override
  Widget build(BuildContext context) {
    return switch (controller.mode) {
      WizardCreationMode.template => _TemplateGrid(
          selectedId: controller.selectedTemplateId,
          onSelect: onSelectTemplate,
        ),
      WizardCreationMode.import => const _ImportPlaceholder(),
      WizardCreationMode.manual || null => const SizedBox.shrink(),
    };
  }
}

/// 模板网格：5 模板卡（name / description / tags 逐字来自
/// `characterTemplates.dart`），点击 → [selectTemplate] 填充 + 选中高亮。
class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({required this.selectedId, required this.onSelect});

  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择一个模板作为起点，之后可以自由修改：',
          style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
        ),
        const SizedBox(height: ConverSpacing.space3),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: ConverSpacing.space3,
          crossAxisSpacing: ConverSpacing.space3,
          childAspectRatio: 1.15,
          children: [
            for (final template in characterTemplates)
              _TemplateCard(
                template: template,
                selected: template.id == selectedId,
                onTap: () => onSelect(template.id),
              ),
          ],
        ),
      ],
    );
  }
}

/// 单张模板卡（名称 / 描述 / 标签；选中态描边高亮，对齐桌面 template-card）。
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final CharacterTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ConverRadii.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(ConverSpacing.space3),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.surfaceContainerHigh
              : colorScheme.surfaceContainerLow,
          border: Border.all(
            color: selected ? colorScheme.primary : palette.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(ConverRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              template.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(color: palette.ink1),
            ),
            const SizedBox(height: 2),
            Text(
              template.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: palette.ink3),
            ),
            const SizedBox(height: ConverSpacing.space2),
            Wrap(
              spacing: ConverSpacing.space1,
              runSpacing: 2,
              children: [
                for (final tag in template.tags)
                  Text(
                    '#$tag',
                    style: textTheme.labelSmall?.copyWith(color: palette.ink2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// import 占位（M4 交付 handler 前保留 UI 骨架）：多行 textarea + disabled
/// 「AI 智能解析」按钮 + 逐字文案「文档 AI 解析随 M4 交付」。
class _ImportPlaceholder extends StatelessWidget {
  const _ImportPlaceholder();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '粘贴角色设定文档或简介，AI 将自动提取角色信息：',
          style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
        ),
        const SizedBox(height: ConverSpacing.space3),
        TextField(
          maxLines: 10,
          minLines: 6,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: '在此粘贴角色设定文档、小说片段、角色简介等',
            border: OutlineInputBorder(),
          ),
          // M4 交付 handler，本票据占位：输入不触发任何解析调用（no-op）。
          onChanged: (_) {},
        ),
        const SizedBox(height: ConverSpacing.space3),
        Row(
          children: [
            OutlinedButton(
              onPressed: null, // disabled：文档 AI 解析随 M4 交付
              child: const Text('AI 智能解析'),
            ),
            const SizedBox(width: ConverSpacing.space3),
            Expanded(
              child: Text(
                '文档 AI 解析随 M4 交付',
                style: textTheme.bodySmall?.copyWith(color: palette.ink3),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 步骤③：基本信息（name / description / avatar / tags）。字段以
/// `initialValue` 绑定 controller（M3-02b 追加，模板/已填值回显）；重进本步
/// 重新从 controller 取当前值，用户编辑不被模板回填覆盖（controller 契约）。
class _Step3 extends StatelessWidget {
  const _Step3({required this.controller});

  final WizardController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '填写角色的基本信息：',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: ConverPalette.of(context).ink2),
        ),
        const SizedBox(height: ConverSpacing.space3),
        TextFormField(
          maxLength: 100,
          initialValue: controller.name,
          decoration: const InputDecoration(
            labelText: '角色名称',
            hintText: '输入角色名称',
            border: OutlineInputBorder(),
          ),
          onChanged: controller.setName,
        ),
        const SizedBox(height: ConverSpacing.space3),
        TextFormField(
          maxLength: 200,
          initialValue: controller.description,
          decoration: const InputDecoration(
            labelText: '简短描述',
            hintText: '角色的一句话简介',
            border: OutlineInputBorder(),
          ),
          onChanged: controller.setDescription,
        ),
        const SizedBox(height: ConverSpacing.space3),
        TextFormField(
          initialValue: controller.avatar,
          decoration: const InputDecoration(
            labelText: '头像 URL',
            hintText: '粘贴头像链接',
            border: OutlineInputBorder(),
          ),
          onChanged: controller.setAvatar,
        ),
        const SizedBox(height: ConverSpacing.space3),
        TextFormField(
          initialValue: controller.tags.join(', '),
          decoration: const InputDecoration(
            labelText: '标签',
            hintText: '如: 冒险, 奇幻, 可爱',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => controller.setTags(splitTags(value)),
        ),
      ],
    );
  }
}

/// 步骤④：人格设定（personality / scenario / systemPrompt）。字段
/// `initialValue` 绑定 controller 回显（同 _Step3 语义）。
class _Step4 extends StatelessWidget {
  const _Step4({required this.controller});

  final WizardController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '设定角色的核心人格——这决定了 AI 如何扮演这个角色：',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: ConverPalette.of(context).ink2),
        ),
        const SizedBox(height: ConverSpacing.space3),
        TextFormField(
          maxLines: 6,
          initialValue: controller.personality,
          decoration: const InputDecoration(
            labelText: '人格设定',
            hintText: '描述角色的性格特征、说话方式、行为模式、背景故事等',
            border: OutlineInputBorder(),
          ),
          onChanged: controller.setPersonality,
        ),
        const SizedBox(height: ConverSpacing.space3),
        TextFormField(
          maxLines: 3,
          initialValue: controller.scenario,
          decoration: const InputDecoration(
            labelText: '场景设定',
            hintText: '对话发生的场景和环境描述',
            border: OutlineInputBorder(),
          ),
          onChanged: controller.setScenario,
        ),
        const SizedBox(height: ConverSpacing.space3),
        TextFormField(
          maxLines: 3,
          initialValue: controller.systemPrompt,
          decoration: const InputDecoration(
            labelText: '自定义 System Prompt（可选）',
            hintText: '留空则使用人格设定作为 System Prompt',
            border: OutlineInputBorder(),
          ),
          onChanged: controller.setSystemPrompt,
        ),
      ],
    );
  }
}

/// 步骤⑤：对话风格（firstMes / mesExample）。字段 `initialValue` 绑定
/// controller 回显（同 _Step3 语义）。
class _Step5 extends StatelessWidget {
  const _Step5({required this.controller});

  final WizardController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '设定角色的对话风格——这决定了角色如何与用户交流：',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: ConverPalette.of(context).ink2),
        ),
        const SizedBox(height: ConverSpacing.space3),
        TextFormField(
          maxLines: 3,
          initialValue: controller.firstMes,
          decoration: const InputDecoration(
            labelText: '开场白',
            hintText: '角色首次对话时自动发送的第一句话',
            border: OutlineInputBorder(),
          ),
          onChanged: controller.setFirstMes,
        ),
        const SizedBox(height: ConverSpacing.space3),
        TextFormField(
          maxLines: 4,
          initialValue: controller.mesExample,
          decoration: const InputDecoration(
            labelText: '对话范例（可选）',
            hintText: '展示角色说话风格的示例对话',
            border: OutlineInputBorder(),
          ),
          onChanged: controller.setMesExample,
        ),
      ],
    );
  }
}

/// 步骤⑥：四段摘要 + 温度滑块 + 保存。
class _Step6 extends StatelessWidget {
  const _Step6({required this.controller});

  final WizardController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '检查角色信息，确认无误后保存：',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: ConverPalette.of(context).ink2),
        ),
        const SizedBox(height: ConverSpacing.space3),
        _SummarySection(
          title: '基本信息',
          rows: [
            _SummaryRow(label: '名称', value: controller.name),
            _SummaryRow(label: '描述', value: controller.description),
            _SummaryRow.tags(label: '标签', tags: controller.tags),
          ],
        ),
        const SizedBox(height: ConverSpacing.space3),
        _SummarySection(
          title: '人格设定',
          rows: [
            _SummaryRow(label: '人格', value: controller.personality),
            _SummaryRow(label: '场景', value: controller.scenario),
            if (controller.systemPrompt.isNotEmpty)
              _SummaryRow(label: '系统提示', value: controller.systemPrompt),
          ],
        ),
        const SizedBox(height: ConverSpacing.space3),
        _SummarySection(
          title: '对话风格',
          rows: [
            _SummaryRow(label: '开场白', value: controller.firstMes),
            _SummaryRow(label: '对话范例', value: controller.mesExample),
          ],
        ),
        const SizedBox(height: ConverSpacing.space3),
        _SummarySection(
          title: '设置',
          rows: [_TemperatureSlider(controller: controller)],
        ),
      ],
    );
  }
}

/// 温度滑块（0–2 / step 0.05 / 默认 0.7，实时两位小数显示）。
class _TemperatureSlider extends StatelessWidget {
  const _TemperatureSlider({required this.controller});

  final WizardController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('温度 (Temperature):',
                style: textTheme.bodySmall?.copyWith(color: palette.ink2)),
            const SizedBox(width: ConverSpacing.space2),
            Text(
              formatTemperature(controller.temperature),
              style: textTheme.bodyMedium?.copyWith(color: palette.ink1),
            ),
          ],
        ),
        Slider(
          value: controller.temperature.clamp(0, 2).toDouble(),
          min: 0,
          max: 2,
          divisions: 40,
          label: formatTemperature(controller.temperature),
          onChanged: controller.setTemperature,
        ),
      ],
    );
  }
}

/// 摘要分区（标题 + 若干行）。
class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ConverSpacing.space3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(ConverRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(color: palette.ink1),
          ),
          const SizedBox(height: ConverSpacing.space2),
          for (final row in rows) row,
        ],
      ),
    );
  }
}

/// 摘要行：空值显示「未填写」。
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value}) : _tags = null;

  /// 标签摘要行（tags 逐项 chip 渲染）。
  const _SummaryRow.tags({required this.label, required List<String> tags})
      : value = null,
        // ignore: prefer_initializing_formals
        _tags = tags;

  final String label;
  final String? value;
  final List<String>? _tags;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final tags = _tags;
    if (tags != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: textTheme.bodySmall?.copyWith(color: palette.ink3),
              ),
            ),
            Expanded(
              child: tags.isEmpty
                  ? Text('未填写',
                      style: textTheme.bodySmall?.copyWith(color: palette.ink2))
                  : Wrap(
                      spacing: ConverSpacing.space2,
                      runSpacing: 2,
                      children: [
                        for (final tag in tags)
                          Text('#$tag',
                              style: textTheme.bodySmall
                                  ?.copyWith(color: palette.ink2)),
                      ],
                    ),
            ),
          ],
        ),
      );
    }
    final empty = value == null || value!.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: palette.ink3),
            ),
          ),
          Expanded(
            child: Text(
              empty ? '未填写' : value!,
              style: textTheme.bodySmall?.copyWith(color: palette.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 校验错误横幅（controller.error 非空时展示）。
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space4,
        vertical: ConverSpacing.space2,
      ),
      child: Text(
        message,
        style: TextStyle(color: colorScheme.onErrorContainer),
      ),
    );
  }
}

/// 底部导航栏：上一步 / 下一步（⑥=保存角色）。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.onBack,
    required this.onNext,
  });

  final WizardController controller;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ConverSpacing.space4,
          ConverSpacing.space2,
          ConverSpacing.space4,
          ConverSpacing.space2,
        ),
        child: Row(
          children: [
            if (controller.step > 1) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  child: const Text('上一步'),
                ),
              ),
              const SizedBox(width: ConverSpacing.space3),
            ],
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onNext,
                child: Text(controller.step == 6 ? '保存角色' : '下一步'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
