import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/providers.dart';
import '../../data/repositories/diary_repository.dart';
import '../../domain/diary/diary_service.dart';
import '../../services/diary/diary_api.dart';
import '../../services/diary/voice_capture.dart';

/// 未配置 AI 网关（AI_GATEWAY_URL 或云端为空）时为 null：语音/整理不可用，文字可手动保存为“其他”。测试里注入假实现。
final diaryApiProvider = Provider<DiaryApi?>((ref) {
  if (!aiGatewayConfigured) return null;
  try {
    final client = Supabase.instance.client;
    return HttpDiaryApi(
      baseUrl: aiGatewayUrl,
      token: () async {
        if (client.auth.currentUser == null) await client.auth.signInAnonymously();
        final t = client.auth.currentSession?.accessToken;
        if (t == null) throw StateError('no session');
        return t;
      },
    );
  } catch (_) {
    return null;
  }
});

final voiceCaptureProvider = Provider<VoiceCapture>((ref) => SystemVoiceCapture());

final diaryServiceProvider = Provider((ref) => DiaryService(ref.watch(databaseProvider)));

/// 今天的日记时间线（日记主页“今天的日记”）
final todayDiaryProvider = StreamProvider.autoDispose<List<TimelineEntry>>((ref) async* {
  final baby = await ref.watch(currentBabyProvider.future);
  yield* ref.watch(diaryRepositoryProvider).watchTimeline(baby.id, DateTime.now());
});

/// 今天的小结是否已生成（首页入口卡第 2 屏）
final todaySummaryReadyProvider = FutureProvider.autoDispose<bool>((ref) async {
  final baby = await ref.watch(currentBabyProvider.future);
  final s = await ref.watch(diaryRepositoryProvider).summaryOf(baby.id, DateTime.now());
  return s?.status == 'ready';
});

/// 首次进入补问性别：跳过后不再反复问
const kDiaryGenderPrompted = 'diary_gender_prompted';

/// 断网时保留的文字草稿
const kDiaryDraft = 'diary_draft';
