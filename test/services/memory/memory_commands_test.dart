/// 记忆指令解析器契约（AC-02）：标签提取 + 剥离展示文本。
library;

import 'package:conver_system_mobile/services/memory/memory_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMemoryCommands', () {
    test('空串返回空指令与空展示文本', () {
      final result = parseMemoryCommands('');
      expect(result.displayContent, '');
      expect(result.commands, isEmpty);
    });

    test('单个 <add:> 标签 + 普通文本：剥离标签并保留文本', () {
      final result = parseMemoryCommands('好的，我记住了。\n<add:我喜欢吃辣>');
      expect(result.displayContent, '好的，我记住了。\n');
      expect(result.addEntries, ['我喜欢吃辣']);
      expect(result.personaEntries, isEmpty);
      expect(result.searchQueries, isEmpty);
    });

    test('混合 add / persona / search 标签：分类正确且保持顺序', () {
      final result = parseMemoryCommands(
        '<persona:她叫艾莉亚>\n今天聊了天气\n<add:她今天心情不好>\n<search:艾莉亚的喜好>',
      );
      expect(result.personaEntries, ['她叫艾莉亚']);
      expect(result.addEntries, ['她今天心情不好']);
      expect(result.searchQueries, ['艾莉亚的喜好']);
      expect(result.commands.map((c) => c.kind), [
        MemoryCommandKind.persona,
        MemoryCommandKind.add,
        MemoryCommandKind.search,
      ]);
      expect(result.displayContent.contains('今天聊了天气'), isTrue);
      expect(result.displayContent.contains('<persona:'), isFalse);
    });

    test('空内容标签被丢弃且标签文本仍被剥离', () {
      final result = parseMemoryCommands('你好<add:>\n再见');
      expect(result.commands, isEmpty);
      expect(result.displayContent, '你好\n再见');
    });

    test('未知标签原样保留；未闭合标签原样保留', () {
      final result = parseMemoryCommands('abc<unknown:x>def<add:内容未闭合');
      expect(result.addEntries, isEmpty);
      expect(result.displayContent, 'abc<unknown:x>def<add:内容未闭合');
    });

    test('标签内容 trim 后为空（纯空白）丢弃', () {
      final result = parseMemoryCommands('<add:   >');
      expect(result.addEntries, isEmpty);
      expect(result.displayContent, '');
    });

    test('同一行多个标签均被提取', () {
      final result = parseMemoryCommands('<add:a><persona:b><search:c>');
      expect(result.addEntries, ['a']);
      expect(result.personaEntries, ['b']);
      expect(result.searchQueries, ['c']);
      expect(result.displayContent, '');
    });

    test('内容含 < 但不含 > 保留 <（非贪婪 + 排除换行）', () {
      final result = parseMemoryCommands('<add:她喜欢 2<3 的比较>');
      expect(result.addEntries, ['她喜欢 2<3 的比较']);
    });
  });
}
