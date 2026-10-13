import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/providers.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/baby_repository.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/data/repositories/cry_event_repository.dart';
import 'package:honghong/data/repositories/feedback_repository.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/domain/models/cry_cause.dart';
import 'package:honghong/domain/models/cry_context.dart';
import 'package:honghong/domain/predictor/cry_predictor.dart';
import 'package:honghong/domain/predictor/rule_based_predictor.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('默认宝宝只创建一次', () async {
    final repo = BabyRepository(db);
    final a = await repo.ensureDefault();
    final b = await repo.ensureDefault();
    expect(a.id, b.id);
  });

  test('记录、睡眠结束和每类最新记录', () async {
    final baby = await BabyRepository(db).ensureDefault();
    final logs = CareLogRepository(db);
    final t0 = DateTime(2026, 10, 13, 8);
    await logs.add(baby.id, CareLogType.feed, at: t0);
    await logs.add(baby.id, CareLogType.feed, at: t0.add(const Duration(hours: 3)));
    await logs.startSession(baby.id, CareLogType.sleep, at: t0.add(const Duration(hours: 1)));
    await logs.endSleep(baby.id, at: t0.add(const Duration(hours: 2)));

    final latest = await logs.latestByType(baby.id);
    expect(latest[CareLogType.feed]!.startedAt, t0.add(const Duration(hours: 3)));
    expect(latest[CareLogType.sleep]!.endedAt, t0.add(const Duration(hours: 2)));
    expect(latest.containsKey(CareLogType.diaper), isFalse);
  });

  test('哭声事件 + 反馈 → 猜中率和先验', () async {
    final baby = await BabyRepository(db).ensureDefault();
    final ctx = CryContext(
      at: DateTime(2026, 10, 13, 14),
      babyAgeMonths: 1,
      sinceLastFeed: const Duration(hours: 4),
    );
    final pred = await RuleBasedPredictor().predict(const AudioFeatures(), ctx);
    expect(pred.ranked.first.cause, CryCause.hungry);

    final events = CryEventRepository(db);
    final id = await events.save(
      babyId: baby.id,
      startedAt: ctx.at,
      durationMs: 8000,
      context: ctx,
      prediction: pred,
    );
    final saved = await events.byId(id);
    expect(Prediction.decode(saved!.predictionJson).ranked.first.cause,
        CryCause.hungry);

    final fb = FeedbackRepository(db);
    await fb.save(id, CryCause.hungry, minutesToSoothe: 5);
    final agree = await fb.top1Agreement(baby.id);
    expect(agree.total, 1);
    expect(agree.hits, 1);

    final priors = priorsFromCounts(await fb.causeCounts(baby.id));
    expect(priors[CryCause.hungry]! > priors[CryCause.gas]!, isTrue);
  });

  test('外键约束生效', () async {
    expect(
      () => FeedbackRepository(db).save('not-exist', CryCause.gas),
      throwsA(anything),
    );
  });
}
