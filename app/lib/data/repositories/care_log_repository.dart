import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/care_detail.dart';
import '../../domain/models/care_log_type.dart';
import '../db/app_database.dart';

/// 护理记录。
/// - 喂奶/睡觉/拍嗝是计时记录：开始时 ended_at 为空（进行中），结束时写入。
/// - 换尿布一点即记：started_at = ended_at。
/// 每种类型同时最多一条进行中（数据库唯一索引兜底）。
class CareLogRepository {
  CareLogRepository(this._db);
  final AppDatabase _db;

  /// 直接写一条完整记录（导入、测试或补录用）
  Future<String> add(String babyId, CareLogType type,
      {DateTime? at, DateTime? endedAt, String? detail, String source = 'quick'}) async {
    final id = const Uuid().v4();
    final start = at ?? DateTime.now();
    await _db.into(_db.careLogs).insert(CareLogsCompanion.insert(
          id: id,
          babyId: babyId,
          type: type.name,
          startedAt: start,
          endedAt: Value(endedAt ?? start),
          detail: Value(detail),
          updatedAt: Value(DateTime.now()),
          source: Value(source),
        ));
    return id;
  }

  /// 开始一次计时。已有进行中的同类记录时直接返回它，不重复开始。
  Future<CareLog> startSession(String babyId, CareLogType type,
      {DateTime? at}) async {
    assert(type.isTimed);
    return _db.transaction(() async {
      final existing = await activeSession(babyId, type);
      if (existing != null) return existing;
      final id = const Uuid().v4();
      await _db.into(_db.careLogs).insert(CareLogsCompanion.insert(
            id: id,
            babyId: babyId,
            type: type.name,
            startedAt: at ?? DateTime.now(),
            updatedAt: Value(DateTime.now()),
          ));
      return byId(id).then((v) => v!);
    });
  }

  /// 点"结束"：停止计时（写入结束时间），之后可在底部面板里微调或"继续"。
  Future<void> stopSession(String id, {DateTime? at}) =>
      (_db.update(_db.careLogs)..where((l) => l.id.equals(id)))
          .write(CareLogsCompanion(endedAt: Value(at ?? DateTime.now()), updatedAt: Value(DateTime.now()), updatedBy: const Value(null), dirty: const Value(true)));

  /// 点"继续"：撤销结束，回到进行中（开始时间不变）。
  Future<void> resumeSession(String id) async {
    final log = await byId(id);
    if (log == null) return;
    final type = CareLogType.values.byName(log.type);
    final other = await activeSession(log.babyId, type);
    if (other != null && other.id != id) return; // 已经开了新的，不覆盖
    await (_db.update(_db.careLogs)..where((l) => l.id.equals(id)))
        .write(CareLogsCompanion(endedAt: const Value(null), updatedAt: Value(DateTime.now()), updatedBy: const Value(null), dirty: const Value(true)));
  }

  /// 保存记录：按微调后的时长写结束时间，并写入细节。
  Future<void> saveSession(String id,
      {required Duration duration, CareDetail? detail}) async {
    final log = await byId(id);
    if (log == null) return;
    await (_db.update(_db.careLogs)..where((l) => l.id.equals(id))).write(
        CareLogsCompanion(
            endedAt: Value(log.startedAt.add(duration)),
            detail: Value(detail?.encode()),
            updatedAt: Value(DateTime.now()),
            updatedBy: const Value(null),
            dirty: const Value(true)));
  }

  /// 补记一条已经结束的记录（全部记录 → 补记）。计时类必须有结束时间；
  /// 换尿布 end 传 null 即与开始相同。新记录 dirty=true，加入家庭时会同步。
  Future<String> backfill(String babyId, CareLogType type,
      {required DateTime start, DateTime? end, CareDetail? detail}) {
    final err = validateTimes(type, start, end);
    if (err != null) throw ArgumentError(err);
    return add(babyId, type, at: start, endedAt: type.isTimed ? end : start, detail: detail?.encode(), source: 'backfill');
  }

  /// 修改已结束记录的开始/结束时间和细节
  Future<void> updateRecord(String id,
      {required DateTime start, DateTime? end, CareDetail? detail}) async {
    final log = await byId(id);
    if (log == null) return;
    final type = CareLogType.values.byName(log.type);
    final err = validateTimes(type, start, end);
    if (err != null) throw ArgumentError(err);
    await (_db.update(_db.careLogs)..where((l) => l.id.equals(id))).write(CareLogsCompanion(
        startedAt: Value(start),
        endedAt: Value(type.isTimed ? end : start),
        detail: Value(detail?.encode()),
        updatedAt: Value(DateTime.now()),
        updatedBy: const Value(null),
        dirty: const Value(true)));
  }

  /// 校验补记/修改的时间；没问题返回 null
  static String? validateTimes(CareLogType type, DateTime start, DateTime? end, {DateTime? now}) {
    final n = (now ?? DateTime.now()).add(const Duration(minutes: 1));
    if (start.isAfter(n)) return '开始时间不能晚于现在';
    if (!type.isTimed) return null;
    if (end == null) return '请选择结束时间';
    if (!end.isAfter(start)) return '结束时间要晚于开始时间';
    if (end.isAfter(n)) return '结束时间不能晚于现在';
    if (end.difference(start) > const Duration(hours: 24)) return '一次不能超过 24 小时';
    return null;
  }

