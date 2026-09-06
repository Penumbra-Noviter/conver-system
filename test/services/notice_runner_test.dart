/// NoticeRunner 测试（2026-09-07 架构深化——候选 2 收拢）。
///
/// 收敛自 chat / characters 两控制器的「超时兜底 + 先错者胜 notice」
/// 编排（原 `.timeout(3s)` 6 处 + notice 12 处重复）；本文件覆盖运行器
/// 全部语义：guard 成功 / 失败 / 超时、先错者胜、set / setFirst / clear。
library;

import 'dart:async';

import 'package:conver_system_mobile/services/notice_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoticeRunner · guard 执行 + 超时兜底', () {
    test('成功 → 返回 op 产物，notice 不变', () async {
      final runner = NoticeRunner();
      runner.set('旧提示');

      final result = await runner.guard(
        op: () async => 42,
        onError: (e) => '失败: $e',
      );

      expect(result, 42);
      expect(runner.notice, '旧提示', reason: '成功不触碰 notice');
    });

    test('op 抛错 → onError 折叠为 notice（先错者胜）+ 返回 null', () async {
      final runner = NoticeRunner();

      final result = await runner.guard(
        op: () async => throw StateError('boom'),
        onError: (e) => '失败了: $e',
      );

      expect(result, isNull);
      expect(runner.notice, '失败了: Bad state: boom');
    });

    test('op 挂起 → timeout 兜底：onError 折叠且不挂死', () async {
      final runner = NoticeRunner();
      final hanging = Completer<int>().future;

      final result = await runner.guard<int>(
        op: () => hanging,
        onError: (e) => '操作超时: $e',
        timeout: const Duration(milliseconds: 50),
      );

      expect(result, isNull);
      expect(runner.notice, startsWith('操作超时: TimeoutException'));
    });
  });

  group('NoticeRunner · notice 语义', () {
    test('先错者胜：已有 notice 时失败不覆盖', () async {
      final runner = NoticeRunner();
      runner.setFirst('先到的错误');

      await runner.guard(
        op: () async => throw StateError('later'),
        onError: (e) => '后到的错误: $e',
      );

      expect(runner.notice, '先到的错误', reason: '先错者胜，后错不覆盖');
    });

    test('set 覆盖式设置 / setFirst 仅填空 / clear 清空', () {
      final runner = NoticeRunner();

      runner.set('A');
      expect(runner.notice, 'A');
      runner.set('B');
      expect(runner.notice, 'B', reason: 'set 覆盖');

      runner.setFirst('C');
      expect(runner.notice, 'B', reason: 'setFirst 先错者胜不覆盖');
      runner.clear();
      runner.setFirst('D');
      expect(runner.notice, 'D', reason: '清空后 setFirst 生效');

      runner.clear();
      expect(runner.notice, isNull);
      expect(runner.hasNotice, isFalse);
    });
  });
}