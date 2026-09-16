/// debugPrint 捕获测试辅助 — 替换全局 [debugPrint] 并记录日志。
///
/// 收敛 `notification_service_test` 三个波末用例重复的
/// 「logs 数组 + debugPrint 替换 + addTearDown 还原」setup 形状。
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

/// 替换全局 [debugPrint] 为记录实现，并注册测试结束时的还原回调。
///
/// 返回捕获到的日志列表（元素为 `String?`，对齐 debugPrint 签名）；断言侧
/// 以 `logs.any((line) => line?.contains(...) ?? false)` 消费。
List<String?> captureDebugPrint() {
  final logs = <String?>[];
  final originalDebugPrint = debugPrint;
  debugPrint = (message, {int? wrapWidth}) => logs.add(message);
  addTearDown(() => debugPrint = originalDebugPrint);
  return logs;
}
