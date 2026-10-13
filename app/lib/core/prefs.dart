import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在 main() 里用 overrideWithValue 注入
final prefsProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('prefsProvider 需要在 main 里注入'));

/// 自动监听哭声开关（持久化，默认关闭）
class AutoListenNotifier extends Notifier<bool> {
  static const key = 'auto_listen';
  @override
  bool build() => ref.watch(prefsProvider).getBool(key) ?? false;

  void set(bool v) {
    state = v;
    ref.read(prefsProvider).setBool(key, v);
  }
}

final autoListenProvider =
    NotifierProvider<AutoListenNotifier, bool>(AutoListenNotifier.new);
