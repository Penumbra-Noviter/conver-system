/// embedding 设置装配腿的配置校验与端点配置记录（VR-01）。
///
/// 职责边界：
/// - [validateEmbeddingBaseUrl]：纯函数（零 I/O），SR-20「base_url 强制 https」
///   的单一落点——非空输入必须 `https://` 前缀，否则抛 [EmbeddingConfigException]；
///   空白输入归一为 null（官方默认端点）。
/// - [EmbeddingEndpointConfig]：装配面数据记录（VR-06/07/08 装配腿的输入形态），
///   不承载 I/O；字段来源见 `SettingsRepository` 四 getter 与校验结果。
library;

/// embedding 端点配置错误 — 装配期（非请求期）配置非法时抛出。
///
/// 与请求期错误面（`EmbeddingFailure`，VR-02）分离：本异常只在
/// [validateEmbeddingBaseUrl] 等装配校验路径抛出，message 不含 key 与原文
/// （对齐 SR-16 摘要口径）。
class EmbeddingConfigException implements Exception {
  /// 创建配置错误；[message] 为面向用户的可读摘要
  const EmbeddingConfigException(this.message);

  /// 错误摘要（不含凭据与输入原文）
  final String message;

  @override
  String toString() => 'EmbeddingConfigException: $message';
}

/// 校验并归一 embedding base_url（SR-20 强制 https）。
///
/// 返回语义：
/// - 空 / 空白（null、''、纯空白）→ `null`（官方默认端点）
/// - `https://...`（协议段后含非空 authority）→ 原样归一：trim 后去尾部斜杠
/// - `http://...`、非 URL 文本、或 `https://` 无 authority（如 `'https://'`、
///   纯协议段或 `'https:///…'`）→ 抛 [EmbeddingConfigException]
String? validateEmbeddingBaseUrl(String? value) {
  const prefix = 'https://';
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  if (!trimmed.startsWith(prefix)) {
    throw const EmbeddingConfigException(
      'embedding_base_url 必须以 https:// 开头（SR-20 强制 HTTPS）',
    );
  }
  // 只归一协议前缀之后的主体，并强制要求非空 authority——纯协议段
  //（'https://'）或以 '/' 起始的路径段（'https:///…'）均为无效端点，错误
  // 应在装配期暴露而非推迟至请求期（Falsify-1 修复）。
  final body = trimmed
      .substring(prefix.length)
      .replaceFirst(RegExp(r'/+$'), '');
  if (body.isEmpty || body.startsWith('/')) {
    throw const EmbeddingConfigException(
      'embedding_base_url 缺少有效主机（SR-20 强制 HTTPS）',
    );
  }
  return '$prefix$body';
}

/// embedding 端点装配面数据记录 — enabled / key / base_url / model 的只读快照。
///
/// 字段值由装配方组装：
/// - [enabled]：`embedding_enabled == 'true'`（SR-19 默认关）
/// - [apiKey]：SecretStore 槽链结果（embedding 槽 → openai 槽 → 空串）
/// - [baseUrl]：[validateEmbeddingBaseUrl] 结果；`null` = 官方默认端点
/// - [model]：`embedding_model`，未配置时为缺省模型
class EmbeddingEndpointConfig {
  /// 创建端点配置快照；装配方负责保证字段语义（参数字段即最终值）
  const EmbeddingEndpointConfig({
    required this.enabled,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });

  /// 是否启用远端 embedding（默认 false，SR-19）
  final bool enabled;

  /// SecretStore 解析后的 API Key（空串 = 未配置）
  final String apiKey;

  /// 归一后的 base_url；null = 使用官方默认端点
  final String? baseUrl;

  /// 模型标识（缺省 `text-embedding-3-small`）
  final String model;
}
