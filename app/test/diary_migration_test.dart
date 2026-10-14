import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:sqlite3/sqlite3.dart';

/// v4 → v5（妈咪日记）：老数据不丢、新列默认值正确、新表可用。
/// fixtures/schema_v4.sql 是 v4 版本 AppDatabase.createAll() 导出的原始 DDL。
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('hh_mig');
    file = File('${dir.path}/v4.sqlite');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  int sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  void seedV4() {
    final raw = sqlite3.open(file.path);
    raw.execute(File('test/fixtures/schema_v4.sql').readAsStringSync());
    raw.execute('PRAGMA user_version = 4');
    final t = DateTime(2026, 10, 13, 8);
    raw.execute("INSERT INTO babies (id, nickname, birth_date, updated_at, dirty) VALUES ('b1', '小糖', ?, ?, 1)",
        [sec(DateTime(2026, 7, 1)), sec(t)]);
    raw.execute(
        "INSERT INTO care_logs (id, baby_id, type, started_at, ended_at, detail, updated_by, updated_at, deleted, dirty) "
        "VALUES ('l1', 'b1', 'feed', ?, ?, '{\"ml\":120}', 'dad', ?, 0, 0)",
        [sec(t), sec(t.add(const Duration(minutes: 15))), sec(t)]);
    raw.execute("INSERT INTO care_logs (id, baby_id, type, started_at, ended_at, deleted, dirty) VALUES ('l2', 'b1', 'diaper', ?, ?, 1, 1)",
        [sec(t), sec(t)]);
    raw.execute("INSERT INTO care_logs (id, baby_id, type, started_at, ended_at) VALUES ('l3', 'b1', 'sleep', ?, NULL)",
        [sec(t.add(const Duration(hours: 1)))]);
    raw.execute("INSERT INTO cry_events (id, baby_id, started_at, duration_ms, context_json, prediction_json, predictor_version) "
        "VALUES ('c1', 'b1', ?, 8000, '{}', '{}', 'rule-v1')", [sec(t)]);
    raw.close();
  }

  test('v4 → v5 老数据不丢，新列有默认值', () async {
    seedV4();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final babies = await db.select(db.babies).get();
    expect(babies.single.nickname, '小糖');
    expect(babies.single.birthDate, DateTime(2026, 7, 1));
    expect(babies.single.dirty, isTrue);
    expect(babies.single.gender, isNull, reason: '老数据不回填性别');

    final logs = {for (final l in await db.select(db.careLogs).get()) l.id: l};
    expect(logs.keys, unorderedEquals(['l1', 'l2', 'l3']));
    expect(logs['l1']!.detail, '{"ml":120}');
    expect(logs['l1']!.updatedBy, 'dad');
    expect(logs['l1']!.endedAt, DateTime(2026, 10, 13, 8, 15));
    expect(logs['l2']!.deleted, isTrue);
    expect(logs['l3']!.endedAt, isNull, reason: '进行中的睡眠保持进行中');
    for (final l in logs.values) {
      expect(l.source, 'quick');
      expect(l.diaryCardId, isNull);
    }
    expect((await db.select(db.cryEvents).get()).single.id, 'c1');

    // 新表存在且可写
    expect(await db.select(db.diaryInputs).get(), isEmpty);
    expect(await db.select(db.diaryCards).get(), isEmpty);
    expect(await db.select(db.dailySummaries).get(), isEmpty);
    final idx = await db.customSelect("SELECT name FROM sqlite_master WHERE type='index' AND name IN ('care_logs_one_active','diary_cards_baby_date')").get();
    expect(idx.map((r) => r.read<String>('name')), unorderedEquals(['care_logs_one_active', 'diary_cards_baby_date']));

    // 进行中会话唯一索引仍然有效
    final repo = CareLogRepository(db);
    final s = await repo.startSession('b1', CareLogType.sleep);
    expect(s.id, 'l3');
    expect(await db.customSelect('PRAGMA user_version').map((r) => r.read<int>('user_version')).getSingle(), 5);
  });

  test('迁移后的结构与全新安装一致', () async {
    seedV4();
    final migrated = AppDatabase(NativeDatabase(file));
    final fresh = AppDatabase.memory();
    addTearDown(() async {
      await migrated.close();
      await fresh.close();
    });
    Future<Map<String, Set<String>>> cols(AppDatabase db) async {
      final m = <String, Set<String>>{};
      for (final t in db.allTables) {
        final rows = await db.customSelect('PRAGMA table_info(${t.actualTableName})').get();
        m[t.actualTableName] = rows.map((r) => '${r.read<String>('name')}:${r.read<String>('type')}:${r.read<int>('notnull')}').toSet();
      }
      return m;
    }

    expect(await cols(migrated), await cols(fresh));
    // 外键约束对新表生效
    await expectLater(
        migrated.into(migrated.diaryCards).insert(DiaryCardsCompanion.insert(
            id: 'x', babyId: 'nope', category: 'mood', kind: 'event', sortTime: DateTime(2026), diaryDate: DateTime(2026), attributes: '{}')),
        throwsA(anything));
  });
}
