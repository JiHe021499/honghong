import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/baby_repository.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/data/repositories/cry_event_repository.dart';
import 'package:honghong/data/repositories/feedback_repository.dart';
import 'package:honghong/domain/models/care_detail.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/domain/models/cry_cause.dart';
import 'package:honghong/domain/models/cry_context.dart';
import 'package:honghong/domain/predictor/cry_predictor.dart';
import 'package:honghong/domain/predictor/rule_based_predictor.dart';
import 'package:honghong/services/audio/wav_trim.dart';
import 'package:honghong/services/cloud/family_sync.dart';
import 'package:honghong/services/cloud/research_upload.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud.dart';

Uint8List makeWav(int seconds, {int rate = 16000}) {
  final n = rate * 2 * seconds;
  final b = Uint8List(44 + n);
  final w = ByteData.sublistView(b);
  b.setRange(0, 4, 'RIFF'.codeUnits);
  w.setUint32(4, 36 + n, Endian.little);
  b.setRange(8, 16, 'WAVEfmt '.codeUnits);
  w.setUint32(16, 16, Endian.little);
  w.setUint16(20, 1, Endian.little);
  w.setUint16(22, 1, Endian.little);
  w.setUint32(24, rate, Endian.little);
  w.setUint32(28, rate * 2, Endian.little);
  w.setUint16(32, 2, Endian.little);
  w.setUint16(34, 16, Endian.little);
  b.setRange(36, 40, 'data'.codeUnits);
  w.setUint32(40, n, Endian.little);
  return b;
}

