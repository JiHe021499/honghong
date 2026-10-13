import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/cry_context.dart';
import '../../domain/predictor/cry_predictor.dart';
import '../db/app_database.dart';

class CryEventRepository {
  CryEventRepository(this._db);
  final AppDatabase _db;

  Future<String> save({
    required String babyId,
    required DateTime startedAt,
    required int durationMs,
    required CryContext context,
    required Prediction prediction,
    String? audioPath,
    double cryConfidence = 0,
    bool autoTriggered = false,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.cryEvents).insert(CryEventsCompanion.insert(
          id: id,
          babyId: babyId,
          startedAt: startedAt,
          durationMs: durationMs,
          audioPath: Value(audioPath),
          cryConfidence: Value(cryConfidence),
          contextJson: jsonEncode(context.toJson()),
          predictionJson: jsonEncode(prediction.toJson()),
          predictorVersion: prediction.predictorVersion,
          autoTriggered: Value(autoTriggered),
        ));
    return id;
  }

  Future<CryEvent?> byId(String id) =>
      (_db.select(_db.cryEvents)..where((e) => e.id.equals(id)))
          .getSingleOrNull();

  Stream<List<CryEvent>> watchRecent(String babyId, {int limit = 50}) =>
      (_db.select(_db.cryEvents)
            ..where((e) => e.babyId.equals(babyId))
            ..orderBy([(e) => OrderingTerm.desc(e.startedAt)])
            ..limit(limit))
          .watch();

  Future<List<CryEvent>> since(String babyId, DateTime from) =>
      (_db.select(_db.cryEvents)
            ..where((e) =>
                e.babyId.equals(babyId) & e.startedAt.isBiggerOrEqualValue(from)))
          .get();

  Future<List<CryEvent>> all() => _db.select(_db.cryEvents).get();
}
