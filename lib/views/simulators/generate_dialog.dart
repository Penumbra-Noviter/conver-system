/// 模拟器 AI 生成对话框（F-M5-08b）——世界观描述输入 → 生成编排 →
/// 进度态 / 成功关闭+toast+列表刷新 / 校验失败展示与重试门。
///
/// 验收语义（工单验收语义契约逐条）：
/// - 描述必填（空拦截：按钮禁用 + 提交前兜底），标题可选；
/// - 生成中进度态（提交按钮隐藏防重复）+ 「取消」中止在途重试（状态机：
///   置取消标志 → [GameGenerator.generate] 下一次尝试前断言 → cancel 结果
///   → 关闭对话框，不泄漏在途调用）；
/// - 成功 → 关闭 + toast「生成成功」→ [onGenerated]（列表刷新）后生成卡可见
///   （generated badge）；
/// - 校验失败 → 错误列表 `[{field}] {message}` + 修正建议 +「重试」按钮
///   （未超重试次数时）/ 耗尽文案（结果 retries 达上限后按钮转「关闭」）；
/// - LLM 调用异常 → 明确失败文案 +「重试」（未进入编排计数，可无限重试）。
///
/// 层级：呈现层（薄 UI）。生成编排全部经注入 [GameGenerator]（构造依赖
/// fake 注入测试，永不触真实网络 / 平台通道）；[onGenerated] 为成功后的
/// 列表刷新 seam（生产 = SimulatorsController.refresh）。
library;

import 'package:flutter/material.dart';

import '../../services/simulator/game_generator.dart'
    show GameGenerator, GenerateResult, maxGenerationRetries;
import '../../services/simulator/generated_game_validator.dart'
    show GenValidationError;
import '../../theme/conver_palette.dart' show ConverPalette;
import '../../theme/colors.dart' show ConverSpacing;

/// 对话框三态状态机（idle 输入 / generating 进度 / failure 失败展示）。
enum _GeneratePhase { idle, generating, failure }

/// AI 生成游戏对话框。
class GenerateDialog extends StatefulWidget {
  const GenerateDialog({
    super.key,
    required this.generator,
    this.onGenerated,
  });

  /// 生成编排服务（生产由 SimulatorsView 装配，测试注入 fake）。
  final GameGenerator generator;

  /// 成功落盘后的列表刷新回调（生产 = SimulatorsController.refresh；
  /// null = 不刷新，测试可省略）。
  final Future<void> Function()? onGenerated;

  @override
  State<GenerateDialog> createState() => _GenerateDialogState();
}

class _GenerateDialogState extends State<GenerateDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  _GeneratePhase _phase = _GeneratePhase.idle;
  bool _cancelled = false;

  /// 编排失败结果（校验失败耗尽 / 非耗尽失败）。
  GenerateResult? _result;

  /// LLM 调用异常文案（异常失败路径，不进入编排 retries 计数）。
  String? _llmError;

  /// 校验失败是否已耗尽重试次数（结果 retries 达总尝试上限 → 按钮转「关闭」）。
  bool get _exhausted =>
      (_result?.retries ?? 0) >= maxGenerationRetries + 1;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// 发起一轮生成（重试入口复用本方法）。
  Future<void> _run() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      return; // 空拦截兜底（按钮已禁用）。
    }
    setState(() {
      _phase = _GeneratePhase.generating;
      _result = null;
      _llmError = null;
      _cancelled = false;
    });
    final title = _titleController.text.trim();
    try {
      final result = await widget.generator.generate(
        description: description,
        title: title.isEmpty ? null : title,
        isCancelled: () => _cancelled,
      );
      if (!mounted) {
        return;
      }
      if (result.ok) {
        await _onSuccess();
        return;
      }
      final cancelled =
          result.errors?.any((e) => e.field == 'cancel') ?? false;
      if (cancelled) {
        Navigator.of(context).pop(); // 取消 → 直接关闭。
        return;
      }
      setState(() {
        _phase = _GeneratePhase.failure;
        _result = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _GeneratePhase.failure;
        _llmError = error.toString();
      });
    }
  }

  /// 成功路径：toast「生成成功」→ onGenerated（列表刷新）→ 关闭对话框。
  Future<void> _onSuccess() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('生成成功')));
    if (widget.onGenerated != null) {
      await widget.onGenerated!();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 取消生成：置标志（重试序列下一次尝试前断言）——中止后续重试，在途
  /// LLM 调用自然结束（不再发起新调用）。
  void _cancel() {
    _cancelled = true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 生成游戏'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: _phase == _GeneratePhase.generating
            ? _buildGenerating()
            : _buildForm(),
      ),
      actions: _buildActions(context),
    );
  }

  /// 输入态 / 失败态内容：标题（可选）+ 描述（必填）+ 失败反馈区。
  Widget _buildForm() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('generate-title-field'),
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '游戏标题（可选）',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ConverSpacing.space3),
          TextField(
            key: const Key('generate-description-field'),
            controller: _descriptionController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '世界观描述（必填）',
              hintText: '描述你想要的游戏世界观，例如「一个雾中的魔法小镇…」',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_phase == _GeneratePhase.failure) ...[
            const SizedBox(height: ConverSpacing.space3),
            _buildFailureFeedback(),
          ],
        ],
      ),
    );
  }

  /// 生成中内容：进度指示 + 文案。
  Widget _buildGenerating() {
    final palette = ConverPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(width: ConverSpacing.space3),
        Expanded(
          child: Text(
            '正在生成游戏…（AI 生成需要一点时间）',
            style: TextStyle(color: palette.ink2),
          ),
        ),
      ],
    );
  }

  /// 失败反馈区：错误列表 [{field}] {message} + 修正建议 + 耗尽文案。
  Widget _buildFailureFeedback() {
    final theme = Theme.of(context);
    final palette = ConverPalette.of(context);
    final llmError = _llmError;
    final result = _result;
    return Container(
      padding: const EdgeInsets.all(ConverSpacing.space3),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_exhausted)
            Text(
              '重试次数已用尽',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          if (result != null)
            for (final err in result.errors ??
                const <GenValidationError>[])
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '[${err.field}] ${err.message}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onErrorContainer),
                ),
              ),
          if (llmError != null)
            Text(
              '生成失败：$llmError',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          if (result?.suggestion != null) ...[
            const SizedBox(height: ConverSpacing.space2),
            Text(
              '建议：${result!.suggestion}',
              style: theme.textTheme.bodySmall?.copyWith(color: palette.ink2),
            ),
          ],
        ],
      ),
    );
  }

  /// 动作区（按状态机态分派）。
  List<Widget> _buildActions(BuildContext context) {
    final descriptionEmpty =
        _descriptionController.text.trim().isEmpty;
    switch (_phase) {
      case _GeneratePhase.idle:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: descriptionEmpty ? null : () => _run(),
            child: const Text('生成'),
          ),
        ];
      case _GeneratePhase.generating:
        return [
          TextButton(
            onPressed: _cancel,
            child: const Text('取消'),
          ),
        ];
      case _GeneratePhase.failure:
        if (_exhausted) {
          return [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ];
        }
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () => _run(),
            child: const Text('重试'),
          ),
        ];
    }
  }
}