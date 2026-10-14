import 'dart:convert';
import 'dart:typed_data';

import '../models/cry_cause.dart';
import '../models/cry_context.dart';

/// 音频特征。v1 可为空；v3 为 YAMNet embedding（1024 维均值）。
class AudioFeatures {
  const AudioFeatures({this.embedding, this.cryConfidence = 0});
  final Float32List? embedding;
  final double cryConfidence;
}

class CauseScore {
  const CauseScore(this.cause, this.probability, this.reason);
  final CryCause cause;
  final double probability; // 0..1，所有原因之和为 1
  final String reason; // 给家长看的一句解释
}

class Prediction {
  const Prediction({required this.ranked, required this.predictorVersion, this.components});
  final List<CauseScore> ranked; // 按概率降序
  final String predictorVersion;

  /// 模型版（阶段 3）各部分的原始输出，用于端上个性化和以后评估：
  /// {'rule': {cause: p}, 'model': {cause: p}, 'model_version': 'cls-1', 'weight': 0.0}
  final Map<String, Object?>? components;
  List<CauseScore> top(int n) => ranked.take(n).toList();

  Map<String, Object?> toJson() => {
        'version': predictorVersion,
        'ranked': [
          for (final s in ranked)
            {'cause': s.cause.name, 'p': s.probability, 'reason': s.reason}
        ],
        if (components != null) 'components': components,
      };

  factory Prediction.fromJson(Map<String, dynamic> json) => Prediction(
        predictorVersion: json['version'] as String,
        components: (json['components'] as Map?)?.cast<String, Object?>(),
        ranked: [
          for (final r in (json['ranked'] as List).cast<Map<String, dynamic>>())
            CauseScore(CryCause.values.byName(r['cause'] as String),
                (r['p'] as num).toDouble(), r['reason'] as String),
        ],
      );

  static Prediction decode(String s) =>
      Prediction.fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// components 里某一部分（rule / model）的第一名
  String? componentTop(String part) {
    final m = (components?[part] as Map?)?.cast<String, Object?>();
    if (m == null || m.isEmpty) return null;
    return m.entries.reduce((a, b) => (a.value as num) >= (b.value as num) ? a : b).key;
  }

  static String? topCauseFromJson(String s) {
    final r = decode(s).ranked;
    return r.isEmpty ? null : r.first.cause.name;
  }
}

/// 猜原因的统一接口。三个阶段只替换实现：
/// v1 RuleBasedPredictor -> v3 TfliteCryPredictor（+ 个性化）。
abstract class CryPredictor {
  String get version;
  Future<Prediction> predict(AudioFeatures audio, CryContext context);
}
