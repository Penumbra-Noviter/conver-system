/// F-M5-08b 游戏生成服务测试——prompt 三件套 / 六项校验重试编排 ≤3 / 非字符串
/// 防御 / 取消中止 / 落盘 source=generated（F-M5-07 管线消费）集成。
///
/// 测试 seam（公共接口边界）：[GameGenerator]（providerFactory / resolveCredentials
/// / resolveSimDir / callGenerate / persistGame 五依赖注入，fake LLM 编排
/// 「第 N 次才过 / 恒失败 / 非字符串」路径），永不触真实网络与平台通道。
///
/// 锚桌面 `desktop/backend/app/services/game_generator.py`：
/// - prompt 三件套（_build_system_prompt / _build_user_prompt / _build_retry_prompt）
///   逐字或语义等价（种子模板引用 `GameSeedTemplate.seedTemplate` 单源）；
/// - 重试编排（MAX_RETRIES=3，总 attempt ≤4；校验错误 + 建议 + 上次 HTML 前
///   1000 字符折回 prompt）；
/// - 3a 非字符串防御分支（计一次失败并重试 / 耗尽后结构化错误）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/llm/llm_provider.dart'
    show LLMProvider, LlmMessage;
import 'package:conver_system_mobile/services/simulator/game_generator.dart'
    show
        GameGenerator,
        GenerationCredentials,
        buildRetryPrompt,
        buildSuggestion,
        buildSystemPrompt,
        buildUserPrompt,
        generatedFallbackName,
        maxGenerateTokens,
        maxGenerationRetries,
        sanitizeTitle;
import 'package:conver_system_mobile/services/simulator/game_seed_template.dart'
    show GameSeedTemplate;
import 'package:conver_system_mobile/services/simulator/generated_game_validator.dart'
    show GenValidationError;
import 'package:conver_system_mobile/services/simulator/import_service.dart'
    show importGame;
import 'package:conver_system_mobile/services/simulator/manifest_parser.dart'
    show parseManifest;
import 'package:conver_system_mobile/services/simulator/simulator_data_dir.dart'
    show SimulatorDataDir;
import 'package:conver_system_mobile/services/simulator/simulator_server.dart'
    show SimulatorServer;
import 'package:conver_system_mobile/view_models/simulators_controller.dart'
    show SimulatorsController, SimulatorGame, SimulatorGameSource,
        SimulatorsState;

import 'support/fake_llm_for_generation.dart'
    show
        FixedGenerationFactory,
        ScriptedFakeLLMProvider,
        buildInvalidGeneratedHtml,
        buildValidGeneratedHtml;

/// 校验必失败 HTML（残留模板标记 + 场景缺失）——本文件旧名兼容引用，
/// 实现单源在 support。
String buildInvalidHtml() => buildInvalidGeneratedHtml();

/// 最小游戏生成器装配（测试 seam 全注入；测试按需覆写个别依赖）。
GameGenerator buildGenerator({
  ScriptedFakeLLMProvider? provider,
  FixedGenerationFactory? factory,
  required Future<GenerationCredentials> Function() resolveCredentials,
  Future<Directory> Function()? resolveSimDir,
  Future<Object?> Function({
    required LLMProvider provider,
    required List<LlmMessage> messages,
    required int maxTokens,
    required String model,
  })?
      callGenerate,
}) {
  final resolvedFactory =
      factory ?? FixedGenerationFactory(provider ?? ScriptedFakeLLMProvider.empty());
  return GameGenerator(
    providerFactory: resolvedFactory,
    resolveCredentials: resolveCredentials,
    resolveSimDir: resolveSimDir ??
        () async => Directory.systemTemp.createTemp('gen-sim-'),
    callGenerate: callGenerate,
    persistGame: (simDir, filename, content) =>
        importGame(simDir, filename, content, source: 'generated'),
  );
}

