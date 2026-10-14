@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/widgets/app_icon.dart';

import '../log_row_layout.dart';

/// 记录行：360dp 宽，长文本，正常 / 1.3 / 1.6 倍字号
void main() {
  setUpAll(loadCjkFont);
  for (final scale in [1.0, 1.3, 1.6]) {
    testWidgets('记录行 360dp ×$scale', (tester) async {
      await setPhone(tester, width: 360);
      await tester.pumpWidget(rowsApp(sampleLogs(DateTime(2026, 10, 14)), scale: scale));
      await tester.runAsync(() async {
        final ctx = tester.element(find.byType(Scaffold));
        for (final i in AppIcon.values) {
          await precacheImage(AssetImage(i.asset), ctx);
        }
      });
      await tester.pump();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('log-rows-360-x$scale.png'));
    });
  }
}
