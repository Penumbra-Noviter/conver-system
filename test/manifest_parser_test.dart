/// F-M5-01 parseManifest 宽容降级 — 对拍桌面测例矩阵。
///
/// 语义逐字锚点（只读）：`desktop/frontend/js/simulators.js` parseManifest /
/// normalizeSaveKeys（及其依赖 `js/save-key-meta.js` SAVE_KEY_META_RE /
/// saveKeyIsValidPattern，TD-67/68 契约之家）。
///
/// 测例来源：`desktop/frontend/tests/simulators.test.js`（parseManifest 结构
/// 性失败 + 宽容降级矩阵）与 `simulator-manifest.test.js`（真实 22 款 manifest
/// 全量解析数据面）。
///
/// 判据边界（结构性失败 vs 条目级剔除）逐字锚桌面：
/// - 结构性失败：畸形 JSON / 顶层非对象 / version ∉ {1,2} / simulators 缺失
///   或非数组 / 条目非对象 / id 缺失或重复 / file 缺失 / type 非法 → 整体失败；
/// - 条目级宽容降级：name / description 缺失 → 空串；saveKeyPrefix / config /
///   saveKeys / endpointMode 非法 → 字段剔除或归一化，不整体失败；
/// - v1 兼容：条目无 saveKeys → 无 saveKeys 属性（「无存档管理」降级信号），
///   saveKeyPrefix 透传（已退役字段仅 v1 数据携带）；type 对 v1/v2 一律必填
///   （桌面逐字，v1 不豁免 type）。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/manifest_parser.dart';

/// v1 合法 manifest（2 款：ai 带 config/saveKeyPrefix + local 无 config）——
/// 桌面 MANIFEST_OK 同构夹具。
final Map<String, Object?> manifestV1 = <String, Object?>{
  'version': 1,
  'simulators': <Object?>[
    <String, Object?>{
      'id': 'life-sim',
      'file': '人生模拟器v3.html',
      'name': '人生模拟器 v3',
      'type': 'ai',
      'description': 'AI 驱动的生命模拟',
      'saveKeyPrefix': 'ls_',
      'config': <String, Object?>{'endpoint': 'cfg-endpoint', 'apikey': 'cfg-apikey', 'model': 'cfg-model'},
    },
    <String, Object?>{
      'id': 'spider-shadow',
      'file': '蛛网之影.html',
      'name': '蛛网之影',
      'type': 'local',
      'description': '纯本地角色扮演',
    },
  ],
};

/// v2 合法 manifest（U9-T1）：saveKeys 字符串数组 = 精确键 + 锚定正则模式。
final Map<String, Object?> manifestV2 = <String, Object?>{
  'version': 2,
  'simulators': <Object?>[
    <String, Object?>{
      'id': 'life-sim',
      'file': '人生模拟器v3.html',
      'name': '人生模拟器 v3',
      'type': 'ai',
      'description': 'AI 驱动的生命模拟',
      'saveKeys': <Object?>['ls_autosave', 'ls_used_names'],
      'config': <String, Object?>{'endpoint': 'cfg-endpoint', 'apikey': 'cfg-apikey', 'model': 'cfg-model'},
    },
    <String, Object?>{
      'id': 'urban-god',
      'file': '神明v3.html',
      'name': '神明 v3',
      'type': 'ai',
      'description': 'AI 驱动的都市神明模拟',
      'saveKeys': <Object?>['god_autosave', r'god_save_\d+'],
      'config': <String, Object?>{'endpoint': 'cfg-endpoint', 'apikey': 'cfg-apikey', 'model': 'cfg-model'},
    },
  ],
};

String encode(Object? data) => json.encode(data);

