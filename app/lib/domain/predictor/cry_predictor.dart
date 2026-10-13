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
  const Prediction({required this.ranked, required this.predictorVersion});
  final List<CauseScore> ranked; // 按概率降序
  final String predictorVersion;
  List<CauseScore> top(int n) => ranked.take(n).toList();
}

/// 猜原因的统一接口。三个阶段只替换实现：
/// v1 RuleBasedPredictor -> v3 TfliteCryPredictor（+ 个性化）。
abstract class CryPredictor {
  String get version;
  Future<Prediction> predict(AudioFeatures audio, CryContext context);
}
