import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../../domain/predictor/cry_predictor.dart';

/// 一帧 → (1024 维 embedding, 哭声得分)
abstract class FrameEmbedder {
  (Float32List, double) run(Float32List frame);
  void close();
}

/// 录音 → 猜原因用的音频特征。每一步都和 ml/src/features.py 一致：
/// 16kHz 单声道 → 63 阶 FIR 低通 3.8kHz → 15600 采样一帧、步长 7800 → YAMNet embedding
/// → 只对哭声得分 ≥ 0.2 的帧取均值（没有就全部帧）。
class CryEmbedder {
  CryEmbedder(this._model);
  final FrameEmbedder _model;

  static const asset = 'assets/models/yamnet_embed.tflite';
  static const sampleRate = 16000, frame = 15600, hop = 7800;
  static const firTaps = 63, firCutoffHz = 3800.0, cryFrameMin = 0.2;
  static const maxSeconds = 12;

  static Future<CryEmbedder> load() async => CryEmbedder(await TfliteFrameEmbedder.load());

  static final Float32List fir = firLowpass();

  /// Hamming 窗 sinc 低通，系数和为 1
  static Float32List firLowpass({int taps = firTaps, double cutoff = firCutoffHz, int sr = sampleRate}) {
    final fc = cutoff / sr, m = taps - 1;
    final h = List<double>.filled(taps, 0);
    for (var n = 0; n < taps; n++) {
      final k = n - m / 2;
      final s = k == 0 ? 2 * fc : math.sin(2 * math.pi * fc * k) / (math.pi * k);
      h[n] = s * (0.54 - 0.46 * math.cos(2 * math.pi * n / m));
    }
    final sum = h.fold<double>(0, (a, b) => a + b);
    return Float32List.fromList([for (final v in h) v / sum]);
  }

  /// 与 numpy.convolve(x, h, mode='same') 相同
  static Float32List lowpass(Float32List x) {
    final h = fir, n = x.length, t = h.length, off = (t - 1) ~/ 2;
    final y = Float32List(n);
    for (var i = 0; i < n; i++) {
      var acc = 0.0;
      // full 卷积下标 i+off：sum_k x[i+off-k] h[k]
      for (var k = 0; k < t; k++) {
        final j = i + off - k;
        if (j >= 0 && j < n) acc += x[j] * h[k];
      }
      y[i] = acc;
    }
    return y;
  }

  static List<Float32List> frames(Float32List x) {
    if (x.length < frame) return [Float32List(frame)..setRange(0, x.length, x)];
    return [for (var i = 0; i + frame <= x.length; i += hop) Float32List.sublistView(x, i, i + frame)];
  }

  AudioFeatures embed(Float32List samples) {
    if (samples.length > sampleRate * maxSeconds) samples = Float32List.sublistView(samples, 0, sampleRate * maxSeconds);
    final fs = frames(lowpass(samples));
    final embs = <Float32List>[];
    final scores = <double>[];
    for (final f in fs) {
      final (e, s) = _model.run(f);
      embs.add(e);
      scores.add(s);
    }
    var keep = [for (final s in scores) s >= cryFrameMin];
    if (!keep.contains(true)) keep = List.filled(scores.length, true);
    final dim = embs.first.length;
    final out = Float32List(dim);
    var n = 0;
    for (var i = 0; i < embs.length; i++) {
      if (!keep[i]) continue;
      n++;
      for (var d = 0; d < dim; d++) {
        out[d] += embs[i][d];
      }
    }
    for (var d = 0; d < dim; d++) {
      out[d] /= n;
    }
    final mean = scores.fold<double>(0, (a, b) => a + b) / scores.length;
    return AudioFeatures(embedding: out, cryConfidence: mean);
  }

  Future<AudioFeatures> embedWav(String path) async => embed(decodeWav16(await File(path).readAsBytes()));

  void close() => _model.close();
}

/// 16 位 PCM WAV → -1..1 浮点（单声道；多声道取第一声道）
Float32List decodeWav16(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  var channels = 1, p = 12;
  while (p + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(p, p + 4));
    var size = bd.getUint32(p + 4, Endian.little);
    if (id == 'fmt ') channels = bd.getUint16(p + 10, Endian.little);
    if (id == 'data') {
      if (size == 0 || p + 8 + size > bytes.length) size = bytes.length - p - 8; // 录音中断时头部长度可能不对
      final n = size ~/ (2 * channels);
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] = bd.getInt16(p + 8 + i * 2 * channels, Endian.little) / 32768.0;
      }
      return out;
    }
    p += 8 + size + (size & 1);
  }
  throw const FormatException('not a PCM wav');
}

class TfliteFrameEmbedder implements FrameEmbedder {
  TfliteFrameEmbedder(this._it) {
    final outs = _it.getOutputTensors();
    _embIdx = outs.indexWhere((t) => t.shape.last == 1024);
    _scoreIdx = outs.indexWhere((t) => t.shape.last == 521);
  }
  final Interpreter _it;
  late final int _embIdx, _scoreIdx;

  static Future<TfliteFrameEmbedder> load() async => TfliteFrameEmbedder(await Interpreter.fromAsset(CryEmbedder.asset));

  @override
  (Float32List, double) run(Float32List frame) {
    final emb = [List<double>.filled(1024, 0)];
    final sc = [List<double>.filled(521, 0)];
    _it.runForMultipleInputs([frame], {_embIdx: emb, _scoreIdx: sc});
    final s = sc[0];
    return (Float32List.fromList(emb[0]), math.max(s[19], s[20]));
  }

  @override
  void close() => _it.close();
}
