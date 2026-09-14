/// 模拟器 AI 生成服务（F-M5-08b）——LLM 直连编排 + prompt 三件套 + 六项校验
/// 重试 ≤3 + 落盘复用导入管线（source=generated）。
///
/// 桌面权威源（只读，语义逐字锚点）：`desktop/backend/app/services/game_generator.py`
/// （`_build_system_prompt` / `_build_user_prompt` / `_build_retry_prompt` /
/// `_build_suggestion` / `_sanitize_title` / `MAX_RETRIES` / max_tokens=8192 /
/// `_generate_with_retry` 编排含 3a 非字符串防御分支）。
///
/// 与桌面的形态差异（语义等价）：
/// - **temperature 用默认 0.7（U-2 更新 R8）**：移动端 `LLMProvider.generate`
///   现具备 temperature 参数（U-2 补入，OpenAI 透传 / Claude 忽略），生成路径
///   调用零改动（不显式传 temperature，取默认 0.7），单温度由 provider 口径决定，
///   重试收敛靠「校验错误 + 修正建议」折回 prompt 而非降温（记入 spec §4.2
///   决策 9 与 grilling-consensus D4）；
/// - **强类型非字符串防御**：桌面 reply 为动态值经 `isinstance(reply, str)`
///   判定；移动端 `LLMProvider.generate` 强类型返回 `Future<String>`，为忠实
///   桌面 3a 防御分支（LLM 返回非字符串 → 计一次失败重试/耗尽返回结构化错误），
///   以 [GenerateHtmlReply] seam 表达「LLM 原始回复」（生产包装 `generate`
///   恒为 String，测试注入非字符串对象驱动防御分支）；
/// - **T-03 单次扫描（移动端形态）**：桌面 `scan_generated_html` 一次打包
///   probe_config + scan_suspicious 供校验闸门与 import_game 复用；移动端
///   import_service 为固定管线（本票只读消费），单次扫描语义在本编排内实现
///   ——`scanSuspicious` 一次计算后经 [GeneratedValidationError.precomputedWarnings]
///   传入校验闸门检查 5，避免生成路径内双重扫描。
/// - **取消语义**（移动端新增）：重试序列中取消 → 中止后续重试（不再发起
///   LLM 调用），返回 cancel 结构化结果给 UI 关闭对话框。
///
/// 协议表面（深模块）：`maxGenerationRetries` / `maxGenerateTokens` /
/// `generatedFallbackName` / `generatedDescriptionFallback` / `generatedSource` /
/// `GenerationCredentials` / `GenerateResult` / `buildSystemPrompt` /
/// `buildUserPrompt` / `buildRetryPrompt` / `buildSuggestion` / `sanitizeTitle` /
/// `deriveGeneratedDescription` / `GameGenerator`。
// ignore_for_file: prefer_initializing_formals — 构造为公开命名参数（装配点
// 语义）+ 私有 `_` 字段，initializing formal 无法同时满足两者（对齐
// simulators_controller.dart 同款惯例）。
library;

import 'dart:io';
import 'dart:convert';

import '../llm/llm_provider.dart'
    show LLMProvider, LLMProviderFactory, LlmMessage;
import 'game_seed_template.dart' show GameSeedTemplate;
import 'generated_game_validator.dart'
    show GenValidationError, validateGeneratedHtml;
import 'import_service.dart'
    show
        ImportResult,
        SimulatorDuplicateError,
        importGame,
        readManifestOrRebuild,
        scanSuspicious,
        writeManifest;

/// 最大重试次数（校验失败后重试打磨；桌面 MAX_RETRIES 逐字）——总尝试
/// attempt ≤ 首试 + maxGenerationRetries = 4。
const int maxGenerationRetries = 3;

/// 单次生成输出 token 上限（桌面 max_tokens=8192 逐字；移动端 LLMProvider
/// 默认 2048 不够生成完整游戏，调用点必须显式传入）。
const int maxGenerateTokens = 8192;

/// 默认文件名（无标题或标题净化后为空时回退；桌面 _FALLBACK_NAME 逐字）。
const String generatedFallbackName = 'generated-game';

/// 生成游戏列表卡片描述兜底文案（F-47：LLM 产出空 world 描述时使用，列表
/// 卡片 description 恒非空）。
const String generatedDescriptionFallback = 'AI 生成的模拟器游戏';

/// 生成游戏在 manifest 中的 source 标记（列表「生成」badge 判定依据；
/// 桌面 GENERATED_SOURCE 逐字）。
const String generatedSource = 'generated';

