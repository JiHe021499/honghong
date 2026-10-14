import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../audio/auto_listen.dart';
import '../audio/cry_embedder.dart';
import '../cloud/cloud_providers.dart';
import 'model_manager.dart';

final headLoaderProvider = Provider<HeadLoader>((ref) => TfliteHeadLoader());

final modelManagerProvider = Provider<ModelManager>((ref) => ModelManager(
      ref.watch(databaseProvider),
      ref.watch(prefsProvider),
      ref.watch(headLoaderProvider),
      dir: getApplicationSupportDirectory,
    ));

/// 当前分类模型；没有可用模型（加载失败、测试环境没有 TFLite）时为 null，只用规则
final activeModelProvider = FutureProvider<LoadedModel?>((ref) async {
  final m = await ref.watch(modelManagerProvider).load();
  ref.onDispose(() => m?.head.close());
  return m;
});

/// 录音 → embedding。测试环境没有 TFLite 原生库，为 null
final cryEmbedderProvider = FutureProvider<CryEmbedder?>((ref) async {
  if (!AutoListenController.enabledInThisEnv) return null;
  try {
    final e = await CryEmbedder.load();
    ref.onDispose(e.close);
    return e;
  } catch (_) {
    return null;
  }
});

/// 检查云端模型更新（启动/回前台时由 SyncCoordinator 调，最多 6 小时一次）。装了新版本就热切换。
Future<String?> checkModelUpdate(Ref ref, {bool force = false}) async {
  final api = ref.read(cloudApiProvider);
  if (api == null) return null;
  final mgr = ref.read(modelManagerProvider);
  final last = DateTime.tryParse(ref.read(prefsProvider).getString(ModelManager.kLastCheck) ?? '');
  if (!force && last != null && DateTime.now().difference(last) < const Duration(hours: 6)) return null;
  final current = await ref.read(activeModelProvider.future);
  final v = await mgr.checkForUpdate(api, currentVersion: current?.meta.version);
  if (v != null) {
    ref.invalidate(activeModelProvider);
    ref.invalidate(cryPredictorProvider);
  }
  return v;
}
