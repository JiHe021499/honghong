import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/domain/models/care_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() {});

  testWidgets('喂奶：点一下开始计时 → 结束弹面板 → 继续 → 再结束保存', (tester) async {
    tester.view.physicalSize = const Size(390, 1100) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = await pumpApp(tester);

    expect(find.text('宝宝在哭'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-feed')));
    await settle(tester);
    expect(find.byKey(const Key('running-feed')), findsOneWidget);
    expect(find.textContaining('喂奶中', findRichText: true), findsWidgets);
    expect(find.text('结束'), findsOneWidget);
    expect(find.textContaining('点「结束」保存'), findsOneWidget);

    // 结束 → 面板
    await tester.tap(find.byKey(const Key('end-feed')));
    await settle(tester, 10);
    expect(find.text('喂奶结束'), findsOneWidget);
    expect(find.textContaining('已停止计时', findRichText: true), findsOneWidget);

    // 继续喂 → 回到进行中
    await tester.tap(find.text('继续喂'));
    await settle(tester, 10);
    expect(find.byKey(const Key('running-feed')), findsOneWidget);

    // 再结束，选右侧，+1 分钟，保存
    await tester.tap(find.byKey(const Key('end-feed')));
    await settle(tester, 10);
    await tester.tap(find.text('右侧'));
    await tester.tap(find.byKey(const Key('dur-plus')));
    await tester.pump();
    await tester.tap(find.text('保存记录'));
    await settle(tester, 10);
    expect(find.byKey(const Key('running-feed')), findsNothing);
    expect(find.text('喂奶 · 母乳'), findsOneWidget);
    expect(find.textContaining('右侧 · 1分钟'), findsOneWidget);
    expect(find.text('已写入 · 可点条目修改'), findsOneWidget);

    final logs = await tester.runAsync(() => CareLogRepository(db).all());
    expect(logs!.single.endedAt, isNotNull);
    expect(CareDetail.decode(logs.single.detail).side, FeedSide.right);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('换尿布：一点即记 + toast，点 toast 改成大便', (tester) async {
    tester.view.physicalSize = const Size(390, 1100) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = await pumpApp(tester);

    await tester.tap(find.byKey(const Key('quick-diaper')));
    await settle(tester);
    expect(find.text('已记下换尿布'), findsOneWidget);
    expect(find.text('已记'), findsOneWidget);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('刚刚'), findsOneWidget);

    await tester.tap(find.byKey(const Key('diaper-toast')));
    await settle(tester, 10);
    expect(find.textContaining('可改类型'), findsOneWidget);
    await tester.tap(find.text('大便'));
    await tester.tap(find.text('更新'));
    await settle(tester, 10);
    expect(find.text('大便'), findsWidgets);
    expect(find.text('未分类'), findsNothing);
    await tester.pump(const Duration(seconds: 5)); // toast 定时器走完
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('进行中的计时重启后恢复显示', (tester) async {
    final db = await pumpApp(tester, seed: (db) async {
      final repo = CareLogRepository(db);
      final baby = await db.select(db.babies).getSingleOrNull();
      final id = baby?.id ?? 'b1';
      if (baby == null) {
        await db.into(db.babies).insert(BabiesCompanionX.make(id));
      }
      await repo.startSession(id, CareLogTypeX.sleep, at: DateTime.now().subtract(const Duration(minutes: 20)));
    });
    expect(find.byKey(const Key('running-sleep')), findsOneWidget);
    expect(find.textContaining('睡觉中', findRichText: true), findsWidgets);
    expect(find.textContaining('20:0'), findsWidgets);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('夜间模式切换并记住', (tester) async {
    tester.view.physicalSize = const Size(390, 1100) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('night-toggle')));
    await settle(tester);
    expect(find.text('夜间模式 · 亮度已调低'), findsOneWidget);
    expect(find.textContaining('语音操作'), findsOneWidget);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getBool('night_mode'), isTrue);
    await unmount(tester);
    await tester.runAsync(db.close);
  });
}