void main() {
  group('Prompt 三件套（锚桌面 game_generator.py，种子模板单源引用）', () {
    test('buildSystemPrompt：种子模板逐字内嵌 + 填充规则全部覆盖', () {
      final prompt = buildSystemPrompt();
      expect(prompt, contains(GameSeedTemplate.seedTemplate),
          reason: '种子模板经 GameSeedTemplate.seedTemplate 单源插值');
      // 填充规则语义（桌面 _build_system_prompt 逐字）。
      expect(prompt, contains('<!-- GEN:config --> → JSON 对象'));
      expect(prompt, contains('<!-- GEN:scenes --> → JSON 数组'));
      expect(prompt, contains('场景数量：至少 3 个'));
      expect(prompt, contains('不超过 15 个'));
      expect(prompt, contains('终局场景（如结局、胜利、失败）的 choices 为空数组 []'));
      expect(prompt, contains('输出**只包含完整 HTML**'));
      expect(prompt, contains('**不要修改模板中已有的 HTML 结构和 CSS 样式**'));
    });

    test('buildUserPrompt：标题可选（无标题不含标题行，有标题逐字）', () {
      final withTitle = buildUserPrompt('一个雾中的小镇', '迷雾镇');
      expect(withTitle, contains('游戏标题：迷雾镇'));
      expect(withTitle, contains('世界观描述：\n一个雾中的小镇'));

      final withoutTitle = buildUserPrompt('一个雾中的小镇', null);
      expect(withoutTitle, isNot(contains('游戏标题：')));
      expect(withoutTitle, contains('一个雾中的小镇'));
    });

    test('buildRetryPrompt：原始描述 + 校验错误 + 建议 + 上次 HTML 前 1000 字符折回',
        () {
      final errors = [
        const GenValidationError(field: 'data', message: '场景数据 JSON 解析失败'),
        const GenValidationError(field: 'cfg', message: '缺少 AI 配置输入框'),
      ];
      final suggestion = '请修正场景数据；请确保 cfg- 三元组存在。';
      final longHtml = buildInvalidHtml() + 'x' * 2000;
      final prompt = buildRetryPrompt(
        '一个雾中的小镇',
        '迷雾镇',
        errors,
        suggestion,
        longHtml,
      );
      expect(prompt, contains('游戏标题：迷雾镇'));
      expect(prompt, contains('一个雾中的小镇'));
      expect(prompt, contains('  - [data] 场景数据 JSON 解析失败'));
      expect(prompt, contains('  - [cfg] 缺少 AI 配置输入框'));
      expect(prompt, contains(suggestion));
      // 上次 HTML 前 1000 字符折回（含尾部省略号），完整文本不整段入 prompt。
      expect(prompt, contains('${longHtml.substring(0, 1000)}...'));
      expect(prompt, isNot(contains(longHtml.substring(1001))));
    });

    test('buildRetryPrompt：短 HTML（≤1000 字符）原样折回', () {
      final shortHtml = buildInvalidHtml();
      final prompt = buildRetryPrompt(
        '描述',
        null,
        const [GenValidationError(field: 'structure', message: '缺骨架')],
        '建议',
        shortHtml,
      );
      expect(prompt, contains('$shortHtml...'));
      expect(prompt, isNot(contains('游戏标题：')));
    });
  });

  group('buildSuggestion（锚桌面 _build_suggestion 逐字段）', () {
    test('六字段建议文案逐字', () {
      final s = buildSuggestion(const [
        GenValidationError(field: 'structure', message: '缺骨架'),
        GenValidationError(field: 'template', message: '残留标记'),
        GenValidationError(field: 'cfg', message: '缺三元组'),
        GenValidationError(field: 'syntax', message: '语法错误'),
        GenValidationError(field: 'data', message: '数据错误'),
        GenValidationError(field: 'security', message: '可疑代码'),
      ]);
      expect(s, contains('请确保生成的 HTML 以 <!DOCTYPE html> 开头'));
      expect(s, contains('请确保已替换所有 <!-- GEN:config --> 和 <!-- GEN:scenes --> 标记'));
      expect(s, contains('请确保模板中的 cfg-endpoint、cfg-apikey、cfg-model 三个 input 元素未被删除'));
      expect(s, contains('请修复 HTML 语法错误：语法错误'));
      expect(s, contains('请修正场景数据：数据错误'));
      expect(s, contains('请移除可疑代码：可疑代码'));
    });

    test('空错误列表 → 通用回退文案', () {
      expect(buildSuggestion(const []), '请重新生成，确保模板标记被正确替换。');
    });
  });

  group('sanitizeTitle（只保留 Unicode 文字/空格/连字符，空回退 generated-game）', () {
    test('剔除标点/emoji/符号，保留中文与数字与连字符', () {
      expect(sanitizeTitle('我的 游戏!@# 2024'), '我的 游戏 2024');
      expect(sanitizeTitle('星空-探索 冒险🚀'), '星空-探索 冒险');
      expect(sanitizeTitle('hello_world'), 'hello_world');
    });

    test('空 / 全剔除 / 纯空白 → generated-game', () {
      expect(sanitizeTitle(''), generatedFallbackName);
      expect(sanitizeTitle('!!!🚀@@@'), generatedFallbackName);
      expect(sanitizeTitle('   '), generatedFallbackName);
      expect(sanitizeTitle('？'), generatedFallbackName);
    });
  });

  group('GameGenerator 常量（锚桌面 MAX_RETRIES=3 / max_tokens=8192）', () {
    test('重试上限与生成 token 上限', () {
      expect(maxGenerationRetries, 3);
      expect(maxGenerateTokens, 8192);
      expect(generatedFallbackName, 'generated-game');
    });
  });

  group('GameGenerator.generate 编排（首试 / 重试 / 耗尽 / 防御 / 取消）', () {
    late Directory simDir;

    setUp(() async {
      simDir = await Directory.systemTemp.createTemp('m5-08b-gen-');
    });

    tearDown(() async {
      if (await simDir.exists()) {
        await simDir.delete(recursive: true);
      }
    });

    GenerationCredentials credentials({
      String provider = 'claude',
      String key = 'sk-test-key',
    }) {
      return GenerationCredentials(
        provider: provider,
        apiKey: key,
        model: 'claude-sonnet-5',
      );
    }

    test('首试通过 → ok=true + retries=0 + 真实落盘 source=generated + '
        '调用点断言（maxTokens=8192 / 消息结构 / provider 解析链）', () async {
      final fake = ScriptedFakeLLMProvider(
        scripts: [buildValidGeneratedHtml()],
      );
      final factory = FixedGenerationFactory(fake);
      final generator = buildGenerator(
        factory: factory,
        resolveCredentials: () async => credentials(),
      );
      final result = await generator.generate(
        description: '一个雾中的小镇',
        title: '迷雾镇',
      );

      expect(result.ok, isTrue);
      expect(result.retries, 0);
      expect(result.errors, isNull);
      expect(result.game?['source'], 'generated',
          reason: '落盘条目携带 source=generated（列表 badge 判定依据）');
      expect(result.game?['name'], '迷雾镇',
          reason: '标题净化进文件名（stem 即 manifest name）');

      // LLM 调用点：provider 解析链（settings default_provider → factory）+ 8192。
      expect(factory.lastProviderKey, 'claude');
      expect(factory.lastApiKey, 'sk-test-key');
      expect(fake.lastMaxTokens, maxGenerateTokens,
          reason: 'generate 调用必须显式传 maxTokens: 8192');
      final messages = fake.lastMessages!;
      expect(messages, hasLength(2));
      expect(messages[0].role, 'system');
      expect(messages[0].content, contains(GameSeedTemplate.seedTemplate));
      expect(messages[1].role, 'user');
      expect(messages[1].content, contains('游戏标题：迷雾镇'));
      expect(messages[1].content, contains('一个雾中的小镇'));
    });

    test('openai 兼容 provider（deepseek）→ factory 派生链 + 生成全流程可用',
        () async {
      final fake = ScriptedFakeLLMProvider(
        scripts: [buildValidGeneratedHtml(title: '星海')],
      );
      final factory = FixedGenerationFactory(fake);
      final generator = buildGenerator(
        factory: factory,
        resolveCredentials: () async =>
            credentials(provider: 'deepseek', key: 'sk-ds-key'),
      );
      final result = await generator.generate(description: '星海远征');

      expect(result.ok, isTrue);
      expect(factory.lastProviderKey, 'deepseek',
          reason: 'openai 兼容 provider 双协议路径均通');
      expect(fake.lastMaxTokens, maxGenerateTokens);
    });

    test('真实落盘：文件落盘 + manifest 原子注册 source=generated', () async {
      final generator = buildGenerator(
        provider: ScriptedFakeLLMProvider(
          scripts: [buildValidGeneratedHtml()],
        ),
        resolveCredentials: () async => credentials(),
        resolveSimDir: () async => simDir,
      );
      final result = await generator.generate(description: '海边村庄');
      expect(result.ok, isTrue, reason: '校验通过 → 落盘成功');

      final htmlFile = File(
        '${simDir.path}${Platform.pathSeparator}$generatedFallbackName.html',
      );
      expect(htmlFile.existsSync(), isTrue,
          reason: '无标题 → 默认文件名 generated-game.html');
      expect(
        htmlFile.readAsStringSync(),
        buildValidGeneratedHtml(),
        reason: '落盘字节 = 生成 HTML 原样（UTF-8）',
      );

      final manifest = json.decode(
        File(
          '${simDir.path}${Platform.pathSeparator}manifest.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      final entry = (manifest['simulators'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      expect(entry['source'], 'generated');
      expect(entry['file'], '$generatedFallbackName.html');
      expect(entry['type'], 'ai',
          reason: '种子模板含 cfg- 三元组 → probe_config 判 ai');
    });

    test('标题净化链：装饰字符剔除 + F-M5-07 二次净化兜底', () async {
      final generator = buildGenerator(
        provider: ScriptedFakeLLMProvider(
          scripts: [buildValidGeneratedHtml()],
        ),
        resolveCredentials: () async => credentials(),
        resolveSimDir: () async => simDir,
      );
      final result =
          await generator.generate(description: '冒险', title: '我的 世界🚀!!');
      expect(result.game?['name'], '我的 世界',
          reason: '净化只保留 Unicode 文字/空格/连字符');
      expect(result.game?['file'], '我的 世界.html');
    });

    test('校验失败第 2 次通过 → retries=1 + 重试 prompt 折叠（错误+建议+'
        '上次 HTML 折回）', () async {
      final fake = ScriptedFakeLLMProvider(
        scripts: [buildInvalidHtml(), buildValidGeneratedHtml()],
      );
      final factory = FixedGenerationFactory(fake);
      final generator = buildGenerator(
        factory: factory,
        resolveCredentials: () async => credentials(),
        resolveSimDir: () async => simDir,
      );
      final result =
          await generator.generate(description: '迷雾小镇', title: '雾镇');

      expect(fake.callCount, 2, reason: '首试 + 1 次重试');
      expect(result.ok, isTrue);
      expect(result.retries, 1);
      expect(result.game?['source'], 'generated');

      // 第二次调用（重试）的 user prompt = buildRetryPrompt 语义：
      // 原始描述 + 校验错误 [field] message + 建议 + 上次 HTML 前 1000 字符。
      final retryUser = fake.lastMessages![1].content;
      expect(retryUser, contains('你之前生成的游戏未通过校验'));
      expect(retryUser, contains('迷雾小镇'));
      expect(retryUser, contains('游戏标题：雾镇'));
      expect(retryUser, contains('  - [template]'));
      expect(retryUser, contains('  - [data]'));
      expect(retryUser, contains('请确保已替换所有 <!-- GEN:config -->'));
      expect(retryUser, contains('请修正场景数据'));
      final badHtml = buildInvalidHtml();
      final head =
          badHtml.length > 1000 ? badHtml.substring(0, 1000) : badHtml;
      expect(retryUser, contains('$head...'),
          reason: '上次 HTML 前 1000 字符折回重试 prompt');
      // 重试 prompt 的 system 依旧 = 种子模板单源（三件套稳定）。
      expect(fake.lastMessages![0].content, contains(GameSeedTemplate.seedTemplate));
    });

    test('恒失败耗尽：首试 + 3 重试共 4 次 attempt → ok=false + 全部错误 + '
        '逐条建议 + retries 报告总尝试', () async {
      final fake = ScriptedFakeLLMProvider(
        scripts: [buildInvalidHtml()],
      );
      final generator = buildGenerator(
        factory: FixedGenerationFactory(fake),
        resolveCredentials: () async => credentials(),
        resolveSimDir: () async => simDir,
      );
      final result =
          await generator.generate(description: '注定失败的生成');

      expect(fake.callCount, maxGenerationRetries + 1,
          reason: '首试 + 最多 3 次重试 = 总 attempt ≤4（锚桌面 MAX_RETRIES=3）');
      expect(result.ok, isFalse);
      expect(result.game, isNull);
      expect(result.retries, maxGenerationRetries + 1);
      expect(result.errors, isNotNull);
      expect(result.errors, isNotEmpty);
      expect(
        result.errors!.map((e) => e.field),
        containsAll(['template', 'data']),
        reason: '坏 HTML 校验收集全部错误（残留标记 + 场景缺失）不中断',
      );
      expect(result.suggestion, contains('请确保已替换所有 <!-- GEN:config -->'),
          reason: '模板字段建议');
      expect(result.suggestion, contains('请修正场景数据'),
          reason: '数据字段建议');
    });

    test('非字符串返回（防御 3a）：第 2 次正常 → 消耗 1 次重试成功', () async {
      var calls = 0;
      final generator = buildGenerator(
        factory: FixedGenerationFactory(ScriptedFakeLLMProvider.empty()),
        resolveCredentials: () async => credentials(),
        resolveSimDir: () async => simDir,
        callGenerate:
            ({required provider, required messages, required maxTokens, required model}) async {
          calls++;
          if (calls == 1) {
            return <String, int>{'unexpected': 1}; // 非字符串对象
          }
          return buildValidGeneratedHtml();
        },
      );
      final result = await generator.generate(description: '海底世界');

      expect(calls, 2, reason: '非字符串消耗一次重试后第 2 次成功');
      expect(result.ok, isTrue);
      expect(result.retries, 1);
      expect(result.game?['source'], 'generated');
    });

    test('非字符串恒失败耗尽 → 结构化错误（data 字段）', () async {
      var calls = 0;
      final generator = buildGenerator(
        factory: FixedGenerationFactory(ScriptedFakeLLMProvider.empty()),
        resolveCredentials: () async => credentials(),
        resolveSimDir: () async => simDir,
        callGenerate:
            ({required provider, required messages, required maxTokens, required model}) async {
          calls++;
          return 12345; // 非字符串
        },
      );
      final result = await generator.generate(description: '数字回复');

      expect(calls, maxGenerationRetries + 1, reason: '防御分支同样受 ≤3 重试约束');
      expect(result.ok, isFalse);
      expect(result.errors!.single.field, 'data');
      expect(result.errors!.single.message, contains('LLM 返回了非字符串类型'));
      expect(result.retries, maxGenerationRetries + 1);
    });

    test('取消语义：重试序列中断言 true → 中止后续重试，不泄漏在途调用',
        () async {
      final fake = ScriptedFakeLLMProvider(
        scripts: [buildInvalidHtml(), buildValidGeneratedHtml()],
      );
      var checked = 0;
      final generator = buildGenerator(
        factory: FixedGenerationFactory(fake),
        resolveCredentials: () async => credentials(),
        resolveSimDir: () async => simDir,
      );
      final result = await generator.generate(
        description: '用户取消的生成',
        isCancelled: () {
          checked++;
          return checked > 1; // 第 2 次检查（重试前）返回 true
        },
      );

      expect(fake.callCount, 1, reason: '取消后不再发起下一次 LLM 调用');
      expect(result.ok, isFalse);
      expect(result.errors!.single.field, 'cancel');
      expect(result.retries, 1,
          reason: '取消发生在前重试轮：报告已执行的尝试数（首试）');
    });

    test('取消语义：首次尝试前取消 → 零 LLM 调用', () async {
      final fake = ScriptedFakeLLMProvider(scripts: [buildValidGeneratedHtml()]);
      final generator = buildGenerator(
        factory: FixedGenerationFactory(fake),
        resolveCredentials: () async => credentials(),
        resolveSimDir: () async => simDir,
      );
      final result = await generator.generate(
        description: '立即取消',
        isCancelled: () => true,
      );
      expect(fake.callCount, 0);
      expect(result.ok, isFalse);
      expect(result.errors!.single.field, 'cancel');
    });

    test('集成断言：落盘后 manifest 可被 parseManifest 读到且列表刷新可见'
        '（source=generated → 生成 badge 判定依据）', () async {
      final generator = buildGenerator(
        provider: ScriptedFakeLLMProvider(scripts: [buildValidGeneratedHtml()]),
        resolveCredentials: () async => credentials(),
        resolveSimDir: () async => simDir,
      );
      final result =
          await generator.generate(description: '新世界', title: '熔炉之城');
      expect(result.ok, isTrue);

      // 1. manifest 原子写后条目含 source=generated。
      final rawManifest = File(
        '${simDir.path}${Platform.pathSeparator}manifest.json',
      ).readAsStringSync();
      final decoded = json.decode(rawManifest) as Map<String, dynamic>;
      final entries =
          (decoded['simulators'] as List).cast<Map<String, dynamic>>();
      expect(entries.single['source'], 'generated');
      expect(entries.single['name'], '熔炉之城',
          reason: 'name 保留原始标题（中文不被净化链破坏）');
      expect(entries.single['file'], '熔炉之城.html');
      expect(entries.single['id'], isA<String>(),
          reason: 'id 为导入管线确定性值（中文标题 slug 回退为 F-M5-07 既定行为）');

      // 2. manifest 文本可被 F-M5-03 parseManifest 宽容解析 → 归一化条目。
      final parsed = parseManifest(rawManifest);
      expect(parsed.ok, isTrue);
      final game = SimulatorGame.fromManifest(parsed.games!.single);
      expect(game.source, SimulatorGameSource.generated,
          reason: 'SimulatorsController 列表可见判据（「生成」badge）');
      expect(game.name, '熔炉之城');

      // 3. 集成 SimulatorsController.refresh：注入的 manifest 拉取读真实盘面
      //    → 布局游戏集含 generated 条目（列表刷新可见路径）。
      final seed = _SeedStub();
      final server = _GenStubServer();
      final controller = SimulatorsController(
        dataDir: SimulatorDataDir(
          resolveDocumentsDir: () async => simDir.parent,
        ),
        seed: seed.call,
        createServer: (_) => server,
        loadManifest: (port) async {
          final text = File(
            '${simDir.path}${Platform.pathSeparator}manifest.json',
          ).readAsStringSync();
          return parseManifest(text);
        },
        port: 0,
      );
      addTearDown(controller.dispose);
      await controller.ensureStarted();
      expect(controller.state, isNot(SimulatorsState.error));
      expect(
        controller.games.any(
          (g) => g.source == SimulatorGameSource.generated,
        ),
        isTrue,
        reason: '生成结果刷新后列表可见（generated badge 语义）',
      );
      expect(controller.games.single.name, '熔炉之城');
    });
  });
}

/// 幂等种子桩（列表编排集成用；不计调用语义，返回 false = 已种子）。
class _SeedStub {
  Future<bool> call(Directory simDir) async => false;
}

/// 服务器桩（复用 W3 测试模式：真实监听能力不在生成编排范围）。
class _GenStubServer extends SimulatorServer {
  _GenStubServer() : super(Directory.systemTemp);

  bool _running = false;

  @override
  Future<int> start({required int port}) async {
    _running = true;
    return port;
  }

  @override
  Future<void> stop() async {}

  @override
  bool get isRunning => _running;
}
