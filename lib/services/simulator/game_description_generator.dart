/// 模拟器游戏简介 LLM 精修（本批次，混合方案）——仿 GameGenerator 链的轻量
/// 调用点：凭据经 `wireCredentialsResolver` 解析（装配闭包注入，不现造
/// CredentialsResolver）+ `LLMProviderFactory` 派生 provider + 非流式
/// `generate` 单次调用，产出 ≤ [maxRefinedChars] 字的中文一句话简介。
///
/// 与 GameGenerator 的差异：无校验/重试/落盘重机器（简介是一次性短文本，失败
/// 由调用方 [GameSummaryService] 降级保留规则简介）；prompt 输入为规则提取
/// 的 [GameSummaryCandidate]（见 `game_summary_extractor.dart`），避免把整个
/// 游戏 HTML（57~140KB）塞进上下文。
///
/// 协议表面（深模块）：`maxRefinedChars` / `maxSummaryTokens` /
/// `GameDescriptionCall` / `buildGameDescriptionPrompt` / `GameDescriptionGenerator`。
// ignore_for_file: prefer_initializing_formals — 构造为公开命名参数（装配点
// 语义）+ 私有 `_` 字段，initializing formal 无法同时满足两者（对齐
// game_generator.dart 同款惯例）。
library;

import '../llm/llm_provider.dart'
    show LLMProvider, LLMProviderFactory, LlmMessage;
import 'game_generator.dart' show GenerationCredentials;
import 'game_summary_extractor.dart' show GameSummaryCandidate;

/// LLM 精修简介最大长度（字符）——卡片三行显示区域，与规则简介同量级。
const int maxRefinedChars = 60;

/// 精修单次调用输出 token 上限（一句话简介，100 token 绰绰有余）。
const int maxSummaryTokens = 100;

/// LLM 原始回复 seam（生产默认包装 [LLMProvider.generate]；测试注入脚本化
/// fake 断言 prompt 与调用参数）。
typedef GameDescriptionCall =
    Future<String> Function({
      required LLMProvider provider,
      required String model,
      required GameSummaryCandidate candidate,
    });

/// 构造精修提示词：系统（一句话编辑 + 反虚构约束）+ 用户（游戏标题 / 界面
/// 文案 / 内容片段）。显式要求不用「AI 驱动 / 模拟器 / localStorage」等词——
/// 直接对治旧模板描述的呆板来源（manifest 内 22 款同句式 + 技术细节混入）。
String buildGameDescriptionPrompt(GameSummaryCandidate candidate) {
  final parts = <String>[
    '游戏标题：${candidate.title}',
    if (candidate.visibleText.isNotEmpty) '界面文案：${candidate.visibleText}',
    for (final snippet in candidate.promptSnippets) '内容片段：$snippet',
  ];
  return parts.join('\n\n');
}

/// 系统提示词：一句有特点的简介 + 只基于给定内容（防虚构/夸张）+ 输出格式。
String _systemPrompt() {
  return '你是一名游戏编辑，为模拟器列表的每款游戏写一句简介。要求：'
      '1. 一句话，中文，不超过 $maxRefinedChars 字；'
      '2. 有特点、有吸引力，说清「这是什么题材、玩什么」；'
      '3. 只依据给定内容写作，不要虚构或夸张游戏没有的内容；'
      '4. 不要使用「AI 驱动」「模拟器」「需配置」「localStorage」「接口」等'
      '技术词；'
      '5. 只输出简介本身，不要引号、标题或任何解释。';
}

/// LLM 简介精修服务——凭据解析 → provider 派生 → 单次生成 → 长度收敛。
///
/// 依赖全部构造注入（测试 embedded fake，永不触真实网络）：[providerFactory]
/// 复用 LLM 工厂（与聊天/生成同源）；[resolveCredentials] 复用凭据解析单点
/// （装配层 `_resolveGenerationCredentials`，S4 收敛）；[callRefine] 为 LLM
/// 回复 seam（生产缺省包装 `provider.generate`）。
///
/// 失败语义：LLM 调用异常经 provider 翻译链上抛（调用方捕获降级）；空回复 /
/// 纯空白回复 → 返回空串（调用方不写回）；成功 → 按 [maxRefinedChars] 截断
/// （按 Unicode 码点，不劈裂代理对）。
class GameDescriptionGenerator {
  /// 构造精修服务；[callRefine] 缺省包装 [LLMProvider.generate]。
  GameDescriptionGenerator({
    required LLMProviderFactory providerFactory,
    required Future<GenerationCredentials> Function() resolveCredentials,
    GameDescriptionCall? callRefine,
  }) : _providerFactory = providerFactory,
       _resolveCredentials = resolveCredentials,
       _callRefine = callRefine ?? _defaultCallRefine;

  final LLMProviderFactory _providerFactory;
  final Future<GenerationCredentials> Function() _resolveCredentials;
  final GameDescriptionCall _callRefine;

  /// 精修一句简介（非流式单次调用）。
  ///
  /// 凭据解析失败 / LLM 调用失败 → 原样上抛（LLMError 族，调用方降级）；回复
  /// 为空白 → 空串；成功 → 空白归一 + [maxRefinedChars] 截断。
  Future<String> refine(GameSummaryCandidate candidate) async {
    final credentials = await _resolveCredentials();
    final provider = _providerFactory.create(
      provider: credentials.provider,
      apiKey: credentials.apiKey,
      baseUrl: credentials.baseUrl,
    );
    final reply = await _callRefine(
      provider: provider,
      model: credentials.model,
      candidate: candidate,
    );
    final text = reply.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) {
      return '';
    }
    final runes = text.runes.toList();
    return runes.length <= maxRefinedChars
        ? text
        : String.fromCharCodes(runes.take(maxRefinedChars));
  }
}

/// 生产默认精修回复 seam：包装 [LLMProvider.generate]（system + user 两段）。
Future<String> _defaultCallRefine({
  required LLMProvider provider,
  required String model,
  required GameSummaryCandidate candidate,
}) {
  return provider.generate(
    messages: <LlmMessage>[
      LlmMessage(role: 'system', content: _systemPrompt()),
      LlmMessage(role: 'user', content: buildGameDescriptionPrompt(candidate)),
    ],
    maxTokens: maxSummaryTokens,
    model: model,
  );
}
