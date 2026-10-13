import 'models/care_log_type.dart';
import 'models/cry_context.dart';

/// 最近一条记录的精简信息（与数据层解耦）
class LastLog {
  const LastLog(this.startedAt, [this.endedAt]);
  final DateTime startedAt;
  final DateTime? endedAt;
}

/// 根据每类最近一条记录生成上下文快照。
CryContext buildCryContext({
  required DateTime now,
  required DateTime birthDate,
  required Map<CareLogType, LastLog> latest,
}) {
  Duration? since(CareLogType t) {
    final l = latest[t];
    return l == null ? null : now.difference(l.startedAt);
  }

  final sleep = latest[CareLogType.sleep];
  final isSleeping = sleep != null && sleep.endedAt == null;
  final sinceWake = sleep == null || isSleeping
      ? null
      : now.difference(sleep.endedAt!);

  return CryContext(
    at: now,
    babyAgeMonths: now.difference(birthDate).inDays / 30.44,
    sinceLastFeed: since(CareLogType.feed),
    sinceLastSleepEnd: sinceWake,
    sinceLastDiaper: since(CareLogType.diaper),
    sinceLastBurp: since(CareLogType.burp),
    isSleeping: isSleeping,
  );
}

String formatSince(Duration d) {
  if (d.inMinutes < 1) return '刚刚';
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? '$h 小时 $m 分前' : '$m 分钟前';
}
