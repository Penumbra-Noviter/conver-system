/// OpenAICompatibleEmbeddingClient — OpenAI Compatible `/embeddings` dio 直连
/// 实现（VR-02，SR-16/17/18）。
///
/// - URL：`{normalizeBaseUrl(baseUrl) ?? 官方默认}/embeddings`；base 归一复用
///   `llm/openai_provider.dart::normalizeBaseUrl`（公开纯函数，只引用不改）。
/// - 请求体 `{"input": [...], "model": model}`；`Authorization: Bearer <key>`，
///   key 仅来自装配层经 SecretStore 槽链解析后写入 [EmbeddingEndpointConfig]
///   （SR-16：本模块不接触 SecretStore，不打印 key）。
/// - 响应硬校验（SR-17）：顶层 JSON 对象 → `data` 非空数组 → 条目数与
///   input 一致 → 每元素 `embedding` 为纯数值数组 → 每数 isFinite →
///   长度 == dims（首样本标定，或 [expectedDims] 注入校验）→ ≤4096 守卫；
///   任一不符 → [EmbeddingParseException]（kind = parse）。
/// - 错误分类（SR-18）：401 → auth、429 → rateLimit、dio 超时 /
///   dart:async TimeoutException → timeout、其余 HTTP 非 2xx 与连接失败 /
///   取消 → network；异常 message 为固定摘要，不含 key 与原文。
/// - 全相位超时默认 [kDefaultEmbeddingTimeout]（对齐 LLM 链 60s）；注入
///   [dio]（测试缝）时超时由注入方负责配置。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../llm/openai_provider.dart' show normalizeBaseUrl;
import 'embedding_client.dart';
import 'embedding_config.dart';

/// 官方默认 embedding 端点基址（`/embeddings` 之前归一后的 /v1 段）。
const String kDefaultEmbeddingBase = 'https://api.openai.com/v1';

/// 单条 embedding 最大长度守卫（SR-17 / SR-18 响应长度防御）。
const int kMaxEmbeddingLength = 4096;

/// 缺省全相位超时（对齐 LLM 链 60s，SR-18）。
const Duration kDefaultEmbeddingTimeout = Duration(seconds: 60);

// ---------------------------------------------------------------------------
// 固定摘要常量（SR-16：不拼接 key / 原文，全部静态文本）
// ---------------------------------------------------------------------------

const String _kNotFoundMessage = 'embedding API key 未配置（装配层未解析到 key）';
const String _kTimeoutMessage = 'embedding 请求超时（对齐 LLM 链 60s，SR-18）';
const String _kAuthMessage = 'embedding 鉴权失败（HTTP 401）';
const String _kRateLimitMessage = 'embedding 触发限流（HTTP 429，调用方降级）';
const String _kHttpErrorMessage = 'embedding 服务返回非 2xx（调用方降级）';
const String _kNetworkMessage = 'embedding 网络失败（连接失败或响应取消）';
const String _kParsePrefix = 'embedding 响应解析失败（SR-17）：';

/// OpenAI Compatible `/embeddings` 的 dio 直连实现。
class OpenAICompatibleEmbeddingClient implements EmbeddingClient {
  /// 创建客户端。
  ///
  /// - [config]：VR-01 装配面端点快照；`enabled` 由装配方/调用方决定是否
  ///   调用本客户端（本模块只负责已启用的请求路径）；`apiKey` 必须是
  ///   SecretStore 槽链的解析结果（SR-16）；`baseUrl` 应已过
  ///   `validateEmbeddingBaseUrl`（SR-20），null = 官方默认端点。
  /// - [dio]：测试缝；缺省自建，connect/send/receive 全相位超时 =
  ///   [timeout]。注入 dio 时超时由注入方配置。
  /// - [expectedDims]：模型已知时的维度注入（与响应首条长度一起校验）；
  ///   null = 以首条响应 embedding 长度标定（同批同长校验）。
  OpenAICompatibleEmbeddingClient({
    required this.config,
    Dio? dio,
    Duration timeout = kDefaultEmbeddingTimeout,
    this.expectedDims,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: timeout,
               sendTimeout: timeout,
               receiveTimeout: timeout,
             ),
           );

  /// 端点装配快照（构造即只读；apiKey 必须是 SecretStore 槽链解析结果）。
  final EmbeddingEndpointConfig config;

  /// 模型已知时的维度注入；null = 首条响应长度标定（同批同长校验）。
  final int? expectedDims;