  /// 与 [start, end] 重叠的同类记录（进行中的按"到现在"算）。
  /// 换尿布传一个前后几分钟的窗口，用来提示可能重复。
  Future<List<CareLog>> overlapping(String babyId, CareLogType type, DateTime start, DateTime end,
      {String? excludeId}) async {
    final rows = await (_db.select(_db.careLogs)
          ..where((l) =>
              l.babyId.equals(babyId) & l.deleted.not() & l.type.equals(type.name) & l.startedAt.isSmallerThanValue(end)))
        .get();
    final now = DateTime.now();
    return rows.where((r) {
      if (r.id == excludeId) return false;
      final rEnd = r.endedAt ?? now;
      return rEnd.isAfter(start);
    }).toList();
  }

  /// 换尿布：一点即记，类型先记为"未分类"
  Future<String> logDiaper(String babyId, {DateTime? at}) => add(
      babyId, CareLogType.diaper,
      at: at, detail: const CareDetail(diaper: DiaperKind.unknown).encode());

  Future<void> updateDetail(String id, CareDetail detail) =>
      (_db.update(_db.careLogs)..where((l) => l.id.equals(id)))
          .write(CareLogsCompanion(detail: Value(detail.encode()), updatedAt: Value(DateTime.now()), updatedBy: const Value(null), dirty: const Value(true)));

  Future<CareLog?> byId(String id) =>
      (_db.select(_db.careLogs)..where((l) => l.id.equals(id) & l.deleted.not()))
          .getSingleOrNull();

  Future<CareLog?> activeSession(String babyId, CareLogType type) =>
      (_db.select(_db.careLogs)
            ..where((l) =>
                l.babyId.equals(babyId) &
                l.deleted.not() &
                l.type.equals(type.name) &
                l.endedAt.isNull()))
          .getSingleOrNull();

  /// 所有进行中的记录，最早开始的在前
  Stream<List<CareLog>> watchActive(String babyId) => (_db.select(_db.careLogs)
        ..where((l) => l.babyId.equals(babyId) & l.deleted.not() & l.endedAt.isNull())
        ..orderBy([(l) => OrderingTerm.asc(l.startedAt)]))
      .watch();

  /// 兼容旧接口：结束进行中的睡眠
  Future<void> endSleep(String babyId, {DateTime? at}) async {
    final open = await activeSession(babyId, CareLogType.sleep);
    if (open != null) await stopSession(open.id, at: at);
  }

  /// 软删除：保留一条 deleted 标记，好同步给家人
  Future<void> delete(String id) async {
    final log = await byId(id);
    if (log == null) return;
    final now = DateTime.now();
    await (_db.update(_db.careLogs)..where((l) => l.id.equals(id))).write(CareLogsCompanion(
        deleted: const Value(true), endedAt: Value(log.endedAt ?? now), updatedAt: Value(now), updatedBy: const Value(null), dirty: const Value(true)));
  }

  /// 每种类型最近一条
  Stream<Map<CareLogType, CareLog>> watchLatestByType(String babyId) {
    return (_db.select(_db.careLogs)
          ..where((l) => l.babyId.equals(babyId) & l.deleted.not())
          ..orderBy([(l) => OrderingTerm.desc(l.startedAt)]))
        .watch()
        .map(_latest);
  }

  Future<Map<CareLogType, CareLog>> latestByType(String babyId) async =>
      _latest(await (_db.select(_db.careLogs)
            ..where((l) => l.babyId.equals(babyId) & l.deleted.not())
            ..orderBy([(l) => OrderingTerm.desc(l.startedAt)]))
          .get());

  Stream<List<CareLog>> watchRecent(String babyId, {int limit = 200}) =>
      (_db.select(_db.careLogs)
            ..where((l) => l.babyId.equals(babyId) & l.deleted.not())
            ..orderBy([(l) => OrderingTerm.desc(l.startedAt)])
            ..limit(limit))
          .watch();

  Future<List<CareLog>> since(String babyId, DateTime from) =>
      (_db.select(_db.careLogs)
            ..where((l) =>
                l.babyId.equals(babyId) & l.deleted.not() & l.startedAt.isBiggerOrEqualValue(from))
            ..orderBy([(l) => OrderingTerm.asc(l.startedAt)]))
          .get();

  /// 家人最近一次记录（家庭卡片上的"爸爸 15 分钟前记录了换尿布"）
  Stream<CareLog?> watchLatestByFamily() => (_db.select(_db.careLogs)
        ..where((l) => l.updatedBy.isNotNull() & l.deleted.not())
        ..orderBy([(l) => OrderingTerm.desc(l.updatedAt)])
        ..limit(1))
      .watchSingleOrNull();

  /// 还没推送给家人的条数
  Future<int> pendingCount() async =>
      (await (_db.select(_db.careLogs)..where((l) => l.dirty)).get()).length +
      (await (_db.select(_db.cryEvents)..where((e) => e.dirty)).get()).length;

  Future<List<CareLog>> all() => (_db.select(_db.careLogs)..where((l) => l.deleted.not())).get();

  static Map<CareLogType, CareLog> _latest(List<CareLog> rows) {
    final m = <CareLogType, CareLog>{};
    for (final r in rows) {
      final t = CareLogType.values.byName(r.type);
      m.putIfAbsent(t, () => r);
    }
    return m;
  }
}
