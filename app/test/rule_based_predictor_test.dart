import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/context_builder.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/domain/models/cry_cause.dart';
import 'package:honghong/domain/models/cry_context.dart';
import 'package:honghong/domain/predictor/cry_predictor.dart';
import 'package:honghong/domain/predictor/rule_based_predictor.dart';

void main() {
  final p = RuleBasedPredictor();
  const audio = AudioFeatures();
  final afternoon = DateTime(2026, 10, 13, 14);

  test('概率归一且降序', () async {
    final r = await p.predict(audio, CryContext(at: afternoon, babyAgeMonths: 1));
    final sum = r.ranked.fold<double>(0, (a, s) => a + s.probability);
    expect(sum, closeTo(1, 1e-9));
    expect(r.ranked.length, CryCause.values.length);
    for (var i = 1; i < r.ranked.length; i++) {
      expect(r.ranked[i - 1].probability >= r.ranked[i].probability, isTrue);
    }
    expect(r.predictorVersion, 'rule-1');
  });

  test('久未喂奶时"饿"排第一', () async {
    final r = await p.predict(
      audio,
      CryContext(
        at: afternoon,
        babyAgeMonths: 1,
        sinceLastFeed: const Duration(hours: 4),
        sinceLastSleepEnd: const Duration(minutes: 20),
        sinceLastDiaper: const Duration(minutes: 30),
      ),
    );
    expect(r.ranked.first.cause, CryCause.hungry);
  });

  test('刚喂完没拍嗝时"胀气"排第一', () async {
    final r = await p.predict(
      audio,
      CryContext(
        at: afternoon,
        babyAgeMonths: 1,
        sinceLastFeed: const Duration(minutes: 15),
        sinceLastSleepEnd: const Duration(minutes: 30),
        sinceLastDiaper: const Duration(minutes: 20),
      ),
    );
    expect(r.ranked.first.cause, CryCause.gas);
  });

  test('夜里醒了很久时"困"排第一', () async {
    final r = await p.predict(
      audio,
      CryContext(
        at: DateTime(2026, 10, 13, 22),
        babyAgeMonths: 2,
        sinceLastFeed: const Duration(minutes: 90),
        sinceLastBurp: const Duration(minutes: 70),
        sinceLastSleepEnd: const Duration(minutes: 150),
        sinceLastDiaper: const Duration(minutes: 40),
      ),
    );
    expect(r.ranked.first.cause, CryCause.sleepy);
  });

  test('个性化先验会改变排序', () async {
    final ctx = CryContext(at: afternoon, babyAgeMonths: 1);
    final base = await p.predict(audio, ctx);
    final personal = await RuleBasedPredictor(priors: {CryCause.holdMe: 3})
        .predict(audio, ctx);
    expect(personal.ranked.first.cause, CryCause.holdMe);
    expect(base.ranked.first.cause, isNot(CryCause.holdMe));
  });

  test('Prediction JSON 往返', () async {
    final r = await p.predict(audio, CryContext(at: afternoon, babyAgeMonths: 1));
    final back = Prediction.decode(jsonEncode(r.toJson()));
    expect(back.predictorVersion, r.predictorVersion);
    expect(back.ranked.map((s) => s.cause), r.ranked.map((s) => s.cause));
  });

  test('buildCryContext 计算间隔和睡眠状态', () {
    final now = DateTime(2026, 10, 13, 12);
    final ctx = buildCryContext(
      now: now,
      birthDate: DateTime(2026, 9, 13),
      latest: {
        CareLogType.feed: LastLog(now.subtract(const Duration(hours: 2))),
        CareLogType.sleep: LastLog(now.subtract(const Duration(hours: 1))),
      },
    );
    expect(ctx.sinceLastFeed, const Duration(hours: 2));
    expect(ctx.isSleeping, isTrue);
    expect(ctx.sinceLastDiaper, isNull);
    expect(ctx.babyAgeMonths, closeTo(1, 0.05));
  });
}
