import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/baby_repository.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/services/lockscreen/quick_actions.dart';
import 'package:honghong/services/lockscreen/quick_surfaces.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());
  final t0 = DateTime(2026, 10, 14, 3, 12);

  List<String> ids(QuickState s) => [for (final b in s.buttons) b.id];

  test('空闲：开始喂奶 / 开始睡觉 / 换尿布', () async {
    final s = await loadQuickState(db, now: t0);
    expect(ids(s), ['start:feed', 'start:sleep', 'diaper']);
    expect(s.chronoSince, isNull);
    expect(s.title, contains('还没有喂奶记录'));
  });

  test('喂奶：开始 → 计时中 → 结束（不是一下记完）', () async {
    expect(await runQuickAction(db, 'start:feed', now: t0), isNull);
    var s = await loadQuickState(db, now: t0);
    expect(s.title, '喂奶中');
    expect(s.chronoSince, t0);
    expect(ids(s), ['end:feed', 'start:burp', 'diaper']);
    final baby = await BabyRepository(db).ensureDefault();
    expect((await CareLogRepository(db).activeSession(baby.id, CareLogType.feed))!.endedAt, isNull);

    // 重复点开始不会开第二条
    await runQuickAction(db, 'start:feed', now: t0.add(const Duration(minutes: 1)));
    expect((await CareLogRepository(db).all()).length, 1);

    final done = await runQuickAction(db, 'end:feed', now: t0.add(const Duration(minutes: 18)));
    expect(done, '已记下：喂奶 18 分钟');
    final log = (await CareLogRepository(db).all()).single;
    expect(log.endedAt, t0.add(const Duration(minutes: 18)));
    expect(log.dirty, isTrue, reason: '会同步给家人');
    s = await loadQuickState(db, done: done, now: t0);
    expect(s.title, done);
    expect(ids(s), ['start:feed', 'start:sleep', 'diaper']);
    // 已经结束的再点结束：无事发生
    expect(await runQuickAction(db, 'end:feed'), isNull);
  });

  test('换尿布一点即记；两个计时同时进行显示两个结束', () async {
    expect(await runQuickAction(db, 'diaper', now: t0), contains('换尿布'));
    final d = (await CareLogRepository(db).all()).single;
    expect(d.type, 'diaper');
    expect(d.endedAt, d.startedAt);

    await runQuickAction(db, 'start:sleep', now: t0);
    await runQuickAction(db, 'start:burp', now: t0.add(const Duration(minutes: 1)));
    final s = await loadQuickState(db, now: t0);
    expect(ids(s), ['end:sleep', 'end:burp', 'diaper']);
    expect(s.body, contains('同时拍嗝中'));
  });

  test('未知按钮忽略', () async {
    expect(await runQuickAction(db, 'start:diaper'), isNull);
    expect(await runQuickAction(db, 'bogus'), isNull);
    expect(await CareLogRepository(db).all(), isEmpty);
  });

  test('小部件/快捷开关数据：空闲、计时中、结束后，与锁屏同一套动作', () async {
    var d = await loadWidgetData(db);
    expect(d['hh_run_type'], '');
    expect(d['hh_feed_start'], 0);
    expect(d['hh_sub'], '还没有喂奶记录');

    await runQuickAction(db, 'start:feed', now: t0);
    d = await loadWidgetData(db);
    expect(d['hh_run_type'], 'feed');
    expect(d['hh_run_label'], '喂奶中');
    expect(d['hh_feed_start'], t0.millisecondsSinceEpoch);
    expect(d['hh_run_start'], t0.millisecondsSinceEpoch);
    expect(d['hh_sleep_start'], 0);
    expect(d['hh_sub'], '03:12 开始');

    final done = await runQuickAction(db, 'end:feed', now: t0.add(const Duration(minutes: 10)));
    await runQuickAction(db, 'diaper', now: t0.add(const Duration(minutes: 11)));
    d = await loadWidgetData(db, done: done);
    expect(d['hh_run_type'], '');
    expect(d['hh_feed_last'], '03:12');
    expect(d['hh_diaper_last'], '03:23');
    expect(d['hh_done'], '已记下：喂奶 10 分钟');
    expect(d['hh_sub'], '上次喂奶 03:12');
  });
}
