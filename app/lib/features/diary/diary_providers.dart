import 'package:drift/drift.dart' hide Column;
import 'package:flutter/widgets.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/diary_repository.dart';
import '../../domain/diary/diary_service.dart';
import '../../domain/diary/summary_service.dart';
import '../../services/diary/diary_api.dart';
import '../../services/diary/cloud_voice_capture.dart';
import '../../services/diary/voice_capture.dart';
import '../../core/app_clock.dart';

/// 未配置 AI 网关（AI_GATEWAY_URL 或云端为空）时为 null：语音/整理不可用，文字可手动保存为“其他”。测试里注入假实现。
/// 网关调用用的 JWT：Supabase 匿名登录
Future<String> _gatewayToken() async {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) await client.auth.signInAnonymously();
  final t = client.auth.currentSession?.accessToken;
  if (t == null) throw StateError('no session');
  return t;
}

/// 未配置 AI 网关（AI_GATEWAY_URL 或云端为空）时为 null：语音/整理不可用，文字可手动保存为“其他”。测试里注入假实现。
final diaryApiProvider = Provider<DiaryApi?>((ref) {
  if (!aiGatewayConfigured) return null;
  try {
    Supabase.instance.client;
    return HttpDiaryApi(baseUrl: aiGatewayUrl, token: _gatewayToken);
  } catch (_) {
    return null;
  }
});

/// 联网识别（讯飞，经网关 /diary-asr）。未配置网关时为 null。
final cloudVoiceCaptureProvider = Provider<VoiceCapture?>((ref) {
  if (!aiGatewayConfigured) return null;
  final url = asrUrl(aiGatewayUrl);
  return CloudVoiceCapture(token: _gatewayToken, connect: (jwt) => IoAsrSocket.connect(url, jwt));
});

final voiceCaptureProvider = Provider<VoiceCapture>((ref) => SystemVoiceCapture());

final diaryServiceProvider = Provider((ref) => DiaryService(ref.watch(databaseProvider)));

/// 今天的日记时间线（日记主页“今天的日记”）
final todayDiaryProvider = StreamProvider.autoDispose<List<TimelineEntry>>((ref) async* {
  final baby = await ref.watch(currentBabyProvider.future);
  yield* ref.watch(diaryRepositoryProvider).watchTimeline(baby.id, AppClock.now());
});

/// 某天的小结行（随数据库变化刷新）
final summaryRowProvider = StreamProvider.autoDispose.family<DailySummary?, DateTime>((ref, day) async* {
  final baby = await ref.watch(currentBabyProvider.future);
  final db = ref.watch(databaseProvider);
  final d = DateTime(day.year, day.month, day.day);
  yield* (db.select(db.dailySummaries)..where((s) => s.babyId.equals(baby.id) & s.date.equals(d))).watchSingleOrNull();
});

/// 今天的小结是否已生成（首页入口卡第 2 屏）
final todaySummaryReadyProvider = Provider.autoDispose<bool>((ref) {
  final n = ref.watch(summaryClockProvider)();
  final s = ref.watch(summaryRowProvider(DateTime(n.year, n.month, n.day))).value;
  return s?.status == 'ready';
});

/// 首次进入补问性别：跳过后不再反复问
const kDiaryGenderPrompted = 'diary_gender_prompted';

/// 断网时保留的文字草稿
const kDiaryDraft = 'diary_draft';

/// 联网识别告知：null=还没问过，true=已同意，false=已拒绝（拒绝后不再自动弹，直接退回文字输入）
const kDiaryCloudAsrConsent = 'diary_cloud_asr_consent';

/// 联网语音识别同意状态：null 未问过 / true 同意 / false 不用。
/// 首次告知弹窗和设置开关都通过它写同一个 pref，保持同步。
final cloudAsrConsentProvider = NotifierProvider<CloudAsrConsentNotifier, bool?>(CloudAsrConsentNotifier.new);

class CloudAsrConsentNotifier extends Notifier<bool?> {
  @override
  bool? build() => ref.watch(prefsProvider).getBool(kDiaryCloudAsrConsent);
  Future<void> set(bool v) async {
    await ref.read(prefsProvider).setBool(kDiaryCloudAsrConsent, v);
    state = v;
  }
}

/// 今日小结服务（时钟可在测试里替换）
final summaryClockProvider = Provider<DateTime Function()>((ref) => AppClock.now);
final summaryServiceProvider =
    Provider((ref) => SummaryService(ref.watch(databaseProvider), api: ref.watch(diaryApiProvider), now: ref.watch(summaryClockProvider)));

/// 前台触发小结（回到前台、打开首页、打开日记页）。失败静默，不打扰用户。
final summaryTriggerProvider = Provider<SummaryTrigger>((ref) {
  final t = SummaryTrigger(ref);
  ref.onDispose(t.dispose);
  return t;
});

class SummaryTrigger with WidgetsBindingObserver {
  SummaryTrigger(this._ref);
  final Ref _ref;
  bool _observing = false;

  Future<void> kick() async {
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    try {
      final baby = await _ref.read(currentBabyProvider.future);
      await _ref.read(summaryServiceProvider).trigger(baby.id, baby.birthDate);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) kick();
  }

  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
  }
}
