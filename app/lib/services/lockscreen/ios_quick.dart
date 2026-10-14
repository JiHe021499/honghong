import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/baby_repository.dart';
import 'quick_actions.dart';

/// iOS 小组件 / 控制中心 / 实时活动的桥（设计见 docs/design/ios-widgets.md）。
/// 小组件扩展里不跑 Flutter：按钮把动作追加到 App Group 里的队列 hh_pending
/// （[{"id":..., "a":"start:feed", "t":毫秒}]），App 启动/回前台时按时间顺序执行，
/// 执行规则就是安卓共用的 runQuickAction（写库 + 标记待同步）。
class PendingAction {
  const PendingAction(this.id, this.action, this.at);
  final String id;
  final String action;
  final DateTime at;
}

class IosQuick {
  static const appGroup = 'group.com.honghong.honghong';
  static const pendingKey = 'hh_pending';
  static const widgetKinds = ['HonghongHome', 'HonghongLock'];
  static const _live = MethodChannel('honghong/live_activity');

  static List<PendingAction> parse(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return [
        for (final m in list)
          PendingAction(m['id'] as String, m['a'] as String, DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt())),
      ]..sort((a, b) => a.at.compareTo(b.at));
    } catch (_) {
      return const [];
    }
  }

  /// 按时间顺序执行；返回最后一个确认文字
  static Future<String?> apply(AppDatabase db, List<PendingAction> actions) async {
    String? done;
    for (final a in actions) {
      done = await runQuickAction(db, a.action, now: a.at) ?? done;
    }
    return done;
  }

  /// 只删掉已经执行过的条目（执行期间扩展可能又追加了新的）
  static String remaining(String? raw, Set<String> processed) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().where((m) => !processed.contains(m['id'])).toList();
      return list.isEmpty ? '' : jsonEncode(list);
    } catch (_) {
      return '';
    }
  }

  static bool _groupSet = false;
  static Future<void> ensureGroup() async {
    if (_groupSet) return;
    await HomeWidget.setAppGroupId(appGroup);
    _groupSet = true;
  }

  /// 执行队列，返回确认文字（没有动作时为 null）
  static Future<String?> drain(AppDatabase db) async {
    await ensureGroup();
    final actions = parse(await HomeWidget.getWidgetData<String>(pendingKey));
    if (actions.isEmpty) return null;
    final done = await apply(db, actions);
    final now = await HomeWidget.getWidgetData<String>(pendingKey);
    await HomeWidget.saveWidgetData<String>(pendingKey, remaining(now, {for (final a in actions) a.id}));
    return done;
  }

  /// 刷新小组件，并让实时活动和进行中的计时一致
  static Future<void> publish(AppDatabase db, Map<String, Object> data) async {
    await ensureGroup();
    for (final e in data.entries) {
      await HomeWidget.saveWidgetData(e.key, e.value);
    }
    for (final k in widgetKinds) {
      try {
        await HomeWidget.updateWidget(iOSName: k);
      } catch (_) {}
    }
    final baby = await BabyRepository(db).ensureDefault();
    final active = await (db.select(db.careLogs)
          ..where((l) => l.babyId.equals(baby.id) & l.deleted.not() & l.endedAt.isNull())
          ..orderBy([(l) => OrderingTerm.asc(l.startedAt)]))
        .get();
    try {
      await _live.invokeMethod('sync', {
        'baby': baby.nickname,
        'sessions': [for (final l in active) {'type': l.type, 'start': l.startedAt.millisecondsSinceEpoch}],
      });
    } catch (_) {}
  }
}
