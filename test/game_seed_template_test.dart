/// F-M5-08a 种子模板测试（锚桌面 `desktop/tests/test_game_template.py` 语义逐字）——
/// `GameSeedTemplate.seedTemplate` 逐字常量（含 `<!-- GEN:config -->` /
/// `<!-- GEN:scenes -->` 两标记、cfg- 三元组隐藏 input、引擎锚点）与
/// `markerPattern` 标记正则（大小写不敏感、拒绝无标记文本）。
///
/// 测试 seam（公共接口边界）：`GameSeedTemplate` 常量 + import 管线
/// [scanInputIds]（只读消费，验证模板渲染后的 cfg- 契约可被导入侧探测到）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/game_seed_template.dart';
import 'package:conver_system_mobile/services/simulator/import_service.dart'
    show scanInputIds;
import 'package:conver_system_mobile/services/simulator/suspicious_patterns.dart';

/// 将模板两标记替换为有效数据（模拟 LLM 填充后的最小合法生成物）。
String renderSeedTemplate() {
  const configJson = '{"title":"测试世界","world":"一个用于测试的世界"}';
  const scenesJson =
      '[{"id":"start","narrative":"你站在空地上。","choices":[]}]';
  return GameSeedTemplate.seedTemplate
      .replaceAll('<!-- GEN:config -->', configJson)
      .replaceAll('<!-- GEN:scenes -->', scenesJson);
}

/// 模板内 `var GAME_CONFIG = <!-- GEN:config -->;` 的替换锚行（渲染前）。
final RegExp _configAnchorRe =
    RegExp('var GAME_CONFIG\\s*=\\s*<!-- GEN:config -->\\s*;');
final RegExp _scenesAnchorRe =
    RegExp('var GAME_SCENES\\s*=\\s*<!-- GEN:scenes -->\\s*;');

