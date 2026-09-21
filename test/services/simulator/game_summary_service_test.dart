/// 模拟器简介编排服务单测（本批次）——真实临时目录 + import_service 写路径：
/// 规则简介同步写回（onlyIfEmpty 不覆盖既有描述）/ 精修开关门控 / 精修替换
/// 写回 + 刷新回调 / 精修失败与空回复降级保留规则简介 / id 缺失零副作用。
library;

import 'dart:io';

import 'package:conver_system_mobile/services/simulator/game_description_generator.dart'
    show GameDescriptionGenerator;
import 'package:conver_system_mobile/services/simulator/game_generator.dart'
    show GenerationCredentials;
import 'package:conver_system_mobile/services/simulator/game_summary_service.dart'
    show GameSummaryService;
import 'package:conver_system_mobile/services/simulator/import_service.dart'
    show readManifest, writeManifest;
import 'package:conver_system_mobile/services/llm/errors.dart' show LLMError;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_llm_for_generation.dart';

/// 含 prompt 设定段的样例游戏 HTML（规则提取必有 fallback）。
const _htmlWithPrompt = '<html><head><title>测试游戏 · 赛博义警</title></head>'
    '<body><script>const W="世界观：赛博朋克都市里，你是一名义体医生。";'
    '</script><button>开始</button></body></html>';

