/// BR-01：BranchSnapshot 版本化载荷 — 编解码 + 版本校验 + 结构校验（SR-30）。
///
/// 测试 seam（公共接口边界）：[BranchSnapshot] 公开 API（toJson / fromJson /
/// 构建子模型）+ [BranchSnapshotUnsupportedVersionError] /
/// [InvalidBranchSnapshotError] 两领域错误。
/// 纯函数测试（零 DB 零 IO）：解码即从 JSON 文本走 jsonDecode → fromJson，
/// 断言错误类型与载荷键值；序列化经 toJson → jsonEncode 断言键序与值。
/// 语义锚点：chat-polish spec §4.7 载荷 + 桌面 `schemas/branch.py`（SNAPSHOT_VERSION=1、
/// validate_branch_snapshot —— 未知版本拒绝；pydantic 结构校验超集）。
library;

import 'dart:convert';

import 'package:conver_system_mobile/services/branch/branch_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// 建一个**结构合法**的完整快照（全字段）。
BranchSnapshot fullSnapshot() {
  return BranchSnapshot(
    version: snapshotVersion,
    characterId: 7,
    modelProvider: 'claude',
    modelName: 'claude-sonnet-5',
    title: '雪夜分叉',
    messages: const [
      BranchSnapshotMessage(role: 'user', content: '第一轮问', createdAt: null),
      BranchSnapshotMessage(role: 'assistant', content: '第一轮答'),
    ],
    lorebookEntries: const [
      BranchSnapshotLorebookEntry(
        title: '雪色',
        keys: ['雪', '夜'],
        content: '雪夜是分叉的起点。',
        constant: true,
        order: 12,
        probability: 80,
        groupName: '景观',
        groupWeight: 60,
        matchMode: 'or',
        position: 'before_char',
        depth: 7,
        source: 'manual',
        enabled: true,
      ),
    ],
    swipes: const [
      BranchSnapshotSwipe(
        messageIndex: 1,
        swipes: ['第一轮答', '重写答'],
        activeSwipeIndex: 1,
      ),
    ],
  );
}

