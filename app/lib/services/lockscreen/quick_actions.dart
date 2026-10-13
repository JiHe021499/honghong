import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/baby_repository.dart';
import '../../data/repositories/care_log_repository.dart';
import '../../domain/models/care_detail.dart';
import '../../domain/models/care_log_type.dart';

/// 锁屏快捷记录的纯逻辑（不依赖通知插件，方便测试）。设计见 docs/design/lockscreen.html。
///
/// 按钮 id：`start:feed` / `start:sleep` / `start:burp` / `end:{type}` / `diaper`

class QuickButton {
  const QuickButton(this.id, this.label, {this.primary = true});
  final String id;
  final String label;
  final bool primary;
}

class QuickState {
  const QuickState({required this.title, required this.body, required this.buttons, this.chronoSince, required this.icon});
  final String title;
  final String body;
  final List<QuickButton> buttons; // 最多 3 个（Android 限制）
  /// 不为空时通知用系统计时器从这个时间开始走秒
  final DateTime? chronoSince;
  /// 大图标（res/drawable-nodpi/hh_{icon}.png，设计师手绘）
  final String icon;
}

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const _running = {CareLogType.feed: '喂奶中', CareLogType.sleep: '睡觉中', CareLogType.burp: '拍嗝中'};
const _icons = {CareLogType.feed: 'care_feed', CareLogType.sleep: 'care_sleep', CareLogType.burp: 'care_burp', CareLogType.diaper: 'care_diaper'};

/// 根据进行中的计时和每类最新记录，算出通知内容和按钮。
/// [done] 是刚刚在锁屏上完成的操作的确认文字（例如"已记下换尿布"）。
QuickState buildQuickState({
  required String babyName,
  required List<CareLog> active,
  required Map<CareLogType, CareLog> latest,
  required DateTime now,
  String? done,
}) {
  final act = [for (final l in active) CareLogType.values.byName(l.type)];
  final buttons = <QuickButton>[
    for (final t in act.take(2)) QuickButton('end:${t.name}', '结束${t.label}'),
  ];
  // 补开始按钮：喂奶中优先给"开始拍嗝"，其他情况先喂奶再睡觉
  final starts = act.contains(CareLogType.feed)
      ? [CareLogType.burp, CareLogType.sleep]
      : [CareLogType.feed, CareLogType.sleep, CareLogType.burp];
  for (final t in starts) {
    if (buttons.length >= 2) break;
    if (!act.contains(t)) buttons.add(QuickButton('start:${t.name}', '开始${t.label}', primary: act.isEmpty));
  }
  buttons.add(const QuickButton('diaper', '换尿布', primary: false));

  if (act.isNotEmpty) {
    final first = active.first;
    final t = act.first;
    final others = act.skip(1).map((x) => _running[x]).join('、');
    return QuickState(
      title: _running[t]!,
      body: '${_hm(first.startedAt)} 开始${others.isEmpty ? '' : ' · 同时$others'} · ${done ?? '结束后可在 App 里补细节'}',
      buttons: buttons,
      chronoSince: first.startedAt,
      icon: _icons[t]!,
    );
  }
  if (done != null) {
    return QuickState(title: done, body: '打开 App 可补细节', buttons: buttons, icon: 'check_done');
  }
  // 用绝对时间（通知不会每分钟刷新，"多久前"会过时）
  final feed = latest[CareLogType.feed];
  final sleep = latest[CareLogType.sleep];
  final parts = <String>[
    if (sleep?.endedAt != null) '${_hm(sleep!.endedAt!)} 醒',
    '点下面直接记',
  ];
  return QuickState(
    title: feed == null ? '$babyName · 还没有喂奶记录' : '$babyName · 上次喂奶 ${_hm(feed.startedAt)}',
    body: parts.join(' · '),
    buttons: buttons,
    icon: 'avatar_baby',
  );
}

/// 执行一个锁屏按钮，返回确认文字。数据写入方式和 App 里完全一致（会标记待同步给家人）。
Future<String?> runQuickAction(AppDatabase db, String id, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final baby = await BabyRepository(db).ensureDefault();
  final logs = CareLogRepository(db);
  if (id == 'diaper') {
    await logs.logDiaper(baby.id, at: at);
    return '已记下换尿布 · 未分类';
  }
  final parts = id.split(':');
  if (parts.length != 2) return null;
  final type = CareLogType.values.asNameMap()[parts[1]];
  if (type == null || !type.isTimed) return null;
  if (parts[0] == 'start') {
    await logs.startSession(baby.id, type, at: at);
    return null;
  }
  if (parts[0] == 'end') {
    final open = await logs.activeSession(baby.id, type);
    if (open == null) return null; // 已经在别处结束了
    await logs.stopSession(open.id, at: at);
    final m = at.difference(open.startedAt).inMinutes;
    return '已记下：${type.label} ${m < 1 ? '不到 1 分钟' : '$m 分钟'}';
  }
  return null;
}

/// 读出渲染通知需要的数据
Future<QuickState> loadQuickState(AppDatabase db, {String? done, DateTime? now}) async {
  final baby = await BabyRepository(db).ensureDefault();
  final logs = CareLogRepository(db);
  final active = await (db.select(db.careLogs)
        ..where((l) => l.babyId.equals(baby.id) & l.deleted.not() & l.endedAt.isNull())
        ..orderBy([(l) => OrderingTerm.asc(l.startedAt)]))
      .get();
  return buildQuickState(
    babyName: baby.nickname,
    active: active,
    latest: await logs.latestByType(baby.id),
    now: now ?? DateTime.now(),
    done: done,
  );
}
