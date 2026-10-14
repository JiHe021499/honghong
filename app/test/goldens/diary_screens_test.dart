@Tags(['golden'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/widgets/app_icon.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/features/diary/diary_flow.dart';
import 'package:honghong/features/diary/diary_providers.dart';

import '../diary_flow_test.dart' show FakeApi, FakeVoice, Clock;
import '../helpers.dart';

/// 妈咪日记 P3 关键屏幕（390×844 @3x），输出 test/goldens/diary-*.png
const _cjk = ['/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'];

Future<void> _loadFonts() async {
  final cjk = FontLoader('Roboto');
  for (final f in _cjk) {
    cjk.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await cjk.load();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(_loadFonts);

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 8);
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pump();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('diary-$name.png'));
  }

  testWidgets('妈咪日记主流程截图', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final h = now.subtract(const Duration(minutes: 20));
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final api = FakeApi(json: {
      'status': 'ok',
      'prompt_version': 'parse-v2',
      'cards': [
        {'category': 'feeding', 'kind': 'aggregate', 'attributes': {'count': 6}, 'confidence': 0.9},
        {'category': 'mood', 'kind': 'event', 'time_period': 'afternoon', 'intensity': '哭得厉害', 'confidence': 0.9},
        {'category': 'diaper', 'kind': 'event', 'event_time': hm(h), 'attributes': {'type': 'poo'}, 'confidence': 0.9},
        {'category': 'sleep', 'kind': 'event', 'attributes': {'duration_min': 40}, 'confidence': 0.5},
      ],
      'risk': {'hit': false},
    });
    final voice = FakeVoice(text: '今天吃奶6次，下午哭得厉害，刚才拉了一次，睡了大概40分钟');
    final clock = Clock();
    final db = await pumpApp(tester, overrides: [
      diaryApiProvider.overrideWithValue(api),
      voiceCaptureProvider.overrideWithValue(voice),
      diaryClockProvider.overrideWithValue(clock.call),
    ], seed: (db) async {
      await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b', nickname: '小米粒', birthDate: now.subtract(const Duration(days: 102))));
      // 首页已记过同一次尿布 → 确认页出现“首页已记过一次”
      await CareLogRepository(db).add('b', CareLogType.diaper, at: h.subtract(const Duration(minutes: 3)));
    });
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(Scaffold).first);
      await precacheImage(const AssetImage('assets/brand/mark-1024.png'), ctx);
      for (final i in AppIcon.values) {
        await precacheImage(AssetImage(i.asset), ctx);
      }
    });
    await tester.ensureVisible(find.byKey(const Key('diary-entry')));
    await shot(tester, '01-entry');

    await tester.tap(find.byKey(const Key('diary-entry')));
    await shot(tester, '03-gender');
    await tester.tap(find.byKey(const Key('gender-skip')));
    await shot(tester, '04-idle');

    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
    clock.t = clock.t.add(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, '06-recording');
    await g.moveBy(const Offset(0, -120));
    await shot(tester, '07-cancel');
    await g.moveBy(const Offset(0, 120));
    await tester.pump();
    await g.up();
    await shot(tester, '11-confirm');

    await tester.tap(find.byKey(const Key('card-3')));
    await shot(tester, '12-edit');
    await tester.ensureVisible(find.byKey(const Key('fold')));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await settle(tester);
    await tester.tap(find.byKey(const Key('fold')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('save')));
    await shot(tester, '08-saved');
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.byKey(const Key('diary-back')));
    await settle(tester, 8);

    voice.ok = false;
    final g2 = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
    await settle(tester, 4);
    await g2.up();
    await shot(tester, '09-voice-error');
    await tester.tap(find.byKey(const Key('voice-err-text')));
    await settle(tester, 8);
    await tester.enterText(find.byKey(const Key('diary-text')), '宝宝发高烧了，一直哭');
    await shot(tester, '10-text');

    api.json = {'status': 'failed', 'cards': []};
    await tester.tap(find.byKey(const Key('diary-text-submit')));
    await shot(tester, '14-failed-risk');

    await tester.pump(const Duration(seconds: 5));
    await unmount(tester);
    await tester.runAsync(db.close);
  }, skip: !File(_cjk.first).existsSync());
}