void main() {
  group('BranchSnapshot.toJson · spec §4.7 载荷结构与键值', () {
    test('完整快照序列化：顶层键 + 各子段键序逐项正确', () {
      final json = fullSnapshot().toJson();

      expect(json.keys.toList(), [
        'version',
        'character_id',
        'model_provider',
        'model_name',
        'title',
        'messages',
        'lorebook_entries',
        'swipes',
      ]);
      expect(json['version'], snapshotVersion);
      expect(json['character_id'], 7);
      expect(json['model_provider'], 'claude');
      expect(json['model_name'], 'claude-sonnet-5');
      expect(json['title'], '雪夜分叉');

      final messages = (json['messages']! as List).cast<Map<String, dynamic>>();
      expect(messages, hasLength(2));
      expect(messages[0].keys.toList(), ['role', 'content', 'created_at']);
      expect(messages[0]['role'], 'user');
      expect(messages[0]['content'], '第一轮问');
      expect(messages[0]['created_at'], isNull);
      expect(messages[1]['created_at'], isNull);

      final entries = (json['lorebook_entries']! as List)
          .cast<Map<String, dynamic>>();
      expect(entries.single.keys.toList(), [
        'title',
        'keys',
        'content',
        'constant',
        'order',
        'probability',
        'group_name',
        'group_weight',
        'match_mode',
        'position',
        'depth',
        'source',
        'enabled',
      ]);
      expect(entries.single['title'], '雪色');
      expect(entries.single['keys'], ['雪', '夜']);
      expect(entries.single['constant'], true);
      expect(entries.single['order'], 12);
      expect(entries.single['group_name'], '景观');
      expect(entries.single['position'], 'before_char');
      expect(entries.single['enabled'], true);
      expect(entries.single['depth'], 7);
      expect(entries.single['source'], 'manual');

      final swipes = (json['swipes']! as List).cast<Map<String, dynamic>>();
      expect(swipes.single.keys.toList(), [
        'message_index',
        'swipes',
        'active_swipe_index',
      ]);
      expect(swipes.single['message_index'], 1);
      expect(swipes.single['swipes'], ['第一轮答', '重写答']);
      expect(swipes.single['active_swipe_index'], 1);
    });

    test('created_at 非空 → UTC ISO 字符串（往返保真口径）', () {
      final json = BranchSnapshot(
        version: snapshotVersion,
        characterId: 1,
        messages: const [
          BranchSnapshotMessage(role: 'user', content: 'hi', createdAt: null),
        ],
      ).toJson();
      // 单独用 UTC 种子消息断言 ISO 字面量。
      final withTime = BranchSnapshotMessage(
        role: 'assistant',
        content: '答',
        createdAt: DateTime.utc(2023, 11, 14, 22, 13, 20),
      ).toJson();
      expect(withTime['created_at'], '2023-11-14T22:13:20.000Z');
      expect(json['messages'], isNotEmpty);
    });
  });

  group('BranchSnapshot.fromJson · 往返解码', () {
    test('toJson → jsonEncode → jsonDecode → fromJson 逐字段一致（往返）', () {
      final snapshot = fullSnapshot();
      final decoded = jsonDecode(jsonEncode(snapshot.toJson()));

      final restored = BranchSnapshot.fromJson(decoded);

      expect(restored.version, snapshotVersion);
      expect(restored.characterId, 7);
      expect(restored.modelProvider, 'claude');
      expect(restored.modelName, 'claude-sonnet-5');
      expect(restored.title, '雪夜分叉');
      expect(restored.messages, hasLength(2));
      expect(restored.messages[0].role, 'user');
      expect(restored.messages[0].content, '第一轮问');
      expect(restored.messages[0].createdAt, isNull);
      expect(restored.messages[1].role, 'assistant');
      expect(restored.messages[1].content, '第一轮答');
      expect(restored.lorebookEntries.single.title, '雪色');
      expect(restored.lorebookEntries.single.keys, ['雪', '夜']);
      expect(restored.lorebookEntries.single.constant, true);
      expect(restored.lorebookEntries.single.position, 'before_char');
      expect(restored.swipes.single.messageIndex, 1);
      expect(restored.swipes.single.swipes, ['第一轮答', '重写答']);
      expect(restored.swipes.single.activeSwipeIndex, 1);
    });

    test('缺省段：messages/lorebook_entries/swipes 缺省为空列表、model 字段为 null', () {
      final snapshot = BranchSnapshot.fromJson({
        'version': snapshotVersion,
        'character_id': 3,
      });

      expect(snapshot.messages, isEmpty);
      expect(snapshot.lorebookEntries, isEmpty);
      expect(snapshot.swipes, isEmpty);
      expect(snapshot.modelProvider, isNull);
      expect(snapshot.modelName, isNull);
      expect(snapshot.title, isNull);
    });
  });

  group('版本校验（SR-30：未知版本拒绝导入）', () {
    test('version 缺失 → BranchSnapshotUnsupportedVersionError', () {
      expect(
        () => BranchSnapshot.fromJson({'character_id': 1, 'messages': []}),
        throwsA(isA<BranchSnapshotUnsupportedVersionError>()),
      );
    });

    test('version 未知（999）→ BranchSnapshotUnsupportedVersionError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': 999,
          'character_id': 1,
          'messages': [],
        }),
        throwsA(isA<BranchSnapshotUnsupportedVersionError>()),
      );
    });

    test('version 为字符串 "1" → 严格类型拒收（UnsupportedVersion）', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': '1',
          'character_id': 1,
          'messages': [],
        }),
        throwsA(isA<BranchSnapshotUnsupportedVersionError>()),
      );
    });
  });

  group('结构校验（SR-30 畸形快照注入矩阵 → InvalidBranchSnapshotError）', () {
    Object? decode(String json) => jsonDecode(json);

    test('非对象（数组 / 字符串 / null）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson('[1,2]'),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
      expect(
        () => BranchSnapshot.fromJson('文本'),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
      expect(
        () => BranchSnapshot.fromJson(null),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('character_id 缺失 → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({'version': snapshotVersion}),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('character_id 类型错误（字符串）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': '7',
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('model_provider / title 类型错误 → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'model_provider': 42,
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'title': ['雪夜'],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('messages 非列表（Map）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'messages': {'role': 'user'},
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('消息项缺 role → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'messages': [
            {'content': '缺角色'},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('消息 role 非法（"npc"）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'messages': [
            {'role': 'npc', 'content': '非法角色'},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('消息 content 类型错误（数字）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'messages': [
            {'role': 'user', 'content': 42},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('消息 created_at 非 ISO 字符串 → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'messages': [
            {'role': 'user', 'content': 'x', 'created_at': '昨天'},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('消息 created_at 类型错误（数字）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'messages': [
            {'role': 'user', 'content': 'x', 'created_at': 42},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('消息项非 JSON 对象（字符串元素）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'messages': ['user'],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('消息 content 缺失 → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'messages': [
            {'role': 'user'},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('lorebook 条目项非 JSON 对象（字符串元素）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'lorebook_entries': ['雪色'],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('swipes 字段非列表（Map）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'swipes': {'message_index': 0},
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('swipes 项非 JSON 对象（字符串元素）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'swipes': ['候选'],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('lorebook_entries 非列表 → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'lorebook_entries': {'title': 'x'},
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('lorebook 条目 keys 非字符串列表 → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'lorebook_entries': [
            {'title': 'x', 'keys': '雪'},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('lorebook 条目 constant 类型错误（字符串）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'lorebook_entries': [
            {'title': 'x', 'constant': 'yes'},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('lorebook 条目 order 非整数（2.5）→ InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'lorebook_entries': [
            {'title': 'x', 'order': 2.5},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('lorebook 条目 enabled 非布尔 → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'lorebook_entries': [
            {'title': 'x', 'enabled': 1},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('swipes 项 message_index 缺失/负数 → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'swipes': [
            {'swipes': []},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'swipes': [
            {'message_index': -1, 'swipes': []},
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('swipes 项 message_index 非整数（2.0 双精度）→ InvalidBranchSnapshotError', () {
      // jsonDecode('{"message_index": 2.0}') 得 double——严格 int 拒收。
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'swipes': [decode('{"message_index": 2.0, "swipes": ["a"]}')],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('swipes 项 active_swipe_index 负数 → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'swipes': [
            {
              'message_index': 0,
              'swipes': ['a'],
              'active_swipe_index': -1,
            },
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('swipes 项 swipes 非字符串列表 → InvalidBranchSnapshotError', () {
      expect(
        () => BranchSnapshot.fromJson({
          'version': snapshotVersion,
          'character_id': 1,
          'swipes': [
            {
              'message_index': 0,
              'swipes': [1, 2],
            },
          ],
        }),
        throwsA(isA<InvalidBranchSnapshotError>()),
      );
    });

    test('合法负样本边界：created_at=null 允许、character_id=0 允许', () {
      final snapshot = BranchSnapshot.fromJson({
        'version': snapshotVersion,
        'character_id': 0,
        'messages': [
          {'role': 'system', 'content': 's', 'created_at': null},
        ],
      });
      expect(snapshot.messages.single.createdAt, isNull);
    });
  });
}
