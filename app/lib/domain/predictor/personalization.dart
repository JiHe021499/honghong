import '../models/cry_cause.dart';
import 'cry_predictor.dart';

/// 端上个性化（轻量、只用本机数据）：根据这个宝宝的家长反馈，
/// ① 调整模型融合权重：模型第一名比规则第一名更常猜中才逐步加权，更差就关掉；
/// ② 每个原因的偏置：模型常把 A 猜成第一但家长说是 B 时，压低 A、抬高 B。
/// 规则部分已有按反馈频率算的先验（priorsFromCounts）。
class Personalization {
  const Personalization({this.weight, this.bias = const {}, this.samples = 0, this.modelHits = 0, this.ruleHits = 0});

  /// null = 用模型元数据里的默认权重
  final double? weight;
  final Map<CryCause, double> bias;
  final int samples;
  final int modelHits;
  final int ruleHits;

  static const minSamples = 8;
  static const maxWeight = 0.6;

  /// [labelled]：(当时的预测, 家长确认的原因)，只含模型参与过（有 components.model）的事件
  factory Personalization.fromFeedback(Iterable<(Prediction, CryCause)> labelled) {
    var n = 0, mh = 0, rh = 0;
    final actual = <CryCause, int>{}, predicted = <CryCause, int>{};
    for (final (p, cause) in labelled) {
      final mt = p.componentTop('model');
      final rt = p.componentTop('rule');
      if (mt == null || rt == null) continue;
      n++;
      if (mt == cause.name) mh++;
      if (rt == cause.name) rh++;
      actual[cause] = (actual[cause] ?? 0) + 1;
      final m = CryCause.values.byName(mt);
      predicted[m] = (predicted[m] ?? 0) + 1;
    }
    if (n < minSamples) return Personalization(samples: n, modelHits: mh, ruleHits: rh);
    final diff = (mh - rh) / n;
    final w = diff <= 0 ? 0.0 : (0.15 + diff).clamp(0.0, maxWeight);
    return Personalization(
      weight: w,
      bias: {
        for (final c in CryCause.values)
          c: (((actual[c] ?? 0) + 1) / ((predicted[c] ?? 0) + 1)).clamp(0.5, 2.0),
      },
      samples: n,
      modelHits: mh,
      ruleHits: rh,
    );
  }
}