/// 生成所需的 LLM 会话凭据（provider 来自 settings default_provider，key 经
/// SecretStore/SettingsRepository 解析链，base_url 经 settings 协议链）。
class GenerationCredentials {
  const GenerationCredentials({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.baseUrl,
  });

  /// LLM provider 标识（claude / openai 兼容协议键）。
  final String provider;

  /// API Key（SecretStore 槽位经 SettingsRepository 解析）。
  final String apiKey;

  /// 生成模型名。
  final String model;

  /// 自定义端点（openai 协议链 base_url；null = provider 官方默认端点）。
  final String? baseUrl;
}

/// 生成结果值对象（ok/game/errors/suggestion/retries）。
///
/// - ok=true：game 为已落盘 manifest 条目（含 source=generated）；
/// - ok=false：errors 为校验失败错误列表 / 非字符串错误 / 取消信号
///   （field='cancel'） / **409「已存在」语义**（field='duplicate'，终止重试），
///   suggestion 为修正建议；retries 语义：成功 = 此前失败次数，失败耗尽 =
///   总尝试次数，取消 / 已存在 = 已执行的尝试数。
class GenerateResult {
  const GenerateResult({
    required this.ok,
    this.game,
    this.errors,
    this.suggestion,
    required this.retries,
  });

  /// 是否生成成功（校验全部通过且已落盘）。
  final bool ok;

  /// 成功时落盘后的 manifest 条目（含 source=generated）。
  final Map<String, dynamic>? game;

  /// 失败时的校验错误列表 / 结构化错误 / 取消信号。
  final List<GenValidationError>? errors;

  /// 失败时的修正建议（供 UI 展示 + 重试 prompt 折叠）。
  final String? suggestion;

  /// 实际使用的重试次数（桌面 GenerateResult.retries 语义）。
  final int retries;
}

/// 取消判定回调（重试序列中断言；true = 中止后续重试）。
typedef GenerationCancellation = bool Function();

/// LLM 原始回复 seam（桌面 llm.generate 动态 reply 的移动端等价物）：
/// 生产不注入（默认包装 [LLMProvider.generate]，恒返回 String）；测试注入
/// 返回非字符串对象以驱动桌面 3a 防御分支。
typedef GenerateHtmlReply = Future<Object?> Function({
  required LLMProvider provider,
  required List<LlmMessage> messages,
  required int maxTokens,
  required String model,
});

/// 生成落盘 seam（生产默认经 F-M5-07 [importGame] source=generated 编排；
/// 测试注入 fake 断言落盘入参）。
typedef PersistGeneratedGame = Future<ImportResult> Function(
  Directory simDir,
  String filename,
  List<int> content,
);

