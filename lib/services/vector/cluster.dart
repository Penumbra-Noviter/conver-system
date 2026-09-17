/// 基于余弦相似度的并查集聚类纯函数（P4 人格演化聚类输入）。
///
/// 两两余弦 ≥ 阈值即并查集合并，输出成员 ≥2 的稳定分组；零 I/O、零依赖。
library;

import 'cosine_similarity.dart';

/// 按两两余弦相似度 ≥ [threshold] 将 [texts] 聚成组，返回成员数 ≥2 的分组。
///
/// - [texts] 与 [vectors] 长度不一致、或任一方为空 → 空列表（不抛异常）；
/// - 退化向量（余弦为 null，如零向量/NaN/维度不齐）不参与合并；
/// - 成员 <2 的组不输出（孤立条目隐藏）；
/// - 输出组按首成员在输入中的顺序排序，组内保持输入序，结果确定。
List<List<String>> clusterSimilar({
  required List<String> texts,
  required List<List<double>> vectors,
  required double threshold,
}) {
  if (texts.length != vectors.length || texts.isEmpty) {
    return const [];
  }
  final unionFind = _UnionFind(texts.length);
  for (var i = 0; i < texts.length; i++) {
    for (var j = i + 1; j < texts.length; j++) {
      final similarity = cosineSimilarity(vectors[i], vectors[j]);
      if (similarity == null || similarity < threshold) {
        continue;
      }
      unionFind.union(i, j);
    }
  }
  // 按 root 归组：首个成员出现的顺序即输出组序，组内按输入序收集。
  final rootToGroupIndex = <int, int>{};
  final groups = <List<String>>[];
  for (var i = 0; i < texts.length; i++) {
    final root = unionFind.find(i);
    final groupIndex = rootToGroupIndex[root];
    if (groupIndex == null) {
      rootToGroupIndex[root] = groups.length;
      groups.add([texts[i]]);
    } else {
      groups[groupIndex].add(texts[i]);
    }
  }
  return groups.where((group) => group.length >= 2).toList(growable: false);
}

/// 朴素并查集：根挂载 + 路径压缩（find 摊还近 O(1)），索引即输入序号。
class _UnionFind {
  _UnionFind(int size) : _parent = List<int>.generate(size, (index) => index);

  final List<int> _parent;

  /// 返回 [x] 所在集合的根，路径压缩摊还近 O(1)。
  int find(int x) {
    if (_parent[x] != x) {
      _parent[x] = find(_parent[x]);
    }
    return _parent[x];
  }

  /// 合并 [a] 与 [b] 所在集合；已同集合时为空操作。
  void union(int a, int b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA == rootB) {
      return;
    }
    _parent[rootB] = rootA;
  }
}
