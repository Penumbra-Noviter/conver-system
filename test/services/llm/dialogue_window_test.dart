/// `dialogue_window.dart` 纯 builder 契约（F-148 最近对话窗口单源）。
///
/// 窗口 = 输入有序消息片段取尾 [limit]（排序不变）；[charBudget] 非空时从后
/// 往前累加 content 长度、超预算截断（保留最近内容），返回窗口消息列表
/// （`List<Message>`，顺序不变——署名由三个伴生服务在调用点各自差异化）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart' show Message;
import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/services/llm/dialogue_window.dart';
import 'package:flutter_test/flutter_test.dart';

Message message({
  required int id,
  required String content,
  Role role = Role.user,
}) {
  return Message(
    id: id,
    conversationId: 1,
    role: role,
    content: content,
    activeSwipeIndex: 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(id * 1000),
  );
}

void main() {
  group('尾 N 窗口（限长，输入有序）', () {
    final msgs = [
      message(id: 1, content: 'a'), // 1
      message(id: 2, content: 'bb'), // 2
      message(id: 3, content: 'ccc'), // 3
      message(id: 4, content: 'dddd'), // 4
      message(id: 5, content: 'eeeee'), // 5
    ];

    test('limit=3 → 取末 3 条且保持输入顺序', () {
      expect(recentDialogueWindow(msgs, limit: 3).map((m) => m.id), [3, 4, 5]);
    });

    test('limit ≥ 条数 → 全部且顺序不变', () {
      expect(
        recentDialogueWindow(msgs, limit: 5).map((m) => m.id),
        [1, 2, 3, 4, 5],
      );
      expect(
        recentDialogueWindow(msgs, limit: 99).map((m) => m.id),
        [1, 2, 3, 4, 5],
      );
    });

    test('limit=0 / 负 limit → 空窗口（防御）', () {
      expect(recentDialogueWindow(msgs, limit: 0), isEmpty);
      expect(recentDialogueWindow(msgs, limit: -1), isEmpty);
    });

    test('空输入 → 空窗口（无预算也空）', () {
      expect(recentDialogueWindow(const [], limit: 3), isEmpty);
      expect(recentDialogueWindow(const [], limit: 3, charBudget: 0), isEmpty);
      expect(
        recentDialogueWindow(const [], limit: 3, charBudget: 100),
        isEmpty,
      );
    });
  });

  group('charBudget 从后截断（保留最近内容）', () {
    test('budget 超全量 → 保留窗口全部', () {
      final msgs = [
        message(id: 1, content: 'aaaa'), // 4
        message(id: 2, content: 'bb'), // 2
        message(id: 3, content: 'cccc'), // 4
      ];
      final window = recentDialogueWindow(msgs, limit: 3, charBudget: 100);
      expect(window.map((m) => m.id), [1, 2, 3]);
    });

    test('budget 恰好等于已保留累计 → 边界保留（> 才截断）', () {
      final msgs = [
        message(id: 1, content: 'aaaa'), // 4
        message(id: 2, content: 'bb'), // 2
        message(id: 3, content: 'cccc'), // 4
      ];
      // 从后：m3(4)→4；m2(2)→6；budget=6 含 m2；m1(4)→10 > 6 截断。
      final window = recentDialogueWindow(msgs, limit: 3, charBudget: 6);
      expect(window.map((m) => m.id), [2, 3]);
    });

    test('单条超预算即断：该条与其更早全部排除', () {
      final msgs = [
        message(id: 1, content: 'a'), // 1
        message(id: 2, content: 'bbbbbbbbbb'), // 10
        message(id: 3, content: 'c'), // 1
      ];
      // 从后：m3(1)→1；m2(10)→11 > 5 → 断 → 仅 [3]。
      final window = recentDialogueWindow(msgs, limit: 3, charBudget: 5);
      expect(window.map((m) => m.id), [3]);
    });

    test('budget=0 → 非空 content 逐条都超预算 → 空窗口', () {
      final msgs = [
        message(id: 1, content: 'a'),
        message(id: 2, content: 'b'),
      ];
      expect(recentDialogueWindow(msgs, limit: 3, charBudget: 0), isEmpty);
    });

    test('budget=0 但含空 content 消息 → 空内容消息保留（0 不超 0）', () {
      final msgs = [
        message(id: 1, content: 'a'),
        message(id: 2, content: ''),
      ];
      final window = recentDialogueWindow(msgs, limit: 3, charBudget: 0);
      expect(window.map((m) => m.id), [2]);
    });

    test('限长作用在预算之前：仅窗口尾参与从后累积', () {
      final msgs = [
        message(id: 1, content: 'a'), // 1
        message(id: 2, content: 'bb'), // 2
        message(id: 3, content: 'cccc'), // 4
        message(id: 4, content: 'ddddd'), // 5
      ];
      // 尾 3 = [2,3,4]；从后：m4(5)→5；m3(4)→9 > 6 断 → 保留 [4]。
      final window = recentDialogueWindow(msgs, limit: 3, charBudget: 6);
      expect(window.map((m) => m.id), [4]);
    });

    test('组合下顺序恒为输入升序（预算作用后不反转）', () {
      final msgs = [
        message(id: 1, content: 'a'), // 1
        message(id: 2, content: 'bb'), // 2
        message(id: 3, content: 'ccc'), // 3
      ];
      final w1 = recentDialogueWindow(msgs, limit: 2, charBudget: 10);
      expect(w1.map((m) => m.id), [2, 3]);
      final w2 = recentDialogueWindow(msgs, limit: 2, charBudget: 3);
      expect(w2.map((m) => m.id), [3], reason: 'm3(3) 恰为预算且在最末');
    });
  });
}