void main() {
  group('markerPattern — 模板标记正则（桌面 MARKER_PATTERN 语义逐字）', () {
    test('匹配 <!-- GEN:config --> 与 <!-- GEN:scenes -->', () {
      expect(GameSeedTemplate.markerPattern.hasMatch('<!-- GEN:config -->'),
          isTrue);
      expect(GameSeedTemplate.markerPattern.hasMatch('<!-- GEN:scenes -->'),
          isTrue);
    });

    test('大小写不敏感（<!-- gen:scenes --> 同理命中）', () {
      expect(GameSeedTemplate.markerPattern.hasMatch('<!-- gen:scenes -->'),
          isTrue);
      expect(GameSeedTemplate.markerPattern.hasMatch('<!-- GeN:Config -->'),
          isTrue);
    });

    test('匹配多空白分隔形态（<!--\\s*GEN: 语义）', () {
      expect(GameSeedTemplate.markerPattern.hasMatch('<!--    GEN:config -->'),
          isTrue);
      expect(GameSeedTemplate.markerPattern.hasMatch('<!--\tGEN:scenes-->'),
          isTrue);
    });

    test('不匹配无标记的普通文本', () {
      expect(GameSeedTemplate.markerPattern.hasMatch('no marker here'),
          isFalse);
      expect(GameSeedTemplate.markerPattern.hasMatch('config'), isFalse);
    });

    test('不匹配 GEN: 但缺注释形态的文本', () {
      expect(GameSeedTemplate.markerPattern.hasMatch('GEN:config'), isFalse);
      expect(GameSeedTemplate.markerPattern.hasMatch('ex: <!-- gen -->'),
          isFalse);
    });
  });

  group('cfgRequiredIds — cfg- 三元组契约', () {
    test('恰为 cfg-endpoint / cfg-apikey / cfg-model 三键', () {
      expect(
        GameSeedTemplate.cfgRequiredIds,
        {'cfg-endpoint', 'cfg-apikey', 'cfg-model'},
      );
      expect(GameSeedTemplate.cfgRequiredIds.length, 3);
    });
  });

  group('seedTemplate — 种子模板逐字锚（桌面 game_template.py）', () {
    test('含两注入标记 <!-- GEN:config --> 与 <!-- GEN:scenes -->', () {
      expect(GameSeedTemplate.seedTemplate, contains('<!-- GEN:config -->'));
      expect(GameSeedTemplate.seedTemplate, contains('<!-- GEN:scenes -->'));
    });

    test('标记位于 var GAME_CONFIG / var GAME_SCENES 赋值行（可注入占位符）', () {
      expect(GameSeedTemplate.seedTemplate, matches(_configAnchorRe));
      expect(GameSeedTemplate.seedTemplate, matches(_scenesAnchorRe));
    });

    test('含 cfg- 三元组三隐藏 input（key-injector 探测用）', () {
      final html = GameSeedTemplate.seedTemplate;
      expect(html, contains('<input type="hidden" id="cfg-endpoint">'));
      expect(html, contains('<input type="hidden" id="cfg-apikey">'));
      expect(html, contains('<input type="hidden" id="cfg-model">'));
    });

    test('含引擎锚点 btn-save / btn-load / btn-restart 与渲染区', () {
      final html = GameSeedTemplate.seedTemplate;
      expect(html, contains('<button id="btn-save"'));
      expect(html, contains('<button id="btn-load"'));
      expect(html, contains('<button id="btn-restart"'));
      expect(html, contains('id="game-narrative"'));
      expect(html, contains('id="game-choices"'));
      expect(html, contains('id="game-world"'));
    });

    test('以 <!DOCTYPE html> 开头并含 <html>（structure 检查恒过）', () {
      final trimmed = GameSeedTemplate.seedTemplate.trimLeft();
      expect(trimmed.startsWith('<!DOCTYPE html>'), isTrue);
      expect(GameSeedTemplate.seedTemplate, contains('<html'));
      expect(GameSeedTemplate.seedTemplate, contains('</html>'));
    });

    test('渲染标记后 cfg- 三元组可被导入侧 scanInputIds 探测到（消费面锚）', () {
      final rendered = renderSeedTemplate();
      final ids = scanInputIds(rendered);
      for (final cid in GameSeedTemplate.cfgRequiredIds) {
        expect(ids, contains(cid), reason: '渲染后应可探测到 $cid');
      }
      // 渲染后的 GAME_SCENES 为有效 JSON 数组（替换无残留标记）
      expect(GameSeedTemplate.markerPattern.hasMatch(rendered), isFalse);
    });

    test('自包含引擎零外部依赖：无外链脚本/样式且无密钥字面量', () {
      final html = GameSeedTemplate.seedTemplate;
      expect(html.toLowerCase(), isNot(contains('<script src=')));
      expect(html.toLowerCase(), isNot(contains('<link href=')));
      expect(html.toLowerCase(), isNot(contains('https://')));
      expect(html.toLowerCase(), isNot(contains('sk-')));
      expect(html.toLowerCase(), isNot(contains('api_key')));
      expect(html.toLowerCase(), isNot(contains('token')));
    });

    test('模板自身不含任意恶意模式（scanSuspicious 零命中）', () {
      final hits = <String>[];
      for (final key in SuspiciousPatterns.keys) {
        if (SuspiciousPatterns.patternFor(key)
            .hasMatch(GameSeedTemplate.seedTemplate)) {
          hits.add(key);
        }
      }
      expect(hits, isEmpty);
    });

    test('占位符替换后 GAME_CONFIG/GAME_SCENES 为可解析 JSON（模版契约闭环）', () {
      final rendered = renderSeedTemplate();
      final configMatch = RegExp(
        r'''var GAME_CONFIG\s*=\s*(\{.*?\})\s*;''',
        dotAll: true,
      ).firstMatch(rendered);
      final scenesMatch = RegExp(
        r'''var GAME_SCENES\s*=\s*(\[.*?\])\s*;''',
        dotAll: true,
      ).firstMatch(rendered);
      expect(configMatch, isNotNull);
      expect(scenesMatch, isNotNull);
      final config = json.decode(configMatch!.group(1)!);
      expect(config, isA<Map<String, dynamic>>());
      final scenes = json.decode(scenesMatch!.group(1)!);
      expect(scenes, isA<List<dynamic>>());
      expect(scenes, hasLength(1));
    });
  });
}