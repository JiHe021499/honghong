import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';

class BabyRepository {
  BabyRepository(this._db);
  final AppDatabase _db;

  /// v1 只支持一个宝宝：没有就创建一个默认的。
  Future<Baby> ensureDefault({DateTime? now}) async {
    final existing = await (_db.select(_db.babies)..limit(1)).getSingleOrNull();
    if (existing != null) return existing;
    final baby = BabiesCompanion.insert(
      id: const Uuid().v4(),
      nickname: '宝宝',
      birthDate: (now ?? DateTime.now()).subtract(const Duration(days: 30)),
    );
    await _db.into(_db.babies).insert(baby);
    return (_db.select(_db.babies)..limit(1)).getSingle();
  }

  Future<void> updateBirthDate(String id, DateTime birth) =>
      (_db.update(_db.babies)..where((b) => b.id.equals(id)))
          .write(BabiesCompanion(birthDate: Value(birth), updatedAt: Value(DateTime.now()), dirty: const Value(true)));

  Future<void> updateNickname(String id, String name) =>
      (_db.update(_db.babies)..where((b) => b.id.equals(id)))
          .write(BabiesCompanion(nickname: Value(name), updatedAt: Value(DateTime.now()), dirty: const Value(true)));

  /// 性别：'boy' | 'girl' | null（跳过/清除）。会随家庭同步推送（D5，不发给 AI）。
  Future<void> updateGender(String id, String? gender) {
    if (gender != null && gender != 'boy' && gender != 'girl') throw ArgumentError.value(gender, 'gender');
    return (_db.update(_db.babies)..where((b) => b.id.equals(id)))
        .write(BabiesCompanion(gender: Value(gender), updatedAt: Value(DateTime.now()), dirty: const Value(true)));
  }
}
