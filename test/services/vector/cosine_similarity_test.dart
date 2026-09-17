/// VR-03 余弦相似度纯函数契约（验收 1/2/3）：几何语义 + 退化输入防御。
library;

import 'dart:math' as math;

import 'package:conver_system_mobile/services/vector/cosine_similarity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('基础几何（验收 1/3）', () {
    test('验收1-同向单位向量为 1.0', () {
      expect(cosineSimilarity([1, 0], [1, 0]), 1.0);
    });

    test('验收1-正交向量为 0.0', () {
      expect(cosineSimilarity([1, 0], [0, 1]), 0.0);
      expect(cosineSimilarity([1, 1], [1, -1]), 0.0);
    });

    test('验收3-反向向量为 -1.0', () {
      expect(cosineSimilarity([1, 0], [-1, 0]), -1.0);
    });

    test('验收3-相同非单位向量趋近 1.0（浮点容差）', () {
      expect(cosineSimilarity([1, 1], [1, 1]), closeTo(1.0, 1e-12));
    });

    test('余弦对向量缩放不变', () {
      expect(cosineSimilarity([2, 4], [4, 2]), closeTo(0.8, 1e-12));
      expect(cosineSimilarity([1, 2], [2, 1]), closeTo(0.8, 1e-12));
      expect(cosineSimilarity([2, 4], [2, 4]), closeTo(1.0, 1e-12));
    });

    test('单元素非零向量按定义计算', () {
      expect(cosineSimilarity([5], [5]), 1.0);
      expect(cosineSimilarity([5], [-5]), -1.0);
    });

    test('通用夹角值域在 [-1, 1]', () {
      final samples = <List<List<double>>>[
        [
          [3, 4],
          [5, 12],
        ],
        [
          [1, -2],
          [2, 1],
        ],
        [
          [0.5, 0.5, 0.5],
          [0.1, -0.9, 0.3],
        ],
      ];
      for (final pair in samples) {
        final value = cosineSimilarity(pair[0], pair[1])!;
        expect(value, greaterThanOrEqualTo(-1.0));
        expect(value, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('退化输入（验收 2，不抛异常）', () {
    test('长度不一致返回 null', () {
      expect(cosineSimilarity([1, 0], [1]), isNull);
      expect(cosineSimilarity([1], [1, 0]), isNull);
    });

    test('空向量返回 null', () {
      expect(cosineSimilarity(const <double>[], const []), isNull);
    });

    test('零向量返回 null', () {
      expect(cosineSimilarity([0, 0], [1, 1]), isNull);
      expect(cosineSimilarity([1, 1], [0, 0]), isNull);
      expect(cosineSimilarity([0], [0]), isNull);
    });

    test('含 NaN 元素返回 null', () {
      expect(cosineSimilarity([double.nan, 1], [1, 1]), isNull);
      expect(cosineSimilarity([1, 1], [double.nan, 1]), isNull);
    });

    test('含正负无穷元素返回 null', () {
      expect(cosineSimilarity([double.infinity, 1], [1, 1]), isNull);
      expect(cosineSimilarity([1, 1], [double.negativeInfinity, 1]), isNull);
    });

    test('退化输入不抛异常（null 兜底不崩）', () {
      final List<List<double>> inputs = [
        const <double>[],
        [0.0, 0.0],
        [double.nan],
        [double.infinity, 1.0],
      ];
      for (final vector in inputs) {
        expect(() => cosineSimilarity(vector, [1, 1]), returnsNormally);
        expect(() => cosineSimilarity([1, 1], vector), returnsNormally);
      }
    });
  });

  group('阈值常量（spec D6 单处定义）', () {
    test('召回阈值 0.5 / 聚类阈值 0.75', () {
      expect(kSemanticRecallMinSimilarity, 0.5);
      expect(kClusterSimilarityThreshold, 0.75);
    });

    test('阈值常量可用于余弦判定', () {
      // [0.75, sqrt(1-0.75^2)] 与单位 x 轴夹角余弦恰为 0.75（> 召回阈值）。
      final near = cosineSimilarity([1, 0], [0.75, math.sqrt(0.4375)])!;
      expect(near, closeTo(kClusterSimilarityThreshold, 1e-12));
      final far = cosineSimilarity([1, 0], [0, 1])!;
      expect(far, lessThan(kSemanticRecallMinSimilarity));
    });
  });
}
