/// VR-05 float32 编解码契约（验收 3）：`List<double>` 与 `Uint8List` 小端
/// LE 往返 + 非法长度守卫。纯函数零 I/O，全部在内存中运行。
library;

import 'dart:typed_data';

import 'package:conver_system_mobile/utils/float32_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('往返（验收 3）', () {
    test('1550 维往返无损（公差 1e-6）', () {
      final values = List<double>.generate(1550, (i) {
        final sign = i.isEven ? 1.0 : -1.0;
        return sign * (i * 0.001 + 0.5);
      });
      final roundTrip = unpackFloat32(packFloat32(values));
      expect(roundTrip.length, 1550);
      for (var i = 0; i < values.length; i++) {
        expect(roundTrip[i], closeTo(values[i], 1e-6));
      }
    });

    test('1536 维标准 embedding 长度往返无损', () {
      final values = List<double>.generate(1536, (i) => (i % 17) * 0.25 - 2.0);
      final roundTrip = unpackFloat32(packFloat32(values));
      expect(roundTrip.length, 1536);
      for (var i = 0; i < values.length; i++) {
        expect(roundTrip[i], closeTo(values[i], 1e-6));
      }
    });

    test('小样本值域往返（正负/小数/零）', () {
      const values = [0.0, -1.0, 3.25, -0.125, 1e-4, -1e5, 2.0];
      final roundTrip = unpackFloat32(packFloat32(values));
      expect(roundTrip.length, values.length);
      for (var i = 0; i < values.length; i++) {
        expect(roundTrip[i], closeTo(values[i], 1e-6));
      }
    });

    test('空列表 <-> 空字节', () {
      final packed = packFloat32(const <double>[]);
      expect(packed, isEmpty);
      expect(unpackFloat32(Uint8List(0)), isEmpty);
    });

    test('NaN 往返保持 isNaN', () {
      final roundTrip = unpackFloat32(packFloat32([double.nan, 1.0]));
      expect(roundTrip.length, 2);
      expect(roundTrip[0].isNaN, isTrue);
      expect(roundTrip[1], closeTo(1.0, 1e-6));
    });
  });

  group('小端字节锚（验收 3）', () {
    test('pack([1.0]) 恰为 00 00 80 3F', () {
      expect(packFloat32([1.0]), [0x00, 0x00, 0x80, 0x3F]);
    });

    test('pack([0.5]) 恰为 00 00 00 3F', () {
      expect(packFloat32([0.5]), [0x00, 0x00, 0x00, 0x3F]);
    });

    test('pack([-1.0]) 恰为 00 00 80 BF（符号位小端）', () {
      expect(packFloat32([-1.0]), [0x00, 0x00, 0x80, 0xBF]);
    });

    test('多元素按顺序连续落盘', () {
      final packed = packFloat32([1.0, 0.5]);
      expect(packed.length, 8);
      expect(packed.sublist(0, 4), [0x00, 0x00, 0x80, 0x3F]);
      expect(packed.sublist(4, 8), [0x00, 0x00, 0x00, 0x3F]);
    });
  });

  group('非法长度守卫（验收 3，FormatException）', () {
    test('非 4 倍数长度全部抛 FormatException', () {
      for (final length in [1, 2, 3, 5, 6, 7]) {
        expect(
          () => unpackFloat32(Uint8List(length)),
          throwsA(isA<FormatException>()),
          reason: 'length=$length',
        );
      }
    });

    test('4 倍数长度不抛', () {
      expect(unpackFloat32(Uint8List(4)).length, 1);
      expect(unpackFloat32(Uint8List(8)).length, 2);
    });
  });

  group('blob 长度契约（spec §9.5：1536 维 = 6144 B/行）', () {
    test('1536 维打包恰为 6144 字节', () {
      expect(packFloat32(List<double>.filled(1536, 0.0)).length, 6144);
    });

    test('1550 维打包恰为 6200 字节', () {
      expect(packFloat32(List<double>.filled(1550, 0.0)).length, 6200);
    });
  });
}
