/// Prompt 组装纯函数契约（T01a 验收）。
///
/// 语义锚点（逐字对齐）：`desktop/backend/app/services/llm/prompt.py`
/// + `desktop/backend/tests/test_prompt.py` 全部测试类：
/// TestApplyTemplateVars / TestParseMesExample / TestSystemPromptFallback /
/// TestScenarioAndPhi / TestFullAssembly / TestSlidingWindow / TestMisc /
/// TestAppendCurrentInput。
///
/// `applyTemplateVars` 为既有 `services/template_vars.dart` 复用函数（本票只
/// 组装、不重写），此处按桌面 TestApplyTemplateVars 锚复述其行为以固定契约面。
library;

import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/services/llm/prompt.dart';
import 'package:conver_system_mobile/services/template_vars.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造历史消息条目（含 role 与 content 属性），桌面 SimpleNamespace 对应物。
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
}) =>
    CharacterData(
      name: name,
      systemPrompt: systemPrompt,
      personality: personality,
      scenario: scenario,
      mesExample: mesExample,
      postHistoryInstructions: postHistoryInstructions,
    );

/// 抽取列表中 role ∈ {user, assistant} 的消息内容（滑窗断言辅助）。
///
/// 对齐桌面锚 `msgs[:-1]`：末条为当前输入（user），不计入历史内容。
List<String> _roundContents(List<PromptMessage> msgs) {
  final head =
      msgs.length > 1 ? msgs.sublist(0, msgs.length - 1) : <PromptMessage>[];
  return [
    for (final m in head)
      if (m.role == 'user' || m.role == 'assistant') m.content,
  ];
}

// ── 1. 模板变量替换（复用 template_vars.dart::applyTemplateVars）──

/// 未知角色类型（非 Role / 非 String）：归一应回退 toString 而非崩溃
/// （桌面 `str(role)` 语义的对抗性面）。
class _OddRole {
  @override
  String toString() => '[odd-role]';
}

