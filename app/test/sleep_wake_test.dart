import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/app_clock.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/baby_repository.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/domain/models/care_detail.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/features/care/sleep_wake_prompt.dart';
import 'package:honghong/features/home/home_page.dart';
import 'package:honghong/services/audio/sleep_wake_detector.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final t0 = DateTime(2026, 10, 15, 3, 0);
  const half = Duration(milliseconds: 500);

  /// 从 [start] 起每 0.5 秒送一帧，返回第一次触发的结果
  DateTime? feed(SleepWakeDetector d, DateTime start, List<bool> frames) {
    for (var i = 0; i < frames.length; i++) {
      final r = d.add(frames[i], start.add(half * i));
      if (r != null) return r;
    }
    return null;
  }

  group('SleepWakeDetector', () {
    test('连续哭 15 秒触发，返回哭声开始时间', () {
      final d = SleepWakeDetector();
      expect(feed(d, t0, List.filled(29, true)), isNull); // 14.5 秒
      expect(d.add(true, t0.add(half * 29)), t0); // 第 30 帧 = 15 秒
    });

    test('60 秒内累计 20 秒触发（断断续续，不连续）', () {
      final d = SleepWakeDetector();
      // 哭 10 秒（20 帧）停 3 秒（6 帧），重复；累计第 40 帧哭声时触发
      final pattern = [for (var k = 0; k < 4; k++) ...List.filled(20, true), ...List.filled(6, false)];
      final r = feed(d, t0, pattern);
      expect(r, t0);
    });

    test('只哭 14 秒不触发；安静超过 20 秒清零', () {
      final d = SleepWakeDetector();
      expect(feed(d, t0, [...List.filled(28, true), ...List.filled(44, false)]), isNull); // 14 秒哭 + 22 秒安静
      // 清零后再哭 7 秒：若没清零，累计 21 秒会触发
      final t1 = t0.add(half * 72);
      expect(feed(d, t1, List.filled(14, true)), isNull);
      expect(d.onset, t1);
    });

    test('安静不到 20 秒不清零：累计跨段触发', () {
      final d = SleepWakeDetector();
      final r = feed(d, t0, [...List.filled(24, true), ...List.filled(30, false), ...List.filled(20, true)]);
      expect(r, t0); // 12 + 8 = 20 秒，开始时间仍是第一段
    });

    test('同一段哭只触发一次，安静清零后可再触发', () {
      final d = SleepWakeDetector();
      expect(feed(d, t0, List.filled(30, true)), t0);
      expect(feed(d, t0.add(half * 30), List.filled(60, true)), isNull);
      final t2 = t0.add(half * 90 + const Duration(seconds: 25));
      expect(feed(d, t2, List.filled(30, true)), t2);
    });

    test('前置条件：睡满 10 分钟且没在喂奶', () {
      final now = t0;
      expect(SleepWakeDetector.eligible(sleepStartedAt: null, feeding: false, now: now), isFalse);
      expect(SleepWakeDetector.eligible(sleepStartedAt: now.subtract(const Duration(minutes: 9)), feeding: false, now: now), isFalse);
      expect(SleepWakeDetector.eligible(sleepStartedAt: now.subtract(const Duration(minutes: 10)), feeding: false, now: now), isTrue);
      expect(SleepWakeDetector.eligible(sleepStartedAt: now.subtract(const Duration(minutes: 30)), feeding: true, now: now), isFalse);
    });
  });

  group('SleepPromptPolicy', () {
    test('每次睡眠最多 3 次', () {
      final p = SleepPromptPolicy();
      for (var i = 0; i < 3; i++) {
        expect(p.canPrompt('s1', t0), isTrue);
        p.recordShown('s1');
      }
      expect(p.canPrompt('s1', t0), isFalse);
      expect(p.canPrompt('s2', t0), isTrue); // 新的一次睡眠重新计
    });

    test('还在睡：20 分钟冷却', () {
      final p = SleepPromptPolicy()..recordShown('s1');
      p.stillAsleep('s1', t0);
      expect(p.canPrompt('s1', t0.add(const Duration(minutes: 19))), isFalse);
      expect(p.canPrompt('s1', t0.add(const Duration(minutes: 20))), isTrue);
    });
  });

  test('CareDetail endedBy 编解码', () {
    final d = CareDetail.decode(const CareDetail(note: '小睡').copyWith(endedBy: 'cry').encode());
    expect(d.endedBy, 'cry');
    expect(d.note, '小睡');
  });

  // ── 组件测试 ──
  Future<(AppDatabase, String)> setup(WidgetTester tester, {bool still = false, Duration slept = const Duration(minutes: 30)}) async {
    tester.view.physicalSize = const Size(390, 1100) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    if (still) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    late String id;
    final db = await pumpApp(tester, seed: (db) async {
      final baby = await BabyRepository(db).ensureDefault();
      id = (await CareLogRepository(db).startSession(baby.id, CareLogType.sleep, at: AppClock.now().subtract(slept))).id;
    });
    await settle(tester);
    return (db, id);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(HomePage)));

  /// 模拟连续哭 15 秒，返回哭声开始时间
  DateTime cry(WidgetTester tester) {
    final ctl = container(tester).read(sleepWakeProvider.notifier);
    final start = AppClock.now();
    for (var i = 0; i < 30; i++) {
      ctl.onFrame(true, start.add(half * i));
    }
    return start;
  }

  testWidgets('睡觉中哭醒 → 底部卡片；结束睡眠写入醒于时间和 endedBy；8 秒提示可撤销', (tester) async {
    final (db, id) = await setup(tester);
    final onset = cry(tester);
    await settle(tester);
    expect(find.byKey(const Key('sleep-wake-card')), findsOneWidget);
    expect(find.text('结束睡眠 · 醒于 ${hm(onset)}'), findsOneWidget);
    // 卡片是 liveRegion
    expect(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true && w.properties.label == '宝宝好像哭醒了'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('sleep-wake-end')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    expect(find.byKey(const Key('sleep-wake-card')), findsNothing);
    expect(find.byKey(const Key('sleep-ended-toast')), findsOneWidget);
    var log = (await tester.runAsync<CareLog?>(() => CareLogRepository(db).byId(id)))!;
    expect(log.endedAt!.difference(onset).inSeconds.abs(), lessThanOrEqualTo(1)); // 数据库按秒存
    expect(CareDetail.decode(log.detail).endedBy, 'cry');

    await tester.tap(find.byKey(const Key('sleep-ended-undo')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    log = (await tester.runAsync<CareLog?>(() => CareLogRepository(db).byId(id)))!;
    expect(log.endedAt, isNull);
    expect(CareDetail.decode(log.detail).endedBy, isNull);
    expect(find.byKey(const Key('sleep-ended-toast')), findsNothing);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('10 分钟没操作收起成状态条，点开恢复；还在睡 → 冷却期不再提示', (tester) async {
    final (db, _) = await setup(tester);
    cry(tester);
    await settle(tester);
    await tester.pump(const Duration(minutes: 10));
    await settle(tester);
    expect(find.byKey(const Key('sleep-wake-card')), findsNothing);
    expect(find.byKey(const Key('sleep-wake-bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sleep-wake-bar')));
    await settle(tester);
    expect(find.byKey(const Key('sleep-wake-card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sleep-wake-still')));
    await settle(tester);
    expect(find.byKey(const Key('sleep-wake-card')), findsNothing);
    // 冷却中再哭不提示
    final ctl = container(tester).read(sleepWakeProvider.notifier);
    final t = AppClock.now().add(const Duration(minutes: 1));
    for (var i = 0; i < 30; i++) {
      ctl.onFrame(true, t.add(half * i));
    }
    await settle(tester);
    expect(find.byKey(const Key('sleep-wake-card')), findsNothing);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('睡不满 10 分钟不提示', (tester) async {
    final (db, _) = await setup(tester, slept: const Duration(minutes: 5));
    cry(tester);
    await settle(tester);
    expect(find.byKey(const Key('sleep-wake-card')), findsNothing);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('家人已结束这次睡眠（同步）→ 提示收起，不覆盖', (tester) async {
    final (db, id) = await setup(tester);
    cry(tester);
    await settle(tester);
    expect(find.byKey(const Key('sleep-wake-card')), findsOneWidget);
    final familyEnd = AppClock.now().subtract(const Duration(minutes: 2));
    await tester.runAsync(() => CareLogRepository(db).stopSession(id, at: familyEnd));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect(find.byKey(const Key('sleep-wake-card')), findsNothing);
    // 即便还有旧引用调用结束，也不覆盖家人的结束时间
    final ok = await tester.runAsync(() => container(tester).read(sleepWakeProvider.notifier).endSleep(sleepId: id, at: AppClock.now()));
    expect(ok, isFalse);
    expect((await tester.runAsync<CareLog?>(() => CareLogRepository(db).byId(id)))!.endedAt!.difference(familyEnd).inSeconds.abs(), lessThanOrEqualTo(1));
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('减少动态：卡片直接出现，无切换动画', (tester) async {
    final (db, _) = await setup(tester, still: true);
    cry(tester);
    await tester.pump();
    expect(find.byKey(const Key('sleep-wake-card')), findsOneWidget);
    expect(find.ancestor(of: find.byKey(const Key('sleep-wake-card')), matching: find.byType(FadeTransition)), findsNothing);
    await unmount(tester);
    await tester.runAsync(db.close);
  });
}