/// 从夹具复制条目并改键值（测试易变体构造）。
Map<String, Object?> altered(Map<String, Object?> entry, Map<String, Object?> changes) {
  return <String, Object?>{...entry, ...changes};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseManifest — 合法归一化（v1/v2）', () {
    test('v1 合法 manifest → 归一化条目：字段透传 + saveKeyPrefix 透传、无 saveKeys 属性', () {
      final result = parseManifest(encode(manifestV1));
      expect(result.ok, isTrue);
      final games = result.games!;
      expect(games, hasLength(2));
      expect(games[0]['id'], 'life-sim');
      expect(games[0]['file'], '人生模拟器v3.html');
      expect(games[0]['name'], '人生模拟器 v3');
      expect(games[0]['type'], 'ai');
      expect(games[0]['description'], 'AI 驱动的生命模拟');
      expect(games[0]['saveKeyPrefix'], 'ls_');
      expect(games[0]['config'], <String, Object?>{'endpoint': 'cfg-endpoint', 'apikey': 'cfg-apikey', 'model': 'cfg-model'});
      expect(games[0].containsKey('saveKeys'), isFalse, reason: 'v1 条目缺 saveKeys → 无 saveKeys 属性（降级信号）');
      expect(games[1]['id'], 'spider-shadow');
      expect(games[1]['type'], 'local');
    });

    test('v2 合法 manifest → saveKeys 原样透出（精确键与正则模式），无 saveKeyPrefix', () {
      final result = parseManifest(encode(manifestV2));
      expect(result.ok, isTrue);
      final games = result.games!;
      expect(games[0]['saveKeys'], <String>['ls_autosave', 'ls_used_names']);
      expect(games[1]['saveKeys'], <String>['god_autosave', r'god_save_\d+']);
      expect(games[0].containsKey('saveKeyPrefix'), isFalse);
    });

    test('空 simulators 列表 → ok 且 games 为空数组（空态判定依据）', () {
      final result = parseManifest(encode(<String, Object?>{'version': 1, 'simulators': <Object?>[]}));
      expect(result.ok, isTrue);
      expect(result.games, isEmpty);
    });

    test('endpointMode 透传：base/full 字符串 → 条目带 endpointMode', () {
      final data = <String, Object?>{
        'version': 2,
        'simulators': <Object?>[
          <String, Object?>{'id': 'a', 'file': 'a.html', 'type': 'ai', 'name': 'A', 'endpointMode': 'full', 'config': <String, Object?>{'endpoint': 'e', 'apikey': 'k', 'model': 'm'}},
          <String, Object?>{'id': 'b', 'file': 'b.html', 'type': 'ai', 'name': 'B', 'endpointMode': 'base', 'config': <String, Object?>{'endpoint': 'e', 'apikey': 'k', 'model': 'm'}},
        ],
      };
      final result = parseManifest(encode(data));
      expect(result.ok, isTrue);
      expect(result.games![0]['endpointMode'], 'full');
      expect(result.games![1]['endpointMode'], 'base');
    });

    test('endpointMode 非法值 / 缺失 → 条目级降级（剔除该字段，不整体失败）', () {
      final data = <String, Object?>{
        'version': 2,
        'simulators': <Object?>[
          <String, Object?>{'id': 'a', 'file': 'a.html', 'type': 'ai', 'name': 'A', 'endpointMode': 'weird', 'config': <String, Object?>{'endpoint': 'e', 'apikey': 'k', 'model': 'm'}},
          <String, Object?>{'id': 'b', 'file': 'b.html', 'type': 'ai', 'name': 'B', 'endpointMode': 42, 'config': <String, Object?>{'endpoint': 'e', 'apikey': 'k', 'model': 'm'}},
          <String, Object?>{'id': 'c', 'file': 'c.html', 'type': 'ai', 'name': 'C', 'config': <String, Object?>{'endpoint': 'e', 'apikey': 'k', 'model': 'm'}},
        ],
      };
      final result = parseManifest(encode(data));
      expect(result.ok, isTrue);
      for (final game in result.games!) {
        expect(game.containsKey('endpointMode'), isFalse, reason: 'endpointMode 剔除: ${game['id']}');
      }
    });

    test('source 白名单：仅 imported / generated 透传，其余/缺失 → 不设 source', () {
      final data = <String, Object?>{
        'version': 2,
        'simulators': <Object?>[
          <String, Object?>{'id': 'a', 'file': 'a.html', 'type': 'local', 'name': 'A', 'source': 'imported'},
          <String, Object?>{'id': 'b', 'file': 'b.html', 'type': 'ai', 'name': 'B', 'source': 'generated'},
          <String, Object?>{'id': 'c', 'file': 'c.html', 'type': 'local', 'name': 'C', 'source': 'weird'},
          <String, Object?>{'id': 'd', 'file': 'd.html', 'type': 'local', 'name': 'D'},
        ],
      };
      final result = parseManifest(encode(data));
      expect(result.ok, isTrue);
      expect(result.games![0]['source'], 'imported');
      expect(result.games![1]['source'], 'generated');
      expect(result.games![2].containsKey('source'), isFalse);
      expect(result.games![3].containsKey('source'), isFalse);
    });
  });

  group('parseManifest — 结构性失败（整体判定失败）', () {
    test('畸形 JSON → 失败，「manifest 不是合法 JSON」', () {
      final result = parseManifest('not-json{{{');
      expect(result.ok, isFalse);
      expect(result.error, 'manifest 不是合法 JSON');
    });

    test('Falsify: 空串输入 → 失败（JSON 解析失败路径）', () {
      expect(parseManifest('').ok, isFalse);
    });

    test('Falsify: 顶层非对象（JSON 数字 / 数组 / null）→ 失败', () {
      expect(parseManifest('42').ok, isFalse);
      expect(parseManifest('[]').ok, isFalse);
      expect(parseManifest('null').ok, isFalse);
    });

    test('version 不兼容（缺失 / 非 1 或 2）→ 失败，「manifest 版本不兼容」', () {
      expect(parseManifest(encode(<String, Object?>{'simulators': <Object?>[]})).error, 'manifest 版本不兼容');
      expect(parseManifest(encode(<String, Object?>{'version': 0, 'simulators': <Object?>[]})).error, 'manifest 版本不兼容');
      expect(parseManifest(encode(<String, Object?>{'version': 3, 'simulators': <Object?>[]})).error, 'manifest 版本不兼容');
    });

    test('simulators 缺失 / 非数组 → 失败', () {
      expect(parseManifest(encode(<String, Object?>{'version': 1})).error, 'manifest 缺少 simulators 列表');
      expect(parseManifest(encode(<String, Object?>{'version': 1, 'simulators': 'x'})).ok, isFalse);
    });

    test('id 缺失 / 重复 → 失败，「manifest 存在缺失或重复的 id」', () {
      final noId = altered((manifestV1['simulators'] as List<Object?>)[0] as Map<String, Object?>, <String, Object?>{'id': null});
      expect(parseManifest(encode(<String, Object?>{'version': 1, 'simulators': <Object?>[noId]})).error, 'manifest 存在缺失或重复的 id');
      final duplicated = <Object?>[
        (manifestV1['simulators'] as List<Object?>)[0],
        (manifestV1['simulators'] as List<Object?>)[0],
      ];
      expect(parseManifest(encode(<String, Object?>{'version': 1, 'simulators': duplicated})).ok, isFalse);
    });

    test('file 缺失 → 失败，「manifest 条目缺少 file 字段」', () {
      final entry = (manifestV1['simulators'] as List<Object?>)[0] as Map<String, Object?>;
      final noFile = <String, Object?>{...entry}..remove('file');
      expect(parseManifest(encode(<String, Object?>{'version': 1, 'simulators': <Object?>[noFile]})).error, 'manifest 条目缺少 file 字段');
    });

    test('type 非法（未知值 / 缺失）→ 失败，「manifest 条目 type 非法」（v1 不豁免）', () {
      final entry = (manifestV1['simulators'] as List<Object?>)[0] as Map<String, Object?>;
      final badType = altered(entry, <String, Object?>{'type': 'web'});
      expect(parseManifest(encode(<String, Object?>{'version': 1, 'simulators': <Object?>[badType]})).error, 'manifest 条目 type 非法');
      final noType = <String, Object?>{...entry}..remove('type');
      expect(parseManifest(encode(<String, Object?>{'version': 1, 'simulators': <Object?>[noType]})).ok, isFalse);
    });

    test('Falsify: 条目非对象（null / 字符串元素）→ 失败', () {
      expect(parseManifest(encode(<String, Object?>{'version': 1, 'simulators': <Object?>[null]})).ok, isFalse);
      expect(parseManifest(encode(<String, Object?>{'version': 1, 'simulators': <Object?>['x']})).ok, isFalse);
    });

    test('Falsify: 条目字段含不可 JSON 序列化值不会被传入（类型系统约束）——数字 id 等价 null 语义', () {
      final entry = (manifestV1['simulators'] as List<Object?>)[0] as Map<String, Object?>;
      final numId = altered(entry, <String, Object?>{'id': 42});
      expect(parseManifest(encode(<String, Object?>{'version': 1, 'simulators': <Object?>[numId]})).ok, isFalse);
    });
  });

  group('parseManifest — 条目级宽容降级', () {
    test('条目级字段缺失（name/description）→ 宽容降级为空串，不整体失败', () {
      final entry = (manifestV1['simulators'] as List<Object?>)[1] as Map<String, Object?>;
      final sparse = <String, Object?>{...entry}..remove('name')..remove('description');
      final result = parseManifest(encode(<String, Object?>{'version': 1, 'simulators': <Object?>[sparse]}));
      expect(result.ok, isTrue);
      expect(result.games![0]['name'], '');
      expect(result.games![0]['description'], '');
    });

    test('Falsify: saveKeyPrefix/config 类型异常 → 降级剔除可选字段，不炸', () {
      final entry = (manifestV1['simulators'] as List<Object?>)[0] as Map<String, Object?>;
      final weird = altered(entry, <String, Object?>{'saveKeyPrefix': 42, 'config': 'not-object'});
      final result = parseManifest(encode(<String, Object?>{'version': 1, 'simulators': <Object?>[weird]}));
      expect(result.ok, isTrue);
      expect(result.games![0].containsKey('saveKeyPrefix'), isFalse);
      expect(result.games![0].containsKey('config'), isFalse);
    });
  });

  group('parseManifest — v2 saveKeys 归一化 / v1 降级兼容（U9-T1）', () {
    test('混合 v1/v2 条目 → 各自归一化：v2 透出 saveKeys，v1 无 saveKeys 属性', () {
      final mixed = <String, Object?>{
        'version': 2,
        'simulators': <Object?>[(manifestV2['simulators'] as List<Object?>)[0], (manifestV1['simulators'] as List<Object?>)[1]],
      };
      final result = parseManifest(encode(mixed));
      expect(result.ok, isTrue);
      expect(result.games![0]['saveKeys'], <String>['ls_autosave', 'ls_used_names']);
      expect(result.games![1].containsKey('saveKeys'), isFalse);
      expect(result.games![1]['id'], 'spider-shadow');
    });

    test('Falsify: saveKeys 非数组 → 条目级降级（saveKeys 剔除），不整体失败', () {
      final entry = (manifestV2['simulators'] as List<Object?>)[0] as Map<String, Object?>;
      final bad = altered(entry, <String, Object?>{'saveKeys': 'ls_autosave'});
      final result = parseManifest(encode(<String, Object?>{'version': 2, 'simulators': <Object?>[bad]}));
      expect(result.ok, isTrue);
      expect(result.games![0].containsKey('saveKeys'), isFalse);
      expect(result.games![0]['id'], 'life-sim');
    });

    test('Falsify: saveKeys 元素非字符串（含 null）→ 条目级降级', () {
      final entry = (manifestV2['simulators'] as List<Object?>)[0] as Map<String, Object?>;
      final bad = altered(entry, <String, Object?>{'saveKeys': <Object?>['ls_autosave', null]});
      final result = parseManifest(encode(<String, Object?>{'version': 2, 'simulators': <Object?>[bad]}));
      expect(result.ok, isTrue);
      expect(result.games![0].containsKey('saveKeys'), isFalse);
    });

    test('Falsify: 模式元素无法编译 → 剔除该项，其余元素保留（元素级降级）', () {
      final entry = (manifestV2['simulators'] as List<Object?>)[1] as Map<String, Object?>;
      final bad = altered(entry, <String, Object?>{'saveKeys': <Object?>['god_autosave', r'god_save_[', r'god_save_\d+']});
      final result = parseManifest(encode(<String, Object?>{'version': 2, 'simulators': <Object?>[bad]}));
      expect(result.ok, isTrue);
      expect(result.games![0]['saveKeys'], <String>['god_autosave', r'god_save_\d+']);
    });

    test('Falsify: 空字符串元素 → 剔除该项（元素级降级）', () {
      final entry = (manifestV2['simulators'] as List<Object?>)[0] as Map<String, Object?>;
      final bad = altered(entry, <String, Object?>{'saveKeys': <Object?>['ls_autosave', '']});
      final result = parseManifest(encode(<String, Object?>{'version': 2, 'simulators': <Object?>[bad]}));
      expect(result.ok, isTrue);
      expect(result.games![0]['saveKeys'], <String>['ls_autosave']);
    });

    test(r'Falsify: 模式自含 ^ / $ 锚点 → 条目级降级（锚定由匹配方统一加，数据不得自锚定）', () {
      final entry = (manifestV2['simulators'] as List<Object?>)[1] as Map<String, Object?>;
      final bad = altered(entry, <String, Object?>{'saveKeys': <Object?>[r'^god_autosave$']});
      final result = parseManifest(encode(<String, Object?>{'version': 2, 'simulators': <Object?>[bad]}));
      expect(result.ok, isTrue);
      expect(result.games![0].containsKey('saveKeys'), isFalse);
    });

    test('Falsify: 清洗后为空数组 → 保留空数组（结构性合法，非降级信号）', () {
      final entry = (manifestV2['simulators'] as List<Object?>)[1] as Map<String, Object?>;
      final bad = altered(entry, <String, Object?>{'saveKeys': <Object?>[r'god_save_[', '']});
      final result = parseManifest(encode(<String, Object?>{'version': 2, 'simulators': <Object?>[bad]}));
      expect(result.ok, isTrue);
      expect(result.games![0]['saveKeys'], isEmpty);
    });
  });

  group('parseManifest — 深度兜底（F-29）', () {
    /// 构造深度为 3 + [inner] 的合法 v2 manifest：顶层对象(1) + simulators
    /// 数组(2) + 条目对象(3) + config 值域嵌套 [inner] 层（`{"a":` 重复）。
    /// 注意：相邻字符串字面量会跨行自动拼接，嵌套串须先算进局部变量再插值。
    String deepValidManifest(int inner) {
      final nesting = '{"a":' * inner;
      final closing = '}' * inner;
      return '{"version":1,"simulators":['
          '{"id":"a","file":"a.html","type":"local","name":"A","config":'
          '$nesting'
          '1'
          '$closing'
          '}]}';
    }

    test('F-29 深度兜底：嵌套超 [maxManifestDepth] → 结构性失败降级（不裸抛 StackOverflowError/不吞成其他结构错误）', () {
      final raw = deepValidManifest(maxManifestDepth - 2); // 总深度 = maxManifestDepth + 1
      final result = parseManifest(raw);
      expect(result.ok, isFalse);
      expect(result.error, 'manifest 嵌套深度超出解析上限');
    });

    test('F-29 深度兜底：恰在上限内的合法深配置 → 正常解析（无 off-by-one 误伤）', () {
      final raw = deepValidManifest(maxManifestDepth - 3); // 总深度恰 = maxManifestDepth
      final result = parseManifest(raw);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.games!.single['id'], 'a');
    });

    test('F-29 深度兜底：常态嵌套（config 深约 100 层）→ 不误伤（深度预扫不产生假阳性）', () {
      final result = parseManifest(deepValidManifest(100));
      expect(result.ok, isTrue);
      expect(result.games!.single['config'], isA<Map<String, dynamic>>());
    });

    test('F-29 Falsify：不平衡闭括号不穿负深度；字符串内花括号/方括号不计入深度（预扫只估结构）', () {
      // 大量孤立闭括号 → 深度守卫不穿负，正常走后续结构判定（畸形 JSON 文案）。
      expect(parseManifest(']]]').error, isNot('manifest 嵌套深度超出解析上限'));
      // 描述文案含 { } [ ] 字面量 → 预扫不误计深度，正常解析。
      final raw = jsonEncode({
        'version': 2,
        'simulators': [
          {
            'id': 'a',
            'file': 'a.html',
            'type': 'local',
            'name': 'A',
            'description': '含 {花括号} 与 [方括号] 的文案',
          },
        ],
      });
      final result = parseManifest(raw);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.games!.single['description'], contains('{'));
    });
  });

  group('parseManifest — 真实 22 款内置 manifest（数据面锚点）', () {
    test('全量解析无整体失败：22 条、saveKeys 全非空、无退役字段、id 唯一', () async {
      final raw = await rootBundle.loadString('assets/simulators/manifest.json');
      final result = parseManifest(raw);
      expect(result.ok, isTrue, reason: result.error);
      final games = result.games!;
      expect(games, hasLength(22));
      final ids = games.map((g) => g['id'] as String).toSet();
      expect(ids, hasLength(22), reason: 'id 全局唯一');
      for (final game in games) {
        final saveKeys = game['saveKeys'] as List<Object?>;
        expect(saveKeys, isNotEmpty, reason: '${game['id']} 归一化后 saveKeys 非空');
        expect(saveKeys.every((k) => k is String), isTrue, reason: '${game['id']} saveKeys 元素为字符串');
        expect(game.containsKey('saveKeyPrefix'), isFalse, reason: '${game['id']} 归一化无退役字段');
        expect(game['type'], 'ai', reason: '${game['id']} 内置条目全为 ai');
        expect(game['endpointMode'], anyOf('base', 'full'), reason: '${game['id']} endpointMode 白名单');
      }
    });
  });
}
