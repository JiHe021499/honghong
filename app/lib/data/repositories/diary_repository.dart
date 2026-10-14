import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/care_log_type.dart';
import '../db/app_database.dart';
import '../../core/app_clock.dart';

/// 时间线上的一行：要么是一条护理记录（快捷/日记/补记），要么是一张不落 care_logs 的日记卡
/// （汇总、情绪、其他）。同一件事只出现一次（架构 §3.6）。
class TimelineEntry {
  const TimelineEntry({required this.src, required this.id, required this.type, required this.sortTime, required this.source});

  /// 'care' | 'card'
  final String src;
  final String id;

  /// care：feed|sleep|diaper|burp；card：feeding|sleep|diaper|mood|other
  final String type;
  final DateTime sortTime;

  /// quick|diary|backfill（卡片固定 diary）
  final String source;

  bool get isCareLog => src == 'care';

  /// 时间线上显示“快捷记录”标签
  bool get isQuick => isCareLog && source == 'quick';

  @override
  String toString() => 'TimelineEntry($src,$type,$source,$sortTime)';
}

/// 一张待保存的卡片；[careLog] 非空时同时写一条 care_logs（source=diary）并互相关联。
class DiaryCardDraft {
  const DiaryCardDraft(this.card, {this.careLog});
  final DiaryCardsCompanion card;
  final CareLogsCompanion? careLog;
}

/// 妈咪日记数据访问：diary_inputs / diary_cards / daily_summaries CRUD 与时间线合并查询。
/// 卡片 → 落库的业务映射在 DiaryService（P3），这里只负责事务和查询。
class DiaryRepository {
  DiaryRepository(this._db);
  final AppDatabase _db;

  static DateTime dayStart(DateTime t) => DateTime(t.year, t.month, t.day);

  /// 事务保存一次输入及其卡片。返回卡片 id（顺序与 [cards] 一致）。
  /// 有 careLog 的卡片：先写 care_logs（source=diary, diaryCardId），再写卡片（careLogId）。
  Future<List<String>> saveInput(DiaryInputsCompanion input, List<DiaryCardDraft> cards) =>
      _db.transaction(() async {
        final inputId = input.id.present ? input.id.value : const Uuid().v4();
        await _db.into(_db.diaryInputs).insert(input.copyWith(id: Value(inputId)));
        final ids = <String>[];
        for (final d in cards) {
          final cardId = d.card.id.present ? d.card.id.value : const Uuid().v4();
          String? logId;
          if (d.careLog != null) {
            logId = d.careLog!.id.present ? d.careLog!.id.value : const Uuid().v4();
            await _db.into(_db.careLogs).insert(d.careLog!.copyWith(
                  id: Value(logId),
                  source: const Value('diary'),
                  diaryCardId: Value(cardId),
                  updatedAt: Value(AppClock.now()),
                ));
          }
          await _db.into(_db.diaryCards).insert(d.card.copyWith(
                id: Value(cardId),
                inputId: Value(inputId),
                careLogId: Value(logId),
                diaryDate: Value(dayStart(d.card.diaryDate.value)),
              ));
          ids.add(cardId);
        }
        return ids;
      });

  Future<DiaryInput?> inputById(String id) =>
      (_db.select(_db.diaryInputs)..where((i) => i.id.equals(id) & i.deleted.not())).getSingleOrNull();

  Future<DiaryCard?> cardById(String id) =>
      (_db.select(_db.diaryCards)..where((c) => c.id.equals(id) & c.deleted.not())).getSingleOrNull();

  /// 护理记录对应的日记卡（时间线上点开 diary 来源的记录看原话）
  Future<DiaryCard?> cardForCareLog(String careLogId) =>
      (_db.select(_db.diaryCards)..where((c) => c.careLogId.equals(careLogId) & c.deleted.not())).getSingleOrNull();

  Future<List<DiaryCard>> cardsOfDay(String babyId, DateTime day) => (_db.select(_db.diaryCards)
        ..where((c) => c.babyId.equals(babyId) & c.deleted.not() & c.diaryDate.equals(dayStart(day)))
        ..orderBy([(c) => OrderingTerm.asc(c.sortTime)]))
      .get();

  /// 编辑卡片（就地编辑），标记 editedByUser
  Future<void> updateCard(String id, DiaryCardsCompanion patch) =>
      (_db.update(_db.diaryCards)..where((c) => c.id.equals(id))).write(patch.copyWith(
            editedByUser: const Value(true),
            updatedAt: Value(AppClock.now()),
            diaryDate: patch.diaryDate.present ? Value(dayStart(patch.diaryDate.value)) : const Value.absent(),
          ));

  /// 软删一张卡片；若关联了护理记录则一并软删（保持同一件事要么都在、要么都不在）。
  Future<void> deleteCard(String id) => _db.transaction(() async {
        final card = await cardById(id);
        if (card == null) return;
        await _softDeleteCard(id);
        if (card.careLogId != null) await _softDeleteCareLog(card.careLogId!);
      });

