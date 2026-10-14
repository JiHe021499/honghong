import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/repositories/baby_repository.dart';
import '../data/repositories/care_log_repository.dart';
import '../data/repositories/diary_repository.dart';
import '../data/repositories/cry_event_repository.dart';
import '../data/repositories/feedback_repository.dart';
import '../domain/context_builder.dart';
import '../domain/models/care_log_type.dart';
import '../domain/models/cry_cause.dart';
import '../domain/predictor/cry_predictor.dart';
import '../domain/predictor/model_predictor.dart';
import '../domain/predictor/personalization.dart';
import '../domain/predictor/rule_based_predictor.dart';
import '../services/model/model_providers.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final babyRepositoryProvider =
    Provider((ref) => BabyRepository(ref.watch(databaseProvider)));
final careLogRepositoryProvider =
    Provider((ref) => CareLogRepository(ref.watch(databaseProvider)));
final diaryRepositoryProvider =
    Provider((ref) => DiaryRepository(ref.watch(databaseProvider)));
final cryEventRepositoryProvider =
    Provider((ref) => CryEventRepository(ref.watch(databaseProvider)));
final feedbackRepositoryProvider =
    Provider((ref) => FeedbackRepository(ref.watch(databaseProvider)));

/// 当前宝宝（v1 单宝宝）
final currentBabyProvider = FutureProvider<Baby>(
    (ref) => ref.watch(babyRepositoryProvider).ensureDefault());

/// 每分钟刷新一次，用于"多久前"的显示
final clockProvider = StreamProvider<DateTime>((ref) => Stream.periodic(
    const Duration(minutes: 1), (_) => DateTime.now()));

final latestLogsProvider =
    StreamProvider<Map<CareLogType, CareLog>>((ref) async* {
  final baby = await ref.watch(currentBabyProvider.future);
  yield* ref.watch(careLogRepositoryProvider).watchLatestByType(baby.id);
});

/// 每秒刷新，用于进行中的计时显示
final secondTickerProvider = StreamProvider<DateTime>((ref) =>
    Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()));

/// 进行中的计时记录（喂奶/睡觉/拍嗝），重启 App 后从数据库恢复
final activeSessionsProvider = StreamProvider<List<CareLog>>((ref) async* {
  final baby = await ref.watch(currentBabyProvider.future);
  yield* ref.watch(careLogRepositoryProvider).watchActive(baby.id);
});

final recentLogsProvider = StreamProvider<List<CareLog>>((ref) async* {
  final baby = await ref.watch(currentBabyProvider.future);
  yield* ref.watch(careLogRepositoryProvider).watchRecent(baby.id);
});

/// 个性化先验：反馈次数做拉普拉斯平滑后归一到均值 1
Map<CryCause, double> priorsFromCounts(Map<String, int> counts) {
  final n = CryCause.values.length;
  final total = counts.entries
      .where((e) => e.key != 'unknown')
      .fold<int>(0, (a, e) => a + e.value);
  if (total == 0) return const {};
  return {
    for (final c in CryCause.values)
      c: ((counts[c.name] ?? 0) + 1) / (total + n) * n,
  };
}

/// 当前使用的猜原因实现：有可用分类模型时用 ModelPredictor（音频模型 + 上下文规则 + 个性化），
/// 否则用 RuleBasedPredictor。反馈后 invalidate 以更新先验和个性化。
final cryPredictorProvider = FutureProvider<CryPredictor>((ref) async {
  final baby = await ref.watch(currentBabyProvider.future);
  final fb = ref.watch(feedbackRepositoryProvider);
  final rule = RuleBasedPredictor(priors: priorsFromCounts(await fb.causeCounts(baby.id)));
  final model = await ref.watch(activeModelProvider.future);
  if (model == null) return rule;
  return ModelPredictor(
    rule: rule,
    head: model.head,
    meta: model.meta,
    personal: Personalization.fromFeedback(await fb.labelledPredictions(baby.id)),
    onFailure: (_) async {
      await ref.read(modelManagerProvider).reportFailure(model.meta.version);
      ref.invalidate(activeModelProvider);
    },
  );
});

/// 一次哭声流程：生成上下文 → 预测 → 存 CryEvent，返回事件 id
final cryFlowProvider = Provider((ref) => CryFlow(ref));

class CryFlow {
  CryFlow(this._ref);
  final Ref _ref;

  Future<String> analyze({
    required DateTime startedAt,
    required int durationMs,
    String? audioPath,
    AudioFeatures audio = const AudioFeatures(),
    bool autoTriggered = false,
  }) async {
    final baby = await _ref.read(currentBabyProvider.future);
    final logs = await _ref.read(careLogRepositoryProvider).latestByType(baby.id);
    final ctx = buildCryContext(
      now: startedAt,
      birthDate: baby.birthDate,
      latest: logs.map((k, v) => MapEntry(k, LastLog(v.startedAt, v.endedAt))),
    );
    if (audio.embedding == null && audioPath != null) {
      try {
        final emb = await _ref.read(cryEmbedderProvider.future);
        if (emb != null) audio = await emb.embedWav(audioPath); // 后台 isolate，不卡界面
      } catch (_) {
        // 特征提取失败：只用记录推断
      }
    }
    final predictor = await _ref.read(cryPredictorProvider.future);
    final sw = Stopwatch()..start();
    final prediction = await predictor.predict(audio, ctx); // 分类头只有一层，主线程 <1ms
    if (kDebugMode) debugPrint('[cry-analyze] 分类+融合 ${sw.elapsedMicroseconds}µs');
    return _ref.read(cryEventRepositoryProvider).save(
          babyId: baby.id,
          startedAt: startedAt,
          durationMs: durationMs,
          context: ctx,
          prediction: prediction,
          audioPath: audioPath,
          cryConfidence: audio.cryConfidence,
          autoTriggered: autoTriggered,
        );
  }
}
