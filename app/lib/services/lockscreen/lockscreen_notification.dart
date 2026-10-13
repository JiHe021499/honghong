import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/app_database.dart';
import 'quick_actions.dart';
import 'quick_surfaces.dart';

/// 锁屏快捷记录：一条常驻、锁屏可见的通知，按钮在后台 isolate 里直接写数据库，不需要解锁。
/// 不使用前台服务：计时由系统 chronometer 显示，App 不需要常驻。
class LockscreenNotification {
  static const prefKey = 'lockscreen_quick';
  static const portName = 'honghong_main_isolate';
  static const _id = 7001;
  static const _channel = AndroidNotificationChannel(
    'quick_log',
    '锁屏快捷记录',
    description: '在锁屏上开始/结束喂奶、睡觉、拍嗝，记换尿布',
    importance: Importance.low, // 不响铃不震动，只常驻
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );

  static final plugin = FlutterLocalNotificationsPlugin();
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void> init({void Function(NotificationResponse)? onForegroundAction}) async {
    if (!supported) return;
    await plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_hh')),
      onDidReceiveNotificationResponse: onForegroundAction,
      onDidReceiveBackgroundNotificationResponse: quickActionBackground,
    );
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// Android 13+ 申请通知权限；更早的系统直接返回 true
  static Future<bool> requestPermission() async {
    if (!supported) return false;
    final a = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await a?.requestNotificationsPermission() ?? true;
  }

  static Future<void> show(QuickState s) async {
    if (!supported) return;
    final details = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.low,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      silent: true,
      showWhen: s.chronoSince != null,
      when: s.chronoSince?.millisecondsSinceEpoch,
      usesChronometer: s.chronoSince != null,
      visibility: NotificationVisibility.public, // 锁屏显示完整内容
      category: AndroidNotificationCategory.status,
      icon: 'ic_stat_hh',
      largeIcon: DrawableResourceAndroidBitmap('hh_${s.icon}'),
      color: const Color(0xFFFF9874),
      actions: [
        for (final b in s.buttons)
          AndroidNotificationAction(b.id, b.label, showsUserInterface: false, cancelNotification: false),
      ],
    );
    await plugin.show(id: _id, title: s.title, body: s.body, notificationDetails: NotificationDetails(android: details));
  }

  static Future<void> cancel() async {
    if (!supported) return;
    await plugin.cancel(id: _id);
  }
}

/// 后台 isolate 入口：App 没开、锁屏状态下点通知按钮时执行
@pragma('vm:entry-point')
Future<void> quickActionBackground(NotificationResponse r) async {
  final id = r.actionId;
  if (id == null) return;
  await runQuickActionInBackground(id);
}

/// 桌面小部件和下拉快捷开关的入口（home_widget 后台回调，uri: honghong://quick?a=start:feed）
@pragma('vm:entry-point')
Future<void> quickWidgetBackground(Uri? uri) async {
  final id = uri?.queryParameters['a'];
  if (id == null) return;
  await runQuickActionInBackground(id);
}

/// 所有快捷入口共用：App 在运行时交给主 isolate（同一个数据库连接，界面立刻刷新）；
/// 否则自己开数据库写入，再刷新锁屏通知、小部件和快捷开关。
Future<void> runQuickActionInBackground(String id) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final main = IsolateNameServer.lookupPortByName(LockscreenNotification.portName);
  if (main != null) {
    main.send(id);
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase();
  try {
    final done = await runQuickAction(db, id);
    if (prefs.getBool(LockscreenNotification.prefKey) ?? false) await LockscreenNotification.init();
    await QuickSurfaces.publish(db, done: done, prefs: prefs);
  } finally {
    await db.close();
  }
}

/// 主 isolate 接收后台转来的按钮
ReceivePort registerMainPort(void Function(String actionId) onAction) {
  IsolateNameServer.removePortNameMapping(LockscreenNotification.portName);
  final port = ReceivePort();
  IsolateNameServer.registerPortWithName(port.sendPort, LockscreenNotification.portName);
  port.listen((m) {
    if (m is String) onAction(m);
  });
  return port;
}
