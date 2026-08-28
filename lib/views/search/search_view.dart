import 'package:flutter/material.dart';

import '../../widgets/placeholder_group.dart';

/// 搜索占位视图（M1 接入全文检索后由真实页面替换）。
class SearchView extends StatelessWidget {
  const SearchView({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderGroup(
      title: '搜索',
      description: '跨会话与角色的全文检索将在这里提供。',
      items: [
        PlaceholderItem('全局搜索', '会话与角色一并检索'),
        PlaceholderItem('搜索历史', '保留最近的查询记录'),
      ],
    );
  }
}
