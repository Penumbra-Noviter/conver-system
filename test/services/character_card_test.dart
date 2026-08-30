/// Character Card V2 转换层单元测试（桌面 `test_character_card.py` 语义移植）。
///
/// 覆盖工单 M3-03 验收 1-5（语义契约）：
/// - 格式识别：V2 信封 / 无 spec data 信封 / V1 旧卡 / 裸 data / 非法结构分级
/// - V1 归一化（char_name 等 8 字段，creatorcomment → {"text": ...}）
/// - name 截断 100 / version 截断 50 / 集合脏数据容错
/// - 头像三形态（裸 base64 魔数推断 MIME / data URI 原样 / URL / 命名空间回读）
/// - temperature 默认 / 命名空间优先 / 裁剪 [0,2] / 非法回退
/// - extensions.conver_system 保真 + V2 往返
library;

import 'dart:convert';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/services/character_card.dart';
import 'package:flutter_test/flutter_test.dart';

/// 极小 PNG / JPEG 裸 base64（供 MIME 推断测试，魔数来自桌面测试 fixture）。
const _pngB64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
const _jpegB64 = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwB//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=';

/// 构造完整 Character 行（必填字段给默认值，供导出侧测试）。
Character _character({
  String name = '测试角色',
  String description = '一个用于测试的角色',
  String personality = '冷静、睿智',
  String scenario = '月下竹林',
  String firstMes = '你好，久等了。',
  String mesExample = '<START>\n{{user}}: 你好\n{{char}}: 欢迎',
  String systemPrompt = '你是测试角色。',
  String postHistoryInstructions = '保持人设。',
  List<String> alternateGreetings = const ['备选开场白'],
  List<String> tags = const ['冒险', '奇幻'],
  String creator = '测试作者',
  String version = '1.0',
  Map<String, dynamic> creatorNotes = const {'note': '创作者备注'},
  Map<String, dynamic> extensions = const {},
  String? avatar,
  double temperature = 0.7,
}) {
  return Character(
    id: 1,
    name: name,
    description: description,
    personality: personality,
    scenario: scenario,
    firstMes: firstMes,
    mesExample: mesExample,
    systemPrompt: systemPrompt,
    postHistoryInstructions: postHistoryInstructions,
    alternateGreetings: alternateGreetings,
    tags: tags,
    creator: creator,
    version: version,
    creatorNotes: creatorNotes,
    extensions: extensions,
    avatar: avatar,
    temperature: temperature,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

/// 完整 V2 data 段（可覆盖）。
Map<String, dynamic> _v2Data(Map<String, dynamic> overrides) {
  return {
    'name': '测试角色',
    'description': '一个用于测试的角色',
    'personality': '冷静、睿智',
    'scenario': '月下竹林',
    'first_mes': '你好，久等了。',
    'mes_example': '<START>\n{{user}}: 你好\n{{char}}: 欢迎',
    'system_prompt': '你是测试角色。',
    'post_history_instructions': '保持人设。',
    'alternate_greetings': ['备选开场白'],
    'tags': ['冒险', '奇幻'],
    'creator': '测试作者',
    'character_version': '1.0',
    'creator_notes': {'note': '创作者备注'},
    'avatar': null,
    'extensions': <String, dynamic>{},
    ...overrides,
  };
}

/// 完整 V2 信封（可覆盖 data 段）。
Map<String, dynamic> _v2Card([Map<String, dynamic> overrides = const {}]) {
  return {'spec': 'chara_card_v2', 'spec_version': '2.0', 'data': _v2Data(overrides)};
}

/// 导出 → 导入往返。
CharacterDraft _roundtrip(Character char) => fromV2Card(toV2Card(char));

/// 断言往返后字段与源角色一致（extensions 只保内容，temperature 注入/回读）。
void _expectRoundtripEqual(Character char, CharacterDraft result) {
  expect(result.name, char.name);
  expect(result.description, char.description);
  expect(result.personality, char.personality);
  expect(result.scenario, char.scenario);
  expect(result.firstMes, char.firstMes);
  expect(result.mesExample, char.mesExample);
  expect(result.systemPrompt, char.systemPrompt);
  expect(result.postHistoryInstructions, char.postHistoryInstructions);
  expect(result.alternateGreetings, char.alternateGreetings);
  expect(result.tags, char.tags);
  expect(result.creator, char.creator);
  expect(result.version, char.version);
  expect(result.creatorNotes, char.creatorNotes);
  expect(result.avatar, char.avatar);
  expect(result.temperature, char.temperature);
  for (final entry in char.extensions.entries) {
    expect(result.extensions[entry.key], entry.value);
  }
}

void main() {
  group('一、格式识别：V2 信封 / 裸 data / 无 spec 的 data 信封', () {
    test('V2 信封完整字段映射到 draft', () {
      final result = fromV2Card(_v2Card());
      expect(result.name, '测试角色');
      expect(result.description, '一个用于测试的角色');
      expect(result.personality, '冷静、睿智');
      expect(result.scenario, '月下竹林');
      expect(result.firstMes, '你好，久等了。');
      expect(result.mesExample, '<START>\n{{user}}: 你好\n{{char}}: 欢迎');
      expect(result.systemPrompt, '你是测试角色。');
      expect(result.postHistoryInstructions, '保持人设。');
      expect(result.alternateGreetings, ['备选开场白']);
      expect(result.tags, ['冒险', '奇幻']);
      expect(result.creator, '测试作者');
      expect(result.version, '1.0', reason: 'character_version → version');
      expect(result.creatorNotes, {'note': '创作者备注'});
      expect(result.temperature, 0.7, reason: '未指定 → 默认');
    });

    test('character_version 优先于 version 字段', () {
      final result = fromV2Card(_v2Card({'character_version': '3.1', 'version': '9.9'}));
      expect(result.version, '3.1');
    });

    test('V2 信封缺 data → 格式错「缺少 data 字段」', () {
      expect(
        () => fromV2Card({'spec': 'chara_card_v2'}),
        throwsA(isA<CardFormatException>().having(
          (e) => e.message, 'message', contains('缺少 data 字段'),
        )),
      );
    });

    test('裸 data（顶层含 name，无 spec/data 信封）', () {
      final result = fromV2Card({'name': '裸角色', 'personality': '直接', 'temperature': 0.5});
      expect(result.name, '裸角色');
      expect(result.personality, '直接');
      expect(result.temperature, 0.5);
    });

    test('无 spec 的 data 信封（宽容分支）', () {
      final result = fromV2Card({'data': {'name': '宽容信封'}});
      expect(result.name, '宽容信封');
    });

    test('结构无法识别 → 格式错「无法识别的角色卡格式」', () {
      for (final bad in [
        {'foo': 'bar'},
        <String, dynamic>{},
      ]) {
        expect(
          () => fromV2Card(bad),
          throwsA(isA<CardFormatException>().having(
            (e) => e.message, 'message', contains('无法识别的角色卡格式'),
          )),
          reason: '输入 $bad',
        );
      }
    });

    test('spec 非 v2 → 格式错「不支持的卡片规格」', () {
      expect(
        () => fromV2Card({'spec': 'chara_card_v1', 'data': <String, dynamic>{}}),
        throwsA(isA<CardFormatException>().having(
          (e) => e.message, 'message', contains('不支持的卡片规格'),
        )),
      );
    });

    test('非 Map 输入 → 格式错「必须是 JSON 对象」', () {
      for (final bad in <dynamic>[
        <Object?>[],
        '字符串',
        123,
        1.5,
        true,
      ]) {
        expect(
          () => fromV2Card(bad),
          throwsA(isA<CardFormatException>().having(
            (e) => e.message, 'message', contains('必须是 JSON 对象'),
          )),
          reason: '输入 $bad',
        );
      }
    });
  });

  group('二、V1 旧卡归一化', () {
    test('V1 旧卡全字段归一化', () {
      final result = fromV2Card({
        'char_name': '旧角色',
        'char_persona': '旧人格',
        'char_greeting': '旧开场',
        'example_dialogue': '旧范例',
        'world_scenario': '旧场景',
        'creatorcomment': '旧备注',
        'char_version': '2.0',
        'description': '旧描述',
      });
      expect(result.name, '旧角色');
      expect(result.personality, '旧人格');
      expect(result.firstMes, '旧开场');
      expect(result.mesExample, '旧范例');
      expect(result.scenario, '旧场景');
      expect(result.creatorNotes, {'text': '旧备注'}, reason: '纯文本 creatorcomment → dict');
      expect(result.version, '2.0');
      expect(result.description, '旧描述');
    });

    test('V1 卡仅含部分旧字段 → 其余默认空值，版本默认 1.0', () {
      final result = fromV2Card({'char_name': '半卡', 'char_greeting': '你好'});
      expect(result.name, '半卡');
      expect(result.firstMes, '你好');
      expect(result.personality, '');
      expect(result.version, '1.0');
    });
  });

  group('三、name 校验与截断', () {
    test('data 缺 name → 校验错「角色名称不能为空」', () {
      expect(
        () => fromV2Card({'spec': 'chara_card_v2', 'data': {'personality': '只有人格'}}),
        throwsA(isA<CardValidationException>().having(
          (e) => e.message, 'message', contains('角色名称不能为空'),
        )),
      );
    });

    test('name 为空白 → 校验错（strip 后为空）', () {
      expect(
        () => fromV2Card({'name': '   '}),
        throwsA(isA<CardValidationException>()),
      );
    });

    test('超长 name 截断到 100 字符', () {
      final result = fromV2Card(_v2Card({'name': '名' * 150}));
      expect(result.name, '名' * 100);
    });
  });

  group('四、头像三形态（导入侧）', () {
    test('裸 base64（PNG 魔数）→ data:image/png 前缀', () {
      final result = fromV2Card(_v2Card({'avatar': _pngB64}));
      expect(result.avatar, 'data:image/png;base64,$_pngB64');
    });

    test('裸 base64（JPEG 魔数）→ data:image/jpeg 前缀', () {
      final result = fromV2Card(_v2Card({'avatar': _jpegB64}));
      expect(result.avatar, 'data:image/jpeg;base64,$_jpegB64');
    });

    test('已带 data:image 前缀 → 原样保留', () {
      const uri = 'data:image/webp;base64,UklGR';
      final result = fromV2Card(_v2Card({'avatar': uri}));
      expect(result.avatar, uri);
    });

    test('data.avatar 为 URL → 原样保留（不包装 base64）', () {
      const url = 'https://example.com/avatar.png';
      final result = fromV2Card(_v2Card({'avatar': url}));
      expect(result.avatar, url);
    });

    test('data.avatar 缺省 → 回读 extensions.conver_system.avatar_url', () {
      const url = 'https://example.com/remote.png';
      final result = fromV2Card(_v2Card({
        'avatar': null,
        'extensions': {'conver_system': {'avatar_url': url}},
      }));
      expect(result.avatar, url);
    });

    test('两种来源均缺 → avatar null', () {
      expect(fromV2Card(_v2Card()).avatar, isNull);
    });

    test('裸 base64 魔数推断：GIF/WEBP/未知/非法 → 正确 MIME 或回退 png', () {
      final cases = <(String, String)>[
        (base64Encode('GIF89a'.codeUnits), 'gif'),
        (base64Encode(<int>[...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]),
            'webp'),
        (base64Encode(<int>[0, 1, 2, 3]), 'png'),
        ('@@@@invalid-base64', 'png'),
      ];
      for (final (raw, mime) in cases) {
        final result = fromV2Card(_v2Card({'avatar': raw}));
        expect(result.avatar, 'data:image/$mime;base64,$raw', reason: 'raw=$raw');
      }
    });
  });

  group('五、temperature：默认 / 命名空间 / 裁剪 / 容错', () {
    test('命名空间缺 temperature → 默认 0.7', () {
      expect(fromV2Card(_v2Card()).temperature, 0.7);
    });

    test('命名空间 temperature 生效', () {
      final result = fromV2Card(_v2Card({
        'extensions': {'conver_system': {'temperature': 0.9}},
      }));
      expect(result.temperature, 0.9);
    });

    test('temperature 越界 / 非法值裁剪或回退', () {
      final cases = <(Object?, double)>[
        (5, 2.0),
        (-1, 0.0),
        ('abc', 0.7),
        ('1.2', 1.2),
        (null, 0.7),
      ];
      for (final (raw, expected) in cases) {
        final result = fromV2Card(_v2Card({
          'extensions': {'conver_system': {'temperature': raw}},
        }));
        expect(result.temperature, expected, reason: 'raw=$raw');
      }
    });
  });

  group('六、extensions / 集合字段容错', () {
    test('未知 extensions + conver_system 命名空间原样保留', () {
      final result = fromV2Card(_v2Card({
        'extensions': {
          'custom_key': {'a': 1},
          'conver_system': {'character_book': {'entries': <Object>[]}},
        },
      }));
      expect(result.extensions['custom_key'], {'a': 1});
      expect(result.extensions['conver_system'], {
        'character_book': {'entries': <Object>[]},
      });
    });

    test('extensions 脏数据容错：纯文本 → {"text": ...}，其它非 dict → 空 dict', () {
      expect(fromV2Card(_v2Card({'extensions': 'abc'})).extensions, {'text': 'abc'});
      expect(fromV2Card(_v2Card({'extensions': 123})).extensions, isEmpty);
    });

    test('tags 脏数据：None → []；单值 → 包裹；混合类型 → str 化', () {
      expect(fromV2Card(_v2Card({'tags': null})).tags, isEmpty);
      expect(fromV2Card(_v2Card({'tags': '单标签'})).tags, ['单标签']);
      expect(fromV2Card(_v2Card({'tags': ['a', 2]})).tags, ['a', '2']);
    });

    test('alternate_greetings 脏数据：None / 空串 → []', () {
      expect(fromV2Card(_v2Card({'alternate_greetings': null})).alternateGreetings, isEmpty);
      expect(fromV2Card(_v2Card({'alternate_greetings': ''})).alternateGreetings, isEmpty);
    });

    test('version 超 50 截断', () {
      final result = fromV2Card(_v2Card({'character_version': 'v' * 60}));
      expect(result.version, 'v' * 50);
    });
  });

  group('七、导出：to_v2_card 信封结构与字段映射', () {
    test('V2 信封结构 + 字段映射（character_version ← version）', () {
      final card = toV2Card(_character());
      expect(card['spec'], 'chara_card_v2');
      expect(card['spec_version'], '2.0');
      final data = card['data']! as Map<String, dynamic>;
      expect(data['name'], '测试角色');
      expect(data['character_version'], '1.0');
      expect(data['creator_notes'], {'note': '创作者备注'});
      expect(data['alternate_greetings'], ['备选开场白']);
      expect(data['tags'], ['冒险', '奇幻']);
    });

    test('base64 data URI → data.avatar 去前缀存原始 base64，命名空间不留 avatar_url', () {
      final card = toV2Card(_character(avatar: 'data:image/png;base64,$_pngB64'));
      final data = card['data']! as Map<String, dynamic>;
      final ns = (data['extensions']! as Map<String, dynamic>)['conver_system']!
          as Map<String, dynamic>;
      expect(data['avatar'], _pngB64);
      expect(ns.containsKey('avatar_url'), isFalse);
    });

    test('URL 头像 → 命名空间 avatar_url，data.avatar 为 null', () {
      const url = 'https://example.com/a.png';
      final card = toV2Card(_character(avatar: url));
      final data = card['data']! as Map<String, dynamic>;
      final ns = (data['extensions']! as Map<String, dynamic>)['conver_system']!
          as Map<String, dynamic>;
      expect(data['avatar'], isNull);
      expect(ns['avatar_url'], url);
    });

    test('无头像 → data.avatar null，命名空间不含 avatar_url', () {
      final card = toV2Card(_character(avatar: null));
      final data = card['data']! as Map<String, dynamic>;
      final ns = (data['extensions']! as Map<String, dynamic>)['conver_system']!
          as Map<String, dynamic>;
      expect(data['avatar'], isNull);
      expect(ns.containsKey('avatar_url'), isFalse);
    });

    test('temperature 以 DB 实时值写入命名空间（覆盖旧值）', () {
      final card = toV2Card(_character(temperature: 1.1));
      final data = card['data']! as Map<String, dynamic>;
      final ns = (data['extensions']! as Map<String, dynamic>)['conver_system']!
          as Map<String, dynamic>;
      expect(ns['temperature'], 1.1);
    });

    test('既有 extensions 内容保留，temperature 注入，base64 头像时移除旧 avatar_url', () {
      final char = _character(
        avatar: 'data:image/png;base64,$_pngB64',
        extensions: {
          'custom_key': '原样',
          'conver_system': {
            'character_book': {'entries': [1]},
            'avatar_url': 'https://old.example/old.png',
          },
        },
      );
      final ext = (toV2Card(char)['data']! as Map<String, dynamic>)['extensions']!
          as Map<String, dynamic>;
      expect(ext['custom_key'], '原样');
      final ns = ext['conver_system']! as Map<String, dynamic>;
      expect(ns['character_book'], {'entries': [1]});
      expect(ns['temperature'], 0.7);
      expect(ns.containsKey('avatar_url'), isFalse, reason: 'base64 优先，旧 URL 被清除');
    });

    test('extensions null → 输出含空 conver_system 命名空间（temperature 注入）', () {
      final ext = (toV2Card(_character(extensions: const {}))['data']!
          as Map<String, dynamic>)['extensions']! as Map<String, dynamic>;
      expect(ext['conver_system'], {'temperature': 0.7});
    });

    test('None 集合字段导出为空 list/dict', () {
      final data = toV2Card(_character(
        alternateGreetings: const [],
        tags: const [],
        creatorNotes: const {},
        extensions: const {},
      ))['data']! as Map<String, dynamic>;
      expect(data['alternate_greetings'], isEmpty);
      expect(data['tags'], isEmpty);
      expect(data['creator_notes'], isEmpty);
    });

    test('URL 头像 + 命名空间 lorebook → 两者都保留', () {
      final char = _character(
        avatar: 'https://example.com/a.png',
        extensions: {'conver_system': {'character_book': {'entries': [2]}}},
      );
      final ns = ((toV2Card(char)['data']! as Map<String, dynamic>)['extensions']!
              as Map<String, dynamic>)['conver_system']! as Map<String, dynamic>;
      expect(ns['avatar_url'], 'https://example.com/a.png');
      expect(ns['character_book'], {'entries': [2]});
      expect(ns['temperature'], 0.7);
    });
  });

  group('八、V2 往返（spec §7 验收）', () {
    test('全字段角色导出→导入往返保真', () {
      final char = _character(avatar: 'data:image/png;base64,$_pngB64');
      _expectRoundtripEqual(char, _roundtrip(char));
    });

    test('JPEG base64 头像往返 MIME 不变', () {
      final char = _character(avatar: 'data:image/jpeg;base64,$_jpegB64');
      _expectRoundtripEqual(char, _roundtrip(char));
    });

    test('URL 头像往返保真', () {
      final char = _character(avatar: 'https://example.com/avatar.png');
      _expectRoundtripEqual(char, _roundtrip(char));
    });

    test('lorebook（character_book）+ 自定义 extensions 往返保留', () {
      final char = _character(
        extensions: {'conver_system': {'character_book': {'entries': [1, 2]}}},
      );
      final result = _roundtrip(char);
      expect(result.extensions['conver_system']!['character_book'], {'entries': [1, 2]});
      expect(result.extensions['conver_system']!['temperature'], 0.7);
    });

    test('仅 name 的最小角色往返不报错，空字段为默认值', () {
      final char = _character(
        name: '最小角色',
        description: '',
        personality: '',
        scenario: '',
        firstMes: '',
        mesExample: '',
        systemPrompt: '',
        postHistoryInstructions: '',
        alternateGreetings: const [],
        tags: const [],
        creator: '',
        creatorNotes: const {},
        extensions: const {},
        avatar: null,
      );
      final result = _roundtrip(char);
      expect(result.name, '最小角色');
      expect(result.description, '');
      expect(result.avatar, isNull);
      expect(result.version, '1.0');
    });
  });
}
