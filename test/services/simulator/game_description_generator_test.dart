/// 模拟器简介 LLM 精修单测（本批次）——脚本化 fake LLM（ScriptedFakeLLMProvider
/// + FixedGenerationFactory）断言：prompt 结构（system + user 含候选内容）/
/// 凭据派生（provider/key/baseUrl 透传）/ 长度收敛 / 空回复 → 空串 / LLM
/// 错误上抛（调用方降级）。
library;

import 'package:conver_system_mobile/services/llm/errors.dart' show LLMError;
import 'package:conver_system_mobile/services/simulator/game_description_generator.dart';
import 'package:conver_system_mobile/services/simulator/game_generator.dart'
    show GenerationCredentials;
import 'package:conver_system_mobile/services/simulator/game_summary_extractor.dart'
    show GameSummaryCandidate;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_llm_for_generation.dart';

/// 样例候选（蛛网之影同构）。
const _candidate = GameSummaryCandidate(
  title: '蛛网之影 · 蜘蛛侠世界观AI角色扮演',
  visibleText: '角色 回档 攻略',
  promptSnippets: ['世界观：你在纽约街头行侠仗义，能力越大责任越大。'],
);

({GameDescriptionGenerator generator, FixedGenerationFactory factory}) _build(
  ScriptedFakeLLMProvider llm, {
  Object? resolveError,
}) {
  final factory = FixedGenerationFactory(llm);
  return (
    generator: GameDescriptionGenerator(
      providerFactory: factory,
      resolveCredentials: () async {
        if (resolveError != null) {
          throw resolveError;
        }
        return const GenerationCredentials(
          provider: 'openai',
          apiKey: 'k',
          model: 'm',
        );
      },
    ),
    factory: factory,
  );
}

void main() {
  group('GameDescriptionGenerator.refine', () {
    test('脚本回复 → 原样返回（截断边界内）', () async {
      const script = '在纽约夜色中行侠仗义的义警成长故事';
      final llm = ScriptedFakeLLMProvider(scripts: const [script]);
      final built = _build(llm);

      final result = await built.generator.refine(_candidate);

      expect(result, script);
      expect(llm.callCount, 1);
      // 凭据派生：provider/key/baseUrl 经 factory 透传。
      expect(built.factory.lastProviderKey, 'openai');
      expect(built.factory.lastApiKey, 'k');
      expect(built.factory.lastBaseUrl, isNull);
      final lastMessages = llm.lastMessages!;
      expect(lastMessages.first.role, 'system');
      expect(lastMessages.first.content, contains('不要使用「AI 驱动」'));
      expect(lastMessages.last.role, 'user');
      expect(lastMessages.last.content, contains('蛛网之影'));
      expect(lastMessages.last.content, contains('纽约街头行侠仗义'));
      expect(llm.lastMaxTokens, maxSummaryTokens);
      expect(llm.lastModel, 'm');
    });

    test('超长回复 → 按码点截断 ≤ maxRefinedChars（不劈裂代理对）', () async {
      final long = '${'精' * 30}😀${'彩' * 30}'; // 61+ 码点 > 60
      final llm = ScriptedFakeLLMProvider(scripts: [long]);
      final built = _build(llm);

      final result = await built.generator.refine(_candidate);

      expect(result.runes.length, lessThanOrEqualTo(maxRefinedChars));
      final lastCodeUnit = result.isNotEmpty
          ? result.codeUnitAt(result.length - 1)
          : 0;
      expect(
        lastCodeUnit < 0xD800 || lastCodeUnit > 0xDFFF,
        isTrue,
        reason: '截断不得劈裂代理对',
      );
    });

    test('空 / 纯空白回复 → 空串（调用方不写回）', () async {
      final llm = ScriptedFakeLLMProvider(scripts: const ['   \n  ']);
      final built = _build(llm);

      expect(await built.generator.refine(_candidate), '');
    });

    test('LLM 调用错误 → 上抛 LLMError 族（调用方捕获降级）', () async {
      final llm = ScriptedFakeLLMProvider(scripts: const ['x']);
      llm.error = LLMError('fake 调用失败');
      final built = _build(llm);

      await expectLater(
        built.generator.refine(_candidate),
        throwsA(isA<LLMError>()),
      );
    });

    test('凭据解析失败 → 原样上抛，不触发 LLM 调用', () async {
      final llm = ScriptedFakeLLMProvider(scripts: const ['x']);
      final built = _build(llm, resolveError: StateError('无 key'));

      await expectLater(
        built.generator.refine(_candidate),
        throwsA(isA<StateError>()),
      );
      expect(llm.callCount, 0);
    });
  });

  group('buildGameDescriptionPrompt', () {
    test('含标题/界面文案/内容片段，空段不占行', () {
      final prompt = buildGameDescriptionPrompt(_candidate);
      expect(prompt, contains('游戏标题：蛛网之影'));
      expect(prompt, contains('界面文案：'));
      expect(prompt, contains('内容片段：'));

      final minimal = buildGameDescriptionPrompt(
        const GameSummaryCandidate(
          title: '仙途',
          visibleText: '',
          promptSnippets: [],
        ),
      );
      expect(minimal, '游戏标题：仙途');
    });
  });
}
