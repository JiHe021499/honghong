import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/models/cry_cause.dart';
import 'package:honghong/domain/models/cry_context.dart';
import 'package:honghong/domain/predictor/cry_predictor.dart';
import 'package:honghong/domain/predictor/model_meta.dart';
import 'package:honghong/domain/predictor/model_predictor.dart';
import 'package:honghong/domain/predictor/personalization.dart';
import 'package:honghong/domain/predictor/rule_based_predictor.dart';
import 'package:honghong/services/audio/cry_embedder.dart';

class FixedHead implements CryHead {
  FixedHead(this.out, {this.fail = false});
  List<double> out;
  bool fail;
  Float32List? last;
  @override
  List<double> run(Float32List f) {
    last = f;
    if (fail) throw StateError('boom');
    return out;
  }

  @override
  void close() {}
}

ModelMeta meta({double weight = 0.35, List<String> context = const [], double minConf = 0.4}) => ModelMeta.fromJson({
      'version': 'cls-t',
      'classes': ['hungry', 'sleepy', 'gas', 'diaper'],
      'sha256': 'x',
      'input': {'embedding': {'dim': 1024}, 'context': context},
      'blend': {'weight': weight, 'min_confidence': minConf, 'min_cry_score': 0.1},
    });

void main() {
  final ctx = CryContext(
    at: DateTime(2026, 10, 14, 14),
    babyAgeMonths: 2,
    sinceLastFeed: const Duration(minutes: 200),
    sinceLastSleepEnd: const Duration(minutes: 30),
    sinceLastDiaper: const Duration(minutes: 40),
  );
  final audio = AudioFeatures(embedding: Float32List(1024), cryConfidence: 0.6);
  Map<CryCause, double> probs(Prediction p) => {for (final s in p.ranked) s.cause: s.probability};

  test('内置模型元数据可解析，类别与 App 原因对齐', () {
    final m = ModelMeta.decode(File('assets/models/cry_head.json').readAsStringSync());
    expect(m.classes, [CryCause.hungry, CryCause.sleepy, CryCause.gas, CryCause.diaper]);
    expect(m.embeddingDim, 1024);
    expect(m.selftestInput!.length, 1024);
    expect(m.blendWeight, 0); // v1 评估不比随机好：影子运行
  });

  test('没有音频 / 哭声得分太低：只用规则，记下跳过原因', () async {
    final rule = RuleBasedPredictor();
    final p = ModelPredictor(rule: rule, head: FixedHead([1, 0, 0, 0]), meta: meta());
    final r = await p.predict(const AudioFeatures(), ctx);
    expect(r.predictorVersion, 'rule-1');
    expect(r.components!['skipped'], 'no_audio');
    final low = await p.predict(AudioFeatures(embedding: Float32List(1024), cryConfidence: 0.05), ctx);
    expect(low.components!['skipped'], 'low_cry_score');
    expect(probs(low), probs(await rule.predict(audio, ctx)));
  });

  test('权重 0（影子运行）：排序和规则完全一样，但记录模型输出', () async {
    final rule = RuleBasedPredictor();
    final p = ModelPredictor(rule: rule, head: FixedHead([0.1, 0.1, 0.1, 0.7]), meta: meta(weight: 0));
    final r = await p.predict(audio, ctx);
    final base = await rule.predict(audio, ctx);
    expect(r.ranked.map((s) => s.cause), base.ranked.map((s) => s.cause));
    expect(r.componentTop('model'), 'diaper');
    expect(r.componentTop('rule'), base.ranked.first.cause.name);
    expect(r.components!['weight'], 0.0);
  });

  test('融合：模型自信时向模型偏移；"要抱"的概率质量保持规则的；总和为 1', () async {
    final rule = RuleBasedPredictor();
    final base = probs(await rule.predict(audio, ctx));
    final r = await ModelPredictor(rule: rule, head: FixedHead([0.05, 0.05, 0.05, 0.85]), meta: meta(weight: 0.5)).predict(audio, ctx);
    final p = probs(r);
    expect(p[CryCause.diaper]! > base[CryCause.diaper]!, isTrue);
    expect(p[CryCause.holdMe], closeTo(base[CryCause.holdMe]!, 1e-9));
    expect(p.values.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
    expect(r.predictorVersion, 'cls-t+rule-1');
    // 不自信（最高 < 0.4）时不融合
    final unsure = await ModelPredictor(rule: rule, head: FixedHead([0.3, 0.25, 0.25, 0.2]), meta: meta(weight: 0.5)).predict(audio, ctx);
    expect(probs(unsure), base);
  });

  test('模型出错：回调通知并退回规则', () async {
    Object? err;
    final r = await ModelPredictor(rule: RuleBasedPredictor(), head: FixedHead([], fail: true), meta: meta(), onFailure: (e) => err = e).predict(audio, ctx);
    expect(err, isNotNull);
    expect(r.components!['skipped'], 'error');
    final bad = await ModelPredictor(rule: RuleBasedPredictor(), head: FixedHead([1, 0]), meta: meta(), onFailure: (e) => err = e).predict(audio, ctx);
    expect(bad.components!['skipped'], 'error');
  });

  test('上下文特征按元数据顺序拼在 embedding 后面', () async {
    final head = FixedHead([0.25, 0.25, 0.25, 0.25]);
    await ModelPredictor(rule: RuleBasedPredictor(), head: head, meta: meta(context: ['since_feed_h', 'is_sleeping', 'hour_sin'])).predict(audio, ctx);
    expect(head.last!.length, 1027);
    expect(head.last![1024], closeTo(200 / 60 / 12, 1e-6));
    expect(head.last![1025], 0);
    expect(head.last![1026], closeTo(math.sin(2 * math.pi * 14 / 24), 1e-6));
  });

  group('端上个性化', () {
    Prediction pred(String model, String rule) => Prediction(ranked: const [], predictorVersion: 'x', components: {
          'rule': {rule: 0.6, 'holdMe': 0.1},
          'model': {model: 0.7, 'hungry': 0.1},
        });

    test('样本不足 8 条：不改权重', () {
      final p = Personalization.fromFeedback([for (var i = 0; i < 7; i++) (pred('gas', 'hungry'), CryCause.gas)]);
      expect(p.weight, isNull);
      expect(p.samples, 7);
    });

    test('模型比规则更常猜中：加权；更差：关掉', () {
      final good = Personalization.fromFeedback([
        for (var i = 0; i < 8; i++) (pred('gas', 'hungry'), CryCause.gas),
        for (var i = 0; i < 2; i++) (pred('gas', 'hungry'), CryCause.hungry),
      ]);
      expect(good.modelHits, 8);
      expect(good.ruleHits, 2);
      expect(good.weight, Personalization.maxWeight);
      final bad = Personalization.fromFeedback([for (var i = 0; i < 10; i++) (pred('gas', 'hungry'), CryCause.hungry)]);
      expect(bad.weight, 0);
      // 偏置：模型老猜胀气但实际是饿 → 压低胀气、抬高饿
      expect(bad.bias[CryCause.gas]! < 1, isTrue);
      expect(bad.bias[CryCause.hungry]! > 1, isTrue);
    });

    test('个性化权重覆盖默认权重，偏置作用在模型输出上', () async {
      final personal = Personalization.fromFeedback([for (var i = 0; i < 10; i++) (pred('diaper', 'hungry'), CryCause.diaper)]);
      final r = await ModelPredictor(rule: RuleBasedPredictor(), head: FixedHead([0.1, 0.1, 0.1, 0.7]), meta: meta(weight: 0), personal: personal).predict(audio, ctx);
      expect(r.components!['weight'], greaterThan(0));
      expect(r.ranked.first.cause, CryCause.diaper);
    });
  });

  group('音频特征（与 ml/src/features.py 一致）', () {
    test('FIR 低通系数与 Python 相同', () {
      final h = CryEmbedder.fir;
      expect(h.length, 63);
      expect(h[0], closeTo(0.00062390644, 1e-8));
      expect(h[31], closeTo(0.47444856, 1e-6));
      expect(h.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-5));
    });

    test('低通结果与 numpy.convolve(mode=same) 相同', () {
      final x = Float32List.fromList([for (var i = 0; i < 200; i++) math.sin(i * 0.05) + math.sin(i * 2.5)]);
      final y = CryEmbedder.lowpass(x);
      expect(y[0], closeTo(0.110519, 1e-4));
      expect(y[10], closeTo(0.483752, 1e-4));
      expect(y[100], closeTo(-0.958106, 1e-4));
      expect(y[199], closeTo(-0.190243, 1e-4));
    });

    test('分帧：不足一帧补零，否则步长 7800', () {
      expect(CryEmbedder.frames(Float32List(1000)).single.length, 15600);
      expect(CryEmbedder.frames(Float32List(16000 * 5)).length, 9);
    });

    test('只对哭声帧取均值；WAV 解码', () {
      final model = _SeqModel([(1.0, 0.9), (5.0, 0.05), (3.0, 0.5)]);
      final f = CryEmbedder(model).embed(Float32List(15600 + 7800 * 2));
      expect(f.embedding![0], closeTo(2.0, 1e-6)); // (1+3)/2，不含非哭声帧
      expect(f.cryConfidence, closeTo((0.9 + 0.05 + 0.5) / 3, 1e-6));
      final wav = _wav([0, 16384, -32768]);
      expect(decodeWav16(wav), [0, 0.5, -1]);
    });
  });
}

