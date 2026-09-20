/// PD-04 Prompt Debug — 组装核心（_assemble 共享）与来源标注契约。
///
/// 语义锚点（逐字对齐）：`desktop/backend/tests/test_prompt_debug.py`
/// （PD-3 六条锁：simple 全序来源 / expert 单条 / world·memory 分源 /
/// [世界知识] 混源回落 / 空态最小 / 重生成路径末条 history）。
///
/// 本文件锁 PD-04 验收 1/2/5 的**组装层**面：
/// - 验收 1：`buildMessages` 输出零变化（既有 prompt_test 基线照样绿）；且
///   `buildMessagesWithSource` 与 `buildMessages` 的 content/role 序列逐条一致
///   （共享 `_assemble` 核心——无第二份组装逻辑）；
/// - 验收 2：来源标注矩阵逐段正确（character/world/memory/history/user/
///   narrative）；mod 常量存在但无产出；
/// - 验收 5：空对话 + 无注入 → 仅 system（character）+ user（user）；重生成
///   路径（appendCurrentInput=false）末条为 history user。
library;

import 'package:conver_system_mobile/services/llm/prompt.dart';
import 'package:conver_system_mobile/services/lorebook/lorebook_engine.dart'
    show InjectedSegment, sourceMemory, sourceWorld;
import 'package:flutter_test/flutter_test.dart';

/// 构造历史消息条目（含 role 与 content 属性）。
HistoryMessage _msg(Object role, String content) =>
    HistoryMessage(role: role, content: content);

/// 构造角色纯数据（name 固定为艾莉，其余字段可覆盖）。
CharacterData _char({
  String name = '艾莉',
  String systemPrompt = '',
  String personality = '',
  String scenario = '',
  String mesExample = '',
  String postHistoryInstructions = '',
  String promptMode = 'simple',
  String expertPrompt = '',
}) =>
    CharacterData(
      name: name,
      systemPrompt: systemPrompt,
      personality: personality,
      scenario: scenario,
      mesExample: mesExample,
      postHistoryInstructions: postHistoryInstructions,
      promptMode: promptMode,
      expertPrompt: expertPrompt,
    );

