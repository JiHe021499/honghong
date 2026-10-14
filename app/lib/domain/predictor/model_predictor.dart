import 'dart:math' as math;
import 'dart:typed_data';

import '../models/cry_cause.dart';
import '../models/cry_context.dart';
import 'cry_predictor.dart';
import 'model_meta.dart';
import 'personalization.dart';
import 'rule_based_predictor.dart';

/// 分类头：输入 [embedding(+上下文)]，输出 meta.classes 顺序的概率
abstract class CryHead {
  List<double> run(Float32List features);
  void close();
}

/// 上下文特征，和 ml/src/features.py 的 CONTEXT_FEATURES 一一对应
double contextFeature(String name, CryContext c) {
  double hours(Duration? d) => math.min((d?.inMinutes ?? 360) / 60.0, 12.0) / 12.0;
  return switch (name) {
    'since_feed_h' => hours(c.sinceLastFeed),
    'since_wake_h' => hours(c.sinceLastSleepEnd),
    'since_diaper_h' => hours(c.sinceLastDiaper),
    'since_burp_h' => hours(c.sinceLastBurp),
    'is_sleeping' => c.isSleeping ? 1.0 : 0.0,
    'hour_sin' => math.sin(2 * math.pi * c.hourOfDay / 24),
    'hour_cos' => math.cos(2 * math.pi * c.hourOfDay / 24),
    'age_months' => math.min(c.babyAgeMonths, 24.0) / 24.0,
    _ => 0.0,
  };
}

/// 阶段 3：音频模型 + 上下文规则融合。
/// p(c) ∝ p_rule(c)^(1-w) · p_model(c)^w（只在模型覆盖的原因上，其余原因保留规则的概率质量）。
/// 没有有效哭声音频、模型不够自信、或模型出错时，只用规则（RuleBasedPredictor）。
class ModelPredictor implements CryPredictor {
  ModelPredictor({
    required this.rule,
    required this.head,
    required this.meta,
    this.personal = const Personalization(),
    this.onFailure,
  });

  final RuleBasedPredictor rule;
  final CryHead head;
  final ModelMeta meta;
  final Personalization personal;

  /// 推理出错时回调（模型管理器据此回滚）
  final void Function(Object error)? onFailure;

  @override
  String get version => '${meta.version}+${rule.version}';

  double get effectiveWeight => personal.weight ?? meta.blendWeight;

  @override
  Future<Prediction> predict(AudioFeatures audio, CryContext context) async {
    final base = await rule.predict(audio, context);
    final ruleP = {for (final s in base.ranked) s.cause: s.probability};
    final emb = audio.embedding;
    if (emb == null || emb.length != meta.embeddingDim || audio.cryConfidence < meta.minCryScore) {
      return Prediction(ranked: base.ranked, predictorVersion: rule.version, components: {
        'rule': _named(ruleP),
        'model_version': meta.version,
        'skipped': emb == null ? 'no_audio' : 'low_cry_score',
      });
    }
    List<double> out;
    try {
      final x = Float32List(meta.inputDim)..setRange(0, meta.embeddingDim, emb);
      for (var i = 0; i < meta.contextFeatures.length; i++) {
        x[meta.embeddingDim + i] = contextFeature(meta.contextFeatures[i], context);
      }
      out = head.run(x);
      if (out.length != meta.classes.length || out.any((v) => v.isNaN)) {
        throw StateError('bad model output');
      }
    } catch (e) {
      onFailure?.call(e);
      return Prediction(ranked: base.ranked, predictorVersion: rule.version, components: {
        'rule': _named(ruleP),
        'model_version': meta.version,
        'skipped': 'error',
      });
    }

    // 个性化偏置后重新归一
    final modelP = <CryCause, double>{};
    for (var i = 0; i < meta.classes.length; i++) {
      final c = meta.classes[i];
      modelP[c] = out[i] * (personal.bias[c] ?? 1.0);
    }
    final ms = modelP.values.fold<double>(0, (a, b) => a + b);
    modelP.updateAll((_, v) => ms > 0 ? v / ms : 1 / modelP.length);

    final conf = modelP.values.reduce(math.max);
    final w = conf < meta.minConfidence ? 0.0 : effectiveWeight.clamp(0.0, 1.0);

    final blended = Map<CryCause, double>.from(ruleP);
    if (w > 0) {
      final mass = meta.classes.fold<double>(0, (a, c) => a + (ruleP[c] ?? 0));
      final raw = {
        for (final c in meta.classes)
          c: math.pow(math.max(ruleP[c] ?? 1e-9, 1e-9), 1 - w) * math.pow(math.max(modelP[c]!, 1e-9), w),
      };
      final rs = raw.values.fold<double>(0, (a, b) => a + b);
      for (final c in meta.classes) {
        blended[c] = raw[c]! / rs * mass;
      }
    }

    final why = {for (final s in base.ranked) s.cause: s.reason};
    final ranked = [
      for (final e in blended.entries)
        CauseScore(e.key, e.value,
            w > 0 && modelP[e.key] != null && modelP[e.key]! == conf ? '${why[e.key]}；哭声特征也更像这一类' : why[e.key]!),
    ]..sort((a, b) => b.probability.compareTo(a.probability));

    return Prediction(ranked: ranked, predictorVersion: version, components: {
      'rule': _named(ruleP),
      'model': _named(modelP),
      'model_version': meta.version,
      'weight': w,
    });
  }

  static Map<String, double> _named(Map<CryCause, double> m) =>
      {for (final e in m.entries) e.key.name: double.parse(e.value.toStringAsFixed(4))};
}
