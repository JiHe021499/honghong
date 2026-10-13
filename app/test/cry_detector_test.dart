import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/services/audio/cry_detector.dart';

void main() {
  test('3 帧里 2 帧超过阈值才触发，触发后冷却', () {
    final t = CryTrigger(threshold: .5, cooldown: const Duration(seconds: 60));
    final t0 = DateTime(2026);
    expect(t.add(.9, t0), isFalse);
    expect(t.add(.1, t0), isFalse);
    expect(t.add(.8, t0), isTrue);
    expect(t.add(.9, t0.add(const Duration(seconds: 1))), isFalse);
    expect(t.add(.9, t0.add(const Duration(seconds: 2))), isFalse, reason: '冷却中');
    expect(t.add(.9, t0.add(const Duration(seconds: 61))), isTrue);
  });

  test('一直很小声不会触发', () {
    final t = CryTrigger();
    for (var i = 0; i < 100; i++) {
      expect(t.add(.05, DateTime(2026).add(Duration(seconds: i))), isFalse);
    }
  });

  test('环形缓冲：攒满一帧后按步长出帧，顺序正确', () {
    final b = FrameBuffer(frame: 4, hop: 2);
    expect(b.add(Float32List.fromList([1, 2, 3])), isEmpty);
    final f = b.add(Float32List.fromList([4, 5, 6]));
    expect(f.map((e) => e.toList()).toList(), [
      [1, 2, 3, 4],
      [3, 4, 5, 6],
    ]);
  });

  test('PCM16 转浮点', () {
    final bytes = Uint8List(4)..buffer.asByteData().setInt16(0, 16384, Endian.little)..buffer.asByteData().setInt16(2, -32768, Endian.little);
    final f = pcm16ToFloat(bytes);
    expect(f[0], closeTo(.5, 1e-6));
    expect(f[1], -1);
  });
}
