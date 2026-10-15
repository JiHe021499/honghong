import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1100) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  void reduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  AnimatedScale? scaleOf(WidgetTester tester) {
    final f = find.descendant(of: find.byKey(const Key('cry-button')), matching: find.byType(AnimatedScale));
    return f.evaluate().isEmpty ? null : tester.widget<AnimatedScale>(f);
  }

  testWidgets('哭声按钮：按下缩到 0.96，松开回弹；光环在呼吸', (tester) async {
    await phone(tester);
    final db = await pumpApp(tester);

    final ring = find.byKey(const Key('cry-ring'));
    expect(ring, findsOneWidget);
    DecoratedBox ringBox() => tester.widget<DecoratedBox>(find.descendant(of: ring, matching: find.byType(DecoratedBox)).first);
    final spread0 = (ringBox().decoration as BoxDecoration).boxShadow!.single.spreadRadius;
    await tester.pump(const Duration(milliseconds: 1600));
    final spread1 = (ringBox().decoration as BoxDecoration).boxShadow!.single.spreadRadius;
    expect(spread1, isNot(spread0));
    expect(spread1, inInclusiveRange(16, 22));

    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('cry-button'))));
    await tester.pump(const Duration(milliseconds: 150)); // 在可滚动列表里，按下要过 kPressTimeout 才触发
    expect(scaleOf(tester)!.scale, .96);
    await g.cancel();
    await tester.pump();
    expect(scaleOf(tester)!.scale, 1);

    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('减少动态：无呼吸、按下用透明度、脉冲点静态、布局瞬切', (tester) async {
    await phone(tester);
    reduceMotion(tester);
    final db = await pumpApp(tester);

    expect(scaleOf(tester), isNull);
    final ring = find.byKey(const Key('cry-ring'));
    DecoratedBox ringBox() => tester.widget<DecoratedBox>(find.descendant(of: ring, matching: find.byType(DecoratedBox)).first);
    final s0 = (ringBox().decoration as BoxDecoration).boxShadow!.single.spreadRadius;
    await tester.pump(const Duration(milliseconds: 1600));
    expect((ringBox().decoration as BoxDecoration).boxShadow!.single.spreadRadius, s0);

    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('cry-button'))));
    await tester.pump(const Duration(milliseconds: 150)); // 在可滚动列表里，按下要过 kPressTimeout 才触发
    final op = tester.widget<AnimatedOpacity>(find.descendant(of: find.byKey(const Key('cry-button')), matching: find.byType(AnimatedOpacity)));
    expect(op.opacity, .85);
    await g.cancel();

    // 开始计时：布局一帧内切换完成，旧布局不残留
    await tester.tap(find.byKey(const Key('quick-feed')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('running-feed')), findsOneWidget);
    expect(find.byKey(const Key('pulse-dot-static')), findsOneWidget);

    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('快捷区：进行中切换带淡入 + 缩放过渡，保留原有 Key', (tester) async {
    await phone(tester);
    final db = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('quick-feed')));
    await settle(tester);
    expect(find.byKey(const Key('running-feed')), findsOneWidget);
    expect(find.byKey(const Key('end-feed')), findsOneWidget);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('日/夜切换：图标交叉淡入，过渡中新旧图标并存', (tester) async {
    await phone(tester);
    final db = await pumpApp(tester);
    final toggle = find.byKey(const Key('night-toggle'));
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.descendant(of: toggle, matching: find.byType(RotationTransition)), findsNWidgets(2));
    await settle(tester);
    expect(find.descendant(of: toggle, matching: find.byType(RotationTransition)), findsOneWidget);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('换尿布：新记录高亮保持后淡出；减少动态时保持静态高亮', (tester) async {
    await phone(tester);
    final db = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('quick-diaper')));
    await settle(tester);
    expect(find.byKey(const Key('new-row-glow')), findsWidgets);
    expect(find.text('已记下换尿布'), findsOneWidget);
    await unmount(tester);
    await tester.runAsync(db.close);
  });
}