/// 构造系统提示词——种子模板 + 填充规则 + 示例（桌面 `_build_system_prompt`
/// 逐字语义；种子模板经 `GameSeedTemplate.seedTemplate` 单源插值，引用于
/// 校验闸门同款常量不上字面量）。
String buildSystemPrompt() {
  return '你是一个叙事游戏生成器。你的任务是根据用户提供的世界观描述，'
      '生成一个完整的 HTML 叙事选择游戏。\n\n'
      '## 种子模板\n\n'
      '以下是完整游戏模板。你需要替换其中的两个标记 <!-- GEN:config --> '
      '和 <!-- GEN:scenes --> 为实际数据。**不要修改模板中已有的 HTML 结构'
      '和 CSS 样式**。\n\n'
      '```\n${GameSeedTemplate.seedTemplate}\n```\n\n'
      '## 填充规则\n\n'
      '### 1. <!-- GEN:config --> → JSON 对象\n\n'
      '替换为以下格式的 JSON（**不要包含注释标记**，直接写 JSON）：\n'
      '{"title": "游戏标题（根据用户描述生成）", "world": '
      '"世界观简介（1-3 句话概括世界背景）"}\n\n'
      '### 2. <!-- GEN:scenes --> → JSON 数组\n\n'
      '替换为场景数据数组，每个场景的格式：\n'
      '{"id": "场景唯一标识（英文字母/数字/下划线）", "narrative": '
      '"叙事文本（描述当前场景的所见所闻所感，1-4 段）", "choices": '
      '[{"text": "选项文本", "next": "目标场景 id"}]}\n\n'
      '## 要求\n\n'
      '1. 场景数量：至少 3 个，建议 5-8 个，不超过 15 个\n'
      '2. 每个场景至少 1 个选项，最多 5 个选项\n'
      '3. 终局场景（如结局、胜利、失败）的 choices 为空数组 []\n'
      '4. 所有选项的 next 值必须指向已存在的场景 id\n'
      '5. 叙事文本要生动、有沉浸感，与世界观一致\n'
      '6. 输出**只包含完整 HTML**，不要添加任何解释或额外文字\n'
      '7. **不要修改模板中已有的 HTML 结构和 CSS 样式**\n\n'
      '## 示例\n\n'
      '用户描述：「一个发生在魔法学院的冒险故事，学生发现了一个秘密通道」\n\n'
      '<!-- GEN:config --> 替换为：\n'
      '{"title":"魔法学院秘道探险","world":"在一所古老的魔法学院中，流传着'
      '一个关于秘密通道的传说。据说通道通往学院最深的秘密，但从未有人走完'
      '全程。"}\n\n'
      '<!-- GEN:scenes --> 替换为：\n'
      '[\n'
      '    {"id": "start", "narrative": "夜深了，你站在图书馆三楼的书架间。'
      '月光透过彩色玻璃窗洒在地板上，照亮了墙壁上的一幅古老挂毯——传说秘密'
      '通道的入口就在这幅挂毯后面。\\n\\n你听到远处传来巡逻的脚步声。", '
      '"choices": [{"text": "掀起挂毯看看", "next": "tunnel"}, '
      '{"text": "先躲进旁边的空教室", "next": "classroom"}]},\n'
      '    {"id": "tunnel", "narrative": "你掀起挂毯，发现后面确实有一扇暗门。'
      '轻轻一推，门开了，露出一条向下延伸的石阶。墙壁上的火把自动亮起，仿佛'
      '在欢迎你。\\n\\n石阶很窄，只能容一人通过。空气中弥漫着潮湿的泥土气息。", '
      '"choices": [{"text": "沿着石阶走下去", "next": "crypt"}, '
      '{"text": "回到图书馆再想想", "next": "start"}]}\n'
      ']';
}

/// 构造用户提示词（桌面 `_build_user_prompt` 逐字：标题可选 + 世界观描述）。
String buildUserPrompt(String description, String? title) {
  final parts = <String>[];
  if (title != null && title.trim().isNotEmpty) {
    parts.add('游戏标题：$title');
  }
  parts.add('世界观描述：\n$description');
  return parts.join('\n\n');
}

/// 构造重试提示词（桌面 `_build_retry_prompt` 逐字）——原始描述 + 上次 HTML
/// 前 1000 字符 + 校验错误 `[field] message` + 修正建议。
String buildRetryPrompt(
  String description,
  String? title,
  List<GenValidationError> errors,
  String suggestion,
  String previousHtml,
) {
  final errorLines = errors
      .map((err) => '  - [${err.field}] ${err.message}')
      .join('\n');
  final titleLine = (title != null && title.trim().isNotEmpty)
      ? '游戏标题：$title\n'
      : '';
  final htmlHead = previousHtml.length > 1000
      ? previousHtml.substring(0, 1000)
      : previousHtml;
  return '你之前生成的游戏未通过校验，需要修正后重新生成。\n\n'
      '## 原始世界观描述\n\n'
      '$titleLine$description\n\n'
      '## 上次生成的 HTML（有问题的版本）\n\n'
      '```\n$htmlHead...\n```\n\n'
      '## 校验错误\n\n'
      '$errorLines\n\n'
      '## 修正建议\n\n'
      '$suggestion\n\n'
      '请重新生成完整的 HTML，修正以上所有错误。';
}

/// 根据校验错误生成修正建议（桌面 `_build_suggestion` 逐字段中文文案）；
/// 空错误列表 → 通用回退文案。
String buildSuggestion(List<GenValidationError> errors) {
  final suggestions = <String>[];
  for (final err in errors) {
    switch (err.field) {
      case 'structure':
        suggestions.add(
          '请确保生成的 HTML 以 <!DOCTYPE html> 开头，包含 '
          '<html>、<head>、<body> 标签。',
        );
      case 'template':
        suggestions.add(
          '请确保已替换所有 <!-- GEN:config --> 和 '
          '<!-- GEN:scenes --> 标记为实际数据，不要保留任何注释标记。',
        );
      case 'cfg':
        suggestions.add(
          '请确保模板中的 cfg-endpoint、cfg-apikey、cfg-model '
          '三个 input 元素未被删除。',
        );
      case 'syntax':
        suggestions.add('请修复 HTML 语法错误：${err.message}');
      case 'data':
        suggestions.add('请修正场景数据：${err.message}');
      case 'security':
        suggestions.add('请移除可疑代码：${err.message}');
    }
  }
  return suggestions.isEmpty ? '请重新生成，确保模板标记被正确替换。' : suggestions.join('；');
}

