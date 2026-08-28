import 'package:flutter/material.dart';

import '../../widgets/placeholder_group.dart';

/// 角色占位视图（M1 接入角色库后由真实页面替换）。
class CharactersView extends StatelessWidget {
  const CharactersView({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderGroup(
      title: '角色',
      description: '角色库将在这里展示，可导入与管理角色卡。',
      items: [
        PlaceholderItem('全部角色', '名称与简介一览'),
        PlaceholderItem('导入角色卡', 'V2 角色卡解析'),
        PlaceholderItem('批量管理', '长按角色进入多选'),
      ],
    );
  }
}
