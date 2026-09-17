/// 余弦相似度纯函数 + 语义阈值常量（spec D6 单处定义）。
///
/// 纯 Dart 零 I/O、零依赖；退化输入一律返回 null 而非抛异常，
/// 供 P2 检索 / P4 聚类复用（D2 内存余弦）。
library;

import 'dart:math' as math;

/// 语义召回（P2 混合检索）最小余弦阈值，spec D6 初值 0.5，标定改此常量。
const double kSemanticRecallMinSimilarity = 0.5;

/// 人格演化聚类（P4）相似余弦阈值，spec D6 初值 0.75，标定改此常量。
const double kClusterSimilarityThreshold = 0.75;

/// 计算 [a] 与 [b] 的余弦相似度，值域 [-1, 1]（按余弦定义）。
///
/// 退化输入返回 null（不抛异常）：
/// - 长度不一致；
/// - 任一为空列表；
/// - 任一向量的范数为零（全部元素为零）；
/// - 任一元素为 NaN 或 ±无穷（非有限值不属于余弦定义域）。
double? cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) {
    return null;
  }
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    final ai = a[i];
    final bi = b[i];
    if (!ai.isFinite || !bi.isFinite) {
      return null;
    }
    dot += ai * bi;
    normA += ai * ai;
    normB += bi * bi;
  }
  if (normA == 0.0 || normB == 0.0) {
    return null;
  }
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}
