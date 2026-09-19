/// F-M5-08b 游戏生成测试辅助——按脚本播放的 fake LLM Provider。
///
/// 覆盖生成编排需要的三类路径（工单测试辅助自建要求）：
/// - 「第 N 次才过校验」：`scripts` 依次播放，首次坏 HTML / 第二次合法；
/// - 「恒失败」：全部脚本为坏 HTML；
/// - 非字符串防御：脚本项可为非 String 对象（[ScriptedFakeLLMProvider] 的
///   [generate] 为 String 返回类型，非字符串路径经 `GameGenerator.callGenerate`
///   seam 注入（见 `game_generator_test.dart`）——本 fake 承载字符串路径，
///   记录每次调用入参供断言（maxTokens=8192 + 消息结构 + 调用序）。
library;

import 'package:conver_system_mobile/services/llm/errors.dart' show LLMError;
import 'package:conver_system_mobile/services/llm/llm_provider.dart'
    show LLMProvider, LLMProviderFactory, LlmMessage;

/// 记录构造入参并恒返回同一 provider 的工厂 fake（[LLMProviderFactory] 抽象
/// 实现）——断言 provider 解析链（settings default_provider → factory 派生，
/// claude / openai 兼容双协议路径）与生成服务装配测试共用。
class FixedGenerationFactory implements LLMProviderFactory {
  FixedGenerationFactory(this.provider);

  /// 每次 [create] 返回的 provider 实例。
  final LLMProvider provider;

  /// 最近一次 [create] 收到的 provider 标识。
  String? lastProviderKey;

  /// 最近一次 [create] 收到的 apiKey。
  String? lastApiKey;

  /// 最近一次 [create] 收到的 baseUrl。
  String? lastBaseUrl;

  @override
  LLMProvider create({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) {
    lastProviderKey = provider;
    lastApiKey = apiKey;
    lastBaseUrl = baseUrl;
    return this.provider;
  }
}

/// 按调用序播放预制内容的 [LLMProvider] fake。
///
/// 第 N 次 [generate] 返回 `scripts[N-1]`；调用次数超出脚本长度后重复播放
/// 最后一个脚本（恒失败编排：单脚本坏 HTML 即每次失败）。
class ScriptedFakeLLMProvider extends LLMProvider {
  ScriptedFakeLLMProvider({required List<String> scripts})
      : _scripts = List<String>.unmodifiable(scripts),
        super(apiKey: 'test-key');

  ScriptedFakeLLMProvider.empty()
      : _scripts = const [],
        super(apiKey: 'test-key');

  final List<String> _scripts;

  /// 调用计数（含重试——断言编排实际尝试次数）。
  int callCount = 0;

  /// 最近一次 [generate] 收到的消息列表（断言 prompt 结构/cancel 语义）。
  List<LlmMessage>? lastMessages;

  /// 最近一次 [generate] 收到的 maxTokens（断言调用点传 8192）。
  int? lastMaxTokens;

  /// 最近一次 [generate] 收到的 model。
  String? lastModel;

  /// 非 null 时 [generate] 原样抛出该异常（模拟 LLM 调用失败传播路径）。
  Object? error;

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) async {
    callCount++;
    lastMessages = messages;
    lastMaxTokens = maxTokens;
    lastModel = model;
    final e = error;
    if (e != null) {
      throw e;
    }
    if (_scripts.isEmpty) {
      return '';
    }
    final index = callCount - 1;
    return index < _scripts.length ? _scripts[index] : _scripts.last;
  }

  @override
  Stream<String> streamRequest({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
    double temperature = 0.7,
  }) {
    throw UnimplementedError('生成路径不使用流式接口');
  }
}

/// 通过六项校验的合法生成 HTML（cfg- 三元组齐全 + GAME_SCENES 合法数组 +
/// 无残留模板标记 + 无可疑模式）——生成编排与对话框测试共用 fixture。
String buildValidGeneratedHtml({String title = '测试世界'}) {
  return '''<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>生成游戏</title></head>
<body>
<script>
(function(){
var GAME_CONFIG = {"title": "$title", "world": "测试世界观"};
var GAME_SCENES = [
  {"id": "start", "narrative": "你站在起点。", "choices": [{"text": "前进", "next": "end"}]},
  {"id": "end", "narrative": "这是结局。", "choices": []}
];
})();
</script>
<input type="hidden" id="cfg-endpoint">
<input type="hidden" id="cfg-apikey">
<input type="hidden" id="cfg-model">
</body>
</html>''';
}

/// 校验必失败（残留模板标记 + 场景缺失）的坏 HTML——重试/耗尽编排 fixture。
String buildInvalidGeneratedHtml() {
  return '''<!DOCTYPE html>
<html>
<body>
<script>
var GAME_CONFIG = <!-- GEN:config -->;
var GAME_SCENES = [];
</script>
</body>
</html>''';
}