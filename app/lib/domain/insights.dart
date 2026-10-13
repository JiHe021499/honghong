import 'models/care_log_type.dart';
import 'models/cry_cause.dart';

/// 规律页用到的简化记录（与数据层解耦，方便测试）
class LogPoint {
  const LogPoint(this.type, this.start, [this.end]);
  final CareLogType type;
  final DateTime start;
  final DateTime? end;
}

class HourlyCry {
  const HourlyCry(this.hours, this.counts, this.peakHour);
  final List<int> hours; // 例如 10..21
  final List<int> counts;
  final int? peakHour; // 没有数据时为 null
}

/// 按小时统计哭声次数（默认展示 10 点到 21 点，峰值从全天找）
HourlyCry cryByHour(List<DateTime> cries, {int from = 10, int to = 21}) {
  final all = List.filled(24, 0);
  for (final c in cries) {
    all[c.hour]++;
  }
  int? peak;
  var best = 0;
  for (var h = 0; h < 24; h++) {
    if (all[h] > best) {
      best = all[h];
      peak = h;
    }
  }
  // 峰值不在默认窗口里时，把窗口挪过去
  if (peak != null && (peak < from || peak > to)) {
    from = (peak - 6).clamp(0, 12);
    to = from + 11;
  }
  final hours = [for (var h = from; h <= to; h++) h];
  return HourlyCry(hours, [for (final h in hours) all[h]], peak);
}

/// 平均喂奶间隔（小时），按相邻两次喂奶开始时间计算；少于 2 次返回 null
double? avgFeedIntervalHours(List<LogPoint> logs) {
  final feeds = logs.where((l) => l.type == CareLogType.feed).map((l) => l.start).toList()
    ..sort();
  if (feeds.length < 2) return null;
  var sum = 0.0;
  var n = 0;
  for (var i = 1; i < feeds.length; i++) {
    final gap = feeds[i].difference(feeds[i - 1]).inMinutes / 60;
    if (gap > 8) continue; // 漏记的大空档不算
    sum += gap;
    n++;
  }
  return n == 0 ? null : sum / n;
}

class FeedTrend {
  const FeedTrend(this.before, this.recent);
  final double? before;
  final double? recent;
}

/// 近 7 天的喂奶间隔：前 4 天 vs 最近 3 天
FeedTrend feedTrend(List<LogPoint> logs, DateTime now) {
  final split = now.subtract(const Duration(days: 3));
  final start = now.subtract(const Duration(days: 7));
  return FeedTrend(
    avgFeedIntervalHours(logs.where((l) => l.start.isAfter(start) && l.start.isBefore(split)).toList()),
    avgFeedIntervalHours(logs.where((l) => !l.start.isBefore(split)).toList()),
  );
}

/// 平均每天睡眠时长（小时）：只算已结束的睡眠，按天数平均
double? avgSleepHoursPerDay(List<LogPoint> logs, DateTime now, {int days = 7}) {
  final from = now.subtract(Duration(days: days));
  final sleeps = logs.where((l) =>
      l.type == CareLogType.sleep && l.end != null && l.start.isAfter(from));
  if (sleeps.isEmpty) return null;
  final firstDay = sleeps.map((l) => l.start).reduce((a, b) => a.isBefore(b) ? a : b);
  final span = (now.difference(firstDay).inHours / 24).ceil().clamp(1, days);
  final total = sleeps.fold<int>(0, (a, l) => a + l.end!.difference(l.start).inMinutes);
  return total / 60 / span;
}

/// 各原因占比（来自家长反馈，"不确定"不计），降序
List<(CryCause, double)> causeShare(Map<String, int> counts) {
  final valid = {
    for (final c in CryCause.values)
      if ((counts[c.name] ?? 0) > 0) c: counts[c.name]!,
  };
  final total = valid.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) return const [];
  return (valid.entries.map((e) => (e.key, e.value / total)).toList()
    ..sort((a, b) => b.$2.compareTo(a.$2)));
}

/// 反馈学习进度：每 50 次反馈算"学满"，用于"已经更懂你家宝宝了"
double learningProgress(int feedbacks) => (feedbacks / 50).clamp(0.0, 1.0);
