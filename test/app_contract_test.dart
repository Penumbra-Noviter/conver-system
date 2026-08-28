import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 契约锁（TECH_DEBT F-4）：`themeMode: ThemeMode.dark` 在 darkTheme 为 null 的
/// 现状下无运行态判别力（任何 ThemeMode 都回退 theme），以源码文本锚锁定装配，
/// 防止该行被无意识移除。M1 引入浅色主题（darkTheme 非 null）后，本测试应升级
/// 为行为断言（注入平台亮度过改动主题不随之切换），届时本文件可退役。
void main() {
  test('app.dart 装配锚：显式 themeMode: ThemeMode.dark（F-4 契约锁）', () {
    final source = File('lib/app.dart').readAsStringSync();
    expect(source, contains('themeMode: ThemeMode.dark'));
  });
}
