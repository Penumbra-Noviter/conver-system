/// 凭据解析链（credential resolution chain）— 主应用 LLM 凭据组合序的单一
/// 归属模块（AR-3 r3-credentials-resolver）。
///
/// 桌面权威源（只读，语义逐字锚点）：`desktop/backend/app/services/llm/resolver.py`
/// （`resolve_llm`）——本模块为移动端对该**单点组合形态**的复刻：provider 缺省/
/// 覆盖优先级 → apiKey 槽链（同协议 → 跨协议兜底）→ 空抛 `ApiKeyMissingError`
/// → base_url 空归一 → model 缺省/覆盖回退，四步组合只存在于本模块。
///
/// 深模块契约（纯 Dart，零 I/O / 零 flutter / 零数据层依赖）：四 reader 注入
/// （`defaultProvider` / `defaultModel` / `apiKey(provider)` / `baseUrl(provider)`），
/// 槽链原语与 Provider 工厂派生**留在消费方原语层**——本模块只收「组合序 +
/// 空 key 抛点」。Key 注入契约变体（`services/simulator/injection.dart`：
/// openai-only / no-throw / TD-66 门控）为**另一独立单源**，本模块不吸收其
/// 语义（claude key 恒不进游戏红线保持由注入契约独享）。
library;

import 'errors.dart';

// 构造为公开命名参数（四 reader 装配点语义）+ 私有 `_` 字段：initializing
// formal 无法同时满足两者，整文件抑制该 lint（对齐 document_parse_service /
// game_generator 等装配类同款惯例）。
// ignore_for_file: prefer_initializing_formals

/// 解析完成的凭据数据记录（生成/聊天消费点分装 Provider 前的最小数据面）。
class ResolvedCredentials {
  /// 构造凭据记录；[baseUrl] 为 null = 使用 provider 官方默认端点。
  const ResolvedCredentials({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.baseUrl,
  });

  /// 解析后的 provider 键（覆盖优先，否则 defaultProvider 回退）。
  final String provider;

  /// 解析后的 API Key（经槽链 reader；非空保证——空 key 在 [CredentialsResolver]
  /// 内已抛 [ApiKeyMissingError]，本字段不可能为空串）。
  final String apiKey;

  /// 模型名（覆盖优先，否则 defaultModel 回退）。
  final String model;

  /// 自定义端点 base URL；空串归一为 null（null = 官方默认端点）。
  final String? baseUrl;
}

/// 主应用 LLM 凭据组合序的单一归属解析器（镜像桌面 `resolver.py::resolve_llm`）。
///
/// 组合序（每 reader 恰读一次）：provider 覆盖/缺省 → apiKey 槽链（空 →
/// [ApiKeyMissingError]，文案逐字复用 `errors.dart` 既有模板）→ base_url 空
/// 归一 → model 覆盖/缺省。消费方（chat / 文档解析 / 模拟器生成）只保留
/// 「差异面 + 工厂派生」，不再各自内联组合序。
class CredentialsResolver {
  /// 注入四 reader；[apiKey] / [baseUrl] 以 provider 为参（槽链原语由装配者
  /// 提供：生产缺省经 `SettingsRepository._slotValue`，测试注入假 reader）。
  CredentialsResolver({
    required Future<String> Function() defaultProvider,
    required Future<String> Function() defaultModel,
    required Future<String> Function(String provider) apiKey,
    required Future<String> Function(String provider) baseUrl,
  })  : _defaultProvider = defaultProvider,
        _defaultModel = defaultModel,
        _apiKey = apiKey,
        _baseUrl = baseUrl;

  final Future<String> Function() _defaultProvider;
  final Future<String> Function() _defaultModel;
  final Future<String> Function(String provider) _apiKey;
  final Future<String> Function(String provider) _baseUrl;

  /// 解析凭据。
  ///
  /// [providerOverride] / [modelOverride] 非空优先（`isNotEmpty` 判据，与既有
  /// 消费点语义逐位一致），空/缺省回退对应 default reader。
  ///
  /// 抛出：[ApiKeyMissingError]——apiKey 槽链返回空串时，消息逐字
  /// 「未配置 {provider} API Key，请在设置中填写」（复用 `errors.dart` 既有
  /// 类 + 文案，零新文案）。
  Future<ResolvedCredentials> resolve({
    String providerOverride = '',
    String modelOverride = '',
  }) async {
    final provider =
        providerOverride.isNotEmpty ? providerOverride : await _defaultProvider();
    final apiKey = await _apiKey(provider);
    if (apiKey.isEmpty) {
      throw ApiKeyMissingError(provider);
    }
    final model =
        modelOverride.isNotEmpty ? modelOverride : await _defaultModel();
    final baseUrl = await _baseUrl(provider);
    return ResolvedCredentials(
      provider: provider,
      apiKey: apiKey,
      model: model,
      baseUrl: baseUrl.isEmpty ? null : baseUrl,
    );
  }
}