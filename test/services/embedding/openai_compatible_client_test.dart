/// VR-02 OpenAICompatibleEmbeddingClient 验收测试。
///
/// seam = [EmbeddingClient.embed] 公共接口 + [OpenAICompatibleEmbeddingClient]
/// 构造参数（config / dio / expectedDims / timeout）。本地 fake HTTP
/// （[FakeEmbeddingServer]）承载请求契约与响应播放，不依赖真实网络；
/// [DioException] 类型注入经私有 [FakeEmbeddingAdapter] 完成。
///
/// fixture 说明：`test/services/embedding/fixtures/` 全部为**合成样例**——
/// schema 依据 OpenAI 官方公开文档 `/embeddings` 响应样例结构编写；
/// 真实响应待 key 补充（集成验收动作见 VR-06 验收 8）。
///
/// 验收映射：票面验收 1~8 逐条如下
/// 1 正常 fixture → 数量/顺序一致（happy group）
/// 2 非 JSON → parse（畸形 group）
/// 3 维度不符（同批标定 / expectedDims）→ parse（畸形 group）
/// 4 NaN/Infinity → parse（畸形 group，1e999 溢出实证）
/// 5 长度 >4096 → parse（畸形 group + 恰 4096 边界）
/// 6 401/429/超时/5xx → auth/rateLimit/timeout/network（分类 group）
/// 7 message/toString 不含 key 与 >10 字符原文（SR-16 group）
/// 8 请求体 input 数组 + Bearer key 非空（请求契约 group）
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conver_system_mobile/services/embedding/embedding_client.dart';
import 'package:conver_system_mobile/services/embedding/embedding_config.dart';
import 'package:conver_system_mobile/services/embedding/openai_compatible_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_embedding_server.dart';

