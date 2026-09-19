/// float32 编解码 — 向量 blob 与内存 `List<double>` 互转（spec §2 D2）。
///
/// 打包格式：IEEE 754 单精度（float32）小端（LE）连续落盘，每元素 4 字节；
/// 纯 Dart 零 I/O、零依赖。1536 维 → 6144 B/行（spec §9.5 量级口径）；
/// 往返存在 float64→float32 重放误差（相对 ~1e-7 量级），调用方按
/// 1e-6 公差断言。
library;

import 'dart:typed_data';

/// `List<double>` → float32 小端字节序列（每元素 4 字节）。
///
/// 空列表 → 空字节；元素不设合法性守卫（NaN/±无穷按 IEEE754 如实打包，
/// 数值面校验归响应解析层，SR-17）。
Uint8List packFloat32(List<double> values) {
  final bytes = Uint8List(values.length * 4);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < values.length; i++) {
    data.setFloat32(i * 4, values[i], Endian.little);
  }
  return bytes;
}

/// float32 小端字节序列 → `List<double>`。
///
/// [bytes] 长度非 4 的倍数 → [FormatException]（长度守卫，防止错位解析
/// 产生垃圾向量）；空字节 → 空列表。
List<double> unpackFloat32(Uint8List bytes) {
  if (bytes.length % 4 != 0) {
    throw FormatException(
      'Float32 blob length must be a multiple of 4, got ${bytes.length}',
    );
  }
  final data = ByteData.sublistView(bytes);
  final count = bytes.length ~/ 4;
  return List<double>.generate(
    count,
    (i) => data.getFloat32(i * 4, Endian.little),
  );
}
