import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/theme/app_theme.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/domain/models/care_detail.dart';
import 'package:honghong/features/care/care_log_row.dart';
import 'package:intl/date_symbol_data_local.dart';

/// 真机反馈用例：长备注、瓶喂带奶量、长觉、换尿布、进行中
List<CareLog> sampleLogs(DateTime day) {
  DateTime t(int h, int m) => DateTime(day.year, day.month, day.day, h, m);
  CareLog l(String id, String type, DateTime s, DateTime? e, CareDetail? d) => CareLog(
      id: id, babyId: 'b', type: type, startedAt: s, endedAt: e, detail: d?.encode(), deleted: false, dirty: false, createdAt: s);
  return [
    l('1', 'sleep', t(7, 27), null, null),
    l('2', 'feed', t(7, 6), t(7, 16), const CareDetail(method: FeedMethod.breast, side: FeedSide.left)),
    l('3', 'sleep', t(5, 53), t(7, 16), const CareDetail(note: '夜间长觉')),
    l('4', 'diaper', t(5, 47), t(5, 47), const CareDetail(diaper: DiaperKind.pee)),
    l('5', 'feed', t(1, 23), t(1, 41), const CareDetail(method: FeedMethod.bottleBreast, ml: 120)),
    l('6', 'sleep', t(0, 53), t(4, 58), const CareDetail(note: '抱着才肯睡，放下就醒，反复好几次')),
    l('7', 'burp', t(0, 44), t(0, 52), const CareDetail(note: '打出来了')),
  ];
}

Widget rowsApp(List<CareLog> logs, {double scale = 1, ThemeData? theme}) => ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AppTheme.day,
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Builder(builder: (ctx) => Container(
                decoration: BoxDecoration(color: ctx.hh.card, borderRadius: BorderRadius.circular(18)),
                child: Column(children: [
                  for (var i = 0; i < logs.length; i++) CareLogRow(log: logs[i], last: i == logs.length - 1, now: () => DateTime(2026, 10, 14, 9, 19, 52)),
                ]),
              )),
          ),
        ),
      ),
    );

Future<void> setPhone(WidgetTester tester, {double width = 360}) async {
  await initializeDateFormatting('zh_CN');
  tester.view.physicalSize = Size(width * 3, 1000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// 用真实中文字体排版（默认测试字体每个字都是方块，宽度不真实）。没有字体时返回 false。
Future<bool> loadCjkFont() async {
  const files = ['/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'];
  if (!files.every((f) => File(f).existsSync())) return false;
  final l = FontLoader('Roboto');
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
  return true;
}
