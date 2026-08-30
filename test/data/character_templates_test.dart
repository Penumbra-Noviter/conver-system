/// 角色模板数据契约（工单 M3-02a 验收 4）。
///
/// 语义锚点（spec §Implementation Decisions 6 步向导 + 共识 A2）：
/// - 恰 5 条内置模板，id 为 senpai / wanderer / tsundere / butler / nekomimi；
/// - 每条 name / description / personality / scenario / first_mes / tags
///   非空，mes_example 与 system_prompt 恒空串；
/// - personality / scenario 逐字含 `{{char}}` 模板占位（桌面模板语义，
///   character-templates.js）；first_mes 至少存在含 `{{char}}` / `{{user}}`
///   占位的模板（桌面对话风格支持模板变量）。
///
/// 期望值来自桌面 `character-templates.js` 已知字面量（独立来源，非用
/// 实现重算——防 tautological）。
library;

import 'package:conver_system_mobile/data/character_templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('模板数据契约（验收 4）', () {
    test('恰 5 条，id 集合与桌面逐字一致', () {
      expect(characterTemplates, hasLength(5));
      expect(
        characterTemplates.map((t) => t.id).toSet(),
        {'senpai', 'wanderer', 'tsundere', 'butler', 'nekomimi'},
      );
    });

    test('每条 name/description/personality/scenario/first_mes/tags 非空',
        () {
      for (final template in characterTemplates) {
        expect(template.name, isNotEmpty, reason: 'id=${template.id} name');
        expect(template.description, isNotEmpty,
            reason: 'id=${template.id} description');
        expect(template.personality, isNotEmpty,
            reason: 'id=${template.id} personality');
        expect(template.scenario, isNotEmpty,
            reason: 'id=${template.id} scenario');
        expect(template.firstMes, isNotEmpty,
            reason: 'id=${template.id} first_mes');
        expect(template.tags, isNotEmpty,
            reason: 'id=${template.id} tags（非空列表）');
      }
    });

    test('mes_example 与 system_prompt 恒空串', () {
      for (final template in characterTemplates) {
        expect(template.mesExample, isEmpty,
            reason: 'id=${template.id} mes_example');
        expect(template.systemPrompt, isEmpty,
            reason: 'id=${template.id} system_prompt');
      }
    });

    test('personality 与 scenario 逐字含 {{char}} 模板占位', () {
      for (final template in characterTemplates) {
        expect(template.personality, contains('{{char}}'),
            reason: 'id=${template.id} personality 含 {{char}}');
        expect(template.scenario, contains('{{char}}'),
            reason: 'id=${template.id} scenario 含 {{char}}');
      }
    });

    test('first_mes 至少一条含 {{char}} / {{user}} 占位（对话风格模板变量）',
        () {
      final anyPlaceholder = characterTemplates.any((t) =>
          t.firstMes.contains('{{char}}') ||
          t.firstMes.contains('{{user}}'));
      expect(anyPlaceholder, isTrue,
          reason: 'first_mes 至少一条含模板占位（桌面对话风格支持模板变量）');
    });

    test('逐字移植锚点：senpai 名称/描述/开场白与桌面已知字面量一致', () {
      final senpai = characterTemplates.singleWhere((t) => t.id == 'senpai');
      expect(senpai.name, '知性学姐');
      expect(senpai.description, '温柔体贴、学识渊博的学姐');
      expect(
        senpai.firstMes,
        '（微笑着转过头）啊，你也在找这本书吗？真巧，我上周刚读完它。',
      );
      expect(senpai.tags, ['校园', '温柔', '学姐', '文学']);
    });

    test('逐字移植锚点：nekomimi 开场白含 {{char}} 占位（自定义名代入）', () {
      final nekomimi =
          characterTemplates.singleWhere((t) => t.id == 'nekomimi');
      expect(
        nekomimi.firstMes,
        contains('我是{{char}}'),
        reason: 'nekomimi 开场白逐字含 {{char}}（nekomimi 是唯一 first_mes 含占位模板）',
      );
    });
  });
}
