import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/prefs.dart';
import 'package:honghong/core/providers.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/baby_repository.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/domain/models/care_detail.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/features/care/care_log_row.dart';
import 'package:honghong/features/logs/log_detail_page.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('仓库：补记与修改', () {
    late AppDatabase db;
    late CareLogRepository logs;
    late String babyId;
    final n0 = DateTime.now();
    final now = DateTime(n0.year, n0.month, n0.day, n0.hour, n0.minute);
    final s = now.subtract(const Duration(hours: 3));

    setUp(() async {
      db = AppDatabase.memory();
      logs = CareLogRepository(db);
      babyId = (await BabyRepository(db).ensureDefault()).id;
    });
    tearDown(() => db.close());

    test('校验：结束必填、要晚于开始、不能在未来、不超过 24 小时', () {
      final v = CareLogRepository.validateTimes;
      expect(v(CareLogType.feed, s, null, now: now), '请选择结束时间');
      expect(v(CareLogType.feed, s, s, now: now), '结束时间要晚于开始时间');
      expect(v(CareLogType.feed, s, now.add(const Duration(hours: 1)), now: now), '结束时间不能晚于现在');
      expect(v(CareLogType.diaper, now.add(const Duration(hours: 1)), null, now: now), '开始时间不能晚于现在');
      expect(v(CareLogType.sleep, s.subtract(const Duration(hours: 30)), s, now: now), '一次不能超过 24 小时');
      expect(v(CareLogType.feed, s, s.add(const Duration(minutes: 20)), now: now), isNull);
      expect(v(CareLogType.diaper, s, null, now: now), isNull);
    });

    test('补记计时类：写入开始/结束和细节，标记待同步', () async {
      final id = await logs.backfill(babyId, CareLogType.feed,
          start: s, end: s.add(const Duration(minutes: 25)), detail: const CareDetail(method: FeedMethod.formula, ml: 120));
      final l = (await logs.byId(id))!;
      expect(l.startedAt, s);
      expect(l.endedAt, s.add(const Duration(minutes: 25)));
      expect(l.dirty, isTrue);
      expect(CareDetail.decode(l.detail).ml, 120);
      // 最近一次喂奶（小部件/锁屏用）随之更新
      expect((await logs.latestByType(babyId))[CareLogType.feed]!.id, id);
    });

    test('补记换尿布：开始=结束；非法时间抛错', () async {
      final id = await logs.backfill(babyId, CareLogType.diaper, start: s, detail: const CareDetail(diaper: DiaperKind.poo));
      final l = (await logs.byId(id))!;
      expect(l.endedAt, l.startedAt);
      expect(() => logs.backfill(babyId, CareLogType.sleep, start: s), throwsArgumentError);
    });

    test('重叠检测：同类重叠才算，排除自己，进行中的算到现在', () async {
      final a = await logs.backfill(babyId, CareLogType.sleep, start: s, end: s.add(const Duration(hours: 1)));
      await logs.backfill(babyId, CareLogType.feed, start: s, end: s.add(const Duration(minutes: 20)));
      final o = await logs.overlapping(babyId, CareLogType.sleep, s.add(const Duration(minutes: 30)), s.add(const Duration(hours: 2)));
      expect(o.map((x) => x.id), [a]);
      expect(await logs.overlapping(babyId, CareLogType.sleep, s, s.add(const Duration(hours: 1)), excludeId: a), isEmpty);
      expect(await logs.overlapping(babyId, CareLogType.sleep, s.add(const Duration(hours: 1)), s.add(const Duration(hours: 2))), isEmpty);
      final run = await logs.startSession(babyId, CareLogType.burp, at: now.subtract(const Duration(minutes: 10)));
      final o2 = await logs.overlapping(babyId, CareLogType.burp, now.subtract(const Duration(minutes: 5)), now.subtract(const Duration(minutes: 1)));
      expect(o2.single.id, run.id);
    });

    test('修改时间：开始/结束都可改，dirty 置位、updatedBy 清空', () async {
      final id = await logs.backfill(babyId, CareLogType.feed, start: s, end: s.add(const Duration(minutes: 10)));
      await (db.update(db.careLogs)..where((l) => l.id.equals(id))).write(const CareLogsCompanion(dirty: Value(false), updatedBy: Value('dad')));
      final ns = s.subtract(const Duration(minutes: 30));
      await logs.updateRecord(id, start: ns, end: ns.add(const Duration(minutes: 15)), detail: const CareDetail(method: FeedMethod.breast, side: FeedSide.right));
      final l = (await logs.byId(id))!;
      expect(l.startedAt, ns);
      expect(l.endedAt, ns.add(const Duration(minutes: 15)));
      expect(l.dirty, isTrue);
      expect(l.updatedBy, isNull);
      expect(() => logs.updateRecord(id, start: ns, end: ns), throwsArgumentError);
    });
  });

  group('界面：全部记录', () {
    Future<AppDatabase> pumpLogs(WidgetTester tester, {Future<void> Function(AppDatabase)? seed}) async {
      SharedPreferences.setMockInitialValues({});
      await initializeDateFormatting('zh_CN');
      final sp = await SharedPreferences.getInstance();
      final db = AppDatabase.memory();
      if (seed != null) await tester.runAsync(() => seed(db));
      await tester.pumpWidget(ProviderScope(
        overrides: [prefsProvider.overrideWithValue(sp), databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: LogDetailPage()),
      ));
      await settle(tester);
      return db;
    }

    testWidgets('右上角补记：默认喂奶 20 分钟，保存后出现在列表并待同步', (tester) async {
      final db = await pumpLogs(tester);
      await tester.tap(find.byKey(const Key('backfill-add')));
      await settle(tester, 10);
      expect(find.text('补记一条'), findsOneWidget);
      expect(find.byKey(const Key('backfill-len')), findsOneWidget);
      await tester.tap(find.text('瓶喂母乳'));
      await settle(tester);
      await tester.ensureVisible(find.text('90ml'));
      await tester.tap(find.text('90ml'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('backfill-save')));
      await tester.tap(find.byKey(const Key('backfill-save')));
      await settle(tester, 10);
      final rows = await tester.runAsync(() => db.select(db.careLogs).get());
      expect(rows!.single.type, 'feed');
      expect(rows.single.dirty, isTrue);
      expect(rows.single.endedAt!.difference(rows.single.startedAt), const Duration(minutes: 20));
      expect(CareDetail.decode(rows.single.detail).ml, 90);
      await unmount(tester);
      await tester.runAsync(db.close);
    });

    testWidgets('与已有同类记录重叠时提示；点已有记录可删除', (tester) async {
      final now = DateTime.now();
      final db = await pumpLogs(tester, seed: (db) async {
        final b = (await BabyRepository(db).ensureDefault()).id;
        await CareLogRepository(db).backfill(b, CareLogType.feed,
            start: now.subtract(const Duration(minutes: 15)), end: now.subtract(const Duration(minutes: 5)));
      });
      await tester.tap(find.byKey(const Key('backfill-add')));
      await settle(tester, 10);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await settle(tester);
      expect(find.byKey(const Key('backfill-overlap')), findsOneWidget);
      await tester.ensureVisible(find.text('取消'));
      await tester.tap(find.text('取消'));
      await settle(tester, 10);

      await tester.tap(find.byType(CareLogRow).first);
      await settle(tester, 10);
      expect(find.text('修改喂奶记录'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('record-delete')));
      await tester.tap(find.byKey(const Key('record-delete')));
      await settle(tester, 6);
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await settle(tester, 10);
      final rows = await tester.runAsync(() => db.select(db.careLogs).get());
      expect(rows!.single.deleted, isTrue);
      expect(rows.single.dirty, isTrue);
      await unmount(tester);
      await tester.runAsync(db.close);
    });
  });
}
