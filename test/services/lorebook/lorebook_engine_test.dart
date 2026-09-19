/// `lib/services/lorebook/lorebook_engine.dart` 契约锁（WL-02）。
///
/// 语义锚点（spec §WL-2 + 桌面 `test_lorebook_engine.py` 逐条迁移）：
/// - 零数据库/IO：模块可独立编译运行（源码 import 检查，无 drift/app_database）；
/// - 命中判定：constant 直进（不判命中）；or/and 子串匹配，大小写**不敏感**
///   （锁定）；空 key / 纯空白 key 不参与；key 周边空白 trim 后参与；
/// - depth 窗口：0=仅输入；N=最近 2N 条「对话消息」+ 输入；>20 裁剪为 20；
///   <0 视为 0；system 指令不计轮；
/// - 概率闸：0 必弃 / 100 必进（均不消耗 RNG）/ 中间值掷点；同种子可复现；
/// - 互斥组：同组按 group_weight 加权抽一（组内只出一条），不同组互不影响；
/// - 输出排序：order 升序、同 order 按 id 升序（确定性）；
/// - 泛词（单字符/标点 key）不报错（告警属 WL-4 前端职责）；
/// - buildWorldInjection：position 分组（world→system / before_char /
///   after_char），组内 (order,id) 升序，{{user}}/{{char}} 模板替换，未知
///   position 回落 system，source_by_id 区分 world/memory，空内容过滤。
library;

import 'dart:io';
import 'dart:math';

import 'package:conver_system_mobile/services/lorebook/lorebook_engine.dart';
import 'package:flutter_test/flutter_test.dart';

LorebookEntryData _entry({
  int id = 1,
  List<String> keys = const ['key'],
  String content = '世界书内容',
  bool constant = false,
  int order = 100,
  int probability = 100,
  String groupName = '',
  int groupWeight = 100,
  String matchMode = 'or',
  String position = 'world',
  bool enabled = true,
}) {
  return LorebookEntryData(
    id: id,
    keys: keys,
    content: content,
    constant: constant,
    order: order,
    probability: probability,
    groupName: groupName,
    groupWeight: groupWeight,
    matchMode: matchMode,
    position: position,
    enabled: enabled,
  );
}

class _FakeMsg {
  const _FakeMsg(this.role, this.content);

  final String role;
  final String content;
}

List<_FakeMsg> _history(List<(String, String)> pairs) {
  return [for (final (role, content) in pairs) _FakeMsg(role, content)];
}

/// 记录 [nextDouble] 调用次数的 RNG（验证概率/组抽签的 RNG 消耗契约）。
class _CountingRandom implements Random {
  _CountingRandom([int? seed]) : _inner = Random(seed);

  final Random _inner;
  int nextDoubleCalls = 0;

  @override
  double nextDouble() {
    nextDoubleCalls++;
    return _inner.nextDouble();
  }

  @override
  int nextInt(int max) => _inner.nextInt(max);

  @override
  bool nextBool() => _inner.nextBool();
}

