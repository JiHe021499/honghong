import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:honghong/features/family/family_card.dart';

import 'helpers.dart';

void main() {
  testWidgets('未连接云端：家庭页和规律页都说明记录只在本机', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('tab-2')));
    await settle(tester);
    expect(find.textContaining('还没连上云端'), findsWidgets);
    expect(find.byKey(const Key('family-create')), findsNothing);
    await tester.tap(find.byKey(const Key('tab-1')));
    await settle(tester);
    expect(find.text('家庭共享'), findsOneWidget);
    expect(find.text('邀请家人 ＋'), findsNothing, reason: '未连接云端时不显示邀请入口');
    await unmount(tester);
  });

  test('多久前', () {
    final now = DateTime(2026, 10, 13, 12);
    expect(agoText(now, now), '刚刚');
    expect(agoText(now.subtract(const Duration(minutes: 15)), now), '15 分钟前');
    expect(agoText(now.subtract(const Duration(hours: 3)), now), '3 小时前');
  });
}
