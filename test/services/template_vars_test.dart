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
  });
}
