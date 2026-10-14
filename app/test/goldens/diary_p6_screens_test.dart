@Tags(['golden'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:honghong/core/router/app_router.dart';
import 'package:honghong/core/widgets/app_icon.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/data/repositories/diary_repository.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/features/diary/diary_flow.dart';
import 'package:honghong/features/diary/diary_providers.dart';
import 'package:honghong/services/diary/diary_metrics.dart';

import '../diary_flow_test.dart' show FakeApi, FakeVoice, Clock;
import '../helpers.dart';

/// 妈咪日记 P6（390×844 @3x），输出 test/goldens/diary-p6-*.png
const _cjk = ['/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'];
final _day = DateTime(2026, 10, 14);

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
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('diary-p6-$name.png'));
  }

  Future<void> boot(WidgetTester tester, {Map<String, Object> prefs = const {}, bool failed3 = false, bool systemOk = true}) async {
    fixClock(tester, DateTime(2026, 10, 14, 21, 30));
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = Clock();
    await pumpApp(tester, prefs: {kDiaryGenderPrompted: true, ...prefs}, overrides: [
      diaryApiProvider.overrideWithValue(FakeApi(json: const {})..summaryText = '今天小米粒吃了 2 次奶，午睡一个多小时。你辛苦啦，早点休息。'),
      voiceCaptureProvider.overrideWithValue(FakeVoice(ok: systemOk)),
      cloudVoiceCaptureProvider.overrideWithValue(FakeVoice()),
      diaryClockProvider.overrideWithValue(clock.call),
      summaryClockProvider.overrideWithValue(clock.call),
    ], seed: (db) async {
      await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b', nickname: '小米粒', birthDate: _day.subtract(const Duration(days: 102))));
      final logs = CareLogRepository(db);
      await logs.add('b', CareLogType.feed, at: _day.add(const Duration(hours: 9)), endedAt: _day.add(const Duration(hours: 9, minutes: 15)));
      await logs.add('b', CareLogType.sleep, at: _day.add(const Duration(hours: 13)), endedAt: _day.add(const Duration(hours: 14, minutes: 20)));
      if (failed3) {
        final r = await DiaryRepository(db).claimSummary('b', _day, promptVersion: 'sum-v1');
        await DiaryRepository(db).updateSummary(r.id, const DailySummariesCompanion(status: Value('failed'), attempts: Value(3)));
      }
    });
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(Scaffold).first);
      for (final i in AppIcon.values) {
        await precacheImage(AssetImage(i.asset), ctx);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester, 10);
  }

  void go(WidgetTester tester, String loc, {bool push = false}) {
    final r = GoRouter.of(tester.element(find.byType(Scaffold).last));
    push ? r.push(loc) : r.go(loc);
  }

  testWidgets('失败满 3 次：时间线重试卡、小结页重试', (tester) async {
    await boot(tester, failed3: true);
    await tester.ensureVisible(find.byKey(const Key('diary-entry')));
    await settle(tester);
    await shot(tester, 'home-entry-failed');
    go(tester, Routes.diaryDay, push: true);
    await settle(tester, 10);
    await shot(tester, 'tl-retry');
    go(tester, Routes.diarySummary, push: true);
    await settle(tester, 10);
    await shot(tester, 'summary-retry');
    await unmount(tester);
  });

  testWidgets('关掉联网识别：打字页提示 → 设置该项', (tester) async {
    await boot(tester, prefs: const {kDiaryCloudAsrConsent: false}, systemOk: false);
    go(tester, Routes.diary);
    await settle(tester, 10);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
    await settle(tester, 3);
    await g.up();
    await settle(tester, 10);
    await tester.tap(find.byKey(const Key('voice-err-text')));
    await settle(tester, 10);
    await shot(tester, 'text-hint');
    await tester.tap(find.byKey(const Key('cloud-asr-hint')));
    await settle(tester, 10);
    await shot(tester, 'settings-cloud-asr');
    await unmount(tester);
  });

  testWidgets('设置：隐私说明、内测数据', (tester) async {
    await boot(tester, prefs: {
      DiaryMetrics.key: '{"2026-10-14":{"save":12,"save_1tap":9,"cards":30,"cards_changed":5,"voice":14,"voice_fail":1,"summary_view":1}}',
    });
    go(tester, Routes.settings);
    await settle(tester, 10);
    await tester.scrollUntilVisible(find.byKey(const Key('diary-metrics')), 200, scrollable: find.byType(Scrollable).last);
    await settle(tester);
    await shot(tester, 'settings-diary');
    await tester.tap(find.byKey(const Key('diary-privacy')));
    await settle(tester);
    await shot(tester, 'privacy');
    await tester.tap(find.text('知道了'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('diary-metrics')));
    await settle(tester);
    await shot(tester, 'metrics');
    await unmount(tester);
  });
}