  /// 时间线上删一条护理记录：source=diary 时同时软删对应卡片（架构 §3.6）。
  Future<void> deleteCareLog(String careLogId) => _db.transaction(() async {
        await _softDeleteCareLog(careLogId);
        await (_db.update(_db.diaryCards)..where((c) => c.careLogId.equals(careLogId) & c.deleted.not()))
            .write(DiaryCardsCompanion(deleted: const Value(true), updatedAt: Value(AppClock.now())));
      });

  Future<void> _softDeleteCard(String id) => (_db.update(_db.diaryCards)..where((c) => c.id.equals(id)))
      .write(DiaryCardsCompanion(deleted: const Value(true), updatedAt: Value(AppClock.now())));

  // 与 CareLogRepository.delete 一致：保留 deleted 标记以便家庭同步，进行中的补上结束时间
  Future<void> _softDeleteCareLog(String id) async {
    final log = await (_db.select(_db.careLogs)..where((l) => l.id.equals(id) & l.deleted.not())).getSingleOrNull();
    if (log == null) return;
    final now = AppClock.now();
    await (_db.update(_db.careLogs)..where((l) => l.id.equals(id))).write(CareLogsCompanion(
        deleted: const Value(true), endedAt: Value(log.endedAt ?? now), updatedAt: Value(now), updatedBy: const Value(null), dirty: const Value(true)));
  }

  static const _timelineSql = '''
SELECT 'care' AS src, id, type, started_at AS sort_time, source FROM care_logs
 WHERE baby_id = ?1 AND deleted = 0 AND started_at >= ?2 AND started_at < ?3
UNION ALL
SELECT 'card' AS src, id, category AS type, sort_time, 'diary' AS source FROM diary_cards
 WHERE baby_id = ?1 AND deleted = 0 AND care_log_id IS NULL AND diary_date = ?2
ORDER BY sort_time, src''';

  Selectable<TimelineEntry> _timeline(String babyId, DateTime day) {
    final d0 = dayStart(day);
    final d1 = DateTime(d0.year, d0.month, d0.day + 1);
    return _db.customSelect(_timelineSql,
        variables: [Variable.withString(babyId), Variable.withDateTime(d0), Variable.withDateTime(d1)],
        readsFrom: {_db.careLogs, _db.diaryCards}).map((r) => TimelineEntry(
          src: r.read<String>('src'),
          id: r.read<String>('id'),
          type: r.read<String>('type'),
          sortTime: r.read<DateTime>('sort_time'),
          source: r.read<String>('source'),
        ));
  }

  /// 某日时间线 = care_logs(当日) ∪ diary_cards(当日, 未关联 care_logs)，按时间升序。
  Future<List<TimelineEntry>> timeline(String babyId, DateTime day) => _timeline(babyId, day).get();
  Stream<List<TimelineEntry>> watchTimeline(String babyId, DateTime day) => _timeline(babyId, day).watch();

  /// 当日次数：只数 care_logs（汇总卡不计入，D2）。
  Future<Map<CareLogType, int>> careCounts(String babyId, DateTime day) async {
    final m = <CareLogType, int>{};
    for (final e in await timeline(babyId, day)) {
      if (!e.isCareLog) continue;
      final t = CareLogType.values.byName(e.type);
      m[t] = (m[t] ?? 0) + 1;
    }
    return m;
  }

  /// 重复事件提醒（D1，不自动去重）：同类型 ±[window] 内已有的首页记录（非日记来源）。
  Future<List<CareLog>> possibleDuplicates(String babyId, CareLogType type, DateTime at,
          {Duration window = const Duration(minutes: 15)}) =>
      (_db.select(_db.careLogs)
            ..where((l) =>
                l.babyId.equals(babyId) &
                l.deleted.not() &
                l.type.equals(type.name) &
                l.source.equals('diary').not() &
                l.startedAt.isBetweenValues(at.subtract(window), at.add(window))))
          .get();

  // ── 今日小结 ──

  Future<DailySummary?> summaryOf(String babyId, DateTime day) => (_db.select(_db.dailySummaries)
        ..where((s) => s.babyId.equals(babyId) & s.date.equals(dayStart(day))))
      .getSingleOrNull();

  /// 幂等占位：当日没有小结时插一条 pending 并返回它；已有则原样返回（不改写，D8）。
  Future<DailySummary> claimSummary(String babyId, DateTime day, {required String promptVersion}) =>
      _db.transaction(() async {
        await _db.into(_db.dailySummaries).insert(
            DailySummariesCompanion.insert(
              id: const Uuid().v4(),
              babyId: babyId,
              date: dayStart(day),
              status: 'pending',
              sourceIds: '[]',
              statsJson: '{}',
              promptVersion: promptVersion,
            ),
            mode: InsertMode.insertOrIgnore);
        return (await summaryOf(babyId, day))!;
      });

  Future<void> updateSummary(String id, DailySummariesCompanion patch) =>
      (_db.update(_db.dailySummaries)..where((s) => s.id.equals(id))).write(patch);
}
