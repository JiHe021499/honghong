@Tags(['golden'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/data/repositories/cry_event_repository.dart';
import 'package:honghong/data/repositories/feedback_repository.dart';
import 'package:honghong/domain/context_builder.dart';
import 'package:honghong/domain/models/care_detail.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/domain/models/cry_cause.dart';
import 'package:honghong/domain/predictor/cry_predictor.dart';
import 'package:honghong/domain/predictor/rule_based_predictor.dart';

import '../helpers.dart';

/// 和设计稿对照用的整页截图（390×844 @3x），输出到 test/goldens/*.png
const _cjk = ['/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'];
const _emoji = '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf';

Future<void> _loadFonts() async {
  final cjk = FontLoader('Roboto');
  for (final f in _cjk) {
    cjk.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await cjk.load();
  final emoji = FontLoader('Noto Color Emoji')..addFont(Future.value(ByteData.sublistView(File(_emoji).readAsBytesSync())));
  await emoji.load();
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
}

Future<void> _seed(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b', nickname: '小米粒', birthDate: now.subtract(const Duration(days: 23))));
  final logs = CareLogRepository(db);
  final d = DateTime(now.year, now.month, now.day);
  // 今天：14:45 换尿布、15:00 母乳左侧 15 分钟、16:20 午睡 42 分钟（截图时间早于这些时就挪到"现在之前"）
  DateTime at(int h, int m) {
    final t = d.add(Duration(hours: h, minutes: m));
    return t.isAfter(now) ? now.subtract(Duration(hours: 18 - h, minutes: 60 - m)) : t;
  }

  await logs.add('b', CareLogType.diaper, at: at(14, 45), detail: const CareDetail(diaper: DiaperKind.pee).encode());
  await logs.add('b', CareLogType.feed,
      at: at(15, 0), endedAt: at(15, 15), detail: const CareDetail(method: FeedMethod.breast, side: FeedSide.left).encode());
  await logs.add('b', CareLogType.sleep, at: at(16, 20), endedAt: at(17, 2), detail: const CareDetail(note: '午睡').encode());
  // 近一周：喂奶间隔从 2.6 小时变成 3 小时；下午 4 点前后哭得多
  for (var day = 7; day >= 1; day--) {
    final base = d.subtract(Duration(days: day)).add(const Duration(hours: 6));
    final gap = day > 3 ? 156 : 180;
    for (var i = 0; i < 6; i++) {
      final s = base.add(Duration(minutes: gap * i));
      await logs.add('b', CareLogType.feed, at: s, endedAt: s.add(const Duration(minutes: 15)));
    }
    final sl = base.add(const Duration(hours: 7));
    await logs.add('b', CareLogType.sleep, at: sl, endedAt: sl.add(const Duration(hours: 2)));
  }
  final cries = CryEventRepository(db);
  final fb = FeedbackRepository(db);
  final hours = [16, 16, 16, 15, 17, 16, 11, 19, 13, 16, 20, 14, 10, 18, 21, 16];
  final causes = [CryCause.hungry, CryCause.hungry, CryCause.sleepy, CryCause.hungry, CryCause.gas, CryCause.sleepy, CryCause.hungry, CryCause.sleepy];
  for (var i = 0; i < hours.length; i++) {
    final t = d.subtract(Duration(days: 1 + i % 6)).add(Duration(hours: hours[i]));
    final ctx = buildCryContext(now: t, birthDate: now.subtract(const Duration(days: 23)), latest: const {});
    final p = await RuleBasedPredictor().predict(const AudioFeatures(), ctx);
    final id = await cries.save(babyId: 'b', startedAt: t, durationMs: 8000, context: ctx, prediction: p);
    if (i < causes.length) await fb.save(id, causes[i]);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(_loadFonts);

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 8);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
  }

  testWidgets('护理记录流程截图', (tester) async {
    await phone(tester);
    final db = await pumpApp(tester, seed: _seed, prefs: {'auto_listen': true});
    await tester.runAsync(() async => precacheImage(const AssetImage('assets/brand/mark-1024.png'), tester.element(find.byType(Scaffold).first)));
    await shot(tester, 'home-01-idle');

    await tester.tap(find.byKey(const Key('quick-feed')));
    await tester.pump(const Duration(seconds: 3));
    await shot(tester, 'home-02-feeding');

    await tester.tap(find.byKey(const Key('end-feed')));
    await settle(tester, 8);
    await tester.tap(find.text('瓶喂母乳'));
    await tester.pump();
    await tester.tap(find.text('90ml'));
    await shot(tester, 'home-03-feed-end');
    await tester.tap(find.text('保存记录'));
    await settle(tester, 8);
    await shot(tester, 'home-10-saved');

    await tester.tap(find.byKey(const Key('quick-sleep')));
    await tester.pump(const Duration(seconds: 2));
    await shot(tester, 'home-04-sleeping');
    await tester.tap(find.byKey(const Key('end-sleep')));
    await settle(tester, 8);
    await shot(tester, 'home-05-sleep-end');
    await tester.tap(find.text('保存记录'));
    await settle(tester, 8);

    await tester.tap(find.byKey(const Key('quick-diaper')));
    await shot(tester, 'home-06-diaper');
    await tester.tap(find.byKey(const Key('diaper-toast')));
    await shot(tester, 'home-07-diaper-edit');
    await tester.tap(find.text('保持原样'));
    await settle(tester, 8);
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.byKey(const Key('quick-burp')));
    await tester.pump(const Duration(seconds: 2));
    await shot(tester, 'home-08-burping');

    await tester.tap(find.byKey(const Key('night-toggle')));
    await shot(tester, 'night-14');
    await tester.tap(find.byKey(const Key('night-toggle')));
    await settle(tester);

    await tester.tap(find.byKey(const Key('cry-button')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 4));
    await shot(tester, 'cry-11-recording');
    await tester.tap(find.text('现在就分析'));
    await settle(tester, 10);
    await shot(tester, 'cry-12-result');
    await tester.tap(find.text('宝宝不哭了，告诉我结果'));
    await settle(tester, 10);
    await tester.tap(find.byKey(const Key('fb-0')));
    await shot(tester, 'cry-13-feedback');
    await tester.tap(find.text('完成'));
    await settle(tester, 10);

    await tester.tap(find.byKey(const Key('tab-1')));
    await settle(tester, 10);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await shot(tester, 'insights-15');
    await tester.tap(find.byKey(const Key('tab-3')));
    await shot(tester, 'settings');

    await tester.pump(const Duration(seconds: 5));
    await unmount(tester);
    await tester.runAsync(db.close);
  }, skip: !File(_emoji).existsSync());
}
