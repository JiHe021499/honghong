import 'package:go_router/go_router.dart';
import 'package:honghong/core/router/app_router.dart';
import 'package:flutter/material.dart' hide Column;
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/data/repositories/diary_repository.dart';
import 'package:honghong/domain/diary/summary_service.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/features/diary/diary_flow.dart';
import 'package:honghong/features/diary/diary_providers.dart';
import 'package:honghong/features/diary/summary_page.dart';
import 'package:honghong/services/diary/diary_api.dart';

import 'diary_flow_test.dart' show FakeApi, FakeVoice, Clock;
import 'helpers.dart';

final day = DateTime(2026, 10, 14);
DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 14, h, m);

Future<void> seedBaby(AppDatabase db) =>
    db.into(db.babies).insert(BabiesCompanion.insert(id: 'b', nickname: '小米粒', birthDate: DateTime(2026, 8, 15)));

Future<void> seedDay(AppDatabase db, {DateTime? on}) async {
  final d = on ?? day;
  await CareLogRepository(db).add('b', CareLogType.feed, at: d.add(const Duration(hours: 8)), endedAt: d.add(const Duration(hours: 8, minutes: 20)));
  await CareLogRepository(db).add('b', CareLogType.feed, at: d.add(const Duration(hours: 12)));
  await CareLogRepository(db).add('b', CareLogType.sleep, at: d.add(const Duration(hours: 13)), endedAt: d.add(const Duration(hours: 13, minutes: 40)));
}

