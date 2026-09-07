/// 关于页（F-M5-10）— 应用名「汇流」/ 版本 / 数据全本地声明 / 技术栈简述。
///
/// 静态文本页，零新依赖（版本号用常量，pubspec 对拍测试锁定防漂移；
/// 不引入 package_info_plus）。跑在既有 Warm Stone 暖灰 + 琥珀主题
/// （design doc §5.1/§5.2）。
library;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';

/// 关于页。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  /// 应用展示名（用户定稿）。
  static const String appName = '汇流';

  /// 版本号（与 `pubspec.yaml` `version: 1.0.0+1` 对齐；`manual_pages_test`
  /// 的版本防漂移测试逐字对拍 pubspec，防常量与清单脱节）。
  static const String appVersion = '1.0.0+1';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
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
              appName,
              style: textTheme.headlineMedium?.copyWith(color: palette.ink1),
            ),
            const SizedBox(height: ConverSpacing.space1),
            Text(
              '版本 $appVersion',
              style: textTheme.bodyMedium?.copyWith(color: palette.ink3),
            ),
            const SizedBox(height: ConverSpacing.space3),
            Text(
              '汇流是一个本地优先的 AI 角色对话与模拟器应用：创建角色、开启'
              '对话、玩 AI 模拟器，所有数据保存在本机。',
              style: textTheme.bodyMedium?.copyWith(
                color: palette.ink2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: ConverSpacing.space5),
            Divider(thickness: 1, color: palette.border),
            const SizedBox(height: ConverSpacing.space4),
            _BlockTitle(textTheme, palette, '数据与隐私'),
            const SizedBox(height: ConverSpacing.space3),
            _Bullet(
              textTheme,
              palette,
              '全部数据保存在本机：角色、对话与设置存于本地 SQLite 数据库；'
              '密钥存于系统安全存储（SecureStorage）。',
            ),
            _Bullet(
              textTheme,
              palette,
              '数据不会上传云端。只有聊天内容会发送给你自己配置的模型服务商。',
            ),
            const SizedBox(height: ConverSpacing.space5),
            Divider(thickness: 1, color: palette.border),
            const SizedBox(height: ConverSpacing.space4),
            _BlockTitle(textTheme, palette, '技术栈'),
            const SizedBox(height: ConverSpacing.space3),
            _Bullet(textTheme, palette, 'Flutter — 跨平台移动端框架（Android / iOS 一套 Dart）'),
            _Bullet(textTheme, palette, 'drift — 本地 SQLite 数据库'),
            _Bullet(textTheme, palette, 'SecureStorage — 系统安全存储（密钥不落明文）'),
          ],
        ),
      ),
    );
  }
}

/// 分组标题（次级章节名）。
class _BlockTitle extends StatelessWidget {
  const _BlockTitle(this.textTheme, this.palette, this.title);

  final TextTheme textTheme;

  final ConverPalette palette;

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: textTheme.titleMedium?.copyWith(
        color: palette.ink1,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// 圆点条目行。
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