void main() {
  late Directory simDir;

  setUp(() async {
    simDir = await Directory.systemTemp.createTemp('summary-svc-');
  });

  tearDown(() async {
    if (await simDir.exists()) {
      await simDir.delete(recursive: true);
    }
  });

  void writeManifestWith(List<Map<String, dynamic>> entries) {
    writeManifest(simDir, {'version': 2, 'simulators': entries});
  }

  String? descriptionOf(String id) {
    final manifest = readManifest(simDir);
    for (final entry in manifest['simulators'] as List) {
      if ((entry as Map)['id'] == id) {
        return entry['description'] as String?;
      }
    }
    return null;
  }

  GameSummaryService buildService({
    required ScriptedFakeLLMProvider llm,
    required bool refineEnabled,
    required void Function() onRefined,
  }) {
    return GameSummaryService(
      generator: GameDescriptionGenerator(
        providerFactory: FixedGenerationFactory(llm),
        resolveCredentials: () async => const GenerationCredentials(
          provider: 'openai',
          apiKey: 'k',
          model: 'm',
        ),
      ),
      llmRefinementEnabled: () async => refineEnabled,
      onDescriptionRefined: onRefined,
    );
  }

  const entry = <String, dynamic>{
    'id': 'game-1',
    'file': 'game-1.html',
    'name': 'game-1',
    'type': 'ai',
    'source': 'imported',
  };

  group('summarizeOnImport', () {
    test('规则简介同步写回（精修关闭：零 LLM 调用）', () async {
      writeManifestWith([entry]);
      final llm = ScriptedFakeLLMProvider(scripts: const ['精修文案']);
      final refined = <int>[];
      final service = buildService(
        llm: llm,
        refineEnabled: false,
        onRefined: () => refined.add(1),
      );

      service.summarizeOnImport(simDir: simDir, game: entry, html: _htmlWithPrompt);

      expect(descriptionOf('game-1'), isNotEmpty);
      expect(descriptionOf('game-1'), contains('赛博朋克'));
      expect(llm.callCount, 0, reason: '精修开关关闭不得触发 LLM 调用');
      expect(refined, isEmpty);
    });

    test('精修开启：异步替换写回 + 刷新回调，规则简介被替换', () async {
      writeManifestWith([entry]);
      final llm = ScriptedFakeLLMProvider(scripts: const ['精修后的简介']);
      final refined = <int>[];
      final service = buildService(
        llm: llm,
        refineEnabled: true,
        onRefined: () => refined.add(1),
      );

      service.summarizeOnImport(simDir: simDir, game: entry, html: _htmlWithPrompt);
      // 同步段：规则简介已写回。
      expect(descriptionOf('game-1'), isNotEmpty);
      // 等待异步精修链完成（纯 Dart 微任务 + 零定时器）。
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(descriptionOf('game-1'), '精修后的简介');
      expect(llm.callCount, 1);
      expect(refined, [1]);
    });

    test('精修失败（LLM 错误）→ 保留规则简介，不崩、不回调', () async {
      writeManifestWith([entry]);
      final llm = ScriptedFakeLLMProvider(scripts: const ['x']);
      llm.error = LLMError('fake 失败');
      final refined = <int>[];
      final service = buildService(
        llm: llm,
        refineEnabled: true,
        onRefined: () => refined.add(1),
      );

      service.summarizeOnImport(simDir: simDir, game: entry, html: _htmlWithPrompt);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(descriptionOf('game-1'), isNotEmpty, reason: '降级保留规则简介');
      expect(descriptionOf('game-1'), contains('赛博朋克'));
      expect(refined, isEmpty);
    });

    test('精修空回复 → 保留规则简介，不回调', () async {
      writeManifestWith([entry]);
      final llm = ScriptedFakeLLMProvider(scripts: const ['   ']);
      final refined = <int>[];
      final service = buildService(
        llm: llm,
        refineEnabled: true,
        onRefined: () => refined.add(1),
      );

      service.summarizeOnImport(simDir: simDir, game: entry, html: _htmlWithPrompt);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(descriptionOf('game-1'), contains('赛博朋克'));
      expect(refined, isEmpty);
    });

    test('条目已有描述 → onlyIfEmpty 不覆盖；精修开启仍可替换', () async {
      writeManifestWith([
        {...entry, 'description': '既有描述'},
      ]);
      final llm = ScriptedFakeLLMProvider(scripts: const ['精修后的简介']);
      final refined = <int>[];
      final service = buildService(
        llm: llm,
        refineEnabled: true,
        onRefined: () => refined.add(1),
      );

      service.summarizeOnImport(simDir: simDir, game: entry, html: _htmlWithPrompt);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(descriptionOf('game-1'), '精修后的简介');
      expect(refined, [1]);
    });

    test('精修开启 + 开关关闭组合：规则简介保留且零 LLM 调用（开关读取幂等）',
        () async {
      writeManifestWith([entry]);
      final llm = ScriptedFakeLLMProvider(scripts: const ['x']);
      final service = buildService(
        llm: llm,
        refineEnabled: false,
        onRefined: () {},
      );

      service.summarizeOnImport(simDir: simDir, game: entry, html: _htmlWithPrompt);
      await Future<void>.delayed(Duration.zero);

      expect(descriptionOf('game-1'), contains('赛博朋克'));
      expect(llm.callCount, 0);
    });

    test('id 缺失 → 零副作用（不写 manifest 不调 LLM）', () async {
      writeManifestWith([entry]);
      final llm = ScriptedFakeLLMProvider(scripts: const ['x']);
      final service = buildService(
        llm: llm,
        refineEnabled: true,
        onRefined: () {},
      );

      service.summarizeOnImport(
        simDir: simDir,
        game: const <String, dynamic>{'file': 'x.html'},
        html: _htmlWithPrompt,
      );
      await Future<void>.delayed(Duration.zero);

      expect(descriptionOf('game-1'), isNull);
      expect(llm.callCount, 0);
    });

    test('规则提取全空（纯 CSS HTML）→ 不写回也不调 LLM', () async {
      writeManifestWith([entry]);
      final llm = ScriptedFakeLLMProvider(scripts: const ['x']);
      final service = buildService(
        llm: llm,
        refineEnabled: true,
        onRefined: () {},
      );

      service.summarizeOnImport(
        simDir: simDir,
        game: entry,
        html: '<style>body{color:#fff}</style>',
      );
      await Future<void>.delayed(Duration.zero);

      expect(descriptionOf('game-1'), isNull);
      expect(llm.callCount, 0);
    });
  });
}