/// 将标题净化（文件名干，可读性层接口）——只保留 Unicode 文字/数字字符、
/// 空格、连字符（桌面 `_sanitize_title` 逐字：剔除标点/emoji 等装饰字符）；
/// 净化后为空或全装饰 → 回退 [generatedFallbackName]。
///
/// F-48 定版（净化增强）：装饰字符剥离后追加归一化——连续空白压缩为单空格、
/// 连续连字符压缩为单连字符、首尾 `-`/`_`/空白装饰剥除——使净化结果不再产出
/// 「纯分隔符」或「残留双空格」等怪文件名（manifest name 与 slug 派生 id 的
/// 可读口径一致）。
///
/// 这是「可读性」层，不是安全层：下游 F-M5-07 `importGame` 内部的
/// sanitizeFilename 会再做保留名 / 字节截断等安全净化（二次净化兜底）。
String sanitizeTitle(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[^\p{L}\p{N}_\s-]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[\s_-]+|[\s_-]+$'), '')
      .trim();
  return cleaned.isEmpty ? generatedFallbackName : cleaned;
}

/// 从生成 HTML 提取 GAME_CONFIG JSON 对象文本（含两端花括号；括号配对 +
/// 字符串字面量跳过，与校验层 `extractScenesLiteral` 同口径）。定位失败或
/// 括号不闭合 → null。
String? _extractConfigLiteral(String htmlText) {
  final match = RegExp(r'(?:var|const|let)\s+GAME_CONFIG\s*=\s*\{')
      .firstMatch(htmlText);
  if (match == null) {
    return null;
  }
  var i = match.end - 1; // 指向 '{'
  var depth = 0;
  String? quote; // 当前字符串引号态（" / ' / `）；null = 不在字符串内
  final n = htmlText.length;
  while (i < n) {
    final ch = htmlText[i];
    if (quote != null) {
      if (ch == r'\') {
        i += 2; // 跳过转义序列（可能为转义引号）
        continue;
      }
      if (ch == quote) {
        quote = null;
      }
      i += 1;
      continue;
    }
    if (ch == '"' || ch == "'" || ch == '`') {
      quote = ch;
    } else if (ch == '{') {
      depth += 1;
    } else if (ch == '}') {
      depth -= 1;
      if (depth == 0) {
        return htmlText.substring(match.end - 1, i + 1);
      }
    }
    i += 1;
  }
  return null;
}

/// 派生生成游戏描述（F-47 空描述兜底）——取生成 HTML 内嵌 GAME_CONFIG 的
/// `world`（世界观简介）作为列表卡片 description；world 缺失 / 空串 /
/// 配置定位或解析失败 → 回退 [generatedDescriptionFallback]（LLM 产出空
/// 描述时卡片不显示空白）。
String deriveGeneratedDescription(String html) {
  final raw = _extractConfigLiteral(html);
  if (raw == null) {
    return generatedDescriptionFallback;
  }
  final Object? decoded;
  try {
    decoded = json.decode(raw);
  } on FormatException {
    return generatedDescriptionFallback;
  }
  if (decoded is! Map<String, dynamic>) {
    return generatedDescriptionFallback;
  }
  final world = decoded['world'];
  if (world is! String || world.trim().isEmpty) {
    return generatedDescriptionFallback;
  }
  return world.trim();
}

/// AI 生成游戏服务（编排：凭据解析 → prompt 三件套 → LLM 直连 → 六项校验 →
/// 重试 ≤3 → 落盘 source=generated）。
///
/// 依赖全部构造注入（测试 embedded fake，永不触真实网络 / 平台通道）：
/// [providerFactory] 生产 [LLMFactory]，测试 Fixed 工厂断言双协议派生；
/// [resolveCredentials] 生产 SettingsRepository + SecretStore 解析链；
/// [resolveSimDir] 生产数据目录解析；[callGenerate] LLM 原始回复 seam（生产
/// 缺省包装 `provider.generate`）；[persistGame] 生产默认 [importGame]
/// source=generated。
class GameGenerator {
  /// 构造生成服务；生产默认 [persistGame] 经 [importGame]（source=generated）
  /// 落盘，[callGenerate] 缺省包装 [LLMProvider.generate]。
  GameGenerator({
    required LLMProviderFactory providerFactory,
    required Future<GenerationCredentials> Function() resolveCredentials,
    required Future<Directory> Function() resolveSimDir,
    GenerateHtmlReply? callGenerate,
    PersistGeneratedGame? persistGame,
  }) : _providerFactory = providerFactory,
       _resolveCredentials = resolveCredentials,
       _resolveSimDir = resolveSimDir,
       _callGenerate = callGenerate ?? _defaultCallGenerate,
       _persistGame = persistGame ?? _defaultPersistGame;

