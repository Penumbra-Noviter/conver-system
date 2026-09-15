/// 记忆 prompt 模板契约（AC-02）：三模式指令 + 记忆库内容组装。
library;

import 'package:conver_system_mobile/services/memory/memory_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('memorySystemPrompt', () {
    test('三模式各含独立标题且均含 add/persona 指令', () {
      final strong = memorySystemPrompt(MemoryPromptMode.strong);
      final medium = memorySystemPrompt(MemoryPromptMode.medium);
      final weak = memorySystemPrompt(MemoryPromptMode.weak);

      expect(strong, contains('严重健忘症模式'));
      expect(medium, contains('关键信息记录模式'));
      expect(weak, contains('被动记录模式'));

      expect(strong, contains('<add:'));
      expect(medium, contains('<persona:'));
      expect(weak, contains('<search:'));
    });

    test('三模式文案互不相同', () {
      final strong = memorySystemPrompt(MemoryPromptMode.strong);
      final medium = memorySystemPrompt(MemoryPromptMode.medium);
      final weak = memorySystemPrompt(MemoryPromptMode.weak);
      expect(strong == medium, isFalse);
      expect(medium == weak, isFalse);
    });
  });

  group('MemoryPromptMode.fromValue', () {
    test('解析三档；未知值回退 medium', () {
      expect(MemoryPromptMode.fromValue('strong'), MemoryPromptMode.strong);
      expect(MemoryPromptMode.fromValue('medium'), MemoryPromptMode.medium);
      expect(MemoryPromptMode.fromValue('weak'), MemoryPromptMode.weak);
      expect(MemoryPromptMode.fromValue('unknown'), MemoryPromptMode.medium);
      expect(MemoryPromptMode.fromValue(null), MemoryPromptMode.medium);
    });
  });

  group('buildMemoryLibrarySection', () {
    test('两者皆空返回空串', () {
      expect(
        buildMemoryLibrarySection(personaFacts: const [], recentEpisodic: const []),
        '',
      );
    });

    test('仅人格事实：含人格事实标题与条目', () {
      final section = buildMemoryLibrarySection(
        personaFacts: const ['她叫艾莉亚'],
        recentEpisodic: const [],
      );
      expect(section, contains('人格事实：'));
      expect(section, contains('- 她叫艾莉亚'));
      expect(section, isNot(contains('近期经历：')));
    });

    test('仅近期经历：含近期经历标题与条目', () {
      final section = buildMemoryLibrarySection(
        personaFacts: const [],
        recentEpisodic: const ['今天聊了天气'],
      );
      expect(section, contains('近期经历：'));
      expect(section, contains('- 今天聊了天气'));
      expect(section, isNot(contains('人格事实：')));
    });

    test('两者皆有：两段并列', () {
      final section = buildMemoryLibrarySection(
        personaFacts: const ['她叫艾莉亚'],
        recentEpisodic: const ['今天聊了天气'],
      );
      expect(section, contains('人格事实：'));
      expect(section, contains('近期经历：'));
      expect(section, contains('【当前记忆库内容】'));
    });
  });
}
