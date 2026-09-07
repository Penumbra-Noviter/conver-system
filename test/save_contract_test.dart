/// 存档契约层测试（对拍桌面 save-manager.test.js 纯函数 seam 边界矩阵）。
///
/// 桌面锚点（只读，语义锚）：`desktop/frontend/tests/save-manager.test.js` ——
/// 整包拒绝 / 白名单防御 / 写前快照回滚（TD-63）/ 尽力而为回滚不遮蔽原始
/// 错误（TD-73）/ `__proto__` 键完整写出（TD-70）/ cfg 与主应用自身键不误收 /
/// 排序去重 / 文件名净化（TD-65）/ 5MB 上限。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/save_contract.dart';

import 'support/fake_storage.dart';

// ══════════════════════════════════════════════════
// 夹具（对齐桌面 save-manager.test.js GAME_* 契约，parseManifest 归一化形状）
// ══════════════════════════════════════════════════

/// 精确键白名单游戏。
const Map<String, Object?> gameExact = {
  'id': 'life-sim',
  'file': '人生模拟器v3.html',
  'name': '人生模拟器 v3',
  'type': 'ai',
  'saveKeys': ['ls_autosave', 'ls_used_names'],
};

/// 正则模式白名单游戏（锚定完整键名匹配）。
const Map<String, Object?> gameRegex = {
  'id': 'urban-god',
  'file': '神明v3.html',
  'name': '神明 v3',
  'type': 'ai',
  'saveKeys': ['god_autosave', r'god_save_\d+'],
};

/// 混合（精确 + 正则）白名单游戏。
const Map<String, Object?> gameMixed = {
  'id': 'twilight-witch',
  'file': '暮色女巫v2.html',
  'name': '暮色女巫 v2',
  'type': 'ai',
  'saveKeys': [
    'twilight_autosave',
    'twilight_cps',
    'twilight_deaths',
    r'twilight_slot_\d+',
  ],
};

/// 无 saveKeys 游戏（「无存档管理」降级信号）。
const Map<String, Object?> gameNoSave = {
  'id': 'spider-shadow',
  'file': '蛛网之影.html',
  'name': '蛛网之影',
  'type': 'local',
};

/// 主应用自身键（当前主应用零 localStorage 键 — 测试以模拟键断言不误伤）。
const String appOwnKey = 'conver_settings_v1';

// ══════════════════════════════════════════════════
// collectGameKeys — 键收集
// ══════════════════════════════════════════════════

