/// 一次哭声发生时的上下文快照。
class CryContext {
  const CryContext({
    required this.at,
    required this.babyAgeMonths,
    this.sinceLastFeed,
    this.sinceLastSleepEnd,
    this.sinceLastDiaper,
    this.sinceLastBurp,
    this.isSleeping = false,
  });

  final DateTime at;
  final double babyAgeMonths;
  final Duration? sinceLastFeed;
  final Duration? sinceLastSleepEnd; // 醒着多久了
  final Duration? sinceLastDiaper;
  final Duration? sinceLastBurp;
  final bool isSleeping;

  int get hourOfDay => at.hour;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'baby_age_months': babyAgeMonths,
        'since_feed_min': sinceLastFeed?.inMinutes,
        'since_wake_min': sinceLastSleepEnd?.inMinutes,
        'since_diaper_min': sinceLastDiaper?.inMinutes,
        'since_burp_min': sinceLastBurp?.inMinutes,
        'is_sleeping': isSleeping,
        'hour': hourOfDay,
      };
}
