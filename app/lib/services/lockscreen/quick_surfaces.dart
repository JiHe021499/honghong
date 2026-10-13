import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/baby_repository.dart';
import '../../data/repositories/care_log_repository.dart';
import '../../domain/models/care_log_type.dart';
import 'lockscreen_notification.dart';
import 'quick_actions.dart';

/// 所有"快捷入口"（锁屏通知、桌面小部件、下拉快捷开关）共用的发布逻辑。
/// 小部件和快捷开关由原生代码（MainActivity 同包的 Kotlin）读 home_widget 的 SharedPreferences 绘制。
class QuickSurfaces {
  static bool get supported => !kIsWeb && Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST');

  static const widgetProviders = ['com.honghong.honghong.QuickWidgetProvider', 'com.honghong.honghong.QuickWidgetSmallProvider'];

  /// 读库后刷新全部入口。锁屏通知只在用户开了开关时显示。
  static Future<void> publish(AppDatabase db, {String? done, SharedPreferences? prefs}) async {
    if (!supported) return;
    final data = await loadWidgetData(db, done: done);
    for (final e in data.entries) {
      await HomeWidget.saveWidgetData(e.key, e.value);
    }
    for (final p in widgetProviders) {
      try {
        await HomeWidget.updateWidget(qualifiedAndroidName: p);
      } catch (_) {}
    }
    final sp = prefs ?? await SharedPreferences.getInstance();
    if (sp.getBool(LockscreenNotification.prefKey) ?? false) {
      await LockscreenNotification.show(await loadQuickState(db, done: done));
    }
  }
}

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 小部件/快捷开关的数据（纯函数，便于测试）。时间都是毫秒时间戳，0 表示没有进行中。
Map<String, Object> widgetData({
  required String babyName,
  required List<CareLog> active,
  required Map<CareLogType, CareLog> latest,
  String? done,
}) {
  int start(CareLogType t) => active.where((l) => l.type == t.name).firstOrNull?.startedAt.millisecondsSinceEpoch ?? 0;
  final first = active.firstOrNull;
  final feed = latest[CareLogType.feed];
  final sleep = latest[CareLogType.sleep];
  final diaper = latest[CareLogType.diaper];
  const running = {'feed': '喂奶中', 'sleep': '睡觉中', 'burp': '拍嗝中'};
  return {
    'hh_baby': babyName,
    'hh_feed_start': start(CareLogType.feed),
    'hh_sleep_start': start(CareLogType.sleep),
    'hh_burp_start': start(CareLogType.burp),
    'hh_run_type': first?.type ?? '',
    'hh_run_label': first == null ? '' : running[first.type]!,
    'hh_run_start': first?.startedAt.millisecondsSinceEpoch ?? 0,
    'hh_feed_last': feed == null ? '' : _hm(feed.startedAt),
    'hh_sleep_woke': sleep?.endedAt == null ? '' : _hm(sleep!.endedAt!),
    'hh_diaper_last': diaper == null ? '' : _hm(diaper.startedAt),
    'hh_done': done ?? '',
    'hh_sub': first != null
        ? '${_hm(first.startedAt)} 开始'
        : [
            feed == null ? '还没有喂奶记录' : '上次喂奶 ${_hm(feed.startedAt)}',
            if (sleep?.endedAt != null) '${_hm(sleep!.endedAt!)} 醒',
          ].join(' · '),
  };
}

Future<Map<String, Object>> loadWidgetData(AppDatabase db, {String? done}) async {
  final baby = await BabyRepository(db).ensureDefault();
  final active = await (db.select(db.careLogs)
        ..where((l) => l.babyId.equals(baby.id) & l.deleted.not() & l.endedAt.isNull())
        ..orderBy([(l) => OrderingTerm.asc(l.startedAt)]))
      .get();
  return widgetData(
    babyName: baby.nickname,
    active: active,
    latest: await CareLogRepository(db).latestByType(baby.id),
    done: done,
  );
}
