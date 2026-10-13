import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/care_log_type.dart';
import '../db/app_database.dart';

class CareLogRepository {
  CareLogRepository(this._db);
  final AppDatabase _db;

  Future<String> add(String babyId, CareLogType type,
      {DateTime? at, DateTime? endedAt, String? detail}) async {
    final id = const Uuid().v4();
    await _db.into(_db.careLogs).insert(CareLogsCompanion.insert(
          id: id,
          babyId: babyId,
          type: type.name,
          startedAt: at ?? DateTime.now(),
          endedAt: Value(endedAt),
          detail: Value(detail),
        ));
    return id;
  }

  /// 结束最近一次未结束的睡眠
  Future<void> endSleep(String babyId, {DateTime? at}) async {
    final open = await (_db.select(_db.careLogs)
          ..where((l) =>
              l.babyId.equals(babyId) &
              l.type.equals(CareLogType.sleep.name) &
              l.endedAt.isNull())
          ..orderBy([(l) => OrderingTerm.desc(l.startedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (open == null) return;
    await (_db.update(_db.careLogs)..where((l) => l.id.equals(open.id)))
        .write(CareLogsCompanion(endedAt: Value(at ?? DateTime.now())));
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

  Stream<List<CareLog>> watchRecent(String babyId, {int limit = 100}) =>
      (_db.select(_db.careLogs)
            ..where((l) => l.babyId.equals(babyId))
            ..orderBy([(l) => OrderingTerm.desc(l.startedAt)])
            ..limit(limit))
          .watch();

  static Map<CareLogType, CareLog> _latest(List<CareLog> rows) {
    final m = <CareLogType, CareLog>{};
    for (final r in rows) {
      final t = CareLogType.values.byName(r.type);
      m.putIfAbsent(t, () => r);
    }
    return m;
  }
}
