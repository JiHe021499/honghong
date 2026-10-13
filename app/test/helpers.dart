import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/prefs.dart';
import 'package:honghong/core/providers.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/main.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用内存数据库和假的 SharedPreferences 启动整个 App
Future<AppDatabase> pumpApp(WidgetTester tester,
    {AppDatabase? db, Map<String, Object> prefs = const {}, Future<void> Function(AppDatabase db)? seed}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await initializeDateFormatting('zh_CN');
  final sp = await SharedPreferences.getInstance();
  final database = db ?? AppDatabase.memory();
  if (seed != null) await tester.runAsync(() => seed(database));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(sp),
      databaseProvider.overrideWithValue(database),
    ],
    child: const HonghongApp(),
  ));
  await settle(tester);
  return database;
}

/// 有脉冲动画和每秒计时器，不能 pumpAndSettle，固定推进几帧
Future<void> settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

class BabiesCompanionX {
  static BabiesCompanion make(String id) =>
      BabiesCompanion.insert(id: id, nickname: '小米粒', birthDate: DateTime.now().subtract(const Duration(days: 23)));
}

typedef CareLogTypeX = CareLogType;
