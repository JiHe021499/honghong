import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/baby_repository.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/domain/diary/diary_service.dart';
import 'package:honghong/domain/diary/parse_result.dart';
import 'package:honghong/domain/models/care_log_type.dart';

void main() {
  late AppDatabase db;
  late DiaryService svc;
  late CareLogRepository logs;
  late String babyId;
  final now = DateTime.now();
  // 用“今天 now 往前”的时间，避免落到未来
  String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final t1 = now.subtract(const Duration(minutes: 30));

  setUp(() async {
    db = AppDatabase.memory();
    svc = DiaryService(db);
    logs = CareLogRepository(db);
    babyId = (await BabyRepository(db).ensureDefault()).id;
  });
  tearDown(() => db.close());

  ParseResult result(List<Map<String, dynamic>> cards, [String text = '原话']) =>
      ParseResult.fromGateway({'status': 'ok', 'prompt_version': 'parse-v2', 'cards': cards}, text: text, inputType: 'voice', now: now);

  test('D1：±15 分钟内首页已有同类记录 → 标重复并取消勾选', () async {
    await db.into(db.careLogs).insert(CareLogsCompanion(id: const Value('home1'),
        babyId: Value(babyId), type: const Value('diaper'), startedAt: Value(t1), endedAt: Value(t1)));
    final r = result([
      {'category': 'diaper', 'kind': 'event', 'event_time': hhmm(t1), 'attributes': {'type': 'pee'}, 'confidence': 0.9},
      {'category': 'mood', 'kind': 'event', 'event_time': hhmm(t1), 'confidence': 0.9},
    ]);
    await svc.prepare(babyId, r);
    expect(r.cards[0].duplicate, isTrue);
    expect(r.cards[0].selected, isFalse);
    expect(r.cards[1].duplicate, isFalse);
  });

  test('D4：只有开始时间的睡眠记为进行中；已有进行中则只存卡片', () async {
    final r = result([{'category': 'sleep', 'kind': 'event', 'event_time': hhmm(t1), 'confidence': 0.9}]);
    await svc.prepare(babyId, r);
    expect(r.cards.single.sleepOngoing, isTrue);
    expect(await svc.save(babyId: babyId, ageInDays: 30, r: r), 1);
    final active = await logs.activeSession(babyId, CareLogType.sleep);
    expect(active, isNotNull);
    expect(active!.endedAt, isNull);

    final r2 = result([{'category': 'sleep', 'kind': 'event', 'event_time': hhmm(now.subtract(const Duration(minutes: 5))), 'confidence': 0.9}]);
    await svc.prepare(babyId, r2);
    expect(r2.cards.single.sleepConflict, isTrue);
    await svc.save(babyId: babyId, ageInDays: 30, r: r2);
    final sleeps = await (db.select(db.careLogs)..where((l) => l.type.equals('sleep'))).get();
    expect(sleeps, hasLength(1));
    expect(await db.select(db.diaryCards).get(), hasLength(2));
  });

  test('保存映射：event 写 care_logs，aggregate 只存卡片，未勾选不存', () async {
    final r = result([
      {'category': 'feeding', 'kind': 'event', 'event_time': hhmm(t1), 'attributes': {'method': 'formula', 'ml': 90}, 'confidence': 0.9},
      {'category': 'feeding', 'kind': 'aggregate', 'attributes': {'count': 6}, 'confidence': 0.9},
      {'category': 'diaper', 'kind': 'event', 'event_time': hhmm(t1), 'attributes': {'type': 'poo'}, 'confidence': 0.9},
      {'category': 'other', 'kind': 'event', 'note': '洗澡', 'confidence': 0.9},
    ]);
    await svc.prepare(babyId, r);
    r.cards[3].selected = false;
    expect(await svc.save(babyId: babyId, ageInDays: 30, r: r), 3);
    final care = await db.select(db.careLogs).get();
    expect(care.map((c) => c.type).toSet(), {'feed', 'diaper'});
    expect(care.every((c) => c.source == 'diary' && c.diaryCardId != null), isTrue);
    final feed = care.firstWhere((c) => c.type == 'feed');
    expect(feed.detail, contains('90'));
    expect(await db.select(db.diaryCards).get(), hasLength(3));
    final input = (await db.select(db.diaryInputs).get()).single;
    expect(input.promptVersion, 'parse-v2');
    expect(input.rawText, '原话');
  });

  test('一条都没勾选：不写库', () async {
    final r = result([{'category': 'mood', 'kind': 'event', 'confidence': 0.9}]);
    r.cards.single.selected = false;
    expect(await svc.save(babyId: babyId, ageInDays: 30, r: r), 0);
    expect(await db.select(db.diaryInputs).get(), isEmpty);
  });

  test('只有时长的睡眠：倒推开始时间，结束不晚于现在', () async {
    final r = result([{'category': 'sleep', 'kind': 'event', 'attributes': {'duration_min': 40}, 'confidence': 0.9}]);
    await svc.prepare(babyId, r);
    await svc.save(babyId: babyId, ageInDays: 30, r: r);
    final s = (await db.select(db.careLogs).get()).single;
    expect(s.endedAt!.difference(s.startedAt).inMinutes, 40);
    expect(s.endedAt!.isAfter(DateTime.now()), isFalse);
  });
}
