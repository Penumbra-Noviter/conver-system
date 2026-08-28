import 'package:flutter/material.dart';

import '../../widgets/placeholder_group.dart';

/// 聊天占位视图（M1 接入会话列表后由真实页面替换）。
class ChatView extends StatelessWidget {
  const ChatView({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderGroup(
      title: '聊天',
      description: '与角色的对话将在这里进行。',
      items: [
        PlaceholderItem('全部会话', '按最近更新排序'),
        PlaceholderItem('新建对话', '从角色库选择开场'),
        PlaceholderItem('批量管理', '长按会话进入多选'),
      ],
    );
  }
}