  final Dio _dio;

  @override
  Future<List<EmbeddingVector>> embed(List<String> texts) async {
    if (texts.isEmpty) {
      return const <EmbeddingVector>[];
    }
    final key = config.apiKey;
    if (key.isEmpty) {
      throw const EmbeddingFailure(
        EmbeddingFailureKind.auth,
        _kNotFoundMessage,
      );
    }
    try {
      final response = await _dio.post<dynamic>(
        _endpoint(),
        data: <String, dynamic>{'input': texts, 'model': config.model},
        options: Options(
          headers: <String, Object>{'Authorization': 'Bearer $key'},
        ),
      );
      return _parseEmbeddings(response.data, expectedCount: texts.length);
    } on FormatException {
      // 非 JSON 文本（text/plain 响应体）在客户端 jsonDecode 失败。
      throw const EmbeddingParseException('$_kParsePrefix响应不是合法 JSON');
    } on DioException catch (error) {
      throw _classify(error);
    }
  }

  /// 拼装 `/embeddings` 端点：base 经 [normalizeBaseUrl] 归一（补 /v1 段）。
  String _endpoint() {
    final normalized =
        normalizeBaseUrl(config.baseUrl) ?? kDefaultEmbeddingBase;
    return '$normalized/embeddings';
  }

  /// 将 dio 异常按 SR-18 分类映射为 [EmbeddingFailure]。
  EmbeddingFailure _classify(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const EmbeddingFailure(
          EmbeddingFailureKind.timeout,
          _kTimeoutMessage,
        );
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        if (status == 401) {
          return const EmbeddingFailure(
            EmbeddingFailureKind.auth,
            _kAuthMessage,
          );
        }
        if (status == 429) {
          return const EmbeddingFailure(
            EmbeddingFailureKind.rateLimit,
            _kRateLimitMessage,
          );
        }
        return const EmbeddingFailure(
          EmbeddingFailureKind.network,
          _kHttpErrorMessage,
        );
      default:
        if (error.error is FormatException) {
          // application/json + 非法体：dio transformer 解码失败包装路径。
          throw const EmbeddingParseException('$_kParsePrefix响应不是合法 JSON');
        }
        if (error.error is TimeoutException) {
          return const EmbeddingFailure(
            EmbeddingFailureKind.timeout,
            _kTimeoutMessage,
          );
        }
        return const EmbeddingFailure(
          EmbeddingFailureKind.network,
          _kNetworkMessage,
        );
    }
  }

  /// 响应硬校验（SR-17）：结构 / 纯数值 / isFinite / dims / 长度守卫。
  ///
  /// [expectedCount] = input 条目数；data 数量不一致视为结构畸形。
  List<EmbeddingVector> _parseEmbeddings(
    Object? data, {
    required int expectedCount,
  }) {
    final Object? decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! Map<String, dynamic>) {
      _parseError('顶层不是 JSON 对象');
    }
    final rawData = decoded['data'];
    if (rawData is! List || rawData.isEmpty) {
      _parseError('data 缺失或非非空数组');
    }
    if (rawData.length != expectedCount) {
      _parseError('data 条目数与 input 数量不一致');
    }

    final vectors = <EmbeddingVector>[];
    int? dims = expectedDims;
    for (final item in rawData) {
      if (item is! Map) {
        _parseError('data 元素不是对象');
      }
      final rawEmbedding = item['embedding'];
      if (rawEmbedding is! List || rawEmbedding.isEmpty) {
        _parseError('embedding 缺失、非数组或为空');
      }
      final values = <double>[];
      for (final value in rawEmbedding) {
        if (value is! num) {
          _parseError('embedding 元素非数值');
        }
        final converted = value.toDouble();
        if (!converted.isFinite) {
          _parseError('embedding 含 NaN/Infinity');
        }
        values.add(converted);
      }
      if (dims == null) {
        // 首条响应标定 dims（模型未知时），后续条目同长校验。
        dims = values.length;
      } else if (values.length != dims) {
        _parseError('embedding 维度与标定 dims 不符');
      }
      if (values.length > kMaxEmbeddingLength) {
        _parseError('embedding 超过 $kMaxEmbeddingLength 长度守卫');
      }
      vectors.add(EmbeddingVector(values));
    }
    return vectors;
  }

  /// 抛解析失败（固定摘要，不含 key 与原文）。
  Never _parseError(String detail) =>
      throw EmbeddingParseException('$_kParsePrefix$detail');
}
