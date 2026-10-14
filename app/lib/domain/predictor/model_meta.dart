import 'dart:convert';

import '../models/cry_cause.dart';

/// 分类模型的元数据（ml/src/train.py 导出的 json，和 .tflite 一起下发）
class ModelMeta {
  const ModelMeta({
    required this.version,
    required this.classes,
    required this.sha256,
    required this.embeddingDim,
    required this.contextFeatures,
    required this.blendWeight,
    required this.minConfidence,
    required this.minCryScore,
    this.selftestInput,
    this.selftestExpected,
    this.selftestTol = 1e-3,
    this.raw = const {},
  });

  final String version;
  final List<CryCause> classes;
  final String sha256;
  final int embeddingDim;
  final List<String> contextFeatures;
  final double blendWeight;
  final double minConfidence;
  final double minCryScore;
  final List<double>? selftestInput;
  final List<double>? selftestExpected;
  final double selftestTol;
  final Map<String, dynamic> raw;

  int get inputDim => embeddingDim + contextFeatures.length;

  factory ModelMeta.fromJson(Map<String, dynamic> j) {
    final input = (j['input'] as Map?)?.cast<String, dynamic>() ?? const {};
    final emb = (input['embedding'] as Map?)?.cast<String, dynamic>() ?? const {};
    final blend = (j['blend'] as Map?)?.cast<String, dynamic>() ?? const {};
    final st = (j['selftest'] as Map?)?.cast<String, dynamic>();
    List<double>? nums(Object? v) => v == null ? null : [for (final x in v as List) (x as num).toDouble()];
    return ModelMeta(
      version: j['version'] as String,
      classes: [for (final c in j['classes'] as List) CryCause.values.byName(c as String)],
      sha256: j['sha256'] as String,
      embeddingDim: (emb['dim'] as num?)?.toInt() ?? 1024,
      contextFeatures: [for (final c in (input['context'] as List?) ?? const []) c as String],
      blendWeight: (blend['weight'] as num?)?.toDouble() ?? 0,
      minConfidence: (blend['min_confidence'] as num?)?.toDouble() ?? 0.4,
      minCryScore: (blend['min_cry_score'] as num?)?.toDouble() ?? 0.1,
      selftestInput: nums(st?['input']),
      selftestExpected: nums(st?['expected']),
      selftestTol: (st?['tol'] as num?)?.toDouble() ?? 1e-3,
      raw: j,
    );
  }

  static ModelMeta decode(String s) => ModelMeta.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
