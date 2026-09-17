/// VR-03 相似聚类纯函数契约（验收 4/5/6/7/8）：并查集合并 + 稳定分组 + 退化防御。
library;

import 'package:conver_system_mobile/services/vector/cluster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('相似合并（验收 4/5/8）', () {
    test('验收4-达标对合并成组', () {
      final groups = clusterSimilar(
        texts: const ['alpha', 'beta'],
        vectors: const [
          [1, 0],
          [1, 0],
        ],
        threshold: 0.5,
      );
      expect(groups, [
        ['alpha', 'beta'],
      ]);
    });

    test('验收5-孤立条目不出现（成员 <2 的组不输出）', () {
      final groups = clusterSimilar(
        texts: const ['alpha', 'beta', 'orphan'],
        vectors: const [
          [1, 0],
          [1, 0],
          [0, 1],
        ],
        threshold: 0.5,
      );
      expect(groups, [
        ['alpha', 'beta'],
      ]);
    });

    test('验收4-低于阈值不合并', () {
      final groups = clusterSimilar(
        texts: const ['alpha', 'beta'],
        vectors: const [
          [1, 0],
          [0, 1],
        ],
        threshold: 0.5,
      );
      expect(groups, isEmpty);
    });

    test('验收8-恰等于阈值视为聚合（threshold=1.0 相同向量）', () {
      final groups = clusterSimilar(
        texts: const ['alpha', 'beta'],
        vectors: const [
          [1, 0],
          [1, 0],
        ],
        threshold: 1.0,
      );
      expect(groups, [
        ['alpha', 'beta'],
      ]);
    });

    test('验收8-threshold=1.0 时非全等向量不合并', () {
      final groups = clusterSimilar(
        texts: const ['alpha', 'beta'],
        vectors: const [
          [1, 0],
          [0, 1],
        ],
        threshold: 1.0,
      );
      expect(groups, isEmpty);
    });

    test('并查集链式传递：a≈b 且 b≈c 时 a/b/c 合并为一组', () {
      // 单位圆上夹角 15° 相邻：cos(a,b)=cos(b,c)=cos15°≈0.966，
      // cos(a,c)=cos30°≈0.866；threshold 0.95 下仅链式合并可达。
      const a = [1.0, 0.0];
      const b = [0.9659258262890683, 0.25881904510252074];
      const c = [0.8660254037844386, 0.5];
      final groups = clusterSimilar(
        texts: const ['alpha', 'beta', 'gamma'],
        vectors: const [a, b, c],
        threshold: 0.95,
      );
      expect(groups, [
        ['alpha', 'beta', 'gamma'],
      ]);
    });

    test('低阈值 -1.0 时正交向量也合并（≥ 语义全域成立）', () {
      final groups = clusterSimilar(
        texts: const ['alpha', 'beta'],
        vectors: const [
          [1, 0],
          [0, 1],
        ],
        threshold: -1.0,
      );
      expect(groups, [
        ['alpha', 'beta'],
      ]);
    });
  });

  group('退化输入（验收 6，不抛异常）', () {
    test('空 texts 返回空列表', () {
      expect(
        clusterSimilar(texts: const [], vectors: const [], threshold: 0.5),
        isEmpty,
      );
    });

    test('texts 与 vectors 长度不一致返回空列表', () {
      expect(
        clusterSimilar(
          texts: const ['alpha'],
          vectors: const [
            [1, 0],
            [0, 1],
          ],
          threshold: 0.5,
        ),
        isEmpty,
      );
      expect(
        clusterSimilar(
          texts: const ['alpha', 'beta'],
          vectors: const [
            [1, 0],
          ],
          threshold: 0.5,
        ),
        isEmpty,
      );
    });

    test('含 NaN 向量的条目不参与合并，不抛异常', () {
      final groups = clusterSimilar(
        texts: const ['alpha', 'beta'],
        vectors: const [
          [1, 0],
          [double.nan, 0],
        ],
        threshold: 0.5,
      );
      expect(groups, isEmpty);
    });

    test('含零向量与无穷向量的条目不参与合并', () {
      final groups = clusterSimilar(
        texts: const ['alpha', 'beta', 'gamma'],
        vectors: const [
          [1, 0],
          [0, 0],
          [double.infinity, 1],
        ],
        threshold: 0.5,
      );
      expect(groups, isEmpty);
    });

    test('单条输入返回空列表', () {
      expect(
        clusterSimilar(
          texts: const ['alpha'],
          vectors: const [
            [1, 0],
          ],
          threshold: 0.5,
        ),
        isEmpty,
      );
    });
  });

  group('顺序稳定性（验收 7）', () {
    test('输出组按首成员输入序、组内保持输入序', () {
      final groups = clusterSimilar(
        texts: const ['alpha', 'beta', 'gamma', 'delta', 'epsilon'],
        vectors: const [
          [1, 0],
          [1, 0],
          [0, 1],
          [0, 1],
          [1, 0],
        ],
        threshold: 0.5,
      );
      // alpha/beta/epsilon 一组（首成员索引 0），gamma/delta 一组（首成员索引 2）。
      expect(groups, [
        ['alpha', 'beta', 'epsilon'],
        ['gamma', 'delta'],
      ]);
    });

    test('同输入重复调用结果一致（确定性）', () {
      final texts = const ['alpha', 'beta', 'gamma', 'delta'];
      final vectors = const <List<double>>[
        [1, 0],
        [1, 0],
        [0, 1],
        [0, 1],
      ];
      final first = clusterSimilar(
        texts: texts,
        vectors: vectors,
        threshold: 0.5,
      );
      final second = clusterSimilar(
        texts: texts,
        vectors: vectors,
        threshold: 0.5,
      );
      expect(first, second);
      expect(first, [
        ['alpha', 'beta'],
        ['gamma', 'delta'],
      ]);
    });
  });
}
