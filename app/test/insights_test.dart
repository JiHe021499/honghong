import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/insights.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/domain/models/cry_cause.dart';

void main() {
  final now = DateTime(2026, 10, 13, 21);

  test('按小时统计哭声，找到峰值', () {
    final r = cryByHour([
      DateTime(2026, 10, 12, 16, 5),
      DateTime(2026, 10, 11, 16, 40),
      DateTime(2026, 10, 10, 11),
    ]);
    expect(r.peakHour, 16);
    expect(r.hours.first, 10);
    expect(r.hours.last, 21);
    expect(r.counts[r.hours.indexOf(16)], 2);
    expect(cryByHour([]).peakHour, isNull);
    // 峰值在凌晨时窗口跟着挪
    final night = cryByHour([DateTime(2026, 10, 12, 3), DateTime(2026, 10, 12, 3, 30)]);
    expect(night.hours, contains(3));
  });

  test('喂奶间隔与趋势：前 4 天 vs 最近 3 天', () {
    final logs = <LogPoint>[];
    // 6 天前到 4 天前：每 2.5 小时
    for (var i = 0; i < 10; i++) {
      logs.add(LogPoint(CareLogType.feed, now.subtract(const Duration(days: 6)).add(Duration(minutes: 150 * i))));
    }
    // 最近 2 天：每 3 小时
    for (var i = 0; i < 10; i++) {
      logs.add(LogPoint(CareLogType.feed, now.subtract(const Duration(days: 2)).add(Duration(minutes: 180 * i))));
    }
    final t = feedTrend(logs, now);
    expect(t.before, closeTo(2.5, .01));
    expect(t.recent, closeTo(3.0, .01));
    expect(avgFeedIntervalHours([LogPoint(CareLogType.feed, now)]), isNull);
  });

  test('超过 8 小时的空档视为漏记，不计入', () {
    final a = now.subtract(const Duration(hours: 20));
    final r = avgFeedIntervalHours([
      LogPoint(CareLogType.feed, a),
      LogPoint(CareLogType.feed, a.add(const Duration(hours: 3))),
      LogPoint(CareLogType.feed, a.add(const Duration(hours: 15))),
    ]);
    expect(r, closeTo(3, .01));
  });

  test('平均每天睡眠只算已结束的', () {
    final s = now.subtract(const Duration(hours: 10));
    final r = avgSleepHoursPerDay([
      LogPoint(CareLogType.sleep, s, s.add(const Duration(hours: 2))),
      LogPoint(CareLogType.sleep, s.add(const Duration(hours: 4)), s.add(const Duration(hours: 5))),
      LogPoint(CareLogType.sleep, now.subtract(const Duration(minutes: 5))), // 进行中
    ], now);
    expect(r, closeTo(3, .01));
  });

  test('哭因占比不计"不确定"', () {
    final r = causeShare({'hungry': 5, 'sleepy': 3, 'unknown': 10, 'gas': 2});
    expect(r.first.$1, CryCause.hungry);
    expect(r.first.$2, closeTo(.5, 1e-9));
    expect(r.length, 3);
    expect(causeShare({}), isEmpty);
    expect(learningProgress(25), .5);
    expect(learningProgress(500), 1);
  });
}
