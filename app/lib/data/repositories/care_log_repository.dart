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
      {DateTime? at, DateTime? endedAt, String? detail}) async {
    final id = const Uuid().v4();
    final start = at ?? DateTime.now();
    await _db.into(_db.careLogs).insert(CareLogsCompanion.insert(
          id: id,
          babyId: babyId,
          type: type.name,
          startedAt: start,
          endedAt: Value(endedAt ?? start),
          detail: Value(detail),
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
          ));
      return byId(id).then((v) => v!);
    });
  }

  /// 点"结束"：停止计时（写入结束时间），之后可在底部面板里微调或"继续"。
  Future<void> stopSession(String id, {DateTime? at}) =>
      (_db.update(_db.careLogs)..where((l) => l.id.equals(id)))
          .write(CareLogsCompanion(endedAt: Value(at ?? DateTime.now())));

  /// 点"继续"：撤销结束，回到进行中（开始时间不变）。
  Future<void> resumeSession(String id) async {
    final log = await byId(id);
    if (log == null) return;
    final type = CareLogType.values.byName(log.type);
    final other = await activeSession(log.babyId, type);
    if (other != null && other.id != id) return; // 已经开了新的，不覆盖
    await (_db.update(_db.careLogs)..where((l) => l.id.equals(id)))
        .write(const CareLogsCompanion(endedAt: Value(null)));
  }

  /// 保存记录：按微调后的时长写结束时间，并写入细节。
  Future<void> saveSession(String id,
      {required Duration duration, CareDetail? detail}) async {
    final log = await byId(id);
    if (log == null) return;
    await (_db.update(_db.careLogs)..where((l) => l.id.equals(id))).write(
        CareLogsCompanion(
            endedAt: Value(log.startedAt.add(duration)),
            detail: Value(detail?.encode())));
  }

  /// 换尿布：一点即记，类型先记为"未分类"
  Future<String> logDiaper(String babyId, {DateTime? at}) => add(
      babyId, CareLogType.diaper,
      at: at, detail: const CareDetail(diaper: DiaperKind.unknown).encode());

  Future<void> updateDetail(String id, CareDetail detail) =>
      (_db.update(_db.careLogs)..where((l) => l.id.equals(id)))
          .write(CareLogsCompanion(detail: Value(detail.encode())));

  Future<CareLog?> byId(String id) =>
      (_db.select(_db.careLogs)..where((l) => l.id.equals(id)))
          .getSingleOrNull();

  Future<CareLog?> activeSession(String babyId, CareLogType type) =>
      (_db.select(_db.careLogs)
            ..where((l) =>
                l.babyId.equals(babyId) &
                l.type.equals(type.name) &
                l.endedAt.isNull()))
          .getSingleOrNull();

  /// 所有进行中的记录，最早开始的在前
  Stream<List<CareLog>> watchActive(String babyId) => (_db.select(_db.careLogs)
        ..where((l) => l.babyId.equals(babyId) & l.endedAt.isNull())
        ..orderBy([(l) => OrderingTerm.asc(l.startedAt)]))
      .watch();

  /// 兼容旧接口：结束进行中的睡眠
  Future<void> endSleep(String babyId, {DateTime? at}) async {
    final open = await activeSession(babyId, CareLogType.sleep);
    if (open != null) await stopSession(open.id, at: at);
  }

  Future<void> delete(String id) =>
      (_db.delete(_db.careLogs)..where((l) => l.id.equals(id))).go();

  /// 每种类型最近一条
  Stream<Map<CareLogType, CareLog>> watchLatestByType(String babyId) {
    return (_db.select(_db.careLogs)
          ..where((l) => l.babyId.equals(babyId))
          ..orderBy([(l) => OrderingTerm.desc(l.startedAt)]))
        .watch()
        .map(_latest);
  }

  Future<Map<CareLogType, CareLog>> latestByType(String babyId) async =>
      _latest(await (_db.select(_db.careLogs)
            ..where((l) => l.babyId.equals(babyId))
            ..orderBy([(l) => OrderingTerm.desc(l.startedAt)]))
          .get());

  Stream<List<CareLog>> watchRecent(String babyId, {int limit = 200}) =>
      (_db.select(_db.careLogs)
            ..where((l) => l.babyId.equals(babyId))
            ..orderBy([(l) => OrderingTerm.desc(l.startedAt)])
            ..limit(limit))
          .watch();

  Future<List<CareLog>> since(String babyId, DateTime from) =>
      (_db.select(_db.careLogs)
            ..where((l) =>
                l.babyId.equals(babyId) & l.startedAt.isBiggerOrEqualValue(from))
            ..orderBy([(l) => OrderingTerm.asc(l.startedAt)]))
          .get();

  Future<List<CareLog>> all() => _db.select(_db.careLogs).get();

  static Map<CareLogType, CareLog> _latest(List<CareLog> rows) {
    final m = <CareLogType, CareLog>{};
    for (final r in rows) {
      final t = CareLogType.values.byName(r.type);
      m.putIfAbsent(t, () => r);
    }
    return m;
  }
}