void main() {
  late FakeServer server;
  late AppDatabase dbA, dbB;
  late FamilySync a, b;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final pa = await SharedPreferences.getInstance();
    server = FakeServer();
    dbA = AppDatabase.memory();
    dbB = AppDatabase.memory();
    a = FamilySync(dbA, FakeCloud(server, 'ua'), pa);
    // 两台手机各自一份 prefs
    b = FamilySync(dbB, FakeCloud(server, 'ub'), pa, keyPrefix: 'b_');
  });
  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  test('创建、用邀请码加入后双向同步护理记录，本机已有记录合并到家庭宝宝', () async {
    final babyA = await BabyRepository(dbA).ensureDefault();
    await CareLogRepository(dbA).add(babyA.id, CareLogType.feed, at: DateTime(2026, 10, 13, 8));
    final babyB = await BabyRepository(dbB).ensureDefault();
    await CareLogRepository(dbB).add(babyB.id, CareLogType.diaper, at: DateTime(2026, 10, 13, 9));

    await a.create(name: '爸爸', avatar: 'dad');
    final code = server.invites.keys.single;
    await expectLater(b.join(code: 'WRONG1', name: '妈妈', avatar: 'mom'), throwsA(anything));
    await b.join(code: code, name: '妈妈', avatar: 'mom');
    await a.sync();

    final logsA = await CareLogRepository(dbA).all();
    final logsB = await CareLogRepository(dbB).all();
    expect(logsA.length, 2);
    expect(logsB.length, 2);
    expect(logsB.every((l) => l.babyId == babyA.id), isTrue, reason: 'B 的记录改挂到家庭宝宝');
    expect((await dbB.select(dbB.babies).get()).single.id, babyA.id);
    // 家人同步下来的记录带上记录人，本机写的为空
    expect(logsA.firstWhere((l) => l.type == 'diaper').updatedBy, 'ub');
    expect(logsA.firstWhere((l) => l.type == 'feed').updatedBy, isNull);
    expect((await CareLogRepository(dbA).watchLatestByFamily().first)!.type, 'diaper');
  });

  test('最后写入者胜出，删除能同步，旧版本不会覆盖新版本', () async {
    final baby = await BabyRepository(dbA).ensureDefault();
    final id = await CareLogRepository(dbA).add(baby.id, CareLogType.feed, at: DateTime(2026, 10, 13, 8));
    await a.create(name: '爸爸', avatar: 'dad');
    await b.join(code: server.invites.keys.single, name: '妈妈', avatar: 'mom');

    // B 改了详情（较新），A 稍后同步不能把它改回去
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await CareLogRepository(dbB).updateDetail(id, const CareDetail(ml: 120));
    await b.sync();
    await a.sync();
    expect((await CareLogRepository(dbA).byId(id))!.detail, const CareDetail(ml: 120).encode());

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await CareLogRepository(dbA).delete(id);
    await a.sync();
    await b.sync();
    expect(await CareLogRepository(dbB).byId(id), isNull);
    expect(await CareLogRepository(dbB).all(), isEmpty);
  });

  test('宝宝性别随家庭同步（妈咪日记 v5）；服务端没有 gender 列时保留本地值', () async {
    final baby = await BabyRepository(dbA).ensureDefault();
    await a.create(name: '爸爸', avatar: 'dad');
    await b.join(code: server.invites.keys.single, name: '妈妈', avatar: 'mom');
    await BabyRepository(dbA).updateGender(baby.id, 'girl');
    // 本地时间按秒存储，人为推后避免与建家庭时的服务端时间戳同秒
    await (dbA.update(dbA.babies)..where((x) => x.id.equals(baby.id)))
        .write(BabiesCompanion(updatedAt: Value(DateTime.now().add(const Duration(seconds: 2)))));
    await a.sync();
    await b.sync();
    expect((await dbB.select(dbB.babies).getSingle()).gender, 'girl');

    // 模拟老服务端：拉取结果里没有 gender 键
    final fid = server.babies.keys.single;
    server.babies[fid] = Map.of(server.babies[fid]!)
      ..remove('gender')
      ..['nickname'] = '糖糖'
      ..['updated_at'] = DateTime.now().add(const Duration(minutes: 1)).toUtc().toIso8601String();
    await b.sync();
    final bb = await dbB.select(dbB.babies).getSingle();
    expect(bb.nickname, '糖糖');
    expect(bb.gender, 'girl');
  });

  test('云端已有性别后可以改成另一个性别，家人收到新值', () async {
    final baby = await BabyRepository(dbA).ensureDefault();
    await a.create(name: '爸爸', avatar: 'dad');
    await b.join(code: server.invites.keys.single, name: '妈妈', avatar: 'mom');
    Future<void> setGender(String g, int sec) async {
      await BabyRepository(dbA).updateGender(baby.id, g);
      await (dbA.update(dbA.babies)..where((x) => x.id.equals(baby.id)))
          .write(BabiesCompanion(updatedAt: Value(DateTime.now().add(Duration(seconds: sec)))));
      await a.sync();
      await b.sync();
    }

    await setGender('girl', 2);
    expect((await dbB.select(dbB.babies).getSingle()).gender, 'girl');
    await setGender('boy', 4);
    expect(server.babies.values.single['gender'], 'boy');
    expect((await dbB.select(dbB.babies).getSingle()).gender, 'boy');
  });

  test('日记来源的护理记录同步给家人（D3），source 不上云，家人那边记为默认 quick', () async {
    await BabyRepository(dbA).ensureDefault();
    await a.create(name: '爸爸', avatar: 'dad');
    await b.join(code: server.invites.keys.single, name: '妈妈', avatar: 'mom');
    final baby = await dbA.select(dbA.babies).getSingle();
    final id = await CareLogRepository(dbA).add(baby.id, CareLogType.diaper, at: DateTime(2026, 10, 13, 9), source: 'diary');
    await a.sync();
    await b.sync();
    final got = (await CareLogRepository(dbB).byId(id))!;
    expect(got.type, 'diaper');
    expect(got.source, 'quick');
  });

  test('两台手机同时开始喂奶：后开始的保留，先开始的自动结束', () async {
    final baby = await BabyRepository(dbA).ensureDefault();
    await a.create(name: '爸爸', avatar: 'dad');
    await b.join(code: server.invites.keys.single, name: '妈妈', avatar: 'mom');
    final t = DateTime(2026, 10, 13, 8);
    await CareLogRepository(dbA).startSession(baby.id, CareLogType.feed, at: t);
    await CareLogRepository(dbB).startSession(baby.id, CareLogType.feed, at: t.add(const Duration(minutes: 3)));
    await a.sync();
    await b.sync();
    await a.sync();
    for (final db in [dbA, dbB]) {
      final active = await CareLogRepository(db).activeSession(baby.id, CareLogType.feed);
      expect(active!.startedAt, t.add(const Duration(minutes: 3)));
      expect((await CareLogRepository(db).all()).length, 2);
    }
  });

  test('哭声判断和反馈同步给家人（不带录音）', () async {
    final baby = await BabyRepository(dbA).ensureDefault();
    await a.create(name: '爸爸', avatar: 'dad');
    await b.join(code: server.invites.keys.single, name: '妈妈', avatar: 'mom');
    final ctx = CryContext(at: DateTime(2026, 10, 13, 20), babyAgeMonths: 1, sinceLastFeed: const Duration(minutes: 200));
    final pred = await RuleBasedPredictor().predict(const AudioFeatures(), ctx);
    final eid = await CryEventRepository(dbA).save(
        babyId: baby.id, startedAt: DateTime(2026, 10, 13, 20), durationMs: 5000, context: ctx, prediction: pred, audioPath: '/tmp/x.wav');
    await FeedbackRepository(dbA).save(eid, CryCause.hungry);
    await a.sync();
    await b.sync();
    final e = await CryEventRepository(dbB).byId(eid);
    expect(e, isNotNull);
    expect(e!.audioPath, isNull);
    expect(await FeedbackRepository(dbB).causeCounts(baby.id), {'hungry': 1});
  });

  test('参与改进：关闭时不传；开启后只在 Wi-Fi 传有反馈的；裁到 30 秒；删除我的数据', () async {
    final prefs = await SharedPreferences.getInstance();
    final up = ResearchUploader(dbA, FakeCloud(server, 'ua'), prefs);
    final baby = await BabyRepository(dbA).ensureDefault();
    final dir = await Directory.systemTemp.createTemp();
    final f = File('${dir.path}/a.wav')..writeAsBytesSync(makeWav(40));
    final ctx = CryContext(at: DateTime(2026, 10, 13, 20), babyAgeMonths: 1, sinceLastFeed: const Duration(minutes: 200));
    final pred = await RuleBasedPredictor().predict(const AudioFeatures(), ctx);
    final repo = CryEventRepository(dbA);
    final e1 = await repo.save(babyId: baby.id, startedAt: DateTime(2026, 10, 13, 20), durationMs: 40000, context: ctx, prediction: pred, audioPath: f.path);
    await repo.save(babyId: baby.id, startedAt: DateTime(2026, 10, 13, 21), durationMs: 4000, context: ctx, prediction: pred, audioPath: f.path);
    await FeedbackRepository(dbA).save(e1, CryCause.sleepy);

    expect((await up.run(onWifi: true, appVersion: 't')).ok, 0, reason: '默认关闭');
    await up.setEnabled(true);
    expect((await up.run(onWifi: false, appVersion: 't')).ok, 0, reason: '没有 Wi-Fi');
    final r = await up.run(onWifi: true, appVersion: 't');
    expect(r.ok, 1, reason: '只传有反馈的那条');
    expect(server.clips.values.single.length, 44 + 16000 * 2 * 30);
    expect((await up.run(onWifi: true, appVersion: 't')).ok, 0, reason: '传过不再传');

    await up.deleteMine();
    expect(server.research, isEmpty);
    expect(server.clips, isEmpty);
    expect(up.enabled, isFalse);
    await dir.delete(recursive: true);
  });

  test('trimWav：短的不变长，坏数据返回 null', () {
    expect(trimWav(makeWav(3))!.length, 44 + 16000 * 2 * 3);
    expect(trimWav(Uint8List.fromList(List.filled(100, 1))), isNull);
  });
}
