import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/baby_repository.dart';
import 'cloud_api.dart';
import '../../core/app_clock.dart';

/// 家庭同步：本地优先。
/// - 本地每次修改都写 updated_at 并标记 dirty；同步时先推送 dirty 行，
///   服务器只接受 updated_at 更新的版本（最后写入者胜出）。
/// - 再按 server_updated_at 游标增量拉取，远端更新的版本覆盖本地。
/// - 删除是软删除（deleted = true），这样删除也能同步给家人。
/// - 录音不共享，只共享判断结果和反馈。
class FamilySync {
  FamilySync(this._db, this._api, this._prefs, {this.keyPrefix = ''});
  final AppDatabase _db;
  final CloudApi _api;
  final SharedPreferences _prefs;
  /// 测试里两台手机共用一个 SharedPreferences，用前缀区分
  final String keyPrefix;

  String get kFamilyId => '${keyPrefix}family_id';
  String get kCursorLogs => '${keyPrefix}family_cursor_logs';
  String get kCursorCries => '${keyPrefix}family_cursor_cries';
  String get kLastSync => '${keyPrefix}family_last_sync';

  String? get familyId => _prefs.getString(kFamilyId);
  DateTime? get lastSync {
    final v = _prefs.getString(kLastSync);
    return v == null ? null : DateTime.tryParse(v);
  }

