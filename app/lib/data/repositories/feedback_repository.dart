import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/cry_cause.dart';
import '../../domain/predictor/cry_predictor.dart';
import '../db/app_database.dart';

class FeedbackRepository {
  FeedbackRepository(this._db);
  final AppDatabase _db;

  /// cause 为 null 表示"不确定"。
  Future<String> save(String cryEventId, CryCause? cause,
      {int? minutesToSoothe, String? note}) async {
    final id = const Uuid().v4();
    await _db.into(_db.feedbacks).insert(FeedbacksCompanion.insert(
          id: id,
          cryEventId: cryEventId,
          resolvedCause: cause?.name ?? 'unknown',
          minutesToSoothe: Value(minutesToSoothe),
          note: Value(note),
        ));
    // 反馈也要同步给家人，并进入"参与改进"上传队列
    await (_db.update(_db.cryEvents)..where((e) => e.id.equals(cryEventId)))
        .write(CryEventsCompanion(updatedAt: Value(DateTime.now()), dirty: const Value(true)));
    return id;
  }

  /// 某宝宝各原因的反馈次数（用于个性化先验和猜中率）
  Future<Map<String, int>> causeCounts(String babyId) async {
    final q = _db.select(_db.feedbacks).join([
      innerJoin(_db.cryEvents,
          _db.cryEvents.id.equalsExp(_db.feedbacks.cryEventId)),
    ])
      ..where(_db.cryEvents.babyId.equals(babyId));
    final counts = <String, int>{};
    for (final row in await q.get()) {
      final c = row.readTable(_db.feedbacks).resolvedCause;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    return counts;
  }

  /// 第一名与反馈一致的比例（核心指标）
  Future<({int total, int hits})> top1Agreement(String babyId) async {
    final q = _db.select(_db.feedbacks).join([
      innerJoin(_db.cryEvents,
          _db.cryEvents.id.equalsExp(_db.feedbacks.cryEventId)),
    ])
      ..where(_db.cryEvents.babyId.equals(babyId) &
          _db.feedbacks.resolvedCause.isNotValue('unknown'));
    var total = 0, hits = 0;
    for (final row in await q.get()) {
      final f = row.readTable(_db.feedbacks);
      final e = row.readTable(_db.cryEvents);
      final top = Prediction.topCauseFromJson(e.predictionJson);
      total++;
      if (top == f.resolvedCause) hits++;
    }
    return (total: total, hits: hits);
  }

  Future<List<Feedback>> all() => _db.select(_db.feedbacks).get();

  /// 反馈总数（"已学习 N 次哭声"）
  Future<int> count() async => (await all()).length;
}