void main() {
  group('activateLorebookEntries · 空输入零异常', () {
    test('空 entries / 空 scan_text → 空结果', () {
      expect(activateLorebookEntries(const [], ''), isEmpty);
      expect(activateLorebookEntries(const [], 'some text'), isEmpty);
      // 非常驻条目 + 空扫描文本：无 key 可命中 → 空。
      expect(activateLorebookEntries([_entry(keys: const ['酒馆'])], ''), isEmpty);
    });

    test('空历史 + 空输入 → 空扫描文本（collectScanText 零异常）', () {
      expect(
        collectScanText(
          const <_FakeMsg>[],
          '',
          5,
          roleOf: (m) => m.role,
          contentOf: (m) => m.content,
        ),
        '',
      );
    });
  });

  group('activateLorebookEntries · constant 直进', () {
    test('constant 条目不判命中：scan_text 不含任何 key 也入选', () {
      final entry = _entry(id: 7, constant: true, keys: const ['绝不出现的关键词']);
      final out = activateLorebookEntries([entry], '完全无关的文本');
      expect(out.map((e) => e.id), [7]);
    });
  });

  group('activateLorebookEntries · or/and 命中矩阵 + 大小写不敏感', () {
    test('or：任一 key 命中即入选', () {
      final entry = _entry(id: 1, keys: const ['apple', 'banana'], matchMode: 'or');
      expect(
        activateLorebookEntries([entry], 'I ate a banana pie').map((e) => e.id),
        [1],
      );
      expect(
        activateLorebookEntries([entry], 'apple orchard').map((e) => e.id),
        [1],
      );
      expect(activateLorebookEntries([entry], 'cherry pie'), isEmpty);
    });

    test('and：全部 key 命中才入选', () {
      final entry = _entry(id: 1, keys: const ['apple', 'banana'], matchMode: 'and');
      expect(activateLorebookEntries([entry], 'apple pie'), isEmpty);
      expect(
        activateLorebookEntries([entry], 'apple banana split').map((e) => e.id),
        [1],
      );
    });

    test('大小写不敏感（锁定）：key 大写、文本小写仍命中', () {
      final entry = _entry(id: 1, keys: const ['APPLE']);
      expect(
        activateLorebookEntries([entry], 'an apple a day').map((e) => e.id),
        [1],
      );
      final entryCn = _entry(id: 2, keys: const ['酒馆']);
      expect(
        activateLorebookEntries([entryCn], '走进小酒馆').map((e) => e.id),
        [2],
      );
    });

    test('空 keys 的非常驻条目永不命中（or/and 空集合陷阱守卫）', () {
      expect(activateLorebookEntries([_entry(id: 1, keys: const [])], 'anything'), isEmpty);
      expect(
        activateLorebookEntries(
          [_entry(id: 1, keys: const [], matchMode: 'and')],
          'anything',
        ),
        isEmpty,
      );
      // 纯空白 key 同样不参与。
      expect(
        activateLorebookEntries([_entry(id: 1, keys: const ['   '])], 'anything'),
        isEmpty,
      );
    });

    test('含周边空白的 key 去除空白后参与匹配（Falsify 修复锁）', () {
      final entry = _entry(id: 1, keys: const ['  foo  ']);
      expect(
        activateLorebookEntries([entry], 'the foo story').map((e) => e.id),
        [1],
      );
      final entryCn = _entry(id: 2, keys: const [' 酒馆 ']);
      expect(
        activateLorebookEntries([entryCn], '走进酒馆').map((e) => e.id),
        [2],
      );
    });
  });

  group('collectScanText · depth 边界', () {
    test('depth=0 → 仅 current_input（历史不参与）', () {
      final history = _history([
        ('user', '第一轮'),
        ('assistant', '回复一'),
        ('user', '第二轮'),
      ]);
      expect(
        collectScanText(
          history,
          '当前输入',
          0,
          roleOf: (m) => m.role,
          contentOf: (m) => m.content,
        ),
        '当前输入',
      );
    });

    test('depth=1 → 最近 2 条对话消息 + 当前输入', () {
      final history = _history([
        ('user', '第一轮'),
        ('assistant', '回复一'),
        ('user', '第二轮'),
        ('assistant', '回复二'),
      ]);
      expect(
        collectScanText(
          history,
          '当前输入',
          1,
          roleOf: (m) => m.role,
          contentOf: (m) => m.content,
        ),
        '第二轮\n回复二\n当前输入',
      );
    });

    test('depth=N → 最近 2N 条对话消息 + 当前输入（不足则取全部）', () {
      final history = _history([
        for (var i = 0; i < 6; i++)
          (i.isEven ? 'user' : 'assistant', '消息$i'),
      ]);
      expect(
        collectScanText(
          history,
          '输入',
          2,
          roleOf: (m) => m.role,
          contentOf: (m) => m.content,
        ),
        '消息2\n消息3\n消息4\n消息5\n输入',
      );
    });

    test('depth>20 裁剪为 20；<0 视为 0（仅输入）', () {
      final history = _history([
        for (var i = 0; i < 60; i++)
          (i.isEven ? 'user' : 'assistant', '消息$i'),
      ]);
      String scan(int depth) => collectScanText(
            history,
            '输入',
            depth,
            roleOf: (m) => m.role,
            contentOf: (m) => m.content,
          );
      final out20 = scan(20);
      final out99 = scan(99);
      expect(out20, out99); // 超限裁剪。
      expect(out20.endsWith('输入'), isTrue);
      expect(out20.split('\n').length, 41); // 2*20 消息 + 输入。
      expect(scan(-5), '输入');
    });

    test('system 指令不计「轮」：窗口只取 user/assistant 对话消息', () {
      final history = _history([
        ('user', '第一轮'),
        ('assistant', '回复一'),
        ('system', '历史后指令'),
        ('user', '第二轮'),
        ('assistant', '回复二'),
      ]);
      expect(
        collectScanText(
          history,
          '输入',
          1,
          roleOf: (m) => m.role,
          contentOf: (m) => m.content,
        ),
        '第二轮\n回复二\n输入',
      );
    });

    test('历史消息 content 为空串 → 保留空行（桌面 str(or "") 语义）', () {
      final history = _history([('user', ''), ('assistant', '回复')]);
      expect(
        collectScanText(
          history,
          '输入',
          1,
          roleOf: (m) => m.role,
          contentOf: (m) => m.content,
        ),
        '\n回复\n输入',
      );
    });
  });

  group('activateLorebookEntries · 排序确定性', () {
    test('输出按 order 升序、同 order 按 id 升序（乱序输入 → 稳定输出）', () {
      final entries = [
        _entry(id: 3, order: 100, keys: const ['x']),
        _entry(id: 1, order: 50, keys: const ['x']),
        _entry(id: 2, order: 100, keys: const ['x']),
      ];
      final out = activateLorebookEntries(entries, 'x marks the spot');
      expect(out.map((e) => e.id), [1, 2, 3]);
    });
  });

  group('activateLorebookEntries · 概率闸与 RNG 可复现', () {
    test('probability=0 必弃、=100 必进（均不消耗 RNG）', () {
      final rng = _CountingRandom(1);
      final zero = _entry(id: 1, keys: const ['x'], probability: 0);
      final hundred = _entry(id: 2, keys: const ['x'], probability: 100);
      final out = activateLorebookEntries([zero, hundred], 'x', rng: rng);
      expect(out.map((e) => e.id), [2]);
      expect(rng.nextDoubleCalls, 0); // 两端值不掷点。
    });

    test('中间概率掷点真实消耗 RNG（验收 6 强化）', () {
      final rng = _CountingRandom(1);
      activateLorebookEntries(
        [_entry(id: 1, keys: const ['x'], probability: 50)],
        'x',
        rng: rng,
      );
      expect(rng.nextDoubleCalls, 1);
    });

    test('中间概率 + rng 注入：同种子两次结果一致（可复现）', () {
      final entries = [
        for (var i = 1; i <= 10; i++)
          _entry(id: i, keys: const ['x'], probability: 50),
      ];
      final out1 = activateLorebookEntries(entries, 'x', rng: Random(20260910))
          .map((e) => e.id)
          .toList();
      final out2 = activateLorebookEntries(entries, 'x', rng: Random(20260910))
          .map((e) => e.id)
          .toList();
      expect(out1, out2);
      expect(out1, isNotEmpty); // 种子实测确定结果（非空即锁）。
    });

    test('同种子跨输入顺序可复现（RNG 消耗随规范序，不随调用方排序漂移）', () {
      final entries = [
        _entry(id: 1, keys: const ['x'], probability: 50),
        _entry(id: 2, keys: const ['x'], probability: 50),
        _entry(id: 3, keys: const ['x'], groupName: 'g', groupWeight: 60),
        _entry(id: 4, keys: const ['x'], groupName: 'g', groupWeight: 40),
      ];
      final a = activateLorebookEntries(entries, 'x', rng: Random(1))
          .map((e) => e.id)
          .toList();
      final b = activateLorebookEntries(entries.reversed.toList(), 'x',
              rng: Random(1))
          .map((e) => e.id)
          .toList();
      expect(a, b);
    });
  });

  group('activateLorebookEntries · 互斥组加权抽一', () {
    test('同组只出一条（加权抽一）；不同组互不影响', () {
      final entries = [
        _entry(id: 1, keys: const ['x'], groupName: '地点', groupWeight: 90),
        _entry(id: 2, keys: const ['x'], groupName: '地点', groupWeight: 10),
        _entry(id: 3, keys: const ['x'], groupName: '人物', groupWeight: 50),
      ];
      final ids =
          activateLorebookEntries(entries, 'x', rng: Random(7))
              .map((e) => e.id)
              .toList();
      expect(ids.where((i) => i == 1 || i == 2).length, 1); // 地点组只出 1 条。
      expect(ids, contains(3)); // 人物组独立选出。
      expect(ids.length, 2);
    });

    test('同组加权抽一同种子可复现', () {
      final entries = [
        _entry(id: 1, keys: const ['x'], groupName: 'g', groupWeight: 60),
        _entry(id: 2, keys: const ['x'], groupName: 'g', groupWeight: 40),
      ];
      final a = activateLorebookEntries(entries, 'x', rng: Random(42))
          .map((e) => e.id)
          .toList();
      final b = activateLorebookEntries(entries, 'x', rng: Random(42))
          .map((e) => e.id)
          .toList();
      expect(a, b);
    });

    test('无组条目全部入选（不参与组抽签）', () {
      final entries = [
        _entry(id: 1, keys: const ['x']),
        _entry(id: 2, keys: const ['x']),
        _entry(id: 3, keys: const ['x'], groupName: 'g'),
        _entry(id: 4, keys: const ['x'], groupName: 'g'),
      ];
      final ids =
          activateLorebookEntries(entries, 'x', rng: Random(3))
              .map((e) => e.id)
              .toList();
      expect(ids, containsAll([1, 2]));
      expect(ids.where((i) => i == 3 || i == 4).length, 1);
    });

    test('group_weight 0/负 → 权重兜底 ≥1（非空组恒可抽，不抛）', () {
      final entries = [
        _entry(id: 1, keys: const ['x'], groupName: 'g', groupWeight: 0),
        _entry(id: 2, keys: const ['x'], groupName: 'g', groupWeight: -5),
      ];
      final out = activateLorebookEntries(entries, 'x', rng: Random(11));
      expect(out.length, 1);
      expect(out.single.id == 1 || out.single.id == 2, isTrue);
    });
  });

  group('activateLorebookEntries · 泛词防护', () {
    test('keys 含单字符/标点：命中判定不报错（泛词告警属 WL-4 前端职责）', () {
      final entries = [
        _entry(id: 1, keys: const ['你']),
        _entry(id: 2, keys: const ['。']),
        _entry(id: 3, keys: const ['，']),
      ];
      final out = activateLorebookEntries(entries, '你好。今天，天气不错');
      expect(out.map((e) => e.id).toSet(), {1, 2, 3});
    });
  });

  group('buildWorldInjection · 分组、排序、模板与来源', () {
    test('按 position 分组（world→system），组内 (order,id) 升序；source 默认 world', () {
      final activated = [
        _entry(id: 2, order: 200, position: 'world', content: '后世界'),
        _entry(id: 1, order: 100, position: 'world', content: '先世界'),
        _entry(id: 3, order: 50, position: 'before_char', content: '角色前'),
        _entry(id: 4, order: 50, position: 'after_char', content: '场景后'),
      ];
      final blocks = buildWorldInjection(activated);
      expect(blocks.keys.toList(), ['system', 'before_char', 'after_char']);
      expect(blocks['system']!.map((s) => s.content), ['先世界', '后世界']);
      expect(blocks['before_char']!.map((s) => s.content), ['角色前']);
      expect(blocks['after_char']!.map((s) => s.content), ['场景后']);
      for (final segs in blocks.values) {
        for (final seg in segs) {
          expect(seg.source, sourceWorld);
        }
      }
    });

    test('content 经 {{user}}/{{char}} 模板替换', () {
      final activated = [_entry(id: 1, content: '{{user}} 与 {{char}} 的回忆')];
      final blocks =
          buildWorldInjection(activated, userName: '小明', charName: '莉莉');
      expect(blocks['system']!.single.content, '小明 与 莉莉 的回忆');
    });

    test('未知 position 回落 world（system 块），不静默丢弃', () {
      final activated = [_entry(id: 1, position: 'in_chat', content: '未知位置内容')];
      final blocks = buildWorldInjection(activated);
      expect(blocks['system']!.single.content, '未知位置内容');
    });

    test('空激活集 → system/before_char/after_char 三空键（无崩溃）', () {
      final blocks = buildWorldInjection(const []);
      expect(blocks.keys.toList(), ['system', 'before_char', 'after_char']);
      expect(blocks.values.every((segs) => segs.isEmpty), isTrue);
    });

    test('空 content 条目过滤：不产生空段（工单验收 8）', () {
      final activated = [
        _entry(id: 1, content: ''),
        _entry(id: 2, content: '有内容'),
      ];
      final blocks = buildWorldInjection(activated);
      expect(blocks['system']!.map((s) => s.content), ['有内容']);
      expect(blocks['before_char'], isEmpty);
      expect(blocks['after_char'], isEmpty);
    });

    test('source_by_id 值非 "auto"（含未知标签）回落 world', () {
      final activated = [_entry(id: 1, content: '未知来源条目')];
      final blocks = buildWorldInjection(
        activated,
        sourceById: const {1: 'unknown-tag'},
      );
      expect(blocks['system']!.single.source, sourceWorld);
    });

    test('source_by_id：缺省条目默认 world；值 == "auto" 标注 memory（经 id 反查）', () {
      final activated = [
        _entry(id: 1, content: '手动来源'),
        _entry(id: 2, content: '记忆来源'),
        _entry(id: 3, position: 'after_char', content: '未标注条目'),
      ];
      final blocks = buildWorldInjection(
        activated,
        sourceById: const {1: 'manual', 2: 'auto'},
        userName: '小明',
        charName: '莉莉',
      );
      expect(
        blocks['system']!.map((s) => (s.content, s.source)),
        [('手动来源', sourceWorld), ('记忆来源', sourceMemory)],
      );
      expect(
        blocks['after_char']!.map((s) => (s.content, s.source)),
        [('未标注条目', sourceWorld)],
      );
    });
  });

  group('数据类值语义（== / hashCode）', () {
    test('InjectedSegment 同字段值相等、异字段不等、hashCode 一致', () {
      const a = InjectedSegment(content: 'x', source: sourceWorld);
      const b = InjectedSegment(content: 'x', source: sourceWorld);
      const c = InjectedSegment(content: 'x', source: sourceMemory);
      expect(a, b);
      expect(a == c, isFalse); // source 差异。
      expect(a.hashCode, b.hashCode);
      final unrelated = Object();
      expect(a == unrelated, isFalse); // 非同类对象恒不等。
    });

    test('LorebookEntryData 全字段相等才等；任一字段差异不等；hashCode 一致', () {
      final base = _entry(
        id: 5,
        keys: const ['a', 'b'],
        content: '内容',
        order: 10,
        probability: 50,
        groupName: 'g',
        groupWeight: 30,
        matchMode: 'and',
        position: 'after_char',
        enabled: false,
      );
      final same = _entry(
        id: 5,
        keys: const ['a', 'b'],
        content: '内容',
        order: 10,
        probability: 50,
        groupName: 'g',
        groupWeight: 30,
        matchMode: 'and',
        position: 'after_char',
        enabled: false,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      expect(base == _entry(id: 6), isFalse); // id 差异。
      expect(base == _entry(id: 5, keys: const ['a']), isFalse); // keys 长度差异。
      expect(base == _entry(id: 5, keys: const ['a', 'c']), isFalse); // keys 内容差异。
      expect(base == _entry(id: 5, keys: const ['a', 'b'], order: 11), isFalse);
      expect(base == _entry(id: 5, keys: const ['a', 'b'], probability: 60), isFalse);
      expect(
        base == _entry(id: 5, keys: const ['a', 'b'], position: 'before_char'),
        isFalse,
      );
      final unrelated = Object();
      expect(base == unrelated, isFalse); // 非同类对象恒不等。
    });
  });

  group('其余语义', () {
    test('scan_text 为空时回退 current_input（调用方可只传输入）', () {
      final entry = _entry(id: 1, keys: const ['你好']);
      expect(
        activateLorebookEntries([entry], '', currentInput: '你好呀')
            .map((e) => e.id),
        [1],
      );
    });

    test('enabled=false 不参与（即使 constant）', () {
      final disabledConstant = _entry(id: 1, constant: true, enabled: false);
      final disabledKeyed = _entry(id: 2, keys: const ['x'], enabled: false);
      final out = activateLorebookEntries([disabledConstant, disabledKeyed], 'x');
      expect(out, isEmpty);
    });

    test('零数据库/IO 依赖：模块源码不引用 drift / app_database / dart:io', () {
      final source =
          File('lib/services/lorebook/lorebook_engine.dart').readAsStringSync();
      expect(source.contains('package:drift'), isFalse);
      expect(source.contains('app_database'), isFalse);
      expect(source.contains('dart:io'), isFalse);
    });
  });
}