void main() {
  group('SummaryService', () {
    late AppDatabase db;
    late FakeApi api;
    late DateTime t;
    SummaryService svc() => SummaryService(db, api: api, now: () => t);
    Future<DailySummary?> row(DateTime d) => DiaryRepository(db).summaryOf('b', d);
    setUp(() async {
      db = AppDatabase.memory();
      api = FakeApi();
      await seedBaby(db);
    });
    tearDown(() => db.close());

    test('21:00 前不生成今天', () async {
      await seedDay(db);
      t = at(20, 59);
      await svc().trigger('b', DateTime(2026, 8, 15));
      expect(await row(day), isNull);
      expect(api.summaryCalls, isEmpty);
    });

    test('21:00 后生成：ready、快照统计、来源 id、幂等键=summaryId', () async {
      await seedDay(db);
      t = at(21, 3);
      await svc().trigger('b', DateTime(2026, 8, 15));
      final r = (await row(day))!;
      expect(r.status, 'ready');
      expect(r.content, api.summaryText);
      expect(r.generatedAt, at(21, 3));
      expect(r.statsJson, contains('"count":2'));
      expect(api.summaryCalls.where((c) => c.startsWith('2026-10-14')).single, '2026-10-14:${r.id}');
    });

    test('空日：status=empty，不调 AI', () async {
      t = at(21, 30);
      await svc().trigger('b', DateTime(2026, 8, 15));
      expect((await row(day))!.status, 'empty');
      expect(api.summaryCalls, isEmpty);
    });

    test('补生成昨天（D7），早上也会补', () async {
      await seedDay(db, on: DateTime(2026, 10, 13));
      t = at(7);
      await svc().trigger('b', DateTime(2026, 8, 15));
      expect((await row(DateTime(2026, 10, 13)))!.status, 'ready');
      expect(await row(day), isNull);
    });

    test('失败最多 3 次，之后不再请求；ready 后不改写（D8）', () async {
      await seedDay(db);
      t = at(21, 10);
      api.error = const DiaryApiException(DiaryApiError.network);
      for (var i = 0; i < 5; i++) {
        await svc().ensure('b', day, DateTime(2026, 8, 15));
      }
      final r = (await row(day))!;
      expect(r.status, 'failed');
      expect(r.attempts, 3);
      expect(api.summaryCalls, hasLength(3));
    });

    test('ready 后再触发、再加记录也不改写', () async {
      await seedDay(db);
      t = at(21);
      await svc().ensure('b', day, DateTime(2026, 8, 15));
      api.summaryText = '改写了';
      await CareLogRepository(db).add('b', CareLogType.feed, at: at(21, 30));
      t = at(22);
      await svc().ensure('b', day, DateTime(2026, 8, 15));
      expect((await row(day))!.content, isNot('改写了'));
      expect(api.summaryCalls, hasLength(1));
    });

    test('并发触发同一天只请求一次', () async {
      await seedDay(db);
      t = at(21, 5);
      await Future.wait([for (var i = 0; i < 4; i++) svc().ensure('b', day, DateTime(2026, 8, 15))]);
      expect(api.summaryCalls, hasLength(1));
    });

    test('未配置网关：保持 pending，不计失败', () async {
      await seedDay(db);
      t = at(21, 5);
      await SummaryService(db, api: null, now: () => t).ensure('b', day, DateTime(2026, 8, 15));
      final r = (await row(day))!;
      expect(r.status, 'pending');
      expect(r.attempts, 0);
    });

    test('四格数字来自快照', () {
      final f = summaryFacts({
        'feed': {'count': 2, 'total_ml': 0},
        'sleep': {'count': 1, 'total_min': 40},
        'diaper': {'count': 1, 'poo': 1, 'pee': 0},
        'mood': [
          {'period': 'afternoon', 'type': '哭闹', 'intensity': '厉害'}
        ],
      });
      expect(f.map((e) => '${e.label}:${e.value}'), ['喂奶:2 次', '睡眠:40 分钟', '便便:1 次', '哭闹:下午']);
    });
  });

  group('小结页 / 入口', () {
    late Clock clock;
    late FakeApi api;
    Future<AppDatabase> boot(WidgetTester tester, {bool data = true, DiaryApiException? err}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      clock = Clock()..t = at(21, 3);
      api = FakeApi(error: err);
      return pumpApp(tester, seed: (db) async {
        await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b', nickname: '小米粒', birthDate: DateTime(2026, 8, 15)));
        if (data) await seedDay(db);
      }, prefs: const {kDiaryGenderPrompted: true}, overrides: [
        diaryApiProvider.overrideWithValue(api),
        voiceCaptureProvider.overrideWithValue(FakeVoice()),
        diaryClockProvider.overrideWithValue(clock.call),
        summaryClockProvider.overrideWithValue(clock.call),
      ]);
    }

    Future<void> openFromHome(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await settle(tester, 10);
      await tester.ensureVisible(find.byKey(const Key('diary-entry')));
      await tester.tap(find.byKey(const Key('diary-entry')));
      await settle(tester, 10);
    }

    testWidgets('21:00 后打开首页自动生成；入口卡直达小结页', (tester) async {
      await boot(tester);
      await openFromHome(tester);
      expect(find.byType(SummaryPage), findsOneWidget);
      expect(find.byKey(const Key('sum-content')), findsOneWidget);
      expect(find.text('10 月 14 日 · 星期三 · 21:03'), findsOneWidget);
      expect(find.text('只根据今天保存的 3 条记录生成'), findsOneWidget);
      expect(find.textContaining('不提供医疗诊断'), findsOneWidget);
      expect(api.summaryCalls, hasLength(1));
      await tester.tap(find.byKey(const Key('sum-day')));
      await settle(tester, 10);
      expect(find.textContaining('生成于 21:03'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('空日 → 屏 23，补记一句进日记', (tester) async {
      await boot(tester, data: false);
      await openFromHome(tester);
      // 空日入口卡仍进日记页；从路由打开小结页 → 屏 23
      expect(find.byType(SummaryPage), findsNothing);
      GoRouter.of(tester.element(find.byType(Scaffold).last)).push(Routes.diarySummary);
      await settle(tester, 10);
      expect(find.text('今天没有日记也没关系，照顾好宝宝和自己就是最重要的事。'), findsOneWidget);
      expect(api.summaryCalls, isEmpty);
      await tester.tap(find.byKey(const Key('sum-add')));
      await settle(tester, 10);
      expect(find.byKey(const Key('diary-mic')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('失败 → 时间线显示“今晚小结还在整理”', (tester) async {
      await boot(tester, err: const DiaryApiException(DiaryApiError.failed));
      await openFromHome(tester);
      await tester.tap(find.byKey(const Key('diary-all')));
      await settle(tester, 10);
      expect(find.byKey(const Key('tl-summary-pending')), findsOneWidget);
      expect(find.text('今晚小结还在整理'), findsOneWidget);
      await unmount(tester);
    });
  });
}
