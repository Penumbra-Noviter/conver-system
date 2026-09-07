/// 桌面版说明页（F-M5-10）— 告知桌面版（Tauri）存在 + 与移动端差异 +
/// 获取途径占位（不实装下载链路）。
///
/// 与手册「桌面版功能（Tauri）」节互文不冲突：手册节介绍桌面版特性，
/// 本页聚焦「移动端 ↔ 桌面版」差异认知与获取途径。静态文本页，零新依赖。
library;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';

/// 桌面版说明页。
class DesktopNotePage extends StatelessWidget {
  const DesktopNotePage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('桌面版说明')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ConverSpacing.space4,
            ConverSpacing.space5,
            ConverSpacing.space4,
            ConverSpacing.space6,
          ),
          children: [
            Text(
              '汇流提供基于 Tauri 的 Windows 桌面应用，功能与移动端一致，'
              '桌面端在部分场景能力更强（见下方差异）。',
              style: textTheme.bodyMedium?.copyWith(
                color: palette.ink2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: ConverSpacing.space5),
            Divider(thickness: 1, color: palette.border),
            const SizedBox(height: ConverSpacing.space4),
            Text(
              '与移动端的差异',
              style: textTheme.titleMedium?.copyWith(
                color: palette.ink1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: ConverSpacing.space3),
            _Bullet(
              textTheme,
              palette,
              '官方端点游戏可跑 — 桌面版游戏可直连 Anthropic / OpenAI 官方'
              '端点；移动端受浏览器 CORS 限制，官方端点不支持游戏直连，需使用 '
              'DeepSeek / Kimi / GLM / Qwen 等国产兼容端点。',
            ),
            _Bullet(
              textTheme,
              palette,
              '拖拽导入 — 桌面版支持把 .html 游戏文件直接拖入列表导入；移动端'
              '仅支持文件选择器选取单个文件。',
            ),
            _Bullet(
              textTheme,
              palette,
              'PC 阅读覆盖层 — 桌面版为导入 / 生成的游戏自动注入 PC 阅读覆盖层'
              '并可 per-game CSS 微调；移动端暂不支持覆盖层机制。',
            ),
            const SizedBox(height: ConverSpacing.space5),
            Divider(thickness: 1, color: palette.border),
            const SizedBox(height: ConverSpacing.space4),
            Text(
              '获取途径',
              style: textTheme.titleMedium?.copyWith(
                color: palette.ink1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: ConverSpacing.space3),
            Text(
              '桌面版安装包下载与安装说明见官方发布渠道（占位，移动端暂不提供'
              '下载跳转）。',
              style: textTheme.bodyMedium?.copyWith(
                color: palette.ink3,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 圆点条目行（对齐关于页视觉层级）。
class _Bullet extends StatelessWidget {
  const _Bullet(this.textTheme, this.palette, this.text);

  final TextTheme textTheme;

  final ConverPalette palette;

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ConverSpacing.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              right: ConverSpacing.space2,
              top: 2,
            ),
            child: Text(
              '·',
              style: textTheme.bodyMedium?.copyWith(color: palette.ink4),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodyMedium?.copyWith(
                color: palette.ink2,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}