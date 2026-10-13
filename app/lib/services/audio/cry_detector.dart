import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

/// 基于 YAMNet（tflite_flutter）的端上哭声检测。
/// 模型：assets/models/yamnet.tflite（TF Hub lite-model_yamnet_classification_tflite_1，约 4MB）
/// 输入 16kHz 单声道 15600 个采样（0.975 秒，-1..1 浮点），输出 521 类得分。
/// 取 "Baby cry, infant cry"（索引 20）和 "Crying, sobbing"（索引 19）的较大值。
class CryDetector {
  CryDetector._(this._interpreter);

  static const asset = 'assets/models/yamnet.tflite';
  static const int sampleRate = 16000;
  static const int frameSamples = 15600;
  static const int babyCryClassIndex = 20;
  static const int cryingClassIndex = 19;
  static const int numClasses = 521;

  final Interpreter _interpreter;

  static Future<CryDetector> load() async =>
      CryDetector._(await Interpreter.fromAsset(asset));

  /// 一帧的哭声得分 0..1
  double score(Float32List frame) {
    assert(frame.length == frameSamples);
    final out = [List<double>.filled(numClasses, 0)];
    _interpreter.run(frame, out);
    final s = out[0];
    return s[babyCryClassIndex] > s[cryingClassIndex] ? s[babyCryClassIndex] : s[cryingClassIndex];
  }

  void close() => _interpreter.close();
}

/// 触发判定：最近 [window] 帧里有 [hits] 帧超过阈值就触发，触发后冷却 [cooldown]。
/// 纯逻辑，方便单测。
class CryTrigger {
  CryTrigger({this.threshold = 0.35, this.window = 3, this.hits = 2, this.cooldown = const Duration(seconds: 60)});

  final double threshold;
  final int window;
  final int hits;
  final Duration cooldown;
  final List<bool> _recent = [];
  DateTime? _lastFired;

  /// 送入一帧得分，返回是否应当开始录音
  bool add(double score, DateTime now) {
    _recent.add(score >= threshold);
    if (_recent.length > window) _recent.removeAt(0);
    if (_lastFired != null && now.difference(_lastFired!) < cooldown) return false;
    if (_recent.where((v) => v).length >= hits) {
      _lastFired = now;
      _recent.clear();
      return true;
    }
    return false;
  }
}

/// 16 位小端 PCM 字节 → -1..1 浮点
Float32List pcm16ToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final bd = ByteData.sublistView(bytes);
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// 滑动窗口缓冲（环形）：攒够一帧后每 [hop] 个采样吐出一帧
class FrameBuffer {
  FrameBuffer({this.frame = CryDetector.frameSamples, this.hop = 8000}) : _ring = Float32List(frame);
  final int frame;
  final int hop;
  final Float32List _ring;
  int _write = 0;
  int _filled = 0;
  int _sinceLast = 0;

  List<Float32List> add(Float32List samples) {
    final frames = <Float32List>[];
    for (final s in samples) {
      _ring[_write] = s;
      _write = (_write + 1) % frame;
      if (_filled < frame) _filled++;
      _sinceLast++;
      if (_filled == frame && _sinceLast >= hop) {
        final out = Float32List(frame);
        // 从最旧的采样开始拷贝
        out.setRange(0, frame - _write, _ring, _write);
        out.setRange(frame - _write, frame, _ring, 0);
        frames.add(out);
        _sinceLast = 0;
      }
    }
    return frames;
  }
}
