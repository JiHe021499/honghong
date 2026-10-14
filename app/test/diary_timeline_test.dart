import 'package:honghong/core/app_clock.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart' hide Column;
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/data/repositories/diary_repository.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/features/diary/diary_flow.dart';
import 'package:honghong/features/diary/diary_providers.dart';

import 'diary_flow_test.dart' show FakeApi, FakeVoice, Clock;
import 'helpers.dart';

void main() {
  // 固定“现在”：真实时钟在接近午夜时会把种子记录挤到同一分钟，结果随运行时刻和时区变化
  final now = DateTime(2026, 10, 14, 18, 30);
  final today = DateTime(now.year, now.month, now.day);
  // 保证在“现在之前”且在今天
  DateTime ago(int min) {
    final t = now.subtract(Duration(minutes: min));
    return t.isBefore(today) ? today.add(const Duration(minutes: 1)) : t;
  }

  /// 首页快捷喂奶 + 日记单次喂奶（写 care_logs）+ 日记汇总“共 6 次” + 情绪卡
  Future<void> seed(AppDatabase db) async {
    await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b', nickname: '小米粒', birthDate: now.subtract(const Duration(days: 60))));
    await CareLogRepository(db).add('b', CareLogType.feed, at: ago(90), endedAt: ago(75));
    DiaryCardsCompanion card(String cat, String kind, DateTime sort, {String attrs = '{}', String? intensity, String? period, String? note}) =>
        DiaryCardsCompanion(
            babyId: const Value('b'), category: Value(cat), kind: Value(kind), sortTime: Value(sort), diaryDate: Value(today),
            attributes: Value(attrs), intensity: Value(intensity), timePeriod: Value(period), note: Value(note), eventTime: Value(kind == 'event' && cat == 'feeding' ? sort : null));
    await DiaryRepository(db).saveInput(
      DiaryInputsCompanion.insert(id: 'in1', babyId: 'b', inputType: 'voice', rawText: '今天吃奶6次，下午哭得厉害，刚才喂了一次', ageInDays: 60, parseStatus: 'ok', promptVersion: 'parse-v2'),
      [
        DiaryCardDraft(card('feeding', 'aggregate', ago(1), attrs: '{"count":6}', period: 'all_day')),
        DiaryCardDraft(card('mood', 'event', ago(30), attrs: '{"type":"哭闹"}', intensity: '厉害', period: 'afternoon', note: '下午哭得厉害')),
        DiaryDraftHelper.feed(card('feeding', 'event', ago(10)), ago(10)),
      ],
    );
  }

  group('不重复计数', () {
    late AppDatabase db;
    setUp(() async {
      AppClock.source = () => now;
      addTearDown(() => AppClock.source = DateTime.now);
      db = AppDatabase.memory();
      await seed(db);
    });
    tearDown(() => db.close());

    test('关联了 care_logs 的日记卡不单独出现；汇总不计入次数', () async {
      final repo = DiaryRepository(db);
      final tl = await repo.timeline('b', today);
      expect(tl.where((e) => e.isCareLog), hasLength(2)); // 快捷 + 日记单次
      expect(tl.where((e) => !e.isCareLog), hasLength(2)); // 汇总 + 情绪
      expect(await db.select(db.diaryCards).get(), hasLength(3));
      expect((await repo.careCounts('b', today))[CareLogType.feed], 2);
    });

    test('时间线上删日记来源的 care_log：卡片一并删除，次数随之减少', () async {
      final repo = DiaryRepository(db);
      final diaryLog = (await db.select(db.careLogs).get()).firstWhere((l) => l.source == 'diary');
      await repo.deleteCareLog(diaryLog.id);
      expect((await repo.careCounts('b', today))[CareLogType.feed], 1);
      final card = await repo.cardForCareLog(diaryLog.id);
      expect(card, isNull);
    });
  });

  group('时间线界面', () {
    late Clock clock;
    Future<AppDatabase> open(WidgetTester tester) async {
      fixClock(tester, now);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      clock = Clock();
      final db = await pumpApp(tester, seed: seed, prefs: const {kDiaryGenderPrompted: true}, overrides: [
        diaryApiProvider.overrideWithValue(FakeApi(json: const {})),
        voiceCaptureProvider.overrideWithValue(FakeVoice()),
        diaryClockProvider.overrideWithValue(clock.call),
      ]);
      await tester.ensureVisible(find.byKey(const Key('diary-entry')));
      await tester.tap(find.byKey(const Key('diary-entry')));
      await settle(tester, 10);
      await tester.tap(find.byKey(const Key('diary-all')));
      await settle(tester, 10);
      return db;
    }

    Finder rowWith(String text) => find.ancestor(of: find.textContaining(text), matching: find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('tl-'))).first;

    testWidgets('查看全部 → 当日时间线：4 条、快捷记录标签、汇总标签排最后', (tester) async {
      await open(tester);
      expect(find.text('今天的日记'), findsWidgets);
      expect(find.textContaining('· 4 条'), findsOneWidget);
      expect(find.text('快捷记录'), findsOneWidget);
      expect(find.text('汇总'), findsOneWidget);
      final ys = [for (final t in ['情绪', '汇总']) tester.getCenter(find.textContaining(t).first).dy];
      expect(ys[0] < ys[1], isTrue);
      await unmount(tester);
    });

    testWidgets('编辑情绪卡：改程度后保存', (tester) async {
      final db = await open(tester);
      await tester.tap(rowWith('情绪'));
      await settle(tester, 8);
      expect(find.text('来自：“下午哭得厉害”'), findsOneWidget);
      await tester.tap(find.text('明显'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('card-save')));
      await settle(tester, 8);
      final mood = await tester.runAsync(() => (db.select(db.diaryCards)..where((c) => c.category.equals('mood'))).getSingle());
      expect(mood!.intensity, '明显');
      expect(mood.editedByUser, isTrue);
      await unmount(tester);
    });

    testWidgets('删除二次确认：再想想不删，确认后从时间线消失', (tester) async {
      await open(tester);
      await tester.tap(rowWith('情绪'));
      await settle(tester, 8);
      await tester.tap(find.byKey(const Key('card-delete')));
      await settle(tester, 8);
      expect(find.text('删除这条日记？'), findsOneWidget);
      expect(find.textContaining('已生成的今日小结不会自动改写'), findsOneWidget);
      await tester.tap(find.byKey(const Key('del-cancel')));
      await settle(tester, 8);
      expect(find.textContaining('· 4 条'), findsOneWidget);

      await tester.tap(rowWith('情绪'));
      await settle(tester, 8);
      await tester.tap(find.byKey(const Key('card-delete')));
      await settle(tester, 8);
      await tester.tap(find.byKey(const Key('del-confirm')));
      await settle(tester, 10);
      expect(find.textContaining('· 3 条'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('切到没有记录的日子：空状态', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('day-2')));
      await settle(tester, 10);
      expect(find.byKey(const Key('tl-empty')), findsOneWidget);
      expect(find.text('这天还没有日记'), findsOneWidget);
      expect(find.textContaining('· 0 条'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('快捷记录只读：点开跳到全部记录', (tester) async {
      await open(tester);
      await tester.tap(rowWith('快捷记录'));
      await settle(tester, 10);
      expect(find.byKey(const Key('tl-count')), findsNothing);
      await unmount(tester);
    });
  });
}

class DiaryDraftHelper {
  static DiaryCardDraft feed(DiaryCardsCompanion card, DateTime at) => DiaryCardDraft(card,
      careLog: CareLogsCompanion(babyId: const Value('b'), type: const Value('feed'), startedAt: Value(at), endedAt: Value(at.add(const Duration(minutes: 5)))));
}
