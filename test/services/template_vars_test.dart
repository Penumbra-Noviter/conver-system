/// applyTemplateVars 纯函数契约（工单 03 验收 A5）。
///
/// 语义锚点：桌面 `services/llm/prompt.py::apply_template_vars`。
library;

import 'package:conver_system_mobile/services/template_vars.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyTemplateVars', () {
    test('空文本原样返回', () {
      expect(applyTemplateVars(''), '');
    });

    test('两占位符全替换', () {
      final result = applyTemplateVars(
        '{{user}}向{{char}}问好，{{user}}又向{{char}}道别。',
        userName: '旅者',
        charName: '艾莉亚',
      );
      expect(result, '旅者向艾莉亚问好，旅者又向艾莉亚道别。');
    });

    test('无占位符文本不变', () {
      const text = '平静的一天，风从山那边吹来。';
      expect(applyTemplateVars(text, userName: '旅者', charName: '艾莉亚'), text);
    });

    test('缺省参数为 User / Character（桌面签名对应物）', () {
      expect(applyTemplateVars('{{user}}与{{char}}'), 'User与Character');
    });

    // ── extraVars 自定义注入（工单 04 / spec §U-3）──

    test('extraVars 替换用户自定义 {{key}}', () {
      expect(
        applyTemplateVars('欢迎来到{{city}}', extraVars: {'city': '长安'}),
        '欢迎来到长安',
      );
    });

    test('先 user → char → 再逐 key 替换 extraVars', () {
      final result = applyTemplateVars(
        '{{user}}在{{city}}遇见{{char}}，{{user}}又去了{{place}}。',
        userName: '旅者',
        charName: '艾莉亚',
        extraVars: {'city': '长安', 'place': '月牙泉'},
      );
      expect(result, '旅者在长安遇见艾莉亚，旅者又去了月牙泉。');
    });

    test('保留 key（user/char）优先：extraVars 同名 key 不覆盖', () {
      final result = applyTemplateVars(
        '{{user}}与{{char}}',
        userName: '旅者',
        charName: '艾莉亚',
        extraVars: {'user': '入侵者', 'char': '替身', 'city': '长安'},
      );
      expect(result, '旅者与艾莉亚');
    });

    test('长 key 与短 key 并存：{{ab}} 不被 {{a}} 吞并', () {
      final result = applyTemplateVars(
        '{{ab}}和{{a}}',
        extraVars: {'a': '短', 'ab': '长'},
      );
      expect(result, '长和短');
    });

    test('extraVars 为空 map 与未传等价（行为不变）', () {
      const text = '{{user}}与{{char}}，无自定义变量。';
      expect(
        applyTemplateVars(text, extraVars: const {}),
        applyTemplateVars(text),
      );
    });
  });
}
