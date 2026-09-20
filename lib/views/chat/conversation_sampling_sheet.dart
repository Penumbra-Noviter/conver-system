/// 对话级采样参数弹层（SP-02）— 可空三态编辑 top_p / presence_penalty /
/// frequency_penalty / max_tokens，保存结果经 [ConversationSamplingInput] 回传。
///
/// 语义锚点：
/// - 值域守卫复用 SP-01 口径（SR-24）：「UI 层 clamp + 服务层兜底双保险」。
///   本层**不重复实现服务层守卫逻辑**（`_guardSamplingRange` /
///   `_resolveMaxTokens` 在 chat_service 单点承载），只做输入层限制
///   （formatter 阻止非法字符）+ 保存层双向 clamp（[parseSamplingDouble] /
///   [parseSamplingInt]）+ 值域提示文案；
/// - 三态语义 = 沿用全局缺省（开关关 → 结果 null）/ 覆盖值（开关开 + 数值 →
///   clamp 后数值）/ 清除回 null（把既有覆盖关掉再保存 → 结果 null）。契约锁
///   「保存后 Conversations 列值 = 显式覆盖值 或 NULL」由外层消费方
///   （[ChatController.saveConversationSampling]，chat_view 接线）落库。
///
/// 层级：呈现层。零数据层引用（layer_boundary_test 契约）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/colors.dart' show ConverRadii, ConverSpacing;
import '../../theme/conver_palette.dart';

/// 对话采样参数输入（四参可空值；null = 不覆盖 → 落库 NULL）。
///
/// 由弹层持有并按「显式覆盖值 或 NULL」契约回传；Conversations 四列
/// （topP / presencePenalty / frequencyPenalty / maxTokens）一一对应。
class ConversationSamplingInput {
  const ConversationSamplingInput({
    this.topP,
    this.presencePenalty,
    this.frequencyPenalty,
    this.maxTokens,
  });

  /// top-p 采样覆盖（值域 [0,1]，越界 clamp）。
  final double? topP;

  /// presence penalty 覆盖（值域 [-2,2]，越界 clamp）。
  final double? presencePenalty;

  /// frequency penalty 覆盖（值域 [-2,2]，越界 clamp）。
  final double? frequencyPenalty;

  /// max_tokens 覆盖（合法 ≥ 1，< 1 钳到 1）。
  final int? maxTokens;
}

/// 采样参数范围描述（每参数一行的「覆盖开关 + 数值输入」形态与值域提示文案）。
class _SamplingRange {
  const _SamplingRange({required this.label, required this.hint});

  /// 参数展示名（对齐 wire 参数名）。
  final String label;

  /// 值域提示文案（如 `0 ~ 1`、`-2 ~ 2`、`≥ 1`）。
  final String hint;
}

/// 对话级采样参数可空覆盖编辑：四参数各自一行「覆盖开关 + 数值输入」。
///
/// 用法：经 `showModalBottomSheet`（结果类型 [ConversationSamplingInput]）弹出；
/// 保存 pop 回 [ConversationSamplingInput]（三态合并），取消 pop null。
///
/// 编辑细节：
/// - [initial] 为当前会话四列回显——非 null 列 → 开关开 + 数值预填；null 列 →
///   开关关 + 「沿用全局/默认」态；
/// - 输入层 [TextField] 仅在开关开时挂载（未覆盖不渲染数值输入）；
/// - 保存时各参数按「开关开 → clamp 后数值（空/不可解析 → null）/ 关 → null」
///   收敛，绝不让非法值进入落库（服务层另有守卫兜底）。
class ConversationSamplingSheet extends StatefulWidget {
  const ConversationSamplingSheet({super.key, required this.initial});

  /// 当前会话四列值（回显态来源）。
  final ConversationSamplingInput initial;

  @override
  State<ConversationSamplingSheet> createState() =>
      _ConversationSamplingSheetState();
}

class _ConversationSamplingSheetState extends State<ConversationSamplingSheet> {
  static const _ranges = [
    _SamplingRange(label: 'top_p', hint: '0 ~ 1'),
    _SamplingRange(label: 'presence_penalty', hint: '-2 ~ 2'),
    _SamplingRange(label: 'frequency_penalty', hint: '-2 ~ 2'),
    _SamplingRange(label: 'max_tokens', hint: '≥ 1'),
  ];

  late bool _overrideTopP = widget.initial.topP != null;
  late bool _overridePresence = widget.initial.presencePenalty != null;
  late bool _overrideFrequency = widget.initial.frequencyPenalty != null;
  late bool _overrideMaxTokens = widget.initial.maxTokens != null;

  late final TextEditingController _topPField =
      TextEditingController(text: _formatInitialDouble(widget.initial.topP));
  late final TextEditingController _presenceField =
      TextEditingController(
          text: _formatInitialDouble(widget.initial.presencePenalty));
  late final TextEditingController _frequencyField =
      TextEditingController(
          text: _formatInitialDouble(widget.initial.frequencyPenalty));
  late final TextEditingController _maxTokensField =
      TextEditingController(text: widget.initial.maxTokens?.toString() ?? '');

  @override
  void dispose() {
    _topPField.dispose();
    _presenceField.dispose();
    _frequencyField.dispose();
    _maxTokensField.dispose();
    super.dispose();
  }