  final LLMProviderFactory _providerFactory;
  final Future<GenerationCredentials> Function() _resolveCredentials;
  final Future<Directory> Function() _resolveSimDir;
  final GenerateHtmlReply _callGenerate;
  final PersistGeneratedGame _persistGame;

  /// 生成游戏（主编排入口）。
  ///
  /// [description] 世界观描述（必填，空串直接失败）；[title] 可选标题（用于
  /// 文件名与 user prompt）；[isCancelled] 取消判定（重试序列中 true → 中止
  /// 后续重试并返回 cancel 结果，不泄漏在途调用）。LLM 调用错误 / 凭据解析
  /// 错误为传播语义（对齐桌面 `Raises LLMError`），由调用方统一处理。
  Future<GenerateResult> generate({
    required String description,
    String? title,
    GenerationCancellation? isCancelled,
  }) {
    return _generateWithRetry(description, title, isCancelled: isCancelled);
  }

  /// 重试编排（对齐桌面 `_generate_with_retry`；自递归不暴露参数）。
  Future<GenerateResult> _generateWithRetry(
    String description,
    String? title, {
    GenerationCancellation? isCancelled,
    String? previousHtml,
    List<GenValidationError>? previousErrors,
    String? previousSuggestion,
    int retriesLeft = maxGenerationRetries,
    int attempted = 0,
  }) async {
    if (isCancelled?.call() ?? false) {
      return GenerateResult(
        ok: false,
        errors: const [GenValidationError(field: 'cancel', message: '已取消生成')],
        retries: attempted,
      );
    }

    final credentials = await _resolveCredentials();
    final provider = _providerFactory.create(
      provider: credentials.provider,
      apiKey: credentials.apiKey,
      baseUrl: credentials.baseUrl,
    );

    // 2. 构造 prompt（首次 = user；重试 = retry 折叠反馈）。
    final userPrompt = (previousHtml != null && previousErrors != null)
        ? buildRetryPrompt(
            description,
            title,
            previousErrors,
            previousSuggestion ?? '',
            previousHtml,
          )
        : buildUserPrompt(description, title);

    final messages = <LlmMessage>[
      LlmMessage(role: 'system', content: buildSystemPrompt()),
      LlmMessage(role: 'user', content: userPrompt),
    ];

    // 3. 调用 LLM（maxTokens 显式 8192——与移动端默认 2048 冲突敏感面）。
    final reply = await _callGenerate(
      provider: provider,
      messages: messages,
      maxTokens: maxGenerateTokens,
      model: credentials.model,
    );

    // 3a. 防御：LLM 返回非字符串 → 计一次失败重试或耗尽返回结构化错误。
    if (reply is! String) {
      final error = GenValidationError(
        field: 'data',
        message: 'LLM 返回了非字符串类型：${reply.runtimeType}',
      );
      if (retriesLeft <= 0) {
        return GenerateResult(
          ok: false,
          errors: [error],
          suggestion: '请重试',
          retries: attempted + 1,
        );
      }
      return _generateWithRetry(
        description,
        title,
        isCancelled: isCancelled,
        previousHtml: reply?.toString(),
        previousErrors: [error],
        previousSuggestion: '请确保 LLM 配置正确并重试',
        retriesLeft: retriesLeft - 1,
        attempted: attempted + 1,
      );
    }

    // 4. 六项校验闸门（T-03 单次扫描：scanSuspicious 一次 → precomputedWarnings
    // 复用，生成路径内不双重扫描）。
    final warnings = scanSuspicious(reply);
    final errors = validateGeneratedHtml(reply, precomputedWarnings: warnings);

    if (errors.isEmpty) {
      // F-46 取消令牌：在途 LLM 响应迟到返回时，落盘前再次断言取消——取消后
      // 迟到成功不落盘（用户见「已取消」但游戏不得出现）；对齐 TD-2 F-34 导入
      // 超时取消令牌模式（isCancelled 仅作为中止信号，不硬性取消底层调用）。
      if (isCancelled?.call() ?? false) {
        return GenerateResult(
          ok: false,
          errors: const [GenValidationError(field: 'cancel', message: '已取消生成')],
          retries: attempted,
        );
      }
      // 校验通过 → 落盘（source=generated）。F-45：落盘触发 SHA 去重 409
      // （生成内容与既有游戏完全相同）→ 识别为「已存在」结构化结果并终止重试
      // （重试只会再产出相同内容，无收敛价值）；不再向调用方抛原始异常以免
      // UI 落入「LLM 失败文案 + 无限重试」循环。
      final Map<String, dynamic> game;
      try {
        game = await _persistGenerated(reply, title);
      } on SimulatorDuplicateError {
        return GenerateResult(
          ok: false,
          errors: const [
            GenValidationError(
              field: 'duplicate',
              message: '已存在相同游戏（内容与现有游戏相同）',
            ),
          ],
          retries: attempted,
        );
      }
      return GenerateResult(ok: true, game: game, retries: attempted);
    }

    // 5. 校验失败 → 重试或返回错误。
    if (retriesLeft <= 0) {
      return GenerateResult(
        ok: false,
        errors: errors,
        suggestion: buildSuggestion(errors),
        retries: attempted + 1,
      );
    }
    return _generateWithRetry(
      description,
      title,
      isCancelled: isCancelled,
      previousHtml: reply,
      previousErrors: errors,
      previousSuggestion: buildSuggestion(errors),
      retriesLeft: retriesLeft - 1,
      attempted: attempted + 1,
    );
  }

