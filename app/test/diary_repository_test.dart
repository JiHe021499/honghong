import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/baby_repository.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/data/repositories/diary_repository.dart';
import 'package:honghong/domain/models/care_log_type.dart';

void main() {
  late AppDatabase db;
  late DiaryRepository diary;
  late CareLogRepository logs;
  late String babyId;
  final day = DateTime(2026, 10, 14);
  DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 14, h, m);

  setUp(() async {
    db = AppDatabase.memory();
    diary = DiaryRepository(db);
    logs = CareLogRepository(db);
    babyId = (await BabyRepository(db).ensureDefault()).id;
  });
  tearDown(() => db.close());

  DiaryInputsCompanion input([String text = '今天吃奶6次，下午哭得厉害，十点拉了一次']) => DiaryInputsCompanion.insert(
      id: 'in1', babyId: babyId, inputType: 'voice', rawText: text, ageInDays: 102, parseStatus: 'ok', promptVersion: 'parse-v1');

  DiaryCardsCompanion card(String category, String kind, DateTime sort, {DateTime? diaryDate, String attrs = '{}'}) =>
      DiaryCardsCompanion(
          babyId: Value(babyId), category: Value(category), kind: Value(kind), sortTime: Value(sort),
          diaryDate: Value(diaryDate ?? sort), attributes: Value(attrs), note: const Value('原话'));

  CareLogsCompanion careLog(CareLogType t, DateTime s) =>
      CareLogsCompanion(babyId: Value(babyId), type: Value(t.name), startedAt: Value(s), endedAt: Value(s));

  /// 一句话 → 汇总喂奶 + 下午情绪 + 10 点便便（event，写 care_logs）
  Future<List<String>> saveSample() => diary.saveInput(input(), [
        DiaryCardDraft(card('feeding', 'aggregate', at(12), attrs: '{"count":6}')),
        DiaryCardDraft(card('mood', 'event', at(15))),
        DiaryCardDraft(card('diaper', 'event', at(10)), careLog: careLog(CareLogType.diaper, at(10))),
      ]);

  test('事务保存：event 卡写 care_logs(source=diary) 并双向关联', () async {
    final ids = await saveSample();
    expect(ids, hasLength(3));
    final diaperCard = (await diary.cardById(ids[2]))!;
    expect(diaperCard.inputId, 'in1');
    expect(diaperCard.careLogId, isNotNull);
    final log = (await logs.byId(diaperCard.careLogId!))!;
    expect(log.source, 'diary');
    expect(log.diaryCardId, diaperCard.id);
    expect(log.dirty, isTrue, reason: '日记写入的护理记录参与家庭同步（D3）');
    expect((await diary.cardForCareLog(log.id))!.id, diaperCard.id);
    expect((await diary.cardById(ids[0]))!.careLogId, isNull);
    expect((await diary.inputById('in1'))!.rawText, contains('吃奶6次'));
  });

  test('事务失败整体回滚', () async {
    await expectLater(
        diary.saveInput(input(), [
          DiaryCardDraft(card('mood', 'event', at(9))),
          DiaryCardDraft(card('mood', 'event', at(9)).copyWith(babyId: const Value('no-such-baby'))),
        ]),
        throwsA(anything));
    expect(await db.select(db.diaryInputs).get(), isEmpty);
    expect(await db.select(db.diaryCards).get(), isEmpty);
  });

  test('时间线合并：快捷记录 + 日记，同一件事只出现一次，按时间排序', () async {
    await logs.add(babyId, CareLogType.feed, at: at(8)); // 快捷
    await logs.backfill(babyId, CareLogType.sleep, start: at(6), end: at(7)); // 补记
    await saveSample();
    // 别的日子 / 已删除的不应出现
    await logs.add(babyId, CareLogType.feed, at: DateTime(2026, 10, 13, 23));
    await diary.saveInput(input().copyWith(id: const Value('in2')), [DiaryCardDraft(card('other', 'event', DateTime(2026, 10, 15, 1)))]);

    final tl = await diary.timeline(babyId, day);
    expect(tl.map((e) => '${e.src}:${e.type}:${e.source}').toList(), [
      'care:sleep:backfill',
      'care:feed:quick',
      'care:diaper:diary',
      'card:feeding:diary',
      'card:mood:diary',
    ]);
    expect(tl.where((e) => e.isQuick), hasLength(1));
    expect(tl.where((e) => e.type == 'diaper'), hasLength(1), reason: '溯源卡不单独出现');
  });

  test('统计次数只数 care_logs，汇总卡不计入（D2）', () async {
    await logs.add(babyId, CareLogType.feed, at: at(8));
    await logs.add(babyId, CareLogType.feed, at: at(11));
    await saveSample(); // 含“今天吃奶6次”汇总
    final c = await diary.careCounts(babyId, day);
    expect(c[CareLogType.feed], 2);
    expect(c[CareLogType.diaper], 1);
  });

  test('凌晨补记归前一天：按 diaryDate 进时间线（D6）', () async {
    await diary.saveInput(input(), [DiaryCardDraft(card('mood', 'event', DateTime(2026, 10, 15, 3), diaryDate: DateTime(2026, 10, 14, 3)))]);
    expect(await diary.timeline(babyId, day), hasLength(1));
    expect(await diary.timeline(babyId, DateTime(2026, 10, 15)), isEmpty);
    expect((await db.select(db.diaryCards).getSingle()).diaryDate, day, reason: '归属日期存本地 00:00');
  });

  test('删除护理记录同时软删日记卡；删卡同时软删护理记录', () async {
    final ids = await saveSample();
    final logId = (await diary.cardById(ids[2]))!.careLogId!;
    await diary.deleteCareLog(logId);
    expect(await logs.byId(logId), isNull);
    expect(await diary.cardById(ids[2]), isNull);
    final row = await (db.select(db.careLogs)..where((l) => l.id.equals(logId))).getSingle();
    expect(row.deleted && row.dirty, isTrue, reason: '保留删除标记以便同步');

    final ids2 = await diary.saveInput(input().copyWith(id: const Value('in2')),
        [DiaryCardDraft(card('feeding', 'event', at(18)), careLog: careLog(CareLogType.feed, at(18)))]);
    final log2 = (await diary.cardById(ids2[0]))!.careLogId!;
    await diary.deleteCard(ids2[0]);
    expect(await logs.byId(log2), isNull);
    expect((await diary.timeline(babyId, day)).map((e) => e.type), ['feeding', 'mood']);
  });

  test('删除快捷记录不影响日记卡', () async {
    final quick = await logs.add(babyId, CareLogType.feed, at: at(8));
    final ids = await saveSample();
    await diary.deleteCareLog(quick);
    expect(await diary.cardById(ids[0]), isNotNull);
    expect(await diary.timeline(babyId, day), hasLength(3));
  });

  test('重复提醒：±15 分钟同类型首页记录命中，日记来源/其他类型/超窗不命中（D1）', () async {
    final quick = await logs.add(babyId, CareLogType.feed, at: at(10, 5));
    final back = await logs.backfill(babyId, CareLogType.feed, start: at(9, 50), end: at(10));
    await logs.add(babyId, CareLogType.feed, at: at(10, 16)); // 超窗
    await logs.add(babyId, CareLogType.diaper, at: at(10)); // 其他类型
    await diary.saveInput(input(), [
      DiaryCardDraft(card('feeding', 'event', at(10)), careLog: careLog(CareLogType.feed, at(10))),
    ]);
    final hits = await diary.possibleDuplicates(babyId, CareLogType.feed, at(10));
    expect(hits.map((l) => l.id), unorderedEquals([quick, back]));
    // 只提示不自动合并：数据都还在
    expect((await diary.careCounts(babyId, day))[CareLogType.feed], 4);
  });

  test('编辑卡片标记 editedByUser，改日期归一到 00:00', () async {
    final ids = await saveSample();
    await diary.updateCard(ids[1], DiaryCardsCompanion(intensity: const Value('有点'), diaryDate: Value(DateTime(2026, 10, 13, 22))));
    final c = (await diary.cardById(ids[1]))!;
    expect(c.editedByUser, isTrue);
    expect(c.intensity, '有点');
    expect(c.diaryDate, DateTime(2026, 10, 13));
    expect(c.updatedAt, isNotNull);
  });

  test('今日小结占位幂等，已有小结不被改写（D8）', () async {
    final a = await diary.claimSummary(babyId, at(21, 3), promptVersion: 'sum-v1');
    final b = await diary.claimSummary(babyId, at(22), promptVersion: 'sum-v2');
    expect(b.id, a.id);
    expect(b.status, 'pending');
    await diary.updateSummary(a.id, const DailySummariesCompanion(status: Value('ready'), content: Value('妈妈辛苦啦')));
    final c = await diary.claimSummary(babyId, day, promptVersion: 'sum-v1');
    expect(c.content, '妈妈辛苦啦');
    expect(await db.select(db.dailySummaries).get(), hasLength(1));
    expect(await diary.summaryOf(babyId, DateTime(2026, 10, 13)), isNull);
  });

  test('watchTimeline 随写入更新', () async {
    final stream = diary.watchTimeline(babyId, day);
    final seen = <int>[];
    final sub = stream.listen((v) => seen.add(v.length));
    await pumpEventQueue();
    await logs.add(babyId, CareLogType.feed, at: at(8));
    await pumpEventQueue();
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 1);
  });

  test('性别可设置/清除，非法值拒绝，并标记待同步', () async {
    final baby = BabyRepository(db);
    await (db.update(db.babies)..where((b) => b.id.equals(babyId))).write(const BabiesCompanion(dirty: Value(false)));
    await baby.updateGender(babyId, 'girl');
    var b = await (db.select(db.babies)..where((x) => x.id.equals(babyId))).getSingle();
    expect(b.gender, 'girl');
    expect(b.dirty, isTrue);
    await baby.updateGender(babyId, null);
    b = await (db.select(db.babies)..where((x) => x.id.equals(babyId))).getSingle();
    expect(b.gender, isNull);
    expect(() => baby.updateGender(babyId, 'x'), throwsArgumentError);
  });
}
