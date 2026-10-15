/// 睡眠中哭醒检测（只在前台、自动监听开着时工作，纯逻辑，便于测试）。
///
/// 自动监听每 0.5 秒给一帧哭声判定。睡觉计时中：
/// - 60 秒内累计哭 ≥20 秒，或连续哭 ≥15 秒（帧间隔 ≤1 秒算连续）→ 触发一次；
/// - 安静 >20 秒 → 清零，下一段哭重新计算；
/// - 触发后同一段哭不再重复触发，直到安静清零。
/// 触发时返回这段哭开始的时间（作为"醒于"时间）。
class SleepWakeDetector {
  SleepWakeDetector({
    this.frame = const Duration(milliseconds: 500),
    this.window = const Duration(seconds: 60),
    this.accumulated = const Duration(seconds: 20),
    this.continuous = const Duration(seconds: 15),
    this.quietReset = const Duration(seconds: 20),
    this.gapTolerance = const Duration(seconds: 1),
  });

  final Duration frame, window, accumulated, continuous, quietReset, gapTolerance;

  final List<DateTime> _cries = [];
  DateTime? _onset, _runStart, _lastCry;
  bool _fired = false;

  DateTime? get onset => _onset;

  void reset() {
    _cries.clear();
    _onset = _runStart = _lastCry = null;
    _fired = false;
  }

  /// 送入一帧；触发时返回哭声开始时间，否则 null
  DateTime? add(bool cry, DateTime now) {
    if (_lastCry != null && now.difference(_lastCry!) > quietReset) reset();
    if (!cry) return null;
    if (_runStart == null || now.difference(_lastCry!) > gapTolerance) _runStart = now;
    _onset ??= now;
    _lastCry = now;
    _cries.add(now);
    _cries.removeWhere((t) => now.difference(t) >= window);
    if (_fired) return null;
    final acc = frame * _cries.length;
    final run = now.difference(_runStart!) + frame;
    if (acc >= accumulated || run >= continuous) {
      _fired = true;
      return _onset;
    }
    return null;
  }

  /// 前置条件：睡觉计时已进行 ≥10 分钟，且没有进行中的喂奶
  static bool eligible({required DateTime? sleepStartedAt, required bool feeding, required DateTime now, Duration minSleep = const Duration(minutes: 10)}) =>
      sleepStartedAt != null && !feeding && now.difference(sleepStartedAt) >= minSleep;
}

/// 每次睡眠最多提示 3 次；"还在睡"后 20 分钟内不再提示。
class SleepPromptPolicy {
  SleepPromptPolicy({this.maxPrompts = 3, this.snooze = const Duration(minutes: 20)});
  final int maxPrompts;
  final Duration snooze;

  final Map<String, int> _shown = {};
  final Map<String, DateTime> _snoozeUntil = {};

  int shownFor(String sleepId) => _shown[sleepId] ?? 0;

  bool canPrompt(String sleepId, DateTime now) {
    if (shownFor(sleepId) >= maxPrompts) return false;
    final until = _snoozeUntil[sleepId];
    return until == null || !now.isBefore(until);
  }

  void recordShown(String sleepId) => _shown[sleepId] = shownFor(sleepId) + 1;

  void stillAsleep(String sleepId, DateTime now) => _snoozeUntil[sleepId] = now.add(snooze);
}