  /// 校验通过 → 落地：标题净化 + 文件名 {title}.html → [importGame]
  /// source=generated 落盘 + manifest 注册。
  ///
  /// F-49：文件名恒为 `{stem}.html`——`sanitizeTitle` 字符集不含 `.`（装饰字符
  /// 剥离层），`stem.endsWith('.html')` 条件恒假，原分支为死代码；桌面
  /// `_persist_generated_game` 同口径（`f"{name}.html"` 无条件拼接）。
  ///
  /// F-47：落盘后按生成 HTML 的 GAME_CONFIG.world 派生列表卡片 description
  /// （world 缺失/空 → 兜底文案 [generatedDescriptionFallback]），补写回
  /// manifest 条目——LLM 产出空描述时列表卡片不显示空白。
  Future<Map<String, dynamic>> _persistGenerated(
    String html,
    String? title,
  ) async {
    final stem = sanitizeTitle(title ?? '');
    final filename = '$stem.html';
    final simDir = await _resolveSimDir();
    final result = await _persistGame(simDir, filename, utf8.encode(html));
    final game = Map<String, dynamic>.from(result.game);
    game['description'] = deriveGeneratedDescription(html);
    _updateManifestEntryDescription(simDir, game);
    return game;
  }

  /// 将派生 description 补写回 sim_dir/manifest.json 对应条目（F-47）——幂等：
  /// 条目不存在 / 已一致 / id 缺失均不写盘（读操作经 [readManifestOrRebuild]
  /// 自带自愈口径，与导入链一致）。
  void _updateManifestEntryDescription(
    Directory simDir,
    Map<String, dynamic> game,
  ) {
    final Object? id = game['id'];
    final Object? description = game['description'];
    if (id is! String || description is! String) {
      return;
    }
    final manifest = readManifestOrRebuild(simDir);
    final simulators = manifest['simulators'];
    if (simulators is! List) {
      return;
    }
    for (final entry in simulators) {
      if (entry is Map && entry['id'] == id) {
        if (entry['description'] == description) {
          return; // 幂等：已一致不重写
        }
        entry['description'] = description;
        writeManifest(simDir, manifest);
        return;
      }
    }
  }
}

/// 生产默认 LLM 回复 seam：包装 [LLMProvider.generate]（恒返回 String）。
Future<Object?> _defaultCallGenerate({
  required LLMProvider provider,
  required List<LlmMessage> messages,
  required int maxTokens,
  required String model,
}) {
  return provider.generate(
    messages: messages,
    maxTokens: maxTokens,
    model: model,
  );
}

/// 生产默认落盘：F-M5-07 [importGame] source=`generated`。
Future<ImportResult> _defaultPersistGame(
  Directory simDir,
  String filename,
  List<int> content,
) {
  return importGame(simDir, filename, content, source: generatedSource);
}
