import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/models/care_detail.dart';
import 'package:honghong/domain/models/care_log_type.dart';

import 'log_row_layout.dart';

void main() {
  var realFont = false;
  setUpAll(() async => realFont = await loadCjkFont());

  test('两行文案和紧凑时长', () {
    final s = DateTime(2026, 10, 14, 5, 53);
    expect(formatDurationCompact(const Duration(hours: 1, minutes: 20)), '1小时20分');
    expect(formatDurationCompact(const Duration(minutes: 25)), '25分钟');
    expect(formatDurationCompact(const Duration(hours: 2)), '2小时');
    expect(formatDurationCompact(const Duration(seconds: 45)), '45秒');
    final feed = logLines(CareLogType.feed, s, s.add(const Duration(minutes: 10)), const CareDetail(method: FeedMethod.breast, side: FeedSide.left).encode());
    expect((feed.title, feed.subtitle), ('喂奶 · 母乳', '左侧 · 10分钟'));
    final bottle = logLines(CareLogType.feed, s, s.add(const Duration(minutes: 12)), const CareDetail(method: FeedMethod.formula, ml: 90).encode());
    expect((bottle.title, bottle.subtitle), ('喂奶 · 配方奶', '12分钟 · 90ml'));
    final sleep = logLines(CareLogType.sleep, s, s.add(const Duration(hours: 1, minutes: 23)), const CareDetail(note: '夜间长觉').encode());
    expect((sleep.title, sleep.subtitle), ('睡觉 · 夜间长觉', '1小时23分'));
    final diaper = logLines(CareLogType.diaper, s, s, const CareDetail(diaper: DiaperKind.pee).encode());
    expect((diaper.title, diaper.subtitle), ('换尿布', '小便'));
    final burp = logLines(CareLogType.burp, s, s.add(const Duration(minutes: 8)), const CareDetail(note: '打出来了').encode());
    expect((burp.title, burp.subtitle), ('拍嗝', '8分钟 · 打出来了'));
  });

  for (final scale in [1.0, 1.3, 1.6]) {
    testWidgets('360dp 宽、字号 ×$scale：不溢出，时间列右对齐，起止时间完整显示', (tester) async {
      await setPhone(tester);
      await tester.pumpWidget(rowsApp(sampleLogs(DateTime(2026, 10, 14)), scale: scale));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final times = find.byKey(const Key('row-time'));
      expect(times, findsNWidgets(7));
      // CI 没有中文字体（测试默认字体每字一个方块，会触发窄屏换行布局），只在真实字体下检查对齐
      if (realFont && scale <= 1.3) {
        final rights = times.evaluate().map((e) => tester.getRect(find.byWidget(e.widget)).right).toSet();
        expect(rights.length, 1, reason: '所有时间右边缘对齐 $rights');
      }
      expect(find.text('05:53–07:16'), findsOneWidget);
      expect(find.text('05:47'), findsOneWidget);
      expect(find.textContaining('开始'), findsOneWidget);
      expect(find.text('1小时23分'), findsOneWidget);
      // 标题（类型 + 关键细节）在常用字号下不截断
      if (realFont && scale <= 1.3) {
        for (final e in find.byKey(const Key('row-title')).evaluate()) {
          final p = tester.renderObject<RenderParagraph>(find.descendant(of: find.byWidget(e.widget), matching: find.byType(RichText)).first);
          expect(p.didExceedMaxLines, isFalse, reason: (e.widget as Text).data);
        }
      }
    });
  }
}