void main() {
  const testKey = 'sk-test-secret-1234';
  const testModel = 'text-embedding-3-small';
  // >10 字符原文：SR-16 断言异常摘要不得含补嵌原文子串。
  const longText = '这是一个长度超过十个字符的补嵌原文内容用于断言不外泄';

  final servers = <FakeEmbeddingServer>[];
  tearDown(() async {
    for (final server in servers.toList()) {
      await server.close();
      servers.remove(server);
    }
  });

  Future<FakeEmbeddingServer> startServer(FakeEmbeddingHandler handler) async {
    final server = FakeEmbeddingServer(handler);
    await server.start();
    servers.add(server);
    return server;
  }

  Future<String> readFixture(String name) =>
      File('test/services/embedding/fixtures/$name').readAsString();

  EmbeddingEndpointConfig makeConfig({
    String apiKey = testKey,
    String? baseUrl = 'https://api.example.com',
    String model = testModel,
    bool enabled = true,
  }) => EmbeddingEndpointConfig(
    enabled: enabled,
    apiKey: apiKey,
    baseUrl: baseUrl,
    model: model,
  );

  OpenAICompatibleEmbeddingClient clientFor(
    FakeEmbeddingServer server, {
    EmbeddingEndpointConfig? config,
    int? expectedDims,
  }) => OpenAICompatibleEmbeddingClient(
    config: config ?? makeConfig(baseUrl: server.baseUrl),
    expectedDims: expectedDims,
  );

  Map<String, dynamic> embeddingItem(List<Object> values, {int index = 0}) => {
    'object': 'embedding',
    'index': index,
    'embedding': values,
  };

  Map<String, dynamic> okResponse(List<Object> data, {String? model}) => {
    'object': 'list',
    'data': data,
    'model': model ?? testModel,
    'usage': {'prompt_tokens': 1, 'total_tokens': 1},
  };

  /// 断言 future 抛 EmbeddingFailure 并返回之（不吞不裸抛：必须分类异常）。
  Future<EmbeddingFailure> expectFailure(
    Future<List<EmbeddingVector>> future,
  ) async {
    try {
      await future;
      fail('期望 EmbeddingFailure，实际成功返回');
    } on EmbeddingFailure catch (failure) {
      return failure;
    }
  }

  /// SR-16：异常 message 与 toString 均不含 key 与 >10 字符原文子串。
  void expectNoSecretLeak(EmbeddingFailure failure) {
    expect(failure.message, isNot(contains(testKey)));
    expect(failure.message, isNot(contains(longText)));
    expect(failure.toString(), isNot(contains(testKey)));
    expect(failure.toString(), isNot(contains(longText)));
  }

  group('请求契约（验收 8 / SR-16 头行为）', () {
    test('POST {base}/v1/embeddings + Bearer key + body input/model', () async {
      final server = await startServer(
        FakeEmbeddingServer.ok(
          okResponse([
            embeddingItem([0.1, 0.2, 0.3], index: 0),
            embeddingItem([0.4, 0.5, 0.6], index: 1),
          ]),
        ),
      );
      await clientFor(server).embed(['第一段文本', 'second text']);

      final captured = server.captured.single;
      expect(captured.method, 'POST');
      expect(captured.path, '/v1/embeddings');
      expect(captured.headers['authorization'], 'Bearer $testKey');
      expect(captured.headers['content-type'], contains('application/json'));

      final body = captured.jsonBody!;
      expect(body['input'], ['第一段文本', 'second text']);
      expect(body['model'], testModel);
    });

    test('baseUrl 已含 /v1 → 不重复拼接版本段', () async {
      final server = await startServer(
        FakeEmbeddingServer.ok(
          okResponse([
            embeddingItem([0.1, 0.2, 0.3]),
          ]),
        ),
      );
      await OpenAICompatibleEmbeddingClient(
        config: makeConfig(baseUrl: '${server.baseUrl}/v1'),
      ).embed(['x']);
      expect(server.captured.single.path, '/v1/embeddings');
    });

    test('baseUrl null → 官方默认端点（adapter 捕获 uri）', () async {
      final adapter = FakeEmbeddingAdapter.respondString(
        jsonEncode(
          okResponse([
            embeddingItem([0.1, 0.2, 0.3]),
          ]),
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      await OpenAICompatibleEmbeddingClient(
        config: makeConfig(baseUrl: null),
        dio: dio,
      ).embed(['x']);
      expect(
        adapter.lastUri.toString(),
        'https://api.openai.com/v1/embeddings',
      );
    });

    test('key 空 → auth 失败且不发请求（SR-16：key 仅装配层解析）', () async {
      final server = await startServer(
        FakeEmbeddingServer.ok(
          okResponse([
            embeddingItem([0.1, 0.2, 0.3]),
          ]),
        ),
      );
      final failure = await expectFailure(
        clientFor(server, config: makeConfig(apiKey: '')).embed([longText]),
      );
      expect(failure.kind, EmbeddingFailureKind.auth);
      expect(server.captured, isEmpty);
      expectNoSecretLeak(failure);
    });

    test('空 input → 返回空列表且零请求', () async {
      final server = await startServer(FakeEmbeddingServer.ok(okResponse([])));
      expect(await clientFor(server).embed(const []), isEmpty);
      expect(server.captured, isEmpty);
    });
  });

  group('happy path（验收 1）', () {
    test('官方样例结构 fixture → 数量/顺序/dims 一致', () async {
      final server = await startServer(
        FakeEmbeddingServer.text(await readFixture('embed_response_ok.json')),
      );
      final vectors = await clientFor(server).embed(['a', 'b']);

      expect(vectors, hasLength(2));
      expect(vectors[0].dims, 3);
      expect(vectors[0].values, [0.010304959, -0.011924531, 0.0040106527]);
      expect(vectors[1].values, [-0.0024870758, 0.009504202, -0.01124527]);
    });

    test('expectedDims 装配注入且与响应一致 → 通过', () async {
      final server = await startServer(
        FakeEmbeddingServer.ok(
          okResponse([
            embeddingItem([0.1, 0.2, 0.3]),
          ]),
        ),
      );
      final vectors = await clientFor(server, expectedDims: 3).embed(['x']);
      expect(vectors.single.dims, 3);
    });

    test('恰好 4096 维 → 通过长度守卫（边界绿）', () async {
      final server = await startServer(
        FakeEmbeddingServer.ok(
          okResponse([embeddingItem(List<double>.filled(4096, 0.5))]),
        ),
      );
      final vectors = await clientFor(server).embed(['x']);
      expect(vectors.single.dims, 4096);
    });
  });

  group('畸形响应 → EmbeddingParseException（验收 2~5，SR-17）', () {
    Future<EmbeddingFailure> expectParse(FakeEmbeddingServer server) async {
      final failure = await expectFailure(clientFor(server).embed([longText]));
      expect(failure, isA<EmbeddingParseException>());
      expect(failure.kind, EmbeddingFailureKind.parse);
      expectNoSecretLeak(failure);
      return failure;
    }

    test('非 JSON 文本（text/plain fixture）→ parse', () async {
      final server = await startServer(
        FakeEmbeddingServer.text(
          await readFixture('embed_response_invalid.txt'),
        ),
      );
      await expectParse(server);
    });

    test(
      'application/json + 非 JSON 体（dio transformer FormatException）→ parse',
      () async {
        final server = await startServer(
          FakeEmbeddingServer.text(
            'this is not json',
            contentType: 'application/json',
          ),
        );
        await expectParse(server);
      },
    );

    test('顶层 JSON 数组 → parse', () async {
      final server = await startServer(
        FakeEmbeddingServer.text('[]', contentType: 'application/json'),
      );
      await expectParse(server);
    });

    test('data 缺失 / 非数组 / 空数组 → parse', () async {
      for (final body in [
        <String, dynamic>{'object': 'list'},
        <String, dynamic>{'object': 'list', 'data': <String, dynamic>{}},
        <String, dynamic>{'object': 'list', 'data': <Object>[]},
      ]) {
        final server = await startServer(FakeEmbeddingServer.ok(body));
        await expectParse(server);
      }
    });

    test('data 元素非对象 / embedding 缺失 / 非数组 / 空数组 → parse', () async {
      for (final data in [
        <Object>['not-a-map'],
        <Object>[
          {'object': 'embedding', 'index': 0},
        ],
        <Object>[
          {'object': 'embedding', 'index': 0, 'embedding': 'x'},
        ],
        <Object>[
          {'object': 'embedding', 'index': 0, 'embedding': <Object>[]},
        ],
      ]) {
        final server = await startServer(
          FakeEmbeddingServer.ok(okResponse(data)),
        );
        await expectParse(server);
      }
    });

    test('embedding 元素非数值 → parse', () async {
      final server = await startServer(
        FakeEmbeddingServer.ok(
          okResponse([
            embeddingItem([0.1, '0.2']),
          ]),
        ),
      );
      await expectParse(server);
    });

    test(
      'embedding 含 Infinity（1e999 溢出 fixture）→ parse（SR-17 isFinite）',
      () async {
        final server = await startServer(
          FakeEmbeddingServer.text(
            await readFixture('embed_response_inf.json'),
          ),
        );
        await expectParse(server);
      },
    );

    test('维度与已标定 dims 不符（fixture 3+4）→ parse（验收 3）', () async {
      final server = await startServer(
        FakeEmbeddingServer.text(
          await readFixture('embed_response_wrong_dims.json'),
        ),
      );
      // input 2 条 ↔ data 2 条：数量校验放行，必须由同批 dims 校验拦截。
      final failure = await expectFailure(
        clientFor(server).embed([longText, 'second']),
      );
      expect(failure, isA<EmbeddingParseException>());
      expect(failure.kind, EmbeddingFailureKind.parse);
      expectNoSecretLeak(failure);
    });

    test('expectedDims 与响应维度不符 → parse（验收 3 配置口径）', () async {
      final server = await startServer(
        FakeEmbeddingServer.ok(
          okResponse([
            embeddingItem([0.1, 0.2, 0.3]),
          ]),
        ),
      );
      final failure = await expectFailure(
        clientFor(server, expectedDims: 4).embed(['x']),
      );
      expect(failure, isA<EmbeddingParseException>());
      expect(failure.kind, EmbeddingFailureKind.parse);
    });

    test('embedding 超长 4097（fixture）→ parse（验收 5 长度守卫）', () async {
      final server = await startServer(
        FakeEmbeddingServer.text(
          await readFixture('embed_response_too_long.json'),
        ),
      );
      await expectParse(server);
    });

    test('data 条目数与 input 数量不一致 → parse（防污染）', () async {
      // input 2 条只回 1 条。
      final server = await startServer(
        FakeEmbeddingServer.ok(
          okResponse([
            embeddingItem([0.1, 0.2, 0.3]),
          ]),
        ),
      );
      final failure = await expectFailure(clientFor(server).embed(['a', 'b']));
      expect(failure.kind, EmbeddingFailureKind.parse);
      // input 1 条却回 2 条。
      final server2 = await startServer(
        FakeEmbeddingServer.ok(
          okResponse([
            embeddingItem([0.1, 0.2, 0.3]),
            embeddingItem([0.4, 0.5, 0.6], index: 1),
          ]),
        ),
      );
      final failure2 = await expectFailure(
        clientFor(server2).embed(const ['only-one']),
      );
      expect(failure2.kind, EmbeddingFailureKind.parse);
    });
  });

  group('HTTP 失败分类（验收 6，SR-18 超时/降级面）', () {
    test('401 → auth', () async {
      final server = await startServer(
        FakeEmbeddingServer.httpError(401, body: 'unauth'),
      );
      final failure = await expectFailure(clientFor(server).embed([longText]));
      expect(failure.kind, EmbeddingFailureKind.auth);
      expectNoSecretLeak(failure);
    });

    test('429 → rateLimit', () async {
      final server = await startServer(FakeEmbeddingServer.httpError(429));
      final failure = await expectFailure(clientFor(server).embed(['x']));
      expect(failure.kind, EmbeddingFailureKind.rateLimit);
    });

    test('400（业务 4xx 非 401/429）→ network', () async {
      final server = await startServer(FakeEmbeddingServer.httpError(400));
      final failure = await expectFailure(clientFor(server).embed(['x']));
      expect(failure.kind, EmbeddingFailureKind.network);
    });

    test('500 / 502 → network', () async {
      for (final status in [500, 502]) {
        final server = await startServer(FakeEmbeddingServer.httpError(status));
        final failure = await expectFailure(clientFor(server).embed(['x']));
        expect(failure.kind, EmbeddingFailureKind.network);
      }
    });

    test('真实传输延迟 → receiveTimeout → timeout（dio 短超时注入）', () async {
      final server = await startServer(
        FakeEmbeddingServer.delayed(
          const Duration(milliseconds: 500),
          body: okResponse([
            embeddingItem([0.1, 0.2, 0.3]),
          ]),
        ),
      );
      // 默认 IO adapter 直连本地 HttpServer：服务器延迟 500ms 不回响应头，
      // 客户端 receiveTimeout 100ms → dio receiveTimeout 真实触发。
      final slowDio = Dio(
        BaseOptions(
          baseUrl: server.baseUrl,
          receiveTimeout: const Duration(milliseconds: 100),
        ),
      );
      final failure = await expectFailure(
        OpenAICompatibleEmbeddingClient(
          config: makeConfig(baseUrl: server.baseUrl),
          dio: slowDio,
        ).embed([longText]),
      );
      expect(failure.kind, EmbeddingFailureKind.timeout);
      expectNoSecretLeak(failure);
    });

    test('DioException connectionTimeout / sendTimeout → timeout', () async {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
      ]) {
        final adapter = FakeEmbeddingAdapter.throwError(
          DioException(
            requestOptions: RequestOptions(path: '/embeddings'),
            type: type,
          ),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final failure = await expectFailure(
          OpenAICompatibleEmbeddingClient(
            config: makeConfig(baseUrl: 'https://adapter.invalid'),
            dio: dio,
          ).embed(['x']),
        );
        expect(failure.kind, EmbeddingFailureKind.timeout);
      }
    });

    test('adapter 抛 dart:async TimeoutException → timeout（包装路径）', () async {
      final adapter = FakeEmbeddingAdapter.throwError(
        TimeoutException('probe timeout'),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final failure = await expectFailure(
        OpenAICompatibleEmbeddingClient(
          config: makeConfig(baseUrl: 'https://adapter.invalid'),
          dio: dio,
        ).embed(['x']),
      );
      expect(failure.kind, EmbeddingFailureKind.timeout);
    });

    test('connectionError / badCertificate / cancel → network', () async {
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.badCertificate,
        DioExceptionType.cancel,
      ]) {
        final adapter = FakeEmbeddingAdapter.throwError(
          DioException(
            requestOptions: RequestOptions(path: '/embeddings'),
            type: type,
          ),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final failure = await expectFailure(
          OpenAICompatibleEmbeddingClient(
            config: makeConfig(baseUrl: 'https://adapter.invalid'),
            dio: dio,
          ).embed([longText]),
        );
        expect(failure.kind, EmbeddingFailureKind.network);
        expectNoSecretLeak(failure);
      }
    });
  });

  group('EmbeddingVector / 分类异常（seam 值类型契约）', () {
    test('dims = values.length；values 不可变', () {
      final vector = EmbeddingVector([0.1, 0.2, 0.3]);
      expect(vector.dims, 3);
      expect(() => vector.values.add(0.4), throwsUnsupportedError);
    });

    test('toString 摘要仅含 dims（不打印数值）', () {
      expect(
        EmbeddingVector([0.1, -999.0, 1e-9]).toString(),
        'EmbeddingVector(dims: 3)',
      );
    });

    test('非有限数构造被 assert 拒绝', () {
      expect(
        () => EmbeddingVector([double.nan]),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EmbeddingVector([double.infinity]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('EmbeddingParseException 恒归 parse kind（畸形 → 降级分类锚点）', () {
      const failure = EmbeddingParseException('probe');
      expect(failure.kind, EmbeddingFailureKind.parse);
      expect(failure, isA<EmbeddingFailure>());
      expect(failure.toString(), contains('EmbeddingParseException'));
    });

    test('常量契约：kMaxEmbeddingLength = 4096', () {
      expect(kMaxEmbeddingLength, 4096);
    });
  });
}

/// 异常注入 / 响应播放的假 adapter（不走真实网络）。
class FakeEmbeddingAdapter implements HttpClientAdapter {
  FakeEmbeddingAdapter._(this._respond, this._throw);

  factory FakeEmbeddingAdapter.respond(ResponseBody body) =>
      FakeEmbeddingAdapter._(() => body, null);
  factory FakeEmbeddingAdapter.respondString(
    String body, {
    int statusCode = 200,
    Map<String, List<String>>? headers,
  }) => FakeEmbeddingAdapter._(
    () => ResponseBody.fromString(
      body,
      statusCode,
      headers:
          headers ??
          {
            Headers.contentTypeHeader: ['application/json'],
          },
    ),
    null,
  );
  factory FakeEmbeddingAdapter.throwError(Object error) =>
      FakeEmbeddingAdapter._(null, error);

  final ResponseBody Function()? _respond;
  final Object? _throw;

  RequestOptions? lastOptions;
  String? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    final body = requestStream == null
        ? null
        : await utf8.decoder.bind(requestStream).join();
    lastBody = body;
    final error = _throw;
    if (error != null) {
      throw error;
    }
    return _respond!();
  }

  Uri? get lastUri => lastOptions?.uri;

  @override
  void close({bool force = false}) {}
}