  static String _ts(DateTime d) => d.toUtc().toIso8601String();
  static DateTime? _parse(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

  /// 创建家庭：把本机宝宝登记成家庭宝宝，现有记录全部推上去
  Future<void> create({required String name, required String avatar}) async {
    final baby = await BabyRepository(_db).ensureDefault();
    final fid = await _api.createFamily(
        babyId: baby.id, nickname: baby.nickname, birthDate: baby.birthDate, name: name, avatar: avatar);
    await _setFamily(fid);
    await _markAllDirty();
    await sync();
  }

  /// 加入家庭：本机记录合并到家庭宝宝名下，再双向同步
  Future<void> join({required String code, required String name, required String avatar}) async {
    final fid = await _api.joinFamily(code: code, name: name, avatar: avatar);
    final remote = await _api.pullBaby(fid);
    if (remote != null) await adoptBaby(remote);
    await _setFamily(fid);
    await _markAllDirty();
    await sync();
  }

  /// 退出家庭：本机数据保留，之后只在本机记录
  Future<void> leave() async {
    await _api.leaveFamily();
    await clearLocalFamily();
  }

  Future<void> clearLocalFamily() async {
    for (final k in [kFamilyId, kCursorLogs, kCursorCries, kLastSync]) {
      await _prefs.remove(k);
    }
  }

  Future<void> _setFamily(String fid) async {
    await _prefs.setString(kFamilyId, fid);
    await _prefs.remove(kCursorLogs);
    await _prefs.remove(kCursorCries);
  }

  Future<void> _markAllDirty() async {
    final now = AppClock.now();
    await (_db.update(_db.careLogs)..where((l) => l.updatedAt.isNull())).write(CareLogsCompanion(updatedAt: Value(now)));
    await (_db.update(_db.cryEvents)..where((e) => e.updatedAt.isNull())).write(CryEventsCompanion(updatedAt: Value(now)));
    await _db.update(_db.careLogs).write(const CareLogsCompanion(dirty: Value(true)));
    await _db.update(_db.cryEvents).write(const CryEventsCompanion(dirty: Value(true)));
  }

  /// 用家庭的宝宝替换本机宝宝：本机记录改挂到家庭宝宝名下
  Future<void> adoptBaby(Map<String, dynamic> remote) async {
    final id = remote['id'] as String;
    await _db.transaction(() async {
      final locals = await _db.select(_db.babies).get();
      if (locals.any((b) => b.id == id)) return;
      await _db.into(_db.babies).insert(BabiesCompanion.insert(
            id: id,
            nickname: remote['nickname'] as String,
            birthDate: DateTime.parse(remote['birth_date'] as String),
            updatedAt: Value(_parse(remote['updated_at'])),
            gender: Value(remote['gender'] as String?),
          ));
      for (final b in locals) {
        await (_db.update(_db.careLogs)..where((l) => l.babyId.equals(b.id))).write(CareLogsCompanion(babyId: Value(id)));
        await (_db.update(_db.cryEvents)..where((e) => e.babyId.equals(b.id))).write(CryEventsCompanion(babyId: Value(id)));
        await (_db.delete(_db.babies)..where((x) => x.id.equals(b.id))).go();
      }
    });
  }

  /// 一次完整同步：推送 → 拉取。返回拉到的条数。
  Future<int> sync() async {
    final fid = familyId;
    if (fid == null) return 0;
    await _pushBaby();
    await _pushLogs(fid);
    await _pushCries(fid);
    var n = await _pullLogs(fid);
    n += await _pullCries(fid);
    await _pullBaby(fid);
    await _prefs.setString(kLastSync, AppClock.now().toIso8601String());
    return n;
  }

  Future<void> _pushBaby() async {
    final b = await (_db.select(_db.babies)..where((b) => b.dirty)).getSingleOrNull();
    if (b == null) return;
    final at = b.updatedAt ?? AppClock.now();
    await _api.pushBaby({
      'id': b.id,
      'nickname': b.nickname,
      'birth_date': b.birthDate.toIso8601String().substring(0, 10),
      'gender': b.gender,
      'updated_at': _ts(at),
    });
    await (_db.update(_db.babies)..where((x) => x.id.equals(b.id) & x.updatedAt.equalsNullable(b.updatedAt)))
        .write(const BabiesCompanion(dirty: Value(false)));
  }

  static Map<String, dynamic> logRow(CareLog l, String fid) => {
        'id': l.id,
        'family_id': fid,
        'baby_id': l.babyId,
        'type': l.type,
        'started_at': _ts(l.startedAt),
        'ended_at': l.endedAt == null ? null : _ts(l.endedAt!),
        'detail': l.detail,
        'updated_at': _ts(l.updatedAt ?? l.createdAt),
        'deleted': l.deleted,
      };

  Future<void> _pushLogs(String fid) async {
    final rows = await (_db.select(_db.careLogs)..where((l) => l.dirty)).get();
    for (var i = 0; i < rows.length; i += 200) {
      final batch = rows.sublist(i, i + 200 > rows.length ? rows.length : i + 200);
      await _api.pushCareLogs([for (final l in batch) logRow(l, fid)]);
      for (final l in batch) {
        // 推送期间又被改过的保持 dirty，下次再推
        await (_db.update(_db.careLogs)..where((x) => x.id.equals(l.id) & x.updatedAt.equalsNullable(l.updatedAt)))
            .write(const CareLogsCompanion(dirty: Value(false)));
      }
    }
  }

  Future<void> _pushCries(String fid) async {
    final rows = await (_db.select(_db.cryEvents)..where((e) => e.dirty)).get();
    for (var i = 0; i < rows.length; i += 100) {
      final batch = rows.sublist(i, i + 100 > rows.length ? rows.length : i + 100);
      final out = <Map<String, dynamic>>[];
      for (final e in batch) {
        final fb = await (_db.select(_db.feedbacks)
              ..where((f) => f.cryEventId.equals(e.id))
              ..orderBy([(f) => OrderingTerm.desc(f.createdAt)])
              ..limit(1))
            .getSingleOrNull();
        out.add({
          'id': e.id,
          'family_id': fid,
          'baby_id': e.babyId,
          'started_at': _ts(e.startedAt),
          'duration_ms': e.durationMs,
          'cry_confidence': e.cryConfidence,
          'context_json': e.contextJson,
          'prediction_json': e.predictionJson,
          'predictor_version': e.predictorVersion,
          'auto_triggered': e.autoTriggered,
          'resolved_cause': fb?.resolvedCause,
          'minutes_to_soothe': fb?.minutesToSoothe,
          'updated_at': _ts(e.updatedAt ?? e.startedAt),
          'deleted': e.deleted,
        });
      }
      await _api.pushCryEvents(out);
      for (final e in batch) {
        await (_db.update(_db.cryEvents)..where((x) => x.id.equals(e.id) & x.updatedAt.equalsNullable(e.updatedAt)))
            .write(const CryEventsCompanion(dirty: Value(false)));
      }
    }
  }

  /// 远端版本是否应覆盖本地：更新的覆盖；同一秒内（本地时间只精确到秒）本地没有未推送的修改时以服务器为准
  static bool _wins(DateTime remote, DateTime? local, bool localDirty) =>
      local == null || remote.isAfter(local) || (!localDirty && !remote.isBefore(local));

  Future<int> _pullLogs(String fid) async {
    final rows = await _api.pullCareLogs(fid, _prefs.getString(kCursorLogs));
    var n = 0;
    for (final r in rows) {
      final id = r['id'] as String;
      final remoteAt = _parse(r['updated_at'])!;
      final local = await (_db.select(_db.careLogs)..where((l) => l.id.equals(id))).getSingleOrNull();
      if (local == null || _wins(remoteAt, local.updatedAt, local.dirty)) {
        await _applyLog(r, remoteAt);
        n++;
      }
      await _prefs.setString(kCursorLogs, r['server_updated_at'] as String);
    }
    return n;
  }

  Future<void> _applyLog(Map<String, dynamic> r, DateTime remoteAt) async {
    final id = r['id'] as String;
    final babyId = r['baby_id'] as String;
    final type = r['type'] as String;
    final started = _parse(r['started_at'])!;
    var ended = _parse(r['ended_at']);
    final deleted = r['deleted'] as bool? ?? false;
    var dirty = false;
    await _db.transaction(() async {
      if (ended == null && !deleted) {
        // 两台手机同时开始了同一种计时：保留后开始的那条，先开始的那条在对方开始时结束
        final other = await (_db.select(_db.careLogs)
              ..where((l) => l.babyId.equals(babyId) & l.type.equals(type) & l.endedAt.isNull() & l.deleted.not() & l.id.equals(id).not()))
            .getSingleOrNull();
        if (other != null) {
          if (!other.startedAt.isAfter(started)) {
            await (_db.update(_db.careLogs)..where((l) => l.id.equals(other.id))).write(
                CareLogsCompanion(endedAt: Value(started), updatedAt: Value(AppClock.now()), dirty: const Value(true)));
          } else {
            ended = other.startedAt;
            dirty = true;
          }
        }
      }
      await _db.into(_db.careLogs).insertOnConflictUpdate(CareLogsCompanion.insert(
            id: id,
            babyId: babyId,
            type: type,
            startedAt: started,
            endedAt: Value(ended),
            detail: Value(r['detail'] as String?),
            updatedAt: Value(dirty ? AppClock.now() : remoteAt),
            updatedBy: Value(dirty || r['updated_by'] == _api.userId ? null : r['updated_by'] as String?),
            deleted: Value(deleted),
            dirty: Value(dirty),
          ));
    });
  }

  Future<int> _pullCries(String fid) async {
    final rows = await _api.pullCryEvents(fid, _prefs.getString(kCursorCries));
    var n = 0;
    for (final r in rows) {
      final id = r['id'] as String;
      final remoteAt = _parse(r['updated_at'])!;
      final local = await (_db.select(_db.cryEvents)..where((e) => e.id.equals(id))).getSingleOrNull();
      if (local == null || _wins(remoteAt, local.updatedAt, local.dirty)) {
        await _db.transaction(() async {
          await _db.into(_db.cryEvents).insertOnConflictUpdate(CryEventsCompanion.insert(
                id: id,
                babyId: r['baby_id'] as String,
                startedAt: _parse(r['started_at'])!,
                durationMs: r['duration_ms'] as int,
                audioPath: Value(local?.audioPath), // 录音只在录的那台手机上
                cryConfidence: Value((r['cry_confidence'] as num? ?? 0).toDouble()),
                contextJson: r['context_json'] as String,
                predictionJson: r['prediction_json'] as String,
                predictorVersion: r['predictor_version'] as String,
                autoTriggered: Value(r['auto_triggered'] as bool? ?? false),
                syncState: Value(local?.syncState ?? 'local'),
                updatedAt: Value(remoteAt),
                deleted: Value(r['deleted'] as bool? ?? false),
                dirty: const Value(false),
              ));
          final cause = r['resolved_cause'] as String?;
          if (cause != null) {
            final has = await (_db.select(_db.feedbacks)..where((f) => f.cryEventId.equals(id))).get();
            if (has.isEmpty) {
              await _db.into(_db.feedbacks).insert(FeedbacksCompanion.insert(
                  id: id, cryEventId: id, resolvedCause: cause, minutesToSoothe: Value(r['minutes_to_soothe'] as int?)));
            } else if (has.last.resolvedCause != cause) {
              await (_db.update(_db.feedbacks)..where((f) => f.id.equals(has.last.id)))
                  .write(FeedbacksCompanion(resolvedCause: Value(cause)));
            }
          }
        });
        n++;
      }
      await _prefs.setString(kCursorCries, r['server_updated_at'] as String);
    }
    return n;
  }

  Future<void> _pullBaby(String fid) async {
    final r = await _api.pullBaby(fid);
    if (r == null) return;
    final remoteAt = _parse(r['updated_at'])!;
    final local = await (_db.select(_db.babies)..where((b) => b.id.equals(r['id'] as String))).getSingleOrNull();
    if (local == null) return adoptBaby(r);
    if (!local.dirty && _wins(remoteAt, local.updatedAt, false)) {
      await (_db.update(_db.babies)..where((b) => b.id.equals(local.id))).write(BabiesCompanion(
          nickname: Value(r['nickname'] as String),
          birthDate: Value(DateTime.parse(r['birth_date'] as String)),
          // 服务端还没跑 0004（没有 gender 列）时保留本地值
          gender: r.containsKey('gender') ? Value(r['gender'] as String?) : const Value.absent(),
          updatedAt: Value(remoteAt)));
    }
  }
}
