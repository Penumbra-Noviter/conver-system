import 'package:flutter/material.dart';

import '../../widgets/placeholder_group.dart';

/// 设置占位视图（分组结构对齐设计文档 §6，后续里程碑逐步开放）。
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderGroup(
      title: '设置',
      description: '应用配置集中管理，各分组将逐步开放。',
      items: [
        PlaceholderItem('API 配置', '服务地址与密钥'),
        PlaceholderItem('默认模型', '供应商与模型选择'),
        PlaceholderItem('对话', '生成参数与行为'),
        PlaceholderItem('主题', '深色为当前视觉基线'),
        PlaceholderItem('模板变量', '自定义注入变量'),
        PlaceholderItem('用户手册', '使用说明'),
        PlaceholderItem('关于', '版本信息'),
        PlaceholderItem('桌面版说明', '桌面端获取指引'),
      ],
    );
  }
}