class _SeqModel implements FrameEmbedder {
  _SeqModel(this.seq);
  final List<(double, double)> seq;
  int i = 0;
  @override
  (Float32List, double) run(Float32List frame) {
    final (v, s) = seq[i++ % seq.length];
    return (Float32List(1024)..fillRange(0, 1024, v), s);
  }

  @override
  void close() {}
}

Uint8List _wav(List<int> samples) {
  final b = BytesBuilder();
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  ByteData u32(int v) => ByteData(4)..setUint32(0, v, Endian.little);
  ByteData u16(int v) => ByteData(2)..setUint16(0, v, Endian.little);
  b.add('RIFF'.codeUnits);
  b.add(u32(36 + samples.length * 2).buffer.asUint8List());
  b.add('WAVEfmt '.codeUnits);
  b.add(u32(16).buffer.asUint8List());
  b.add(u16(1).buffer.asUint8List());
  b.add(u16(1).buffer.asUint8List());
  b.add(u32(16000).buffer.asUint8List());
  b.add(u32(32000).buffer.asUint8List());
  b.add(u16(2).buffer.asUint8List());
  b.add(u16(16).buffer.asUint8List());
  b.add('data'.codeUnits);
  b.add(u32(samples.length * 2).buffer.asUint8List());
  b.add(data.buffer.asUint8List());
  return b.toBytes();
}
