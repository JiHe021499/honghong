import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/diary_repository.dart';
import '../../services/diary/diary_api.dart';
import '../models/care_detail.dart';
import 'diary_card.dart';
import 'diary_card_db.dart';

/// 小结生成时刻（D12：固定 21:00）
const summaryHour = 21;

/// 失败最多重试 3 次（架构 §5.3）
const summaryMaxAttempts = 3;

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);
String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 一天的聚合统计（发给网关的 stats，也作为 statsJson 快照给小结页的四格数字用）
class DayStats {
  DayStats(this.stats, this.sourceIds);
  final Map<String, Object?> stats;
  final List<String> sourceIds;
  bool get isEmpty => sourceIds.isEmpty;
}

/// 今日小结（架构 §5.4）：前台触发、21:00 后生成、补生成昨天、幂等、空日、不改写。
class SummaryService {
  SummaryService(this._db, {required this.api, required this.now, this.promptVersion = 'sum-v1'}) : _repo = DiaryRepository(_db);
  final AppDatabase _db;
  final DiaryRepository _repo;
  final DiaryApi? api;
  final DateTime Function() now;
  final String promptVersion;

  /// 同一进程里同一 (宝宝, 日期) 只允许一个生成在跑：首页和日记页同时触发时只发一次请求
  static final _inflight = <String, Future<DailySummary?>>{};

  /// 触发点（回到前台、打开首页、打开日记页）调用。返回今天（或刚补的昨天）的小结状态。
  Future<void> trigger(String babyId, DateTime birthDate) async {
    final n = now();
    final today = _d(n);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    // D7：昨天没生成（21:00 后一直没打开）→ 补生成昨天
    if (!yesterday.isBefore(_d(birthDate))) await ensure(babyId, yesterday, birthDate);
    if (n.hour >= summaryHour) await ensure(babyId, today, birthDate);
  }

  /// 生成某天的小结（若需要）。已 ready / empty / 失败满 3 次的直接返回，不改写（D8）。
  Future<DailySummary?> ensure(String babyId, DateTime day, DateTime birthDate) {
    final key = '$babyId:${_ymd(day)}';
    final running = _inflight[key];
    if (running != null) return running;
    final f = _ensure(babyId, _d(day), birthDate).whenComplete(() {
      _inflight.remove(key); // 不要返回被移除的 Future，否则 whenComplete 会等自己
    });
    _inflight[key] = f;
    return f;
  }

  Future<DailySummary?> _ensure(String babyId, DateTime day, DateTime birthDate) async {
    final existing = await _repo.summaryOf(babyId, day);
    if (existing != null && !_retryable(existing)) return existing;
    final row = existing ?? await _repo.claimSummary(babyId, day, promptVersion: promptVersion);
    if (!_retryable(row)) return row;
    final s = await statsOf(babyId, day);
    if (s.isEmpty) {
      await _repo.updateSummary(row.id, DailySummariesCompanion(status: const Value('empty'), generatedAt: Value(now())));
      return _repo.summaryOf(babyId, day);
    }
    final a = api;
    if (a == null) return row; // 未配置网关：保持 pending，不计失败次数
    try {
      final r = await a.summary(
        date: _ymd(day),
        ageInDays: day.difference(_d(birthDate)).inDays.clamp(0, 3 * 366),
        stats: s.stats,
        idempotencyKey: row.id,
      );
      await _repo.updateSummary(
          row.id,
          DailySummariesCompanion(
            status: const Value('ready'),
            content: Value(r.content),
            promptVersion: Value(r.promptVersion),
            sourceIds: Value(jsonEncode(s.sourceIds)),
            statsJson: Value(jsonEncode(s.stats)),
            generatedAt: Value(now()),
            attempts: Value(row.attempts + 1),
          ));
    } on DiaryApiException {
      await _repo.updateSummary(row.id, DailySummariesCompanion(status: const Value('failed'), attempts: Value(row.attempts + 1)));
    }
    return _repo.summaryOf(babyId, day);
  }

  static bool _retryable(DailySummary s) => s.status == 'pending' || (s.status == 'failed' && s.attempts < summaryMaxAttempts);

  /// 当日统计：次数只数 care_logs（D2），汇总卡单列 aggregate_count；情绪、其他只发短词。
  Future<DayStats> statsOf(String babyId, DateTime day) async {
    final d0 = _d(day);
    final d1 = DateTime(d0.year, d0.month, d0.day + 1);
    final logs = await (_db.select(_db.careLogs)
          ..where((l) => l.babyId.equals(babyId) & l.deleted.not() & l.startedAt.isBiggerOrEqualValue(d0) & l.startedAt.isSmallerThanValue(d1)))
        .get();
    final cards = (await _repo.cardsOfDay(babyId, d0)).where((c) => c.careLogId == null).toList();
    final ids = [...logs.map((l) => l.id), ...cards.map((c) => c.id)];
    var feed = 0, ml = 0, sleep = 0, sleepMin = 0, diaper = 0, poo = 0, pee = 0;
    for (final l in logs) {
      final detail = CareDetail.decode(l.detail);
      switch (l.type) {
        case 'feed':
          feed++;
          ml += (detail.ml ?? 0).round();
        case 'sleep':
          sleep++;
          if (l.endedAt != null) sleepMin += l.endedAt!.difference(l.startedAt).inMinutes;
        case 'diaper':
          diaper++;
          final k = detail.diaper;
          if (k == DiaperKind.poo || k == DiaperKind.both) poo++;
          if (k == DiaperKind.pee || k == DiaperKind.both) pee++;
      }
    }
    int? aggFeed, aggSleepMin;
    final mood = <Map<String, String?>>[];
    final other = <String>[];
    for (final row in cards) {
      final c = cardFromDb(row);
      switch (c.category) {
        case DiaryCategory.feeding:
          if (c.aggregate) aggFeed = c.intAttr('count') ?? aggFeed;
        case DiaryCategory.sleep:
          final m = c.intAttr('duration_min');
          if (m != null) {
            if (c.aggregate) {
              aggSleepMin = m;
            } else {
              sleep++;
              sleepMin += m;
            }
          }
        case DiaryCategory.diaper:
          break;
        case DiaryCategory.mood:
          if (mood.length < 10) mood.add({'period': c.period?.wire, 'type': _short(c.strAttr('type')), 'intensity': _short(c.intensity)});
        case DiaryCategory.other:
          final t = _short(c.strAttr('topic'));
          if (t != null && other.length < 10 && !other.contains(t)) other.add(t);
      }
    }
    final stats = <String, Object?>{
      if (feed > 0 || aggFeed != null) 'feed': {'count': feed, if (ml > 0) 'total_ml': ml, 'aggregate_count': ?aggFeed},
      if (sleep > 0 || aggSleepMin != null) 'sleep': {'count': sleep, 'total_min': sleepMin > 0 ? sleepMin : (aggSleepMin ?? 0)},
      if (diaper > 0) 'diaper': {'count': diaper, 'poo': poo, 'pee': pee},
      if (mood.isNotEmpty) 'mood': mood,
      if (other.isNotEmpty) 'other': other,
    };
    return DayStats(stats, ids);
  }

  static String? _short(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t.characters10;
  }
}

extension on String {
  String get characters10 => runes.length <= 10 ? this : String.fromCharCodes(runes.take(10));
}
