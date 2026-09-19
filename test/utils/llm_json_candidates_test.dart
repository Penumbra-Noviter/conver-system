/// `lib/utils/llm_json_candidates.dart` 契约测试（AD-03 S2 三级容错提取单源）。
///
/// 语义锚点（spec S2 + Grilling 共识）：
/// - 输出有序候选段：原文 trim 在前 → fenced 代码块段（按 marker 序逐个）→
///   open/close 范围段（首 open 到末 close）；
/// - marker 字面量（`['```json\n', '```\n', '```']`）单源仅存于 helper 默认值；
/// - helper 为纯字符串操作自身不抛异常：trim 后为空（无候选）→ 空列表，解析
///   失败语义由调用方类型化解码决定；
/// - fenced 段提取后 trim、范围段不 trim，与三处既有实现逐字等价。
///
/// 注：候选列表不去重、裸 ```（marker3）会从首个 ``` 起再产出一份兜底候选、
/// 范围段从首 open 跨到末 close——三者均为既有实现的忠实语义（调用方逐个
/// 解码，失败候选自动跳过），此处以精确列表锁定，防未来"优化"破坏。
library;

import 'package:conver_system_mobile/utils/llm_json_candidates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('llmJsonCandidates · 直接候选（原文 trim 在前）', () {
    test('非空原文为首个候选（含首尾空白 trim）', () {
      expect(
        llmJsonCandidates('  {"a": 1}  ', open: '{', close: '}'),
        ['{"a": 1}', '{"a": 1}'], // 范围段与直接候选内容重复（不去重语义）。
      );
    });

    test('无 fenced 无范围 → 仅原文候选', () {
      expect(
        llmJsonCandidates('纯文本没有标记', open: '{', close: '}'),
        ['纯文本没有标记'],
      );
    });

    test('trim 后为空 → 空列表（空输入分支）', () {
      expect(llmJsonCandidates('', open: '{', close: '}'), isEmpty);
      expect(llmJsonCandidates('   \n\t  ', open: '{', close: '}'), isEmpty);
    });
  });

  group('llmJsonCandidates · fenced 代码块段', () {
    test('```json\\n 标记提取并 trim；裸 ``` 兜底候选也在列', () {
      const raw = '开头\n```json\n  {"a": 1}  \n```\n结尾';
      expect(llmJsonCandidates(raw, open: '{', close: '}'), [
        '开头\n```json\n  {"a": 1}  \n```\n结尾', // 直接候选（原文）。
        '{"a": 1}', // ```json\n 标记 → trim 后提取。
        'json\n  {"a": 1}', // 裸 ``` 兜底：首 ``` 起、首个闭 ``` 止（含 json\n 前缀）。
        '{"a": 1}', // 范围候选（内容同 fenced，不去重）。
      ]);
    });

    test('marker 优先序：```json\\n 候选在前，```\\n 不二次命中', () {
      const raw = '```json\n{"a": 1}\n```\n后面没有更多代码块';
      expect(llmJsonCandidates(raw, open: '{', close: '}'), [
        '```json\n{"a": 1}\n```\n后面没有更多代码块',
        '{"a": 1}', // ```json\n 标记提取。
        'json\n{"a": 1}', // 裸 ``` 兜底候选（decode 必失败，调用方跳过）。
        '{"a": 1}', // 范围候选。
      ]);
    });

    test('fenced 无闭合 ``` → 不产生 fenced 候选（失败分支）', () {
      const raw = '```json\n{"a": 1}';
      expect(llmJsonCandidates(raw, open: '{', close: '}'), [
        '```json\n{"a": 1}', // 直接候选。
        '{"a": 1}', // 范围候选。
      ]);
    });

    test('自定义 fenceMarkers 覆盖默认（单 marker 生效）', () {
      const raw = '```\n{"a": 1}\n``` 尾';
      expect(
        llmJsonCandidates(raw, open: '{', close: '}', fenceMarkers: const ['```\n']),
        ['```\n{"a": 1}\n``` 尾', '{"a": 1}', '{"a": 1}'],
      );
    });

    test('自定义 marker 完全不匹配 → 无 fenced 候选', () {
      const raw = '@@@\n{"a": 1}\n@@@';
      expect(
        llmJsonCandidates(raw, open: '{', close: '}', fenceMarkers: const ['@@@\n']),
        ['@@@\n{"a": 1}\n@@@', '{"a": 1}'],
      );
    });
  });

  group('llmJsonCandidates · open/close 范围段', () {
    test('首 open 到末 close 范围提取（不 trim）', () {
      const raw = '前缀 { "a": 1 } 后缀';
      expect(llmJsonCandidates(raw, open: '{', close: '}'), [
        '前缀 { "a": 1 } 后缀', // 直接候选。
        '{ "a": 1 }', // 范围候选：保留内部空白（不 trim）。
      ]);
    });

    test('array 语义：open=[ close=] 提取方括号范围', () {
      const raw = '说明 ["a", "b"] 结束';
      expect(llmJsonCandidates(raw, open: '[', close: ']'), [
        '说明 ["a", "b"] 结束',
        '["a", "b"]',
      ]);
    });

    test('只 open 无 close / 只 close 无 open → 不产生范围候选', () {
      expect(
        llmJsonCandidates('前缀 { 没有闭合', open: '{', close: '}'),
        ['前缀 { 没有闭合'],
      );
      expect(
        llmJsonCandidates('没有开启 } 后缀', open: '{', close: '}'),
        ['没有开启 } 后缀'],
      );
      // open == close 且仅出现一次 → 首末相等 → 不满足 end > start。
      expect(
        llmJsonCandidates('a < b', open: '<', close: '<'),
        ['a < b'],
      );
    });

    test('空分隔符 → 跳过范围段不抛（helper 不抛异常契约）', () {
      expect(llmJsonCandidates('x', open: '', close: ''), ['x']);
      expect(llmJsonCandidates('', open: '', close: ''), isEmpty);
    });
  });

  group('llmJsonCandidates · 顺序总览与不抛异常', () {
    test('候选顺序固定：直接 → fenced（marker 序）→ 范围（跨到末 close）', () {
      const raw = 'x ```json\n{"a":1}\n``` y {z}';
      expect(llmJsonCandidates(raw, open: '{', close: '}'), [
        'x ```json\n{"a":1}\n``` y {z}', // 直接候选。
        '{"a":1}', // ```json\n 标记 fenced 候选。
        'json\n{"a":1}', // 裸 ``` 兜底候选。
        '{"a":1}\n``` y {z}', // 范围段：首 { 到末 }（跨对象忠实语义）。
      ]);
    });

    test('畸形输入不抛异常（helper 自身不抛契约）', () {
      expect(
        () => llmJsonCandidates('{', open: '{', close: '}'),
        returnsNormally,
      );
      expect(
        () => llmJsonCandidates('}', open: '{', close: '}'),
        returnsNormally,
      );
      expect(
        () => llmJsonCandidates('```\n', open: '{', close: '}'),
        returnsNormally,
      );
      expect(
        () => llmJsonCandidates('a' * 10000, open: '{', close: '}'),
        returnsNormally,
      );
      expect(
        () => llmJsonCandidates('', open: '{', close: '}', fenceMarkers: const []),
        returnsNormally,
      );
      expect(
        () => llmJsonCandidates('x', open: '', close: ''),
        returnsNormally,
      );
    });

    test('fenceMarkers 空列表 → 跳过 fenced 级仍产生直接与范围候选', () {
      const raw = 'x {a} y';
      expect(
        llmJsonCandidates(raw, open: '{', close: '}', fenceMarkers: const []),
        ['x {a} y', '{a}'],
      );
    });
  });
}
