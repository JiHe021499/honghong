import 'dart:math' as math;

import '../models/cry_cause.dart';
import '../models/cry_context.dart';
import 'cry_predictor.dart';

/// 第一阶段：基于上下文的规则加权。
/// 每个原因有基础分，再按各项时间间隔加分，最后 softmax 归一化。
/// [priors] 为该宝宝的个性化权重（由历史反馈统计得出），默认全 1。
class RuleBasedPredictor implements CryPredictor {
  RuleBasedPredictor({Map<CryCause, double>? priors}) : priors = priors ?? const {};

  final Map<CryCause, double> priors;

  @override
  String get version => 'rule-1';

  /// 按月龄估计的喂奶间隔（分钟）。
  static double feedIntervalMin(double ageMonths) {
    if (ageMonths < 1) return 150;
    if (ageMonths < 3) return 180;
    if (ageMonths < 6) return 210;
    return 240;
  }

  /// 按月龄估计的清醒时长上限（分钟）。
  static double wakeWindowMin(double ageMonths) {
    if (ageMonths < 1) return 60;
    if (ageMonths < 3) return 90;
    if (ageMonths < 6) return 120;
    return 150;
  }

  /// ratio = 已过时间 / 典型间隔；越接近或超过 1 分数越高，封顶 3。
  static double _ramp(Duration? d, double typicalMin) {
    if (d == null) return 0.5; // 没有记录：中性
    final r = d.inMinutes / typicalMin;
    return (r * r * 1.5).clamp(0.0, 3.0);
  }

  @override
  Future<Prediction> predict(AudioFeatures audio, CryContext c) async {
    final age = c.babyAgeMonths;
    final raw = <CryCause, double>{};
    final why = <CryCause, String>{};

    raw[CryCause.hungry] = 0.4 + _ramp(c.sinceLastFeed, feedIntervalMin(age));
    why[CryCause.hungry] = c.sinceLastFeed == null
        ? '还没有喂奶记录'
        : '距上次喂奶 ${_fmt(c.sinceLastFeed!)}';

    var sleepy = 0.3 + (c.isSleeping ? 0 : _ramp(c.sinceLastSleepEnd, wakeWindowMin(age)));
    final h = c.hourOfDay;
    if (h >= 19 || h < 6) sleepy += 0.4; // 夜间更可能闹觉
    if (h >= 16 && h < 19) sleepy += 0.2; // 傍晚闹
    raw[CryCause.sleepy] = sleepy;
    why[CryCause.sleepy] = c.sinceLastSleepEnd == null
        ? '当前时段容易闹觉'
        : '已经醒了 ${_fmt(c.sinceLastSleepEnd!)}';

    // 胀气：刚喂完奶不久且没拍嗝，3 个月内更常见
    var gas = 0.3;
    final feed = c.sinceLastFeed;
    if (feed != null && feed.inMinutes <= 60) {
      gas += 0.8;
      final burp = c.sinceLastBurp;
      if (burp == null || burp > feed) gas += 0.6; // 本次喂奶后未拍嗝
    }
    if (age < 3) gas += 0.3;
    raw[CryCause.gas] = gas;
    why[CryCause.gas] = '刚喂完奶不久时容易胀气';

    raw[CryCause.diaper] = 0.3 + _ramp(c.sinceLastDiaper, 180);
    why[CryCause.diaper] = c.sinceLastDiaper == null
        ? '还没有换尿布记录'
        : '距上次换尿布 ${_fmt(c.sinceLastDiaper!)}';

    raw[CryCause.holdMe] = 0.6;
    why[CryCause.holdMe] = '其他需求都满足时，可能只是想被抱';

    // 个性化先验
    raw.updateAll((k, v) => v * (priors[k] ?? 1.0));

    // softmax（温度 1）
    final maxV = raw.values.reduce(math.max);
    final exps = raw.map((k, v) => MapEntry(k, math.exp(v - maxV)));
    final sum = exps.values.fold<double>(0, (a, b) => a + b);
    final ranked = exps.entries
        .map((e) => CauseScore(e.key, e.value / sum, why[e.key]!))
        .toList()
      ..sort((a, b) => b.probability.compareTo(a.probability));

    return Prediction(ranked: ranked, predictorVersion: version);
  }

  static String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '$h 小时 $m 分' : '$m 分钟';
  }
}
