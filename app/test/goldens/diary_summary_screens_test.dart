@Tags(['golden'])
library;


import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:honghong/core/router/app_router.dart';
import 'package:honghong/core/theme/app_theme.dart';
import 'package:honghong/core/widgets/app_icon.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/data/repositories/diary_repository.dart';
import 'package:honghong/domain/models/care_detail.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/features/diary/diary_flow.dart';
import 'package:honghong/features/diary/diary_providers.dart';
import 'package:honghong/services/diary/diary_api.dart';

import '../diary_flow_test.dart' show FakeApi, FakeVoice, Clock;
import '../helpers.dart';

/// 妈咪日记 P5 今日小结（390×844 @3x），输出 test/goldens/diary-sum-*.png
const _cjk = ['/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'];
final _day = DateTime(2026, 10, 14);
DateTime _at(int h, [int m = 0]) => DateTime(2026, 10, 14, h, m);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() async {
    final cjk = FontLoader('Roboto');
    for (final f in _cjk) {
      cjk.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await cjk.load();
  });

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 8);
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('diary-sum-$name.png'));
  }

  Future<FakeApi> boot(WidgetTester tester, {bool data = true, DiaryApiException? err}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = Clock()..t = _at(21);
    final api = FakeApi(error: err)..summaryText = '今天小米粒吃了 6 次奶，午睡一个多小时，下午有点闹。你辛苦啦，早点休息。';
    await pumpApp(tester, prefs: const {kDiaryGenderPrompted: true}, overrides: [
      diaryApiProvider.overrideWithValue(api),
      voiceCaptureProvider.overrideWithValue(FakeVoice()),
      diaryClockProvider.overrideWithValue(clock.call),
      summaryClockProvider.overrideWithValue(clock.call),
    ], seed: (db) async {
      await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b', nickname: '小米粒', birthDate: _day.subtract(const Duration(days: 102))));
      if (!data) return;
      final logs = CareLogRepository(db);
      await logs.add('b', CareLogType.sleep, at: _at(13, 10), endedAt: _at(14, 25));
      await logs.add('b', CareLogType.diaper, at: _at(10), detail: const CareDetail(diaper: DiaperKind.poo).encode());
      DiaryCardsCompanion card(String cat, String kind, DateTime sort, {String attrs = '{}', String? intensity, String? period}) => DiaryCardsCompanion(
          babyId: const Value('b'), category: Value(cat), kind: Value(kind), sortTime: Value(sort), diaryDate: Value(_day),
          attributes: Value(attrs), intensity: Value(intensity), timePeriod: Value(period));
      await DiaryRepository(db).saveInput(
        DiaryInputsCompanion.insert(id: 'in1', babyId: 'b', inputType: 'voice', rawText: '今天吃奶6次，下午哭得厉害，有点鼻塞', ageInDays: 102, parseStatus: 'ok', promptVersion: 'parse-v2'),
        [
          DiaryCardDraft(card('feeding', 'aggregate', _at(20), attrs: '{"count":6}', period: 'all_day')),
          DiaryCardDraft(card('mood', 'event', _at(16), attrs: '{"type":"哭闹"}', intensity: '厉害', period: 'afternoon')),
          DiaryCardDraft(card('other', 'event', _at(18), attrs: '{"topic":"鼻塞"}')),
        ],
      );
    });
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(Scaffold).first);
      for (final i in AppIcon.values) {
        await precacheImage(AssetImage(i.asset), ctx);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester, 10);
    return api;
  }

  testWidgets('今日小结：首页入口、屏 21、屏 22', (tester) async {
    fixClock(tester, DateTime(2026, 10, 14, 21));
    await boot(tester);
    await tester.ensureVisible(find.byKey(const Key('diary-entry')));
    await settle(tester);
    await shot(tester, '02-home-entry');
    await tester.tap(find.byKey(const Key('diary-entry')));
    await settle(tester, 10);
    await shot(tester, '21-summary');
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).last)).read(nightModeProvider.notifier).set(true);
    await settle(tester, 10);
    await shot(tester, '22-summary-night');
    await unmount(tester);
  });

  testWidgets('今日小结：屏 23 当天无记录', (tester) async {
    fixClock(tester, DateTime(2026, 10, 14, 21));
    await boot(tester, data: false);
    GoRouter.of(tester.element(find.byType(Scaffold).last)).push(Routes.diarySummary);
    await settle(tester, 10);
    await shot(tester, '23-summary-empty');
    await unmount(tester);
  });

  testWidgets('生成失败：时间线“今晚小结还在整理”', (tester) async {
    fixClock(tester, DateTime(2026, 10, 14, 21));
    await boot(tester, err: const DiaryApiException(DiaryApiError.failed));
    GoRouter.of(tester.element(find.byType(Scaffold).last)).push(Routes.diaryDay);
    await settle(tester, 10);
    await shot(tester, 'tl-pending');
    await unmount(tester);
  });
}
