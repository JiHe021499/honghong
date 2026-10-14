import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:honghong/core/app_clock.dart';
import 'package:honghong/core/router/app_router.dart';
import 'package:honghong/features/diary/diary_providers.dart';
import 'package:honghong/services/diary/diary_metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  late DateTime t;
  setUp(() {
    t = DateTime(2026, 10, 14, 10);
    AppClock.source = () => t;
  });
  tearDown(() => AppClock.source = DateTime.now);

  Future<DiaryMetrics> fresh([Map<String, Object> v = const {}]) async {
    SharedPreferences.setMockInitialValues(v);
    return DiaryMetrics(await SharedPreferences.getInstance());
  }

  test('三个比率与 7 天窗口', () async {
    final m = await fresh();
    await m.add(DiaryMetric.save);
    await m.add(DiaryMetric.saveOneTap);
    await m.add(DiaryMetric.cards, 3);
    await m.add(DiaryMetric.voice, 4);
    await m.add(DiaryMetric.voiceFail);
    t = DateTime(2026, 10, 2); // 12 天前：不在近 7 天
    await m.add(DiaryMetric.save, 5);
    t = DateTime(2026, 10, 14, 11);
    await m.add(DiaryMetric.save);
    await m.add(DiaryMetric.cards, 2);
    await m.add(DiaryMetric.cardsChanged);
    final tot = m.totals();
    expect(tot[DiaryMetric.save], 2);
    final r = DiaryMetrics.rates(tot);
    expect(r.oneTap, .5);
    expect(r.cardChange, .2);
    expect(r.voiceFail, .25);
    expect(m.totals(days: 30)[DiaryMetric.save], 7);
    expect(m.report(), contains('一键保存率 50%（1/2）'));
    expect(m.report(), contains('卡片修改率 20%（1/5）'));
    expect(m.report(), contains('识别失败率 25%（1/4）'));
  });

  test('分母为 0 显示 —；查看小结每天只计 1 次；超过 30 天的自动清掉', () async {
    final m = await fresh();
    expect(m.report(), contains('一键保存率 —'));
    await m.add(DiaryMetric.summaryView);
    await m.add(DiaryMetric.summaryView);
    expect(m.totals()[DiaryMetric.summaryView], 1);
    t = DateTime(2026, 12, 1);
    await m.add(DiaryMetric.save);
    expect(m.totals(days: 400)[DiaryMetric.summaryView], 0);
  });

  test('坏数据不崩溃', () async {
    final m = await fresh({DiaryMetrics.key: 'not json'});
    expect(m.totals()[DiaryMetric.save], 0);
    await m.add(DiaryMetric.save);
    expect(m.totals()[DiaryMetric.save], 1);
  });

  testWidgets('设置：妈咪日记与隐私、内测数据可复制', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await pumpApp(tester, prefs: {
      kDiaryGenderPrompted: true,
      DiaryMetrics.key: '{"2026-10-14":{"save":4,"save_1tap":3,"cards":10,"cards_changed":1,"voice":5,"voice_fail":1}}',
    });
    GoRouter.of(tester.element(find.byType(Scaffold).last)).go(Routes.settings);
    await settle(tester, 10);
    await tester.scrollUntilVisible(find.byKey(const Key('diary-privacy')), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const Key('diary-privacy')));
    await settle(tester);
    expect(find.textContaining('科大讯飞股份有限公司'), findsOneWidget);
    expect(find.textContaining('DeepSeek'), findsOneWidget);
    expect(find.textContaining('不提供医疗诊断'), findsWidgets);
    await tester.tap(find.text('知道了'));
    await settle(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('diary-metrics')), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byKey(const Key('diary-metrics')));
    await settle(tester);
    expect(find.textContaining('一键保存率 75%（3/4）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('metrics-copy')));
    await settle(tester);
    expect(copied, contains('识别失败率 20%（1/5）'));
    expect(copied, isNot(contains('喂')));
    await unmount(tester);
  });
}
