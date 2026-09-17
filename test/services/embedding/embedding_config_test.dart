/// VR-01 embedding 设置装配腿 — 端点校验纯函数契约测试。
///
/// 验收 6（SR-20 强制 https）逐条映射：
/// - 空 / 空白 → null（官方默认端点）
/// - `https://...` → 原样归一（去尾斜杠）
/// - `http://...` → 抛配置错误
/// - 非 URL 文本 → 抛配置错误
/// 纯函数，零 I/O，无 setUp 依赖。
library;

import 'package:conver_system_mobile/services/embedding/embedding_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateEmbeddingBaseUrl（SR-20 协议强制 + 空白归一）', () {
    test('空 / 空白输入返回 null（官方默认端点语义）', () {
      expect(validateEmbeddingBaseUrl(null), isNull);
      expect(validateEmbeddingBaseUrl(''), isNull);
      expect(validateEmbeddingBaseUrl('   '), isNull);
      expect(validateEmbeddingBaseUrl('\t\n'), isNull);
    });

    test('https 输入原样归一：去尾部斜杠', () {
      expect(
        validateEmbeddingBaseUrl('https://api.openai.com'),
        'https://api.openai.com',
      );
      expect(
        validateEmbeddingBaseUrl('https://api.openai.com/'),
        'https://api.openai.com',
      );
      expect(
        validateEmbeddingBaseUrl('https://api.openai.com/v1/'),
        'https://api.openai.com/v1',
      );
      expect(
        validateEmbeddingBaseUrl('  https://api.openai.com/v1/  '),
        'https://api.openai.com/v1',
      );
    });

    test('http 输入抛配置错误（SR-20 明文 http 拒绝）', () {
      expect(
        () => validateEmbeddingBaseUrl('http://api.openai.com'),
        throwsA(isA<EmbeddingConfigException>()),
      );
      expect(
        () => validateEmbeddingBaseUrl('http://api.openai.com/v1/'),
        throwsA(isA<EmbeddingConfigException>()),
      );
    });

    test('非 URL 文本抛配置错误', () {
      expect(
        () => validateEmbeddingBaseUrl('not-a-url'),
        throwsA(isA<EmbeddingConfigException>()),
      );
      expect(
        () => validateEmbeddingBaseUrl('ftp://example.com'),
        throwsA(isA<EmbeddingConfigException>()),
      );
      expect(
        () => validateEmbeddingBaseUrl('api.openai.com'),
        throwsA(isA<EmbeddingConfigException>()),
      );
    });

    test('配置错误暴露 message 且 toString 可读（不含输入原文）', () {
      const error = EmbeddingConfigException('embedding_base_url 必须 https');
      expect(error.message, 'embedding_base_url 必须 https');
      expect(
        error.toString(),
        'EmbeddingConfigException: embedding_base_url 必须 https',
      );
    });
  });

  group('EmbeddingEndpointConfig（装配面数据记录）', () {
    test('构造携带四字段（enabled / apiKey / baseUrl / model）', () {
      const config = EmbeddingEndpointConfig(
        enabled: true,
        apiKey: 'sk-embed',
        baseUrl: 'https://api.openai.com/v1',
        model: 'text-embedding-3-small',
      );

      expect(config.enabled, isTrue);
      expect(config.apiKey, 'sk-embed');
      expect(config.baseUrl, 'https://api.openai.com/v1');
      expect(config.model, 'text-embedding-3-small');
    });

    test('未配置面：默认关、无 key、baseUrl 可空、model 可空', () {
      const config = EmbeddingEndpointConfig(
        enabled: false,
        apiKey: '',
        baseUrl: null,
        model: '',
      );

      expect(config.enabled, isFalse);
      expect(config.apiKey, isEmpty);
      expect(config.baseUrl, isNull);
      expect(config.model, isEmpty);
    });
  });
}
