import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/baby_repository.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/domain/models/care_detail.dart';
import 'package:honghong/domain/models/care_log_type.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late CareLogRepository logs;
  late String babyId;
  final t0 = DateTime(2026, 10, 13, 18, 5);

  setUp(() async {
    db = AppDatabase.memory();
    logs = CareLogRepository(db);
    babyId = (await BabyRepository(db).ensureDefault()).id;
  });
  tearDown(() => db.close());

  test('开始计时：同类型只能有一条进行中，重复点返回同一条', () async {
    final a = await logs.startSession(babyId, CareLogType.feed, at: t0);
    final b = await logs.startSession(babyId, CareLogType.feed, at: t0.add(const Duration(minutes: 1)));
    expect(b.id, a.id);
    expect(a.endedAt, isNull);
    // 不同类型可以同时进行
    await logs.startSession(babyId, CareLogType.sleep, at: t0);
    final active = await logs.watchActive(babyId).first;
    expect(active.map((l) => l.type).toSet(), {'feed', 'sleep'});
  });

  test('数据库唯一索引兜底：直接插第二条进行中的同类记录会失败', () async {
    await logs.startSession(babyId, CareLogType.burp, at: t0);
    expect(
      () => db.into(db.careLogs).insert(CareLogsCompanion.insert(
          id: 'x', babyId: babyId, type: 'burp', startedAt: t0)),
      throwsA(anything),
    );
  });

  test('结束 → 继续 → 结束并保存（微调时长 + 细节）', () async {
    final s = await logs.startSession(babyId, CareLogType.feed, at: t0);
    await logs.stopSession(s.id, at: t0.add(const Duration(minutes: 3, seconds: 20)));
    expect((await logs.byId(s.id))!.endedAt, t0.add(const Duration(minutes: 3, seconds: 20)));
    expect(await logs.activeSession(babyId, CareLogType.feed), isNull);

    await logs.resumeSession(s.id);
    final resumed = await logs.byId(s.id);
    expect(resumed!.endedAt, isNull);
    expect(resumed.startedAt, t0, reason: '继续不改开始时间');
    expect((await logs.activeSession(babyId, CareLogType.feed))!.id, s.id);

    await logs.stopSession(s.id, at: t0.add(const Duration(minutes: 15)));
    await logs.saveSession(s.id,
        duration: const Duration(minutes: 16),
        detail: const CareDetail(method: FeedMethod.breast, side: FeedSide.left));
    final saved = (await logs.byId(s.id))!;
    expect(saved.endedAt, t0.add(const Duration(minutes: 16)));
    final d = CareDetail.decode(saved.detail);
    expect(d.method, FeedMethod.breast);
    expect(d.side, FeedSide.left);
    expect(describeLog(CareLogType.feed, saved.startedAt, saved.endedAt, saved.detail), '母乳 · 左侧 16 分钟');

    // 结束后可以开始新的一次
    final next = await logs.startSession(babyId, CareLogType.feed, at: t0.add(const Duration(hours: 3)));
    expect(next.id, isNot(s.id));
  });

  test('继续时如果已经开了新的同类计时，不覆盖', () async {
    final a = await logs.startSession(babyId, CareLogType.sleep, at: t0);
    await logs.stopSession(a.id, at: t0.add(const Duration(minutes: 20)));
    final b = await logs.startSession(babyId, CareLogType.sleep, at: t0.add(const Duration(minutes: 30)));
    await logs.resumeSession(a.id);
    expect((await logs.byId(a.id))!.endedAt, isNotNull);
    expect((await logs.activeSession(babyId, CareLogType.sleep))!.id, b.id);
  });

  test('换尿布一点即记（未分类），之后可改成大便', () async {
    final id = await logs.logDiaper(babyId, at: t0);
    final l = (await logs.byId(id))!;
    expect(l.endedAt, l.startedAt, reason: '换尿布不进入计时');
    expect(describeLog(CareLogType.diaper, l.startedAt, l.endedAt, l.detail), '换尿布 · 未分类');
    await logs.updateDetail(id, const CareDetail(diaper: DiaperKind.poo));
    final e = (await logs.byId(id))!;
    expect(CareDetail.decode(e.detail).diaper, DiaperKind.poo);
    expect(describeLog(CareLogType.diaper, e.startedAt, e.endedAt, e.detail), '换尿布 · 大便');
    expect(await logs.watchActive(babyId).first, isEmpty);
  });

  test('进行中的计时在 App 重启（重新打开数据库）后还在', () async {
    final dir = await Directory.systemTemp.createTemp('hh');
    final file = File('${dir.path}/db.sqlite');
    var fdb = AppDatabase(NativeDatabase(file));
    final bid = (await BabyRepository(fdb).ensureDefault()).id;
    final s = await CareLogRepository(fdb).startSession(bid, CareLogType.sleep, at: t0);
    await fdb.close();

    fdb = AppDatabase(NativeDatabase(file));
    final again = await CareLogRepository(fdb).activeSession(bid, CareLogType.sleep);
    expect(again?.id, s.id);
    expect(again?.startedAt, t0);
    await fdb.close();
    await dir.delete(recursive: true);
  });

  test('迁移 v1 → v4：旧的时间点记录补成已结束，多余未结束睡眠收尾，建唯一索引', () async {
    final dir = await Directory.systemTemp.createTemp('hh');
    final file = File('${dir.path}/v1.sqlite');
    // 先建一个 v2 库，再退回成 v1 的样子：删掉索引、user_version=1、写入 v1 风格数据
    var fdb = AppDatabase(NativeDatabase(file));
    final bid = (await BabyRepository(fdb).ensureDefault()).id;
    await fdb.customStatement('DROP INDEX care_logs_one_active');
    Future<void> raw(String id, String type, DateTime at) => fdb.into(fdb.careLogs).insert(
        CareLogsCompanion.insert(id: id, babyId: bid, type: type, startedAt: at));
    await raw('f1', 'feed', t0);
    await raw('f2', 'feed', t0.add(const Duration(hours: 3)));
    await raw('d1', 'diaper', t0);
    await raw('b1', 'burp', t0);
    await raw('s1', 'sleep', t0); // 旧的忘了结束
    await raw('s2', 'sleep', t0.add(const Duration(hours: 1))); // 最新的：保留为进行中
    await fdb.into(fdb.careLogs).insert(CareLogsCompanion.insert(
        id: 's0', babyId: bid, type: 'sleep', startedAt: t0, endedAt: Value(t0.add(const Duration(minutes: 40)))));
    // v3 新增的同步列也退回去
    for (final t in ['babies', 'care_logs', 'cry_events']) {
      for (final c in ['updated_at', 'dirty', if (t != 'babies') 'deleted', if (t == 'care_logs') 'updated_by']) {
        await fdb.customStatement('ALTER TABLE $t DROP COLUMN $c');
      }
    }
    await fdb.customStatement('PRAGMA user_version = 1');
    await fdb.close();

    fdb = AppDatabase(NativeDatabase(file));
    final repo = CareLogRepository(fdb);
    Future<DateTime?> end(String id) async => (await repo.byId(id))!.endedAt;
    expect(await end('f1'), t0);
    expect(await end('f2'), t0.add(const Duration(hours: 3)));
    expect(await end('d1'), t0);
    expect(await end('b1'), t0);
    expect(await end('s1'), t0);
    expect(await end('s2'), isNull);
    expect(await end('s0'), t0.add(const Duration(minutes: 40)), reason: '已结束的不动');
    final idx = await fdb.customSelect("SELECT name FROM sqlite_master WHERE type='index' AND name='care_logs_one_active'").get();
    expect(idx, hasLength(1));
    final ver = await fdb.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 4);
    await fdb.close();
    await dir.delete(recursive: true);
  });

  test('格式化', () {
    expect(formatTimer(const Duration(minutes: 3, seconds: 20)), '3:20');
    expect(formatTimer(const Duration(hours: 1, minutes: 5, seconds: 9)), '1:05:09');
    expect(formatDuration(const Duration(minutes: 42)), '42 分钟');
    expect(formatDuration(const Duration(hours: 1, minutes: 5)), '1 小时 5 分');
    final d = const CareDetail(method: FeedMethod.formula, ml: 90);
    expect(describeLog(CareLogType.feed, t0, t0.add(const Duration(minutes: 10)), d.encode()), '配方奶 · 10 分钟 90ml');
    expect(describeLog(CareLogType.sleep, t0, t0.add(const Duration(minutes: 42)), const CareDetail(note: '小睡').encode()), '小睡 · 42 分钟');
    expect(CareDetail.decode('not json').method, isNull);
  });
}
