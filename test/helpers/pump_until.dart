/// 轮询等待测试辅助 — 循环 pump 直至条件满足。
///
/// 收敛 6 个测试文件各自内联的 `pumpUntil`（chat_entry_test 200 次 + 其余
/// 5 文件 300 次，F-107），窗口统一 300×10ms；供真实异步落库 / 回合收尾 /
/// 流完成等轮询等待复用。
library;

import 'package:flutter_test/flutter_test.dart';

/// 循环 pump 直至 [condition] 为真（真实异步落库 / 回合收尾 / 流完成等
/// 轮询等待）；窗口耗尽即 [expect] 抛 [TestFailure]，失败消息 [why] 只描述
/// 现象不归因。
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String why = '',
}) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: why);
}
