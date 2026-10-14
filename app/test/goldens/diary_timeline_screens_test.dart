@Tags(['golden'])
library;

import 'package:honghong/core/app_clock.dart';

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions, Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/widgets/app_icon.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/data/repositories/diary_repository.dart';
import 'package:honghong/domain/models/care_detail.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/features/diary/diary_flow.dart';
import 'package:honghong/features/diary/diary_providers.dart';

import '../diary_flow_test.dart' show FakeApi, FakeVoice, Clock;
import '../helpers.dart';

/// 妈咪日记 P4 关键屏幕（390×844 @3x），输出 test/goldens/diary-tl-*.png
const _cjk = ['/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'];

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
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('diary-tl-$name.png'));
  }

  testWidgets('妈咪日记时间线截图', (tester) async {
    fixClock(tester, DateTime(2026, 10, 14, 18, 30));
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int h, int m) {
      final t = today.add(Duration(hours: h, minutes: m));
      return t.isAfter(now) ? now.subtract(Duration(minutes: (18 - h) * 10 + 1)) : t;
    }

    final voice = FakeVoice(text: '今天吃奶6次，下午哭得厉害');
    final api = FakeApi(json: {
      'status': 'ok',
      'prompt_version': 'parse-v2',
      'cards': [
        {'category': 'feeding', 'kind': 'aggregate', 'attributes': {'count': 6}, 'confidence': 0.9},
        {'category': 'mood', 'kind': 'event', 'time_period': 'afternoon', 'attributes': {'type': '哭闹'}, 'intensity': '厉害', 'note': '下午哭得厉害', 'confidence': 0.9},
      ],
    });
    final clock = Clock();
    final db = await pumpApp(tester, prefs: const {kDiaryGenderPrompted: true}, overrides: [
      diaryApiProvider.overrideWithValue(api),
      voiceCaptureProvider.overrideWithValue(voice),
      diaryClockProvider.overrideWithValue(clock.call),
    ], seed: (db) async {
      await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b', nickname: '小米粒', birthDate: now.subtract(const Duration(days: 102))));
      final logs = CareLogRepository(db);
      await logs.add('b', CareLogType.feed, at: at(15, 0), endedAt: at(15, 15), detail: const CareDetail(method: FeedMethod.breast, side: FeedSide.left).encode());
      await logs.add('b', CareLogType.sleep, at: at(13, 20), endedAt: at(14, 30), source: 'backfill');
      await logs.add('b', CareLogType.diaper, at: at(11, 5), detail: const CareDetail(diaper: DiaperKind.poo).encode(), source: 'backfill');
    });
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(Scaffold).first);
      for (final i in AppIcon.values) {
        await precacheImage(AssetImage(i.asset), ctx);
      }
    });
    await tester.ensureVisible(find.byKey(const Key('diary-entry')));
    await tester.tap(find.byKey(const Key('diary-entry')));
    await settle(tester, 10);

    // 屏 16：说一句 → 确认 → 保存后进入时间线
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
    clock.t = clock.t.add(const Duration(seconds: 3));
    await settle(tester, 3);
    await g.up();
    await settle(tester, 10);
    await tester.tap(find.byKey(const Key('save')));
    await settle(tester, 4);
    await shot(tester, '16-saved');

    // 屏 17：带今日小结
    await tester.runAsync(() => db.into(db.dailySummaries).insert(DailySummariesCompanion.insert(
        id: 's1', babyId: 'b', date: today, status: 'ready', sourceIds: '[]', statsJson: '{}', promptVersion: 'sum-v1',
        content: const Value('今天小米粒吃了 6 次奶，午睡一个多小时，下午有点闹，你辛苦啦。'), generatedAt: Value(today.add(const Duration(hours: 21))))));
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.byKey(const Key('day-1')));
    await settle(tester, 6);
    await tester.tap(find.byKey(const Key('day-0')));
    await shot(tester, '17-timeline');

    await tester.tap(find.textContaining('情绪').first);
    await shot(tester, '18-edit');
    await tester.tap(find.byKey(const Key('card-delete')));
    await shot(tester, '19-delete');
    await tester.tap(find.byKey(const Key('del-cancel')));
    await settle(tester, 8);

    await tester.tap(find.byKey(const Key('day-2')));
    await shot(tester, '20-empty');

    await tester.tap(find.byKey(const Key('diary-back')));
    await settle(tester, 8);
    await shot(tester, '05-diary-all');

    await tester.pump(const Duration(seconds: 5));
    await unmount(tester);
    await tester.runAsync(db.close);
    // 避免未使用告警
    expect(DiaryRepository, isNotNull);
  }, skip: !File(_cjk.first).existsSync());
}
