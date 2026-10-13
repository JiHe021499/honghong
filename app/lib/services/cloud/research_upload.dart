import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/db/app_database.dart';
import '../audio/wav_trim.dart';
import 'cloud_api.dart';

/// "参与改进"：只上传有反馈、且录音在本机的哭声（16kHz 单声道，最长 30 秒）+ 标注。
/// 默认关闭；只在 Wi-Fi 下传；失败的下次再试（以本地 uuid 为主键，重复上传幂等）。
class ResearchUploader {
  ResearchUploader(this._db, this._api, this._prefs);
  final AppDatabase _db;
  final CloudApi _api;
  final SharedPreferences _prefs;

  static const kOptIn = 'research_opt_in';
  static const kConsentAt = 'research_consent_at';

  bool get enabled => _prefs.getBool(kOptIn) ?? false;

  Future<void> setEnabled(bool v) async {
    await _prefs.setBool(kOptIn, v);
    if (v) await _prefs.setString(kConsentAt, DateTime.now().toIso8601String());
  }

  /// 待上传：有反馈、有本机录音、还没传过
  Future<List<CryEvent>> pending() async {
    final q = _db.select(_db.cryEvents).join([
      innerJoin(_db.feedbacks, _db.feedbacks.cryEventId.equalsExp(_db.cryEvents.id)),
    ])
      ..where(_db.cryEvents.syncState.isNotValue('synced') &
          _db.cryEvents.deleted.not() &
          _db.cryEvents.audioPath.isNotNull());
    final seen = <String>{};
    return [
      for (final r in await q.get())
        if (seen.add(r.readTable(_db.cryEvents).id)) r.readTable(_db.cryEvents),
    ];
  }

  Future<int> uploadedCount() async =>
      (await (_db.select(_db.cryEvents)..where((e) => e.syncState.equals('synced'))).get()).length;

  /// 上传一轮，返回 (成功, 失败)
  Future<({int ok, int failed})> run({required bool onWifi, required String appVersion}) async {
    if (!enabled || !onWifi) return (ok: 0, failed: 0);
    final todo = await pending();
    if (todo.isEmpty) return (ok: 0, failed: 0);
    final uid = await _api.ensureSignedIn();
    await _api.upsertDevice(
        appVersion: appVersion, consentAt: DateTime.tryParse(_prefs.getString(kConsentAt) ?? '') ?? DateTime.now());
    var ok = 0, failed = 0;
    final babiesDone = <String>{};
    for (final e in todo) {
      try {
        // 研究用宝宝 id 按设备派生：同一个家庭的两台手机互不冲突，也无法关联到家庭
        final rid = const Uuid().v5(Namespace.url.value, 'honghong:$uid:${e.babyId}');
        if (babiesDone.add(rid)) {
          final baby = await (_db.select(_db.babies)..where((b) => b.id.equals(e.babyId))).getSingle();
          await _api.upsertResearchBaby(id: rid, ageMonths: e.startedAt.difference(baby.birthDate).inDays / 30.44);
        }
        String? clip;
        final f = File(e.audioPath!);
        if (await f.exists()) {
          final wav = trimWav(await f.readAsBytes());
          if (wav != null) clip = await _api.uploadClip(e.id, wav);
        }
        await _api.upsertResearchEvent({
          'id': e.id,
          'baby_id': rid,
          'started_at': e.startedAt.toUtc().toIso8601String(),
          'duration_ms': e.durationMs,
          'clip_path': clip,
          'cry_confidence': e.cryConfidence,
          'context': jsonDecode(e.contextJson),
          'prediction': jsonDecode(e.predictionJson),
          'predictor_version': e.predictorVersion,
        });
        final fbs = await (_db.select(_db.feedbacks)..where((x) => x.cryEventId.equals(e.id))).get();
        for (final fb in fbs) {
          await _api.upsertResearchFeedback({
            'id': fb.id,
            'cry_event_id': e.id,
            'resolved_cause': fb.resolvedCause,
            'minutes_to_soothe': fb.minutesToSoothe,
          });
        }
        await (_db.update(_db.cryEvents)..where((x) => x.id.equals(e.id)))
            .write(const CryEventsCompanion(syncState: Value('synced')));
        ok++;
      } catch (_) {
        failed++;
      }
    }
    return (ok: ok, failed: failed);
  }

  /// 删除云端研究数据并关闭上传；本机数据不受影响
  Future<void> deleteMine() async {
    await _api.deleteMyResearchData();
    await setEnabled(false);
    await _prefs.remove(kConsentAt);
    await _db.update(_db.cryEvents).write(const CryEventsCompanion(syncState: Value('local')));
  }
}
