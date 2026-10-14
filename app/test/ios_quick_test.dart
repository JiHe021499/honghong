import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/services/lockscreen/ios_quick.dart';

void main() {
  test('parse sorts by time and tolerates junk', () {
    expect(IosQuick.parse(null), isEmpty);
    expect(IosQuick.parse('not json'), isEmpty);
    final raw = jsonEncode([
      {'id': 'b', 'a': 'end:feed', 't': 2000},
      {'id': 'a', 'a': 'start:feed', 't': 1000},
    ]);
    expect(IosQuick.parse(raw).map((e) => e.id), ['a', 'b']);
  });

  test('remaining keeps actions appended during drain', () {
    final raw = jsonEncode([
      {'id': 'a', 'a': 'diaper', 't': 1},
      {'id': 'c', 'a': 'diaper', 't': 3},
    ]);
    expect(jsonDecode(IosQuick.remaining(raw, {'a'})), [
      {'id': 'c', 'a': 'diaper', 't': 3}
    ]);
    expect(IosQuick.remaining(raw, {'a', 'c'}), '');
  });

  test('apply runs queued actions with their own timestamps', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final t0 = DateTime(2026, 10, 14, 8, 0);
    final done = await IosQuick.apply(db, [
      PendingAction('1', 'start:feed', t0),
      PendingAction('2', 'end:feed', t0.add(const Duration(minutes: 20))),
      PendingAction('3', 'diaper', t0.add(const Duration(minutes: 25))),
    ]);
    expect(done, isNotNull);
    final logs = await db.select(db.careLogs).get();
    final feed = logs.firstWhere((l) => l.type == 'feed');
    expect(feed.startedAt, t0);
    expect(feed.endedAt, t0.add(const Duration(minutes: 20)));
    expect(feed.dirty, isTrue);
    expect(logs.where((l) => l.type == 'diaper'), hasLength(1));
  });
}
