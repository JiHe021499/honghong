import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/theme/app_theme.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const d = Hh.day, n = Hh.nightP;

  group('Hh.lerp 逐字段插值', () {
    test('t=0 / t=1 返回端点', () {
      expect(identical(d.lerp(n, 0), d), isTrue);
      expect(identical(d.lerp(n, 1), n), isTrue);
      expect(identical(d.lerp(null, .5), d), isTrue);
    });

    test('t=.5 颜色取中间值', () {
      final m = d.lerp(n, .5);
      for (final (a, b, v) in [
        (d.bg, n.bg, m.bg),
        (d.card, n.card, m.card),
        (d.ink, n.ink, m.ink),
        (d.peach2, n.peach2, m.peach2),
        (d.statusBg, n.statusBg, m.statusBg),
        (d.cryFrom, n.cryFrom, m.cryFrom),
        (d.tabBg, n.tabBg, m.tabBg),
        (d.shadow, n.shadow, m.shadow),
        (d.ring, n.ring, m.ring),
      ]) {
        expect(v, Color.lerp(a, b, .5));
      }
    });

    test('nightness / 渐变 / 阴影插值，night 布尔过半跳变', () {
      final q = d.lerp(n, .25), m = d.lerp(n, .5);
      expect(q.nightness, .25);
      expect(m.nightness, .5);
      expect(q.night, isFalse);
      expect(m.night, isTrue);
      expect(m.statusGradient.colors.first, Color.lerp(d.statusGradient.colors.first, n.statusGradient.colors.first, .5));
      expect(m.runGradient.colors.last, Color.lerp(d.runGradient.colors.last, n.runGradient.colors.last, .5));
      // 夜间阴影为空：中间态是缩放后的日间阴影
      expect(m.cardShadows.single, d.cardShadows.single.scale(.5));
      expect(m.primaryShadows.single, d.primaryShadows.single.scale(.5));
    });

    test('dn / dnd / dnShadows / dnFill 辅助方法', () {
      final m = d.lerp(n, .5);
      expect(m.dn(Colors.white, Colors.black), Color.lerp(Colors.white, Colors.black, .5));
      expect(m.dnd(10, 20), 15);
      expect(d.dn(Colors.white, Colors.black), Colors.white);
      expect(n.dn(Colors.white, Colors.black), Colors.black);
      const s = [BoxShadow(color: Color(0x40000000), blurRadius: 8)];
      expect(d.dnShadows(s, null), s);
      expect(n.dnShadows(s, null), isNull);
      expect(m.dnShadows(s, null)!.single, s.single.scale(.5));
      const g = LinearGradient(colors: [Colors.white, Colors.white]);
      expect(d.dnFill(g, Colors.black), g);
      expect((n.dnFill(g, Colors.black) as LinearGradient).colors, [Colors.black, Colors.black]);
    });
  });

  Color scaffoldBg(WidgetTester tester) => Theme.of(tester.element(find.byType(Scaffold).first)).scaffoldBackgroundColor;

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1100) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('日夜切换：中途颜色是中间值，400ms 后到夜间', (tester) async {
    await phone(tester);
    final db = await pumpApp(tester);
    expect(scaffoldBg(tester), Hh.day.bg);
    await tester.tap(find.byKey(const Key('night-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final mid = scaffoldBg(tester);
    expect(mid, isNot(Hh.day.bg));
    expect(mid, isNot(Hh.nightP.bg));
    final hh = Theme.of(tester.element(find.byType(Scaffold).first)).extension<Hh>()!;
    expect(hh.nightness, inExclusiveRange(0, 1));
    await settle(tester);
    expect(scaffoldBg(tester), Hh.nightP.bg);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('减少动态：日夜瞬切', (tester) async {
    await phone(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final db = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('night-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(scaffoldBg(tester), Hh.nightP.bg);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).extension<Hh>()!.nightness, 1);
    await unmount(tester);
    await tester.runAsync(db.close);
  });
}