void main() {
  group('collectGameKeys · saveKeys 白名单匹配键收集', () {
    test('精确键：只收集白名单命中且存在的键；cfg 键与主应用自身键不误收', () {
      final storage = FakeSaveStorage({
        'ls_autosave': '{"v":1}',
        'ls_used_names': '["a"]',
        'ls_cfg': '{"apiKey":"sk-test"}', // cfg 键（含 API Key）— 不在白名单
        appOwnKey: '{"theme":"dark"}', // 主应用自身键 — 不在白名单
        'unrelated_key': 'x',
      });
      expect(collectGameKeys(gameExact, storage),
          ['ls_autosave', 'ls_used_names']);
    });

    test(r'正则模式：锚定完整键名匹配（god_save_\d+ → 数字后缀命中，非数字/带尾缀不命中）', () {
      final storage = FakeSaveStorage({
        'god_autosave': 'a',
        'god_save_1': 'b',
        'god_save_42': 'c',
        'god_save_abc': 'd', // 非数字后缀 — 不命中
        'god_save_1x': 'e', // 锚定 ^…$：后缀 1x 不命中
      });
      expect(collectGameKeys(gameRegex, storage),
          ['god_autosave', 'god_save_1', 'god_save_42']);
    });

    test('混合（精确 + 正则）：slot 模式与精确键同收；cfg 键不误收', () {
      final storage = FakeSaveStorage({
        'twilight_autosave': 'a',
        'twilight_cps': 'b',
        'twilight_deaths': 'c',
        'twilight_slot_0': 'd',
        'twilight_slot_7': 'e',
        'twilight_config': '{"apiKey":"sk"}', // cfg 键 — 不在 saveKeys
      });
      expect(collectGameKeys(gameMixed, storage), [
        'twilight_autosave',
        'twilight_cps',
        'twilight_deaths',
        'twilight_slot_0',
        'twilight_slot_7',
      ]);
    });

    test('saveKeys 空数组 → 收集为空（结构性合法但零键）', () {
      final storage = FakeSaveStorage({'ls_autosave': 'x'});
      expect(
          collectGameKeys({...gameExact, 'saveKeys': <String>[]}, storage), []);
    });

    test('saveKeys 缺失 → 收集为空（「无存档管理」降级信号）', () {
      final storage = FakeSaveStorage({'spiderweb_state': 'x'});
      expect(collectGameKeys(gameNoSave, storage), []);
    });

    test('去重：同一键命中多条白名单条目（精确 + 正则）只收集一次', () {
      final storage = FakeSaveStorage({'god_save_1': 'x'});
      expect(
          collectGameKeys(
              {...gameRegex, 'saveKeys': ['god_save_1', r'god_save_\d+']},
              storage),
          ['god_save_1']);
    });

    test('收集结果排序确定（不依赖 localStorage 枚举顺序）', () {
      final storage = FakeSaveStorage({'ls_used_names': 'a', 'ls_autosave': 'b'});
      expect(collectGameKeys(gameExact, storage),
          ['ls_autosave', 'ls_used_names']);
    });

    test('Falsify:game null / saveKeys 非数组 / storage null → [] 不炸', () {
      expect(collectGameKeys(null, FakeSaveStorage()), []);
      expect(
          collectGameKeys(
              {'id': 'x', 'saveKeys': 'ls_autosave'}, FakeSaveStorage()),
          []);
      expect(collectGameKeys(gameExact, null), []);
    });

    test('Falsify:白名单含不可编译正则元素 → 跳过该元素不炸（防御 parseManifest 外的原始数据）', () {
      final storage = FakeSaveStorage({'god_autosave': 'a', 'god_save_1': 'b'});
      expect(
          collectGameKeys(
              {...gameRegex, 'saveKeys': ['god_autosave', 'god_save_[']},
              storage),
          ['god_autosave']);
    });
  });

  // ══════════════════════════════════════════════════
  // buildExportPayload — 导出 JSON 形状与收录规则
  // ══════════════════════════════════════════════════

  group('buildExportPayload · 导出 JSON 形状与收录规则', () {
    const now = '2026-08-14T00:00:00.000Z';

    test('形状：{game_id, game_name, saved_at, keys:{键:值}}；saved_at 可注入（纯函数确定性）', () {
      final storage = FakeSaveStorage(
          {'ls_autosave': '{"v":1}', 'ls_used_names': '["a"]'});
      final payload = buildExportPayload(
          gameExact, ['ls_autosave', 'ls_used_names'], storage, now: now);
      expect(payload, {
        'game_id': 'life-sim',
        'game_name': '人生模拟器 v3',
        'saved_at': now,
        'keys': {'ls_autosave': '{"v":1}', 'ls_used_names': '["a"]'},
      });
    });

    test('收录规则：只收录白名单命中且存在的键；传入的 cfg 键名 → 防御不收录（导出导不出 cfg 键）', () {
      final storage = FakeSaveStorage({
        'ls_autosave': 'a',
        'ls_cfg': '{"apiKey":"sk-test"}',
      });
      final payload =
          buildExportPayload(gameExact, ['ls_autosave', 'ls_cfg'], storage,
              now: now);
      expect(payload['keys'], {'ls_autosave': 'a'});
    });

    test('正则模式键收集后导出：键值原样收录', () {
      final storage =
          FakeSaveStorage({'god_autosave': 'a', 'god_save_3': '{"hp":10}'});
      final keyNames = collectGameKeys(gameRegex, storage);
      final payload =
          buildExportPayload(gameRegex, keyNames, storage, now: now);
      expect(payload['keys'],
          {'god_autosave': 'a', 'god_save_3': '{"hp":10}'});
    });

    test('keyNames 含不存在于 storage 的键 → 不收录（只导出当前存在的键）', () {
      final storage = FakeSaveStorage({'ls_autosave': 'a'});
      final payload = buildExportPayload(
          gameExact, ['ls_autosave', 'ls_used_names'], storage,
          now: now);
      expect(payload['keys'], {'ls_autosave': 'a'});
    });

    test('saved_at 缺省为 ISO8601（未注入时输出可解析）', () {
      final storage = FakeSaveStorage({'ls_autosave': 'a'});
      final payload = buildExportPayload(gameExact, ['ls_autosave'], storage);
      final savedAt = payload['saved_at']! as String;
      expect(DateTime.tryParse(savedAt), isNotNull);
    });

    test('Falsify:storage null / keyNames 非数组 → keys 为空对象，不炸', () {
      expect(buildExportPayload(gameExact, ['ls_autosave'], null, now: now)['keys'], <String, String>{});
      expect(buildExportPayload(gameExact, 'ls_autosave', FakeSaveStorage({}), now: now)['keys'], <String, String>{});
    });

    test('Falsify:game null → game_id/game_name 为空串，不炸', () {
      final payload = buildExportPayload(null, const [], FakeSaveStorage({}), now: now);
      expect(payload['game_id'], '');
      expect(payload['game_name'], '');
      expect(payload['keys'], <String, String>{});
    });
  });

  // ══════════════════════════════════════════════════
  // validateImportPayload — 导入校验（整包拒绝）
  // ══════════════════════════════════════════════════

  group('validateImportPayload · 白名单校验（任一非法整包拒绝）', () {
    test('合法包：键名全命中白名单且值为合法 JSON 字符串 → ok:true，keys 全量返回', () {
      final payload = {
        'game_id': 'urban-god',
        'game_name': '神明 v3',
        'saved_at': '2026-08-14T00:00:00.000Z',
        'keys': {
          'god_autosave': '{"v":1}',
          'god_save_3': '{"hp":10}',
          'god_save_42': '[1,2]',
        },
      };
      final result = validateImportPayload(payload, gameRegex);
      expect(result.ok, isTrue);
      expect(result.keys, {
        'god_autosave': '{"v":1}',
        'god_save_3': '{"hp":10}',
        'god_save_42': '[1,2]',
      });
    });

    test('合法值边界：数字 / null / 对象形态的 JSON 文本均可解析 → 通过', () {
      final payload = {'keys': {'ls_autosave': '123', 'ls_used_names': 'null'}};
      final result = validateImportPayload(payload, gameExact);
      expect(result.ok, isTrue);
      expect(result.keys, {'ls_autosave': '123', 'ls_used_names': 'null'});
    });

    test('任一非法键（含 cfg 键名 / 非白名单键）→ 整包拒绝，error 列出全部非法键名', () {
      final payload = {
        'keys': {
          'ls_autosave': '{"v":1}',
          'ls_cfg': '{"apiKey":"sk-test"}',
          'evil_extra': '"x"',
        },
      };
      final result = validateImportPayload(payload, gameExact);
      expect(result.ok, isFalse);
      expect(result.error, contains('存档文件校验失败'));
      expect(result.error, contains('键「ls_cfg」不在该游戏存档键白名单内'));
      expect(result.error, contains('键「evil_extra」不在该游戏存档键白名单内'));
    });

    test('Falsify:载荷非对象（null / 数组 / 字符串）→ 拒绝「存档文件格式无效」', () {
      expect(validateImportPayload(null, gameExact).error,
          '存档文件格式无效：顶层必须是对象');
      expect(validateImportPayload(const [], gameExact).error,
          '存档文件格式无效：顶层必须是对象');
      expect(validateImportPayload('abc', gameExact).error,
          '存档文件格式无效：顶层必须是对象');
    });

    test('Falsify:keys 缺失 → 拒绝「存档文件缺少 keys 字段」；keys 非普通对象（数组）→ 拒绝', () {
      expect(validateImportPayload({'game_id': 'x'}, gameExact).error,
          '存档文件缺少 keys 字段');
      expect(validateImportPayload({'keys': <String>[]}, gameExact).error,
          '存档文件 keys 字段必须是对象');
      expect(validateImportPayload({'keys': 'x'}, gameExact).error,
          '存档文件 keys 字段必须是对象');
    });

    test('Falsify:值非 string（数字 / 对象）→ 整包拒绝', () {
      final payload = {
        'keys': {'ls_autosave': 42, 'ls_used_names': {'a': 1}},
      };
      final result = validateImportPayload(payload, gameExact);
      expect(result.ok, isFalse);
      expect(result.error, contains('键「ls_autosave」的值不是合法 JSON 字符串'));
      expect(result.error, contains('键「ls_used_names」的值不是合法 JSON 字符串'));
    });

    test('Falsify:值 string 但 JSON 不可解析（裸文本 / 空串）→ 整包拒绝', () {
      final result = validateImportPayload(
          {'keys': {'ls_autosave': 'not-json', 'ls_used_names': ''}},
          gameExact);
      expect(result.ok, isFalse);
      expect(result.error, contains('键「ls_autosave」的值不是合法 JSON 字符串'));
      expect(result.error, contains('键「ls_used_names」的值不是合法 JSON 字符串'));
    });

    test(r'正则白名单键名匹配语义与收集一致：god_save_3 合法；god_save_abc 与字面 \d+ 键名非法（不按字面放行）', () {
      final ok = validateImportPayload(
          {'keys': {'god_save_3': '{"v":1}'}}, gameRegex);
      expect(ok.ok, isTrue);
      final bad = validateImportPayload(
          {'keys': {'god_save_abc': '"x"'}}, gameRegex);
      expect(bad.ok, isFalse);
      expect(bad.error, contains('键「god_save_abc」不在该游戏存档键白名单内'));
      // 正则模式键名本身含元字符（字面 'god_save_\\d+'）→ 正则语义不匹配数字要求 → 非法
      final literal = validateImportPayload(
          {'keys': {r'god_save_\d+': '"x"'}}, gameRegex);
      expect(literal.ok, isFalse);
      expect(literal.error, contains('不在该游戏存档键白名单内'));
    });

    test('Falsify:game 无 saveKeys → 整体拒绝「该游戏无存档管理…无法导入」', () {
      final result =
          validateImportPayload({'keys': {'spiderweb_state': '"x"'}}, gameNoSave);
      expect(result.ok, isFalse);
      expect(result.error, '该游戏无存档管理（saveKeys 未声明），无法导入');
      // game 非对象 / null → 同样按无白名单拒绝
      expect(validateImportPayload({'keys': <String, String>{}}, null).ok,
          isFalse);
    });

    test('非法键过多（>10）→ error 截断至 10 条并计数', () {
      final keys = <String, Object?>{};
      for (var i = 0; i < 15; i++) {
        keys['bad_key_$i'] = '"x"';
      }
      final result = validateImportPayload({'keys': keys}, gameExact);
      expect(result.ok, isFalse);
      expect(result.error, contains('等共 15 个问题（仅列出前 10 个）'));
      expect('键「'.allMatches(result.error!).length, 10);
    });

    test('空 keys 对象 → 合法空包（ok:true，应用为 no-op）', () {
      final result = validateImportPayload(
          {'keys': <String, String>{}}, gameExact);
      expect(result.ok, isTrue);
      expect(result.keys, <String, String>{});
    });

    test('__proto__ 键：白名单命中 → 完整写出（Dart Map 语义，无原型吞键）', () {
      final game = {
        ...gameExact,
        'saveKeys': [...(gameExact['saveKeys']! as List), '__proto__'],
      };
      // 导入真实路径为 JSON.parse 产物：自有 __proto__ 属性（Dart jsonDecode 产生普通键）
      final payload =
          jsonDecode('{"keys":{"ls_autosave":"\\"a\\"","__proto__":"\\"p\\""}}');
      final result = validateImportPayload(payload, game);
      expect(result.ok, isTrue);
      expect(result.keys.keys.toList()..sort(), ['__proto__', 'ls_autosave']);
      expect(result.keys['__proto__'], '"p"');
      expect(result.keys['ls_autosave'], '"a"');
    });
  });

  // ══════════════════════════════════════════════════
  // applyImportPayload — 应用（同名替换写回）
  // ══════════════════════════════════════════════════

  group('applyImportPayload · 白名单键同名替换写回', () {
    test('合法键写回：同名键替换旧值；返回写入计数', () {
      final storage = FakeSaveStorage({'ls_autosave': 'old', 'app_own': 'keep'});
      final written = applyImportPayload(gameExact,
          {'ls_autosave': '{"v":2}', 'ls_used_names': '["b"]'}, storage);
      expect(written, 2);
      expect(storage['ls_autosave'], '{"v":2}');
      expect(storage['ls_used_names'], '["b"]');
      expect(storage['app_own'], 'keep'); // 主应用键不受影响
    });

    test('Falsify:非白名单键（cfg 键名）→ 防御不写入（导入写不进去）', () {
      final storage = FakeSaveStorage();
      final written = applyImportPayload(gameExact,
          {'ls_cfg': '{"apiKey":"sk"}', 'ls_autosave': 'ok'}, storage);
      expect(written, 1);
      expect(storage['ls_cfg'], isNull);
      expect(storage['ls_autosave'], 'ok');
    });

    test('Falsify:值非字符串 → 跳过不写入', () {
      final storage = FakeSaveStorage();
      final written =
          applyImportPayload(gameExact, {'ls_autosave': {'a': 1}}, storage);
      expect(written, 0);
      expect(storage['ls_autosave'], isNull);
    });

    test('Falsify:keys 含非字符串键 → 跳过不写入（Dart Map 键类型防御）', () {
      final storage = FakeSaveStorage();
      final written = applyImportPayload(
          gameExact, {42: '"x"', 'ls_autosave': 'ok'}, storage);
      expect(written, 1);
      expect(storage['42'], isNull);
      expect(storage['ls_autosave'], 'ok');
    });

    test('Falsify:game null / saveKeys 缺失 / keys 非对象 / storage null → 0 不炸', () {
      final storage = FakeSaveStorage();
      expect(applyImportPayload(null, {'ls_autosave': 'x'}, storage), 0);
      expect(
          applyImportPayload(
              gameNoSave, {'spiderweb_state': 'x'}, storage),
          0);
      expect(applyImportPayload(gameExact, 'x', storage), 0);
      expect(applyImportPayload(gameExact, {'ls_autosave': 'x'}, null), 0);
    });

    test('__proto__ 键全链路：validate → apply 完整写回（TD-70 无原型累积器语义）', () {
      final game = {
        ...gameExact,
        'saveKeys': [...(gameExact['saveKeys']! as List), '__proto__'],
      };
      final payload =
          jsonDecode('{"keys":{"ls_autosave":"\\"a\\"","__proto__":"\\"p\\""}}');
      final result = validateImportPayload(payload, game);
      expect(result.ok, isTrue);

      final storage = FakeSaveStorage();
      final written = applyImportPayload(game, result.keys, storage);
      expect(written, 2);
      expect(storage['__proto__'], '"p"');
      expect(storage['ls_autosave'], '"a"');
    });
  });

  // ══════════════════════════════════════════════════
  // applyImportPayload — 写前快照 + 失败回滚（TD-63 裁定修法，非容量预检）
  // ══════════════════════════════════════════════════

  group('applyImportPayload · 写前快照 + 失败回滚（TD-63）', () {
    test('第 N 键 setItem 抛错 → 前 N-1 键逆序回滚（原值还原 / 新增键移除）且异常上抛', () {
      final game = {
        ...gameExact,
        'saveKeys': ['ls_new_key', 'ls_autosave', 'ls_used_names', 'ls_bomb_key'],
      };
      final storage =
          FakeSaveStorage({'ls_autosave': 'old', 'ls_used_names': 'keep'});
      storage.setItemThrows['ls_bomb_key'] =
          StateError('QuotaExceededError'); // 第 4 键写入失败
      final keys = {
        'ls_new_key': '"new"', // 写前不存在 → 回滚应移除（新增键）
        'ls_autosave': '{"v":2}', // 写前 old → 回滚应还原原值
        'ls_used_names': '["b"]', // 写前 keep → 回滚应还原原值
        'ls_bomb_key': 'boom', // 抛错键本身未写入，无需回滚
      };
      expect(() => applyImportPayload(game, keys, storage),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('QuotaExceededError'))));
      expect(storage['ls_new_key'], isNull);
      expect(storage['ls_autosave'], 'old');
      expect(storage['ls_used_names'], 'keep');
      expect(storage['ls_bomb_key'], isNull);
    });

    test('回滚自身失败不遮蔽原始错误：单个键还原失败继续还原其余键（尽力而为，TD-73）', () {
      final game = {
        ...gameExact,
        'saveKeys': ['ls_key_a', 'ls_key_b', 'ls_key_c', 'ls_bomb'],
      };
      final originalErr = StateError('QuotaExceededError: 写入失败');
      final storage = FakeSaveStorage({'ls_key_b': 'old-b'}); // 仅 b 写前存在（a / c 为新增键）
      storage.setItemThrows['ls_bomb'] = originalErr; // 第 4 键写入失败（原始错误）
      storage.removeItemThrows['ls_key_c'] = StateError('回滚也失败'); // c 还原失败（回滚异常）
      final keys = {
        'ls_key_a': '"new-a"', // 写前不存在 → 回滚应 removeItem 移除
        'ls_key_b': '"new-b"', // 写前 old-b → 回滚应还原原值
        'ls_key_c': '"new-c"', // 写前不存在 → 回滚应移除，但 removeItem 抛错 → 残留新值
        'ls_bomb': 'boom', // 抛错键本身未写入，无需回滚
      };

      Object? caught;
      try {
        applyImportPayload(game, keys, storage);
      } catch (e) {
        caught = e;
      }
      expect(caught, same(originalErr)); // 原始错误同一性：回滚异常不遮蔽（TD-73）
      expect(storage['ls_key_a'], isNull); // 已写新键仍被 removeItem 还原（continue 语义）
      expect(storage['ls_key_b'], 'old-b'); // 更早写入的旧键继续还原为原值
      expect(storage['ls_key_c'], '"new-c"'); // 回滚也失败的键保持新值（尽力而为的既定残留）
      expect(storage['ls_bomb'], isNull);
    });
  });

  // ══════════════════════════════════════════════════
  // deleteGameKeys — 删除（确认由 UI 层负责）
  // ══════════════════════════════════════════════════

  group('deleteGameKeys · 清除全部命中键（主应用键不误伤）', () {
    test('删除全部白名单命中键并返回被删键名；cfg 键与主应用自身键不受影响', () {
      final storage = FakeSaveStorage({
        'ls_autosave': 'a',
        'ls_used_names': 'b',
        'ls_cfg': '{"apiKey":"sk"}',
        appOwnKey: '{"theme":"dark"}',
      });
      final removed = deleteGameKeys(gameExact, storage);
      expect(removed, ['ls_autosave', 'ls_used_names']);
      expect(storage['ls_autosave'], isNull);
      expect(storage['ls_used_names'], isNull);
      expect(storage['ls_cfg'], '{"apiKey":"sk"}');
      expect(storage[appOwnKey], '{"theme":"dark"}');
    });

    test('Falsify:game null / storage null → [] 不炸', () {
      expect(deleteGameKeys(null, FakeSaveStorage()), []);
      expect(deleteGameKeys(gameExact, null), []);
    });

    test('无命中键 → [] 且不触碰 removeItem（storage 内容不变）', () {
      final storage = FakeSaveStorage({'app_own': 'keep'});
      final before = storage.snapshot;
      expect(deleteGameKeys(gameExact, storage), []);
      expect(storage.snapshot, before);
    });
  });

  // ══════════════════════════════════════════════════
  // sanitizeFilename — 导出文件名净化（TD-65）
  // ══════════════════════════════════════════════════

  group('sanitizeFilename · 导出文件名净化（TD-65）', () {
    test('含引号/路径分隔符/控制字符/% 的 id → 净化（全部替换为 _）', () {
      // " \ / 控制字符 % — 全部应替换为 _
      expect(sanitizeFilename('a"b\\c/d\x01e%f'), 'a_b_c_d_e_f');
      expect(sanitizeFilename('a:b*c?e<g>h|i'), 'a_b_c_e_g_h_i');
    });

    test('尾部点与空格 → 修剪（净化边界：. 与空格尾缀剔除）', () {
      expect(sanitizeFilename('trail. '), 'trail');
      expect(sanitizeFilename('life-sim.'), 'life-sim');
    });

    test('空 id → 兜底 game（净化边界：空结果兜底）', () {
      expect(sanitizeFilename(''), 'game');
      expect(sanitizeFilename('...'), 'game'); // 全部被尾部修剪剔除 → 空 → game
      expect(sanitizeFilename('   '), 'game'); // 空格尾部修剪剔除 → 空 → game
    });

    test('非字符串 → game 防御（Falsify）', () {
      expect(sanitizeFilename(null), 'game');
      expect(sanitizeFilename(123), 'game');
    });

    test('正常 id 净化后不变（既有契约：<gameId>-saves.json 保持）', () {
      expect(sanitizeFilename('life-sim'), 'life-sim');
      expect(sanitizeFilename('twilight-witch'), 'twilight-witch');
      expect(sanitizeFilename('my-little-pony'), 'my-little-pony');
    });
  });

  // ══════════════════════════════════════════════════
  // maxImportBytes — 5MB 上限常量契约
  // ══════════════════════════════════════════════════

  group('maxImportBytes · 导入文件大小守卫上限', () {
    test('= 5 * 1024 * 1024（桌面 MAX_IMPORT_BYTES 逐字）', () {
      expect(maxImportBytes, 5 * 1024 * 1024);
    });
  });
}