import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Babies, CareLogs, CryEvents, Feedbacks, ModelVersions, DiaryInputs, DiaryCards, DailySummaries])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// 测试用内存数据库
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(activeSessionIndexSql);
          await customStatement(diaryIndexesSql);
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) await migrateV1ToV2(this);
          if (from < 3) {
            await m.addColumn(babies, babies.updatedAt);
            await m.addColumn(babies, babies.dirty);
            for (final c in [careLogs.updatedAt, careLogs.deleted, careLogs.dirty]) {
              await m.addColumn(careLogs, c);
            }
            for (final c in [cryEvents.updatedAt, cryEvents.deleted, cryEvents.dirty]) {
              await m.addColumn(cryEvents, c);
            }
            await customStatement('DROP INDEX IF EXISTS care_logs_one_active');
            await customStatement(activeSessionIndexSql);
          }
          if (from < 4) await m.addColumn(careLogs, careLogs.updatedBy);
          if (from < 5) {
            // 妈咪日记：老数据 gender 为 null 不回填；历史 care_logs 默认 source=quick
            await m.addColumn(babies, babies.gender);
            await m.addColumn(careLogs, careLogs.source);
            await m.addColumn(careLogs, careLogs.diaryCardId);
            await m.createTable(diaryInputs);
            await m.createTable(diaryCards);
            await m.createTable(dailySummaries);
            await customStatement(diaryIndexesSql);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // 锁屏按钮可能在另一个 isolate 里同时写库
          await customStatement('PRAGMA busy_timeout = 5000');
        },
      );
}

/// 每个宝宝每种类型最多一条进行中的记录（ended_at 为空）。
const activeSessionIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS care_logs_one_active '
    'ON care_logs (baby_id, type) WHERE ended_at IS NULL AND deleted = 0';

/// 时间线按宝宝+归属日期查日记卡（schema v5）
const diaryIndexesSql =
    'CREATE INDEX IF NOT EXISTS diary_cards_baby_date ON diary_cards (baby_id, diary_date)';

/// v1 → v2：v1 的喂奶/拍嗝/换尿布是"点一下记一个时间点"（ended_at 为空），
/// v2 起 ended_at 为空表示"进行中"。先把旧的时间点记录补成已结束，
/// 再把多余的未结束睡眠收尾（只留最新一条），最后建唯一索引。
Future<void> migrateV1ToV2(GeneratedDatabase db) async {
  await db.customStatement("UPDATE care_logs SET ended_at = started_at "
      "WHERE ended_at IS NULL AND type IN ('feed', 'burp', 'diaper')");
  await db.customStatement('UPDATE care_logs SET ended_at = started_at '
      "WHERE ended_at IS NULL AND type = 'sleep' AND EXISTS ("
      'SELECT 1 FROM care_logs o WHERE o.baby_id = care_logs.baby_id '
      "AND o.type = 'sleep' AND o.ended_at IS NULL "
      'AND o.started_at > care_logs.started_at)');
  await db.customStatement('CREATE UNIQUE INDEX IF NOT EXISTS care_logs_one_active '
      'ON care_logs (baby_id, type) WHERE ended_at IS NULL');
}

LazyDatabase _open() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
          File(p.join(dir.path, 'honghong.sqlite')));
    });
