import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/features/cry/analyzing_view.dart';
import 'package:honghong/services/audio/cry_embedder.dart';

/// 输出取决于帧内容（确定性），用来比较同步版和后台版结果完全一致；
/// 每帧故意忙等一会儿，模拟 YAMNet 的计算量。
class _ContentModel implements FrameEmbedder {
  _ContentModel({this.busyMs = 0});
  final int busyMs;
  static String? lastIsolate;
  @override
  (Float32List, double) run(Float32List frame) {
    lastIsolate = Isolate.current.debugName;
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < busyMs) {}
    var sum = 0.0, energy = 0.0;
    for (final v in frame) {
      sum += v;
      energy += v * v;
    }
    final e = Float32List(1024);
    for (var d = 0; d < 1024; d++) {
      e[d] = sum * math.sin(d * .01) + energy * math.cos(d * .02);
    }
    return (e, (energy / frame.length * 50).clamp(0.0, 1.0));
  }

  @override
  void close() {}
}

FrameEmbedder _fast() => _ContentModel();
FrameEmbedder _slow() => _ContentModel(busyMs: 60);

Future<String> _writeWav(int n) async {
  final pcm = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    pcm.setInt16(i * 2, (12000 * math.sin(i * .07) * math.sin(i * .0013)).round(), Endian.little);
  }
  final h = ByteData(44);
  void s(int o, String t) => t.codeUnits.asMap().forEach((k, c) => h.setUint8(o + k, c));
  s(0, 'RIFF');
  h.setUint32(4, 36 + n * 2, Endian.little);
  s(8, 'WAVE');
  s(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, 1, Endian.little);
  h.setUint32(24, 16000, Endian.little);
  h.setUint32(28, 32000, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  s(36, 'data');
  h.setUint32(40, n * 2, Endian.little);
  final f = File('${Directory.systemTemp.createTempSync('hh').path}/x.wav');
  await f.writeAsBytes([...h.buffer.asUint8List(), ...pcm.buffer.asUint8List()]);
  return f.path;
}

void main() {
  test('后台 isolate 的结果和主线程同步计算完全相同', () async {
    final path = await _writeWav(16000 * 10);
    final sync = CryEmbedder(_ContentModel()).embed(decodeWav16(File(path).readAsBytesSync()));
    final bg = await CryEmbedder.embedWavInBackground(path, _fast);
    expect(bg.embedding, orderedEquals(sync.embedding!));
    expect(bg.cryConfidence, sync.cryConfidence);
  });

  test('分析在后台 isolate 跑，主线程事件循环不被阻塞', () async {
    final path = await _writeWav(16000 * 10); // 19 帧 × 60ms ≈ 1.1s
    _ContentModel.lastIsolate = null;
    var ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 16), (_) => ticks++);
    final sw = Stopwatch()..start();
    await CryEmbedder.embedWavInBackground(path, _slow);
    timer.cancel();
    final expected = sw.elapsedMilliseconds ~/ 16;
    expect(sw.elapsedMilliseconds, greaterThan(1000));
    // 如果在主线程跑，这 1 秒里一帧都不会触发
    expect(ticks, greaterThan(expected ~/ 2), reason: '$ticks ticks in ${sw.elapsedMilliseconds}ms');
    expect(_ContentModel.lastIsolate, isNull); // 模型只在另一个 isolate 里被调用过
  });

  testWidgets('减少动态效果时分析动画静止', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: Scaffold(body: AnalyzingView())),
    ));
    await tester.pumpAndSettle(); // 不会因为循环动画超时
    expect(find.text(AnalyzingView.text), findsOneWidget);
  });
}
