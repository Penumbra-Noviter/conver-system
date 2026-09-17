/// Embedding 协议面 seam 与值/错误类型（VR-02，SR-16/17/18）。
///
/// - [EmbeddingVector]：单条文本的向量值（dims 语义 = `values.length`），
///   构造时拒绝非有限数，列表不可变。
/// - [EmbeddingClient]：测试可注入的 seam——远端 embedding 协议面的全部
///   行为经 [EmbeddingClient.embed] 暴露，实现可替换（dio / fake）。
/// - 错误面：[EmbeddingFailure] 携带 [EmbeddingFailureKind] 分类摘要；
///   [EmbeddingParseException] 归 parse kind（SR-17 调用方降级锚点）。
///   `message` / `toString` 均不含 API Key 与补嵌原文（SR-16 摘要口径）。
library;

/// 单条文本的 embedding 向量（dims 语义 = [values] 长度）。
class EmbeddingVector {
  /// 创建向量；[values] 会被不可变包装，且每个元素必须 isFinite
  /// （NaN/Infinity 在解析层已被 SR-17 拒绝，此处构造断言兜底）。
  EmbeddingVector(List<double> values)
    : assert(values.every((value) => value.isFinite)),
      _values = List<double>.unmodifiable(values);

  final List<double> _values;

  /// 向量数值（长度即 dims；列表不可修改）。
  List<double> get values => _values;

  /// 向量维度（= 模型指纹的 dims 分量）。
  int get dims => _values.length;

  @override
  String toString() => 'EmbeddingVector(dims: $dims)';
}

/// embedding 失败分类（SR-18 降级路径按 kind 分派）。
enum EmbeddingFailureKind {
  /// 鉴权失败（401 / key 未配置）。
  auth,

  /// 限流（429）。
  rateLimit,

  /// 传输超时（dio 全相位超时，默认对齐 LLM 链 60s）。
  timeout,

  /// 响应解析硬校验失败（SR-17，[EmbeddingParseException] 恒归此类）。
  parse,

  /// 其他网络失败（连接失败 / 非 401·429 的 HTTP 错误等）。
  network,
}

/// embedding 请求失败——携带分类 [kind] 与用户可读的固定摘要 [message]。
///
/// SR-16：message 与 toString 只含固定摘要，不含 API Key 与补嵌原文
/// （连 >10 字符的输入子串也不得出现）。
class EmbeddingFailure implements Exception {
  /// 创建分类失败；[message] 为固定摘要（调用方按 [kind] 降级）。
  const EmbeddingFailure(this.kind, this.message);

  /// 失败分类（auth / rateLimit / timeout / parse / network）。
  final EmbeddingFailureKind kind;

  /// 固定摘要（不含 key 与原文，SR-16）。
  final String message;

  @override
  String toString() => 'EmbeddingFailure.${kind.name}: $message';
}

/// 响应解析硬校验失败（SR-17），恒归 [EmbeddingFailureKind.parse]。
///
/// 畸形响应（非 JSON / data 缺失或非数组 / embedding 非纯数值数组 /
/// NaN·Infinity / 维度与标定不符 / 超长）统一抛本异常，调用方捕获后
/// 降级回退关键词检索，不阻断主回复。
class EmbeddingParseException extends EmbeddingFailure {
  /// 创建解析失败；[message] 为固定摘要（不含 key 与原文）。
  const EmbeddingParseException(String message)
    : super(EmbeddingFailureKind.parse, message);

  @override
  String toString() => 'EmbeddingParseException: $message';
}

/// Embedding 客户端 seam——远端 `/embeddings` 协议面的行为契约。
///
/// 实现（`OpenAICompatibleEmbeddingClient`）经构造注入 Dio 与端点配置；
/// 测试经本接口注入 fake。调用方降级契约：embed 失败时抛
/// [EmbeddingFailure]（含 [EmbeddingParseException]），异常必须分类
/// 不得裸抛未包装错误。
abstract interface class EmbeddingClient {
  /// 将 [texts] 批量转为向量；返回顺序与 [texts] 一致。
  ///
  /// - 空列表 → 立即返回空列表（零网络请求）。
  /// - 失败 → 抛 [EmbeddingFailure]（畸形响应归 [EmbeddingParseException]，
  ///   SR-17；调用方捕获后降级）。
  Future<List<EmbeddingVector>> embed(List<String> texts);
}
