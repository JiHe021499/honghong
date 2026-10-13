import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../../features/update/update_providers.dart';
import 'cloud_api.dart';
import 'family_sync.dart';
import 'research_upload.dart';
import 'supabase_cloud_api.dart';

/// 未配置云端（没有 dart-define）时为 null，App 全部离线运行。测试里可注入假实现。
final cloudApiProvider = Provider<CloudApi?>((ref) {
  if (!cloudConfigured) return null;
  try {
    return SupabaseCloudApi(Supabase.instance.client);
  } catch (_) {
    return null; // 初始化失败也不影响本地使用
  }
});

final familySyncProvider = Provider<FamilySync?>((ref) {
  final api = ref.watch(cloudApiProvider);
  if (api == null) return null;
  return FamilySync(ref.watch(databaseProvider), api, ref.watch(prefsProvider));
});

final researchUploaderProvider = Provider<ResearchUploader?>((ref) {
  final api = ref.watch(cloudApiProvider);
  if (api == null) return null;
  return ResearchUploader(ref.watch(databaseProvider), api, ref.watch(prefsProvider));
});

/// 当前家庭 id（本机记住的），变化时手动 invalidate
final familyIdProvider = Provider<String?>((ref) => ref.watch(familySyncProvider)?.familyId);

final familyMembersProvider = FutureProvider<List<FamilyMember>>((ref) async {
  final api = ref.watch(cloudApiProvider);
  if (api == null || ref.watch(familyIdProvider) == null) return const [];
  return api.members();
});

final inviteCodeProvider = FutureProvider<String?>((ref) async {
  final api = ref.watch(cloudApiProvider);
  if (api == null || ref.watch(familyIdProvider) == null) return null;
  return await api.inviteCode() ?? await api.refreshInvite();
});

/// "参与改进"开关
class ResearchOptIn extends Notifier<bool> {
  @override
  bool build() => ref.watch(prefsProvider).getBool(ResearchUploader.kOptIn) ?? false;
  Future<void> set(bool v) async {
    await ref.read(researchUploaderProvider)?.setEnabled(v);
    state = v;
    if (v) ref.read(syncCoordinatorProvider).kick();
  }
}

final researchOptInProvider = NotifierProvider<ResearchOptIn, bool>(ResearchOptIn.new);

/// 同步状态（给家庭页和设置页显示）
class SyncStatus {
  const SyncStatus({this.running = false, this.lastFamilySync, this.error, this.uploaded = 0, this.pendingUploads = 0});
  final bool running;
  final DateTime? lastFamilySync;
  final String? error;
  final int uploaded;
  final int pendingUploads;
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus(lastFamilySync: ref.read(familySyncProvider)?.lastSync);
  void put(SyncStatus s) => state = s;
}

/// 调度：启动、回到前台、本地数据变化（防抖 4 秒）时同步；失败按 1/5/30 分钟退避重试。
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final c = SyncCoordinator(ref);
  ref.onDispose(c.dispose);
  return c;
});

class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator(this._ref);
  final Ref _ref;
  StreamSubscription<void>? _dbSub;
  Timer? _debounce, _retry;
  int _failures = 0;
  bool _running = false, _again = false, _started = false;

  static const _backoff = [Duration(minutes: 1), Duration(minutes: 5), Duration(minutes: 30)];

  void start() {
    if (_started || _ref.read(cloudApiProvider) == null) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final db = _ref.read(databaseProvider);
    _dbSub = db
        .tableUpdates()
        .listen((_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(seconds: 4), kick);
        });
    kick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) kick();
  }

  Future<void> kick() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    final status = _ref.read(syncStatusProvider.notifier);
    status.put(SyncStatus(running: true, lastFamilySync: _ref.read(syncStatusProvider).lastFamilySync));
    String? error;
    try {
      final fam = _ref.read(familySyncProvider);
      if (fam?.familyId != null) {
        final n = await fam!.sync();
        if (n > 0) _ref.invalidate(currentBabyProvider);
      }
    } catch (e) {
      error = '家庭同步失败，稍后自动重试';
    }
    final up = _ref.read(researchUploaderProvider);
    var pending = 0, uploaded = 0;
    if (up != null) {
      try {
        final conn = await Connectivity().checkConnectivity();
        final version = _ref.read(packageInfoProvider).value?.version ?? '';
        final r = await up.run(onWifi: conn.contains(ConnectivityResult.wifi), appVersion: version);
        if (r.failed > 0) error ??= '有 ${r.failed} 条上传失败，稍后自动重试';
        pending = (await up.pending()).length;
        uploaded = await up.uploadedCount();
      } catch (_) {
        error ??= '上传失败，稍后自动重试';
      }
    }
    status.put(SyncStatus(
        lastFamilySync: _ref.read(familySyncProvider)?.lastSync,
        error: error,
        uploaded: uploaded,
        pendingUploads: pending));
    _retry?.cancel();
    if (error != null) {
      _retry = Timer(_backoff[_failures.clamp(0, _backoff.length - 1)], kick);
      _failures++;
    } else {
      _failures = 0;
    }
    _running = false;
    if (_again) {
      _again = false;
      unawaited(kick());
    }
  }

  void dispose() {
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _dbSub?.cancel();
    _debounce?.cancel();
    _retry?.cancel();
  }
}