void main() {
  group('验收1 · 共享 _assemble 核心（buildMessagesWithSource 与 buildMessages '
      'content/role 逐条一致）', () {
    test('simple 富输入：world(字符串) + mes_example + 历史 + PHI，逐条一致', () {
      final char = _char(
        personality: '你是测试角色。',
        scenario: '月下竹林',
        mesExample: '<START>\n{{user}}: 例1\n{{char}}: 例2',
        postHistoryInstructions: '保持人设。',
      );
      final history = [_msg('user', '历史1'), _msg('assistant', '历史2')];
      final world = {
        'before_char': ['角色前置'],
        'system': ['背景一'],
        'after_char': ['场景后'],
      };

      final plain = buildMessages(
        char,
        history: history,
        userContent: '当前输入',
        world: world,
      );
      final tagged = buildMessagesWithSource(
        char,
        history: history,
        userContent: '当前输入',
        world: world,
      );

      expect(tagged.length, plain.length);
      for (var i = 0; i < plain.length; i++) {
        expect(tagged[i].role, plain[i].role,
            reason: 'role 逐条一致 @$i');
        expect(tagged[i].content, plain[i].content,
            reason: 'content 逐条一致 @$i');
      }
    });

    test('expert + 非空 → system 单条，与 buildMessages 逐条一致', () {
      final char = _char(
        promptMode: 'expert',
        expertPrompt: '你是{{char}}，专家指令。',
        systemPrompt: '系统提示', // 应被忽略
        scenario: '场景设定', // 应被忽略
        postHistoryInstructions: '历史指令', // 应被忽略
        mesExample: '<START>\n{{user}}: 例\n{{char}}: 例2',
      );
      final history = [_msg('user', '问'), _msg('assistant', '答')];

      final plain = buildMessages(char, history: history, userContent: '你好');
      final tagged = buildMessagesWithSource(
        char,
        history: history,
        userContent: '你好',
      );

      expect(tagged.length, plain.length);
      for (var i = 0; i < plain.length; i++) {
        expect(tagged[i].role, plain[i].role);
        expect(tagged[i].content, plain[i].content);
      }
    });

    test('世界书带来源注入块 → 与 buildMessages（纯字符串等价）逐条一致', () {
      final char = _char(
        personality: '你是测试角色。',
        scenario: '月下竹林',
        postHistoryInstructions: '保持人设。',
      );
      final history = [_msg('user', '历史1'), _msg('assistant', '历史2')];

      final plain = buildMessages(
        char,
        history: history,
        userContent: '当前输入',
        world: {
          'system': ['背景一'],
        },
      );
      final tagged = buildMessagesWithSource(
        char,
        history: history,
        userContent: '当前输入',
        world: {
          'system': [InjectedSegment(content: '背景一', source: sourceWorld)],
        },
      );

      expect(tagged.length, plain.length);
      for (var i = 0; i < plain.length; i++) {
        expect(tagged[i].role, plain[i].role);
        expect(tagged[i].content, plain[i].content);
      }
    });
  });

  group('验收2 · 来源标注矩阵', () {
    test('simple 全序来源：before_char/system/scenario/after_char/[叙述风格]/'
        '[世界知识]/mes_example/preset/history/PHI/user', () {
      final char = _char(
        personality: '你是测试角色。',
        scenario: '月下竹林',
        mesExample: '<START>\n{{user}}: 例1\n{{char}}: 例2',
        postHistoryInstructions: '保持人设。',
      );
      final history = [_msg('user', '历史1'), _msg('assistant', '历史2')];
      final world = {
        'before_char': [
          InjectedSegment(content: '角色前置', source: sourceWorld),
        ],
        'system': [
          InjectedSegment(content: '背景一', source: sourceWorld),
        ],
        'after_char': [
          InjectedSegment(content: '场景后', source: sourceWorld),
        ],
      };

      final segments = buildMessagesWithSource(
        char,
        history: history,
        userContent: '当前输入',
        world: world,
        narrativeStyle: '叙述风格规则',
        presetDialogue: '<START>\n{{user}}: 预例\n{{char}}: 预答',
      );

      expect(segments, [
        (role: 'system', content: '角色前置', source: sourceWorld),
        (role: 'system', content: '你是测试角色。', source: sourceCharacter),
        (role: 'system', content: '[场景设定]\n月下竹林', source: sourceCharacter),
        (role: 'system', content: '场景后', source: sourceWorld),
        (role: 'system', content: '[叙述风格]\n叙述风格规则', source: sourceNarrative),
        (role: 'system', content: '[世界知识]\n背景一', source: sourceWorld),
        (role: 'user', content: '例1', source: sourceCharacter),
        (role: 'assistant', content: '例2', source: sourceCharacter),
        (role: 'user', content: '预例', source: sourceCharacter),
        (role: 'assistant', content: '预答', source: sourceCharacter),
        (role: 'user', content: '历史1', source: sourceHistory),
        (role: 'assistant', content: '历史2', source: sourceHistory),
        (role: 'system', content: '保持人设。', source: sourceCharacter),
        (role: 'user', content: '当前输入', source: sourceUser),
      ]);
    });

    test('[叙述风格] 相关段 source=narrative', () {
      final segments = buildMessagesWithSource(
        _char(personality: '人设'),
        userContent: '输入',
        narrativeStyle: '不要 AI 味',
      );
      expect(
        segments.where((s) => s.content.startsWith('[叙述风格]')),
        [
          (role: 'system', content: '[叙述风格]\n不要 AI 味', source: sourceNarrative),
        ],
      );
    });

    test('expert + 非空 → system 段单条 expert_prompt，来源 character，'
        '无 scenario/PHI（桌面对应 test_expert_single_system_source_character）',
        () {
      final char = _char(
        promptMode: 'expert',
        expertPrompt: '你是{{char}}，专家指令。',
        personality: '你是测试角色。',
        scenario: '场景设定', // 应被忽略
        postHistoryInstructions: '历史指令', // 应被忽略
      );
      final segments = buildMessagesWithSource(char, userContent: '你好');
      expect(segments, [
        (role: 'system', content: '你是艾莉，专家指令。', source: sourceCharacter),
        (role: 'user', content: '你好', source: sourceUser),
      ]);
    });

    test('[世界知识] 混合 world/memory 来源 → 回落 world（内容仍逐条合并）', () {
      final segments = buildMessagesWithSource(
        _char(personality: '人设'),
        userContent: '输入',
        world: {
          'system': [
            InjectedSegment(content: '手动知识', source: sourceWorld),
            InjectedSegment(content: '记忆知识', source: sourceMemory),
          ],
        },
      );
      expect(
        segments.where((s) => s.content.startsWith('[世界知识]')),
        [
          (
            role: 'system',
            content: '[世界知识]\n手动知识\n\n记忆知识',
            source: sourceWorld,
          ),
        ],
      );
    });

    test('[世界知识] 单一 memory 来源 → source=memory（auto 条目来源保真）', () {
      final segments = buildMessagesWithSource(
        _char(personality: '人设'),
        userContent: '输入',
        world: {
          'system': [
            InjectedSegment(content: '记忆知识', source: sourceMemory),
          ],
        },
      );
      expect(
        segments.where((s) => s.content.startsWith('[世界知识]')),
        [
          (
            role: 'system',
            content: '[世界知识]\n记忆知识',
            source: sourceMemory,
          ),
        ],
      );
    });

    test('world 内纯字符串项 → 来源回退 world（桌面对应 '
        'test_plain_string_world_defaults_source_world）', () {
      final segments = buildMessagesWithSource(
        _char(personality: '人设'),
        userContent: '输入',
        world: {
          'system': ['纯字符串知识'],
        },
      );
      expect(
        segments.where((s) => s.content.startsWith('[世界知识]')),
        [
          (
            role: 'system',
            content: '[世界知识]\n纯字符串知识',
            source: sourceWorld,
          ),
        ],
      );
    });

    test('来源常量值域 + mod 占位存在但组装零产出', () {
      // 常量值（桌面 SOURCE_* 对应物）。
      expect(sourceCharacter, 'character');
      expect(sourceWorld, 'world');
      expect(sourceMemory, 'memory');
      expect(sourceMod, 'mod');
      expect(sourceHistory, 'history');
      expect(sourceUser, 'user');
      expect(sourceNarrative, 'narrative');

      // 组装产物（含 world 各位置 + 全注入物）绝不产生 mod 来源。
      final segments = buildMessagesWithSource(
        _char(
          personality: '人设',
          scenario: '场景',
          mesExample: '<START>\n{{user}}: 例\n{{char}}: 例2',
          postHistoryInstructions: 'PHI',
        ),
        history: [_msg('user', '历史')],
        userContent: '输入',
        world: {
          'before_char': ['前置'],
          'system': ['知识'],
          'after_char': ['后置'],
        },
        narrativeStyle: '风格',
        presetDialogue: '<START>\n{{user}}: 预\n{{char}}: 预答',
      );
      expect(segments.any((s) => s.source == sourceMod), isFalse,
          reason: 'mod 常量为占位，本批组装零产出');
    });
  });

  group('验收5 · 空态最小 / 重生成路径', () {
    test('空对话（无历史）+ 无注入 → 仅 system(character) + user(user) '
        '（桌面对应 test_debug_empty_conversation_minimal）', () {
      final segments = buildMessagesWithSource(
        _char(personality: '你是空态角色。'),
        userContent: '',
        appendCurrentInput: true,
      );
      expect(segments, [
        (role: 'system', content: '你是空态角色。', source: sourceCharacter),
        (role: 'user', content: '', source: sourceUser),
      ]);
    });

    test('重生成路径 appendCurrentInput=false：末条为历史末条 user（source='
        'history），无尾随 system/PHI（桌面对应 '
        'test_regenerate_path_no_trailing_system）', () {
      final char = _char(
        personality: '人设',
        postHistoryInstructions: '保持人设。',
      );
      final history = [
        _msg('user', '问1'),
        _msg('assistant', '答1'),
        _msg('user', '问2'),
      ];
      final segments = buildMessagesWithSource(
        char,
        history: history,
        userContent: '忽略',
        appendCurrentInput: false,
      );
      expect(segments.last,
          (role: 'user', content: '问2', source: sourceHistory));
      expect(segments.last.role, isNot('system'));
      // 无尾随 system（PHI 已剥离）。
      expect(segments.where((s) => s.content == '保持人设。'), isEmpty);
    });
  });
}