  /// 覆盖值回显格式：整数值去掉小数尾（1.0 → `1`），其余原样（0.4 → `0.4`）。
  static String _formatInitialDouble(double? value) {
    if (value == null) {
      return '';
    }
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  void _save() {
    final result = ConversationSamplingInput(
      topP: _overrideTopP
          ? parseSamplingDouble(_topPField.text, min: 0, max: 1)
          : null,
      presencePenalty: _overridePresence
          ? parseSamplingDouble(_presenceField.text, min: -2, max: 2)
          : null,
      frequencyPenalty: _overrideFrequency
          ? parseSamplingDouble(_frequencyField.text, min: -2, max: 2)
          : null,
      maxTokens: _overrideMaxTokens ? parseSamplingInt(_maxTokensField.text) : null,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          ConverSpacing.space4,
          ConverSpacing.space2,
          ConverSpacing.space4,
          ConverSpacing.space4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '对话采样参数',
              style: textTheme.titleMedium?.copyWith(color: palette.ink1),
            ),
            const SizedBox(height: ConverSpacing.space1),
            Text(
              '覆盖当前会话的采样参数；关闭开关则沿用全局默认。',
              style: textTheme.bodySmall?.copyWith(color: palette.ink4),
            ),
            const SizedBox(height: ConverSpacing.space3),
            _SamplingParamRow(
              range: _ranges[0],
              switchKey: const Key('sampling-switch-top_p'),
              fieldKey: const Key('sampling-field-top_p'),
              active: _overrideTopP,
              isInteger: false,
              controller: _topPField,
              onActiveChanged: (value) =>
                  setState(() => _overrideTopP = value),
            ),
            const Divider(height: ConverSpacing.space5),
            _SamplingParamRow(
              range: _ranges[1],
              switchKey: const Key('sampling-switch-presence_penalty'),
              fieldKey: const Key('sampling-field-presence_penalty'),
              active: _overridePresence,
              isInteger: false,
              controller: _presenceField,
              onActiveChanged: (value) =>
                  setState(() => _overridePresence = value),
            ),
            const Divider(height: ConverSpacing.space5),
            _SamplingParamRow(
              range: _ranges[2],
              switchKey: const Key('sampling-switch-frequency_penalty'),
              fieldKey: const Key('sampling-field-frequency_penalty'),
              active: _overrideFrequency,
              isInteger: false,
              controller: _frequencyField,
              onActiveChanged: (value) =>
                  setState(() => _overrideFrequency = value),
            ),
            const Divider(height: ConverSpacing.space5),
            _SamplingParamRow(
              range: _ranges[3],
              switchKey: const Key('sampling-switch-max_tokens'),
              fieldKey: const Key('sampling-field-max_tokens'),
              active: _overrideMaxTokens,
              isInteger: true,
              controller: _maxTokensField,
              onActiveChanged: (value) =>
                  setState(() => _overrideMaxTokens = value),
            ),
            const SizedBox(height: ConverSpacing.space4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('sampling-cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: ConverSpacing.space2),
                FilledButton(
                  key: const Key('sampling-save'),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单参数行：参数名 + 覆盖开关；开关开 → 数值输入（formatter 阻止非法字符 +
/// 值域提示），关 → 「沿用全局/默认」态。
class _SamplingParamRow extends StatelessWidget {
  const _SamplingParamRow({
    required this.range,
    required this.switchKey,
    required this.fieldKey,
    required this.active,
    required this.isInteger,
    required this.controller,
    required this.onActiveChanged,
  });

  final _SamplingRange range;
  final Key switchKey;
  final Key fieldKey;
  final bool active;
  final bool isInteger;
  final TextEditingController controller;
  final ValueChanged<bool> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(range.label, style: textTheme.bodyMedium),
              const SizedBox(height: ConverSpacing.space1),
              if (active)
                TextField(
                  key: fieldKey,
                  controller: controller,
                  style: textTheme.bodyMedium,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: !isInteger,
                    signed: true,
                  ),
                  inputFormatters: [
                    isInteger
                        ? FilteringTextInputFormatter.digitsOnly
                        : FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.\-]'),
                          ),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '请输入数值',
                    helperText: '值域 ${range.hint}',
                    helperStyle:
                        TextStyle(fontSize: 12, color: palette.ink4),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: ConverSpacing.space3,
                      vertical: ConverSpacing.space2,
                    ),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ConverRadii.md),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ConverRadii.md),
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                )
              else
                Text(
                  '沿用全局/默认',
                  style:
                      textTheme.bodySmall?.copyWith(color: palette.ink4),
                ),
            ],
          ),
        ),
        const SizedBox(width: ConverSpacing.space2),
        Switch(
          key: switchKey,
          value: active,
          onChanged: onActiveChanged,
        ),
      ],
    );
  }
}

/// 采样双精度文本的解析 + 值域 clamp（SP-02 UI 层；SR-24 口径的输入侧补充，
/// 服务层 [ChatService._guardSamplingRange] 为兜底）。
///
/// 返回 null 表示「不覆盖」：[text] 为 null / 空 / 全空白 / 不可解析（含
/// NaN / ±Infinity，formatter 已阻止字母输入，此处纯防御）。合法值越界
/// clamp 到 [min, max]（含端点原样保留）。
double? parseSamplingDouble(
  String? text, {
  required double min,
  required double max,
}) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final value = double.tryParse(trimmed);
  if (value == null || value.isNaN || value.isInfinite) {
    return null;
  }
  return value.clamp(min, max).toDouble();
}

/// 采样整数文本（max_tokens）的解析 + 下限钳制（SP-02 UI 层；服务层
/// [_resolveMaxTokens] 为兜底）。
///
/// 返回 null 表示「不覆盖」（null / 空 / 不可解析）；合法值 < 1 钳到 1
/// （对齐 SR-24「maxTokens ≥ 1」口径——不让 <1 覆盖值落库形成「已覆盖却
/// 回退全局」的歧义态）。
int? parseSamplingInt(String? text) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final value = int.tryParse(trimmed);
  if (value == null) {
    return null;
  }
  return value < 1 ? 1 : value;
}