import 'dart:async';
import 'dart:isolate';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs.dart';
import '../../core/providers.dart';
import 'lockscreen_notification.dart';
import 'quick_actions.dart';

/// 设置里的"锁屏快捷记录"开关（默认关闭）
class LockscreenEnabled extends Notifier<bool> {
  @override
  bool build() => ref.watch(prefsProvider).getBool(LockscreenNotification.prefKey) ?? false;

  /// 打开时申请通知权限；没拿到权限返回 false
  Future<bool> set(bool v) async {
    if (v && !await LockscreenNotification.requestPermission()) return false;
    await ref.read(prefsProvider).setBool(LockscreenNotification.prefKey, v);
    state = v;
    final c = ref.read(lockscreenControllerProvider);
    v ? await c.refresh() : await LockscreenNotification.cancel();
    return true;
  }
}

final lockscreenEnabledProvider = NotifierProvider<LockscreenEnabled, bool>(LockscreenEnabled.new);

final lockscreenControllerProvider = Provider<LockscreenController>((ref) {
  final c = LockscreenController(ref);
  ref.onDispose(c.dispose);
  return c;
});

/// 主 isolate：数据变化时刷新通知；接收锁屏按钮（App 运行时由后台 isolate 转过来）
class LockscreenController with WidgetsBindingObserver {
  LockscreenController(this._ref);
  final Ref _ref;
  StreamSubscription<void>? _sub;
  ReceivePort? _port;
  Timer? _debounce;
  bool _started = false;

  Future<void> start() async {
    if (_started || !LockscreenNotification.supported) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await LockscreenNotification.init(onForegroundAction: (r) {
      if (r.actionId != null) handle(r.actionId!);
    });
    _port = registerMainPort(handle);
    final db = _ref.read(databaseProvider);
    _sub = db.tableUpdates(TableUpdateQuery.onAllTables([db.careLogs, db.babies])).listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), refresh);
    });
    await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App 进程活着但锁屏操作走了另一个数据库连接时，让界面重新查询
      final db = _ref.read(databaseProvider);
      db.markTablesUpdated([db.careLogs]);
    }
  }

  Future<void> handle(String actionId) async {
    final db = _ref.read(databaseProvider);
    final done = await runQuickAction(db, actionId);
    await refresh(done: done);
  }

  Future<void> refresh({String? done}) async {
    if (!(_ref.read(prefsProvider).getBool(LockscreenNotification.prefKey) ?? false)) return;
    await LockscreenNotification.show(await loadQuickState(_ref.read(databaseProvider), done: done));
  }

  void dispose() {
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _debounce?.cancel();
    _port?.close();
  }
}