void main() {
  group('TestApplyTemplateVars', () {
    test('两占位符缺省替换为 User / Character', () {
      expect(applyTemplateVars('{{user}} 对 {{char}} 说'), 'User 对 Character 说');
    });

    test('自定义昵称与角色名', () {
      expect(
        applyTemplateVars(
          '{{user}} 对 {{char}} 说',
          userName: '小明',
          charName: '艾莉',
        ),
        '小明 对 艾莉 说',
      );
    });

    test('空文本原样返回', () {
      expect(applyTemplateVars(''), '');
    });

    test('无占位符文本原样返回', () {
      expect(applyTemplateVars('你好，世界'), '你好，世界');
    });

    test('先 user 后 char、一次性替换不递归（替换值含占位符不再展开）', () {
      // 第二遍只处理结果中残留的 {{char}}，替换值中的占位符不再展开。
      expect(applyTemplateVars('我是{{char}}', charName: '{{user}}'), '我是{{user}}');
    });
  });

  // ── 2. mes_example 解析 ──

  group('TestParseMesExample', () {
    test('空串返回空列表', () {
      expect(parseMesExample(''), isEmpty);
    });

    test('纯空白返回空列表', () {
      expect(parseMesExample('   \n  '), isEmpty);
    });

    test('仅 <START> 标记返回空列表', () {
      expect(parseMesExample('<START>'), isEmpty);
      expect(parseMesExample('<START>\n<START>\n'), isEmpty);
    });

    test('单轮解析', () {
      expect(
        parseMesExample('<START>\n{{user}}: 你好\n{{char}}: 欢迎'),
        [
          (role: 'user', content: '你好'),
          (role: 'assistant', content: '欢迎'),
        ],
      );
    });

    test('多轮 <START> 分隔', () {
      expect(
        parseMesExample(
          '<START>\n{{user}}: 第一问\n{{char}}: 第一答\n'
          '<START>\n{{user}}: 第二问\n{{char}}: 第二答',
        ),
        [
          (role: 'user', content: '第一问'),
          (role: 'assistant', content: '第一答'),
          (role: 'user', content: '第二问'),
          (role: 'assistant', content: '第二答'),
        ],
      );
    });

    test('无前缀行忽略', () {
      expect(
        parseMesExample('<START>\n这是一句旁白\n{{user}}: 你好'),
        [(role: 'user', content: '你好')],
      );
    });

    test('内容模板变量替换', () {
      expect(
        parseMesExample(
          '{{user}}: 我是{{user}}\n{{char}}: 我是{{char}}',
          userName: '小明',
          charName: '艾莉',
        ),
        [
          (role: 'user', content: '我是小明'),
          (role: 'assistant', content: '我是艾莉'),
        ],
      );
    });

    test('空内容行跳过', () {
      expect(
        parseMesExample('<START>\n{{user}}:\n{{char}}: 欢迎'),
        [(role: 'assistant', content: '欢迎')],
      );
    });

    test('空行跳过', () {
      expect(
        parseMesExample('<START>\n\n{{user}}: 你好\n\n{{char}}: 欢迎\n'),
        [
          (role: 'user', content: '你好'),
          (role: 'assistant', content: '欢迎'),
        ],
      );
    });

    test('冒号无空格容错（lstrip(":") 语义）', () {
      expect(
        parseMesExample('<START>\n{{user}}:你好\n{{char}}:欢迎'),
        [
          (role: 'user', content: '你好'),
          (role: 'assistant', content: '欢迎'),
        ],
      );
    });

    test('多个连续冒号全部剥离（lstrip(":") 语义）', () {
      expect(
        parseMesExample('<START>\n{{user}}::: 你好'),
        [(role: 'user', content: '你好')],
      );
    });
  });

  // ── 3. system prompt 回退 ──

  group('TestSystemPromptFallback', () {
    test('system_prompt 优先', () {
      final msgs = buildMessages(
        _char(systemPrompt: '覆盖提示', personality: '人格设定'),
        userContent: '你好',
      );
      expect(msgs.first, (role: 'system', content: '覆盖提示'));
    });

    test('无 system_prompt 回退 personality', () {
      final msgs = buildMessages(
        _char(systemPrompt: '', personality: '人格设定'),
        userContent: '你好',
      );
      expect(msgs.first, (role: 'system', content: '人格设定'));
    });
  });

  // ── 4. scenario / PHI 组装顺序与内容 ──

  group('TestScenarioAndPhi', () {
    test('scenario 与 PHI 位置', () {
      final msgs = buildMessages(
        _char(scenario: '竹林', postHistoryInstructions: '保持人设'),
        userContent: '你好',
      );
      expect(msgs[1], (role: 'system', content: '[场景设定]\n竹林'));
      expect(msgs[msgs.length - 2], (role: 'system', content: '保持人设'));
      expect(msgs.last, (role: 'user', content: '你好'));
    });

    test('scenario 与 PHI 模板变量替换', () {
      final msgs = buildMessages(
        _char(
          scenario: '{{char}}场景',
          postHistoryInstructions: '{{char}}指令',
        ),
        userContent: '{{user}}你好',
        userName: '小明',
      );
      expect(msgs[1].content, '[场景设定]\n艾莉场景');
      expect(msgs[msgs.length - 2].content, '艾莉指令');
      expect(msgs.last.content, '小明你好');
    });

    test('无 scenario 与无 PHI 时仅 system + user', () {
      final msgs = buildMessages(_char(), userContent: '你好');
      expect([for (final m in msgs) m.role], ['system', 'user']);
    });
  });

  // ── 5. 完整组装顺序 ──

  group('TestFullAssembly', () {
    test('mes_example + 历史 + PHI + 当前输入全顺序', () {
      final msgs = buildMessages(
        _char(
          systemPrompt: '系统提示',
          scenario: '场景设定',
          mesExample: '<START>\n{{user}}: 例1\n{{char}}: 例2',
          postHistoryInstructions: '历史指令',
        ),
        history: [
          _msg(Role.user, '历史1'),
          _msg(Role.assistant, '历史2'),
        ],
        userContent: '当前输入',
        userName: '小明',
      );
      expect(
        [for (final m in msgs) m.role],
        [
          'system', // system prompt
          'system', // scenario
          'user', // mes_example 例1
          'assistant', // mes_example 例2
          'user', // 历史1
          'assistant', // 历史2
          'system', // PHI
          'user', // 当前输入
        ],
      );
      expect(msgs[0], (role: 'system', content: '系统提示'));
      expect(msgs[1], (role: 'system', content: '[场景设定]\n场景设定'));
      expect(msgs[2], (role: 'user', content: '例1'));
      expect(msgs[3], (role: 'assistant', content: '例2'));
      expect(msgs[4], (role: 'user', content: '历史1'));
      expect(msgs[5], (role: 'assistant', content: '历史2'));
      expect(msgs[6], (role: 'system', content: '历史指令'));
      expect(msgs[7], (role: 'user', content: '当前输入'));
    });
  });

  // ── 6. 滑窗截断边界 ──

  group('TestSlidingWindow', () {
    List<HistoryMessage> historyOf(int n) => [
          for (var i = 0; i < n; i++)
            _msg(i.isEven ? Role.user : Role.assistant, 'm$i'),
        ];

    test('恰好等于窗口不截断', () {
      final msgs = buildMessages(
        _char(),
        history: historyOf(4),
        userContent: '当前',
        maxRounds: 2,
      );
      expect(_roundContents(msgs), ['m0', 'm1', 'm2', 'm3']);
    });

    test('超过窗口取最后 max_rounds*2 条', () {
      final msgs = buildMessages(
        _char(),
        history: historyOf(10),
        userContent: '当前',
        maxRounds: 2,
      );
      expect(_roundContents(msgs), ['m6', 'm7', 'm8', 'm9']);
    });

    test('少于窗口全保留', () {
      final msgs = buildMessages(
        _char(),
        history: historyOf(2),
        userContent: '当前',
        maxRounds: 30,
      );
      expect(_roundContents(msgs), ['m0', 'm1']);
    });

    test('历史 role 为纯字符串归一正确', () {
      final msgs = buildMessages(
        _char(),
        history: [_msg('user', 's1'), _msg('assistant', 's2')],
        userContent: '当前',
        maxRounds: 1,
      );
      // 对齐桌面锚 msgs[:-1]：末条为当前输入，不计入历史。
      final head =
          msgs.length > 1 ? msgs.sublist(0, msgs.length - 1) : <PromptMessage>[];
      final historyMsgs = [
        for (final m in head)
          if (m.role == 'user' || m.role == 'assistant') m,
      ];
      expect(historyMsgs, [
        (role: 'user', content: 's1'),
        (role: 'assistant', content: 's2'),
      ]);
    });

    test('空历史不抛错（Falsify）', () {
      final msgs = buildMessages(_char(), userContent: '你好');
      expect(msgs, [
        (role: 'system', content: ''),
        (role: 'user', content: '你好'),
      ]);
    });
  });

  // ── 7. 其他边界 ──

  group('TestMisc', () {
    test('当前输入追加且模板变量替换', () {
      final msgs = buildMessages(_char(), userContent: '{{user}}说');
      expect(msgs.last, (role: 'user', content: 'User说'));
    });

    test('空角色名回退 Character', () {
      final msgs = buildMessages(
        CharacterData(name: '', systemPrompt: '{{char}}提示'),
        userContent: '你好',
      );
      expect(msgs.first, (role: 'system', content: 'Character提示'));
    });

    test('空历史 + 无 extras 输出 [system(""), user(输入)]', () {
      final msgs = buildMessages(_char(), userContent: '你好');
      expect(msgs, [
        (role: 'system', content: ''),
        (role: 'user', content: '你好'),
      ]);
    });

    test('未知 role 类型回退 toString 不崩溃（Falsify）', () {
      final msgs = buildMessages(
        _char(),
        history: [_msg(_OddRole(), '兜底内容')],
        userContent: '当前',
      );
      expect(msgs[1], (role: '[odd-role]', content: '兜底内容'));
      expect(msgs.last.role, 'user');
    });
  });

  // ── 8. append_current_input 显式路径 ──

  group('TestAppendCurrentInput', () {
    test('默认 True 追加当前输入', () {
      final msgs = buildMessages(
        _char(),
        history: [_msg(Role.user, '历史1'), _msg(Role.assistant, '历史2')],
        userContent: '当前输入',
      );
      expect(msgs.last, (role: 'user', content: '当前输入'));
    });

    test('True 显式传参保留 PHI 于末条 user 之前', () {
      final msgs = buildMessages(
        _char(postHistoryInstructions: '保持人设'),
        history: [_msg(Role.user, '历史1'), _msg(Role.assistant, '历史2')],
        userContent: '当前输入',
        appendCurrentInput: true,
      );
      expect(
        msgs[msgs.length - 2],
        (role: 'system', content: '保持人设'),
      );
      expect(msgs.last, (role: 'user', content: '当前输入'));
    });

    test('False 不追加当前输入（末尾不出现当前输入内容）', () {
      final msgs = buildMessages(
        _char(),
        history: [_msg(Role.user, '历史1'), _msg(Role.assistant, '历史2')],
        userContent: '被忽略的当前输入',
        appendCurrentInput: false,
      );
      final contents = [for (final m in msgs) m.content];
      expect(contents, isNot(contains('被忽略的当前输入')));
    });

    test('False 末条为历史末条 user（待回复触发源）', () {
      final msgs = buildMessages(
        _char(),
        history: [
          _msg(Role.user, '第一轮问'),
          _msg(Role.assistant, '第一轮答'),
          _msg(Role.user, '第二轮问'),
        ],
        userContent: '忽略',
        appendCurrentInput: false,
      );
      expect(msgs.last, (role: 'user', content: '第二轮问'));
    });

    test('False + PHI：剥离尾随 system，触发 user 仅出现一次（无幽灵 user）', () {
      final msgs = buildMessages(
        _char(postHistoryInstructions: '保持人设'),
        history: [
          _msg(Role.user, '第一轮问'),
          _msg(Role.assistant, '第一轮答'),
          _msg(Role.user, '第二轮问'),
        ],
        userContent: '忽略',
        appendCurrentInput: false,
      );
      expect(msgs.last, (role: 'user', content: '第二轮问'));
      expect(msgs.last.role, isNot('system'));
      final occurrences = [
        for (final m in msgs)
          if (m.role == 'user' && m.content == '第二轮问') m,
      ];
      expect(occurrences, hasLength(1));
    });

    test('False + 空历史：不抛错，无 user 消息', () {
      final msgs = buildMessages(
        _char(),
        userContent: '忽略',
        appendCurrentInput: false,
      );
      expect([for (final m in msgs) if (m.role == 'user') m], isEmpty);
    });

    test('False：user_content 被忽略、不校验、不追加（签名兼容）', () {
      final history = [
        _msg(Role.user, '第一轮问'),
        _msg(Role.assistant, '第一轮答'),
        _msg(Role.user, '第二轮问'),
      ];
      for (final ignored in ['', '任意内容']) {
        final msgs = buildMessages(
          _char(),
          history: history,
          userContent: ignored,
          appendCurrentInput: false,
        );
        expect(msgs.last, (role: 'user', content: '第二轮问'));
      }
    });

    test('False + 无 PHI：无残留 system 尾随', () {
      final msgs = buildMessages(
        _char(),
        history: [
          _msg(Role.user, '问1'),
          _msg(Role.assistant, '答1'),
          _msg(Role.user, '问2'),
        ],
        userContent: '忽略',
        appendCurrentInput: false,
      );
      expect(msgs.last, (role: 'user', content: '问2'));
    });

    test('False + 滑窗截断 + PHI：截断后末条仍为触发 user', () {
      final history = [
        for (var i = 0; i < 10; i++)
          _msg(i.isEven ? Role.user : Role.assistant, 'm$i'),
      ];
      history.add(_msg(Role.user, '触发问'));
      final msgs = buildMessages(
        _char(postHistoryInstructions: '保持人设'),
        history: history,
        userContent: '忽略',
        maxRounds: 2,
        appendCurrentInput: false,
      );
      // 滑窗保留 [m7, m8, m9, 触发问]，PHI 伪尾随被剥离 → 末条 = 触发问
      expect(msgs.last, (role: 'user', content: '触发问'));
      expect(msgs.last.role, isNot('system'));
    });

    test('False：历史尾随多 system（含 PHI）全部剥离，末条恒为触发 user', () {
      // 历史末条 user 之后有若干 system 残注 + PHI；while 语义要求全剥，
      // 末条回归触发 user（仅剥离单个 system 的实现将无法通过）。
      final msgs = buildMessages(
        _char(postHistoryInstructions: '保持人设'),
        history: [
          _msg(Role.user, '先问'),
          _msg(Role.assistant, '先答'),
          _msg(Role.user, '再触发'),
          _msg(Role.system, '系统残注1'),
          _msg(Role.system, '系统残注2'),
        ],
        userContent: '忽略',
        appendCurrentInput: false,
      );
      expect(msgs.last, (role: 'user', content: '再触发'));
      final triggerIndex = msgs.lastIndexWhere(
        (m) => m == (role: 'user', content: '再触发'),
      );
      expect(msgs.sublist(triggerIndex + 1), isEmpty,
          reason: '触发 user 之后不得残留任何 system');
    });
  });
}
