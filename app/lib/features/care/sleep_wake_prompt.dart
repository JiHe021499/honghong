import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_clock.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/care_detail.dart';
import '../../domain/models/care_log_type.dart';
import '../../services/audio/sleep_wake_detector.dart';
import 'care_sheets.dart';

/// 一次"睡眠中哭醒"提示
@immutable
class SleepPrompt {
  const SleepPrompt({required this.sleepId, required this.cryOnsetAt, this.collapsed = false});
  final String sleepId;
  final DateTime cryOnsetAt;

  /// 10 分钟没操作 → 收起成一条状态条
  final bool collapsed;
}

/// 刚通过提示结束的睡眠（8 秒内可撤销 / 改时间）
@immutable
class SleepEnded {
  const SleepEnded({required this.logId, required this.endedAt, required this.previousDetail});
  final String logId;
  final DateTime endedAt;
  final String? previousDetail;
}

@immutable
class SleepWakeState {
  const SleepWakeState({this.prompt, this.ended});
  final SleepPrompt? prompt;
  final SleepEnded? ended;
}

String hm(DateTime t) => DateFormat('HH:mm').format(t);

/// 睡眠中哭醒 → 提示一键结束睡眠（只在前台；从不自动结束）
class SleepWakeController extends Notifier<SleepWakeState> {
  static const collapseAfter = Duration(minutes: 10);
  static const toastFor = Duration(seconds: 8);

  final detector = SleepWakeDetector();
  final policy = SleepPromptPolicy();
  Timer? _collapse, _toast;
  String? _sleepId;

  @override
  SleepWakeState build() {
    ref.onDispose(() {
      _collapse?.cancel();
      _toast?.cancel();
    });
    // 家人那边已经结束了这次睡眠（同步过来）→ 收起提示，不覆盖对方的记录
    ref.listen(activeSessionsProvider, (_, next) {
      final p = state.prompt;
      final active = next.value;
      if (p == null || active == null) return;
      if (!active.any((l) => l.id == p.sleepId)) dismiss();
    });
    return const SleepWakeState();
  }

  CareLog? _activeSleep() => (ref.read(activeSessionsProvider).value ?? const <CareLog>[]).where((l) => l.type == CareLogType.sleep.name).firstOrNull;

  /// 睡觉计时中返回 true（这时自动监听不再自动跳录音页）
  bool get sleeping => _activeSleep() != null;

  /// 自动监听每一帧调用。返回 true 表示睡觉中、本帧已由这里处理。
  bool onFrame(bool cry, DateTime now) {
    final sleep = _activeSleep();
    if (sleep == null) {
      _sleepId = null;
      detector.reset();
      return false;
    }
    if (_sleepId != sleep.id) {
      _sleepId = sleep.id;
      detector.reset();
    }
    final feeding = (ref.read(activeSessionsProvider).value ?? const <CareLog>[]).any((l) => l.type == CareLogType.feed.name);
    if (!SleepWakeDetector.eligible(sleepStartedAt: sleep.startedAt, feeding: feeding, now: now)) {
      detector.reset();
      return true;
    }
    final onset = detector.add(cry, now);
    if (onset != null && state.prompt == null && policy.canPrompt(sleep.id, now)) {
      policy.recordShown(sleep.id);
      _show(SleepPrompt(sleepId: sleep.id, cryOnsetAt: onset));
    }
    return true;
  }

  void _show(SleepPrompt p) {
    state = SleepWakeState(prompt: p, ended: state.ended);
    _armCollapse();
  }

  void _armCollapse() {
    _collapse?.cancel();
    _collapse = Timer(collapseAfter, () {
      final p = state.prompt;
      if (p == null) return;
      state = SleepWakeState(prompt: SleepPrompt(sleepId: p.sleepId, cryOnsetAt: p.cryOnsetAt, collapsed: true), ended: state.ended);
    });
  }

  /// 点开收起的状态条
  void expand() {
    final p = state.prompt;
    if (p == null) return;
    state = SleepWakeState(
      prompt: SleepPrompt(sleepId: p.sleepId, cryOnsetAt: p.cryOnsetAt),
      ended: state.ended,
    );
    _armCollapse();
  }

  void dismiss() {
    _collapse?.cancel();
    if (state.prompt != null) state = SleepWakeState(ended: state.ended);
  }

  /// "还在睡"：20 分钟内不再提示
  void stillAsleep() {
    final p = state.prompt;
    if (p != null) policy.stillAsleep(p.sleepId, AppClock.now());
    dismiss();
  }

  /// 结束睡眠，结束时间 = [at]（默认哭声开始时间）。睡眠已被别人结束时什么都不做，返回 false。
  Future<bool> endSleep({String? sleepId, DateTime? at}) async {
    final id = sleepId ?? state.prompt?.sleepId;
    final when = at ?? state.prompt?.cryOnsetAt ?? AppClock.now();
    dismiss();
    if (id == null) return false;
    final repo = ref.read(careLogRepositoryProvider);
    final log = await repo.byId(id);
    if (log == null || log.endedAt != null) return false; // 已结束（家人同步）：不覆盖
    final end = when.isAfter(log.startedAt) ? when : AppClock.now();
    final detail = CareDetail.decode(log.detail).copyWith(endedBy: 'cry');
    await repo.saveSession(id, duration: end.difference(log.startedAt), detail: detail);
    _toast?.cancel();
    state = SleepWakeState(
      prompt: state.prompt,
      ended: SleepEnded(logId: id, endedAt: end, previousDetail: log.detail),
    );
    _toast = Timer(toastFor, clearToast);
    return true;
  }

  void clearToast() {
    _toast?.cancel();
    if (state.ended != null) state = SleepWakeState(prompt: state.prompt);
  }

  /// 撤销：回到睡觉计时中，细节恢复原样
  Future<void> undo() async {
    final e = state.ended;
    clearToast();
    if (e == null) return;
    final repo = ref.read(careLogRepositoryProvider);
    await repo.resumeSession(e.logId);
    await repo.updateDetail(e.logId, CareDetail.decode(e.previousDetail));
  }

  /// 改时间：打开结束面板（编辑模式），保留 endedBy
  Future<void> editTime(BuildContext context) async {
    final e = state.ended;
    clearToast();
    if (e == null) return;
    final repo = ref.read(careLogRepositoryProvider);
    final log = await repo.byId(e.logId);
    if (log == null || log.endedAt == null || !context.mounted) return;
    final r = await showSessionEndSheet(context, log, log.endedAt!, editing: true);
    if (r == null || r.resume) return;
    await repo.saveSession(
      log.id,
      duration: r.duration,
      detail: (r.detail ?? const CareDetail()).copyWith(endedBy: 'cry'),
    );
  }
}

final sleepWakeProvider = NotifierProvider<SleepWakeController, SleepWakeState>(SleepWakeController.new);

bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 首页底部：哭醒提示卡 / 收起后的状态条
class SleepWakeCard extends ConsumerStatefulWidget {
  const SleepWakeCard({super.key, required this.onListen});
  final VoidCallback onListen;
  @override
  ConsumerState<SleepWakeCard> createState() => _SleepWakeCardState();
}

class _SleepWakeCardState extends ConsumerState<SleepWakeCard> {
  @override
  Widget build(BuildContext context) {
    ref.listen(sleepWakeProvider.select((s) => s.prompt), (prev, next) {
      if (prev == null && next != null) HapticFeedback.mediumImpact();
    });
    final p = ref.watch(sleepWakeProvider.select((s) => s.prompt));
    final ctl = ref.read(sleepWakeProvider.notifier);
    final c = context.hh;
    Widget child;
    if (p == null) {
      child = const SizedBox.shrink(key: ValueKey('none'));
    } else if (p.collapsed) {
      child = Semantics(
        key: const ValueKey('bar'),
        button: true,
        liveRegion: true,
        label: '宝宝 ${hm(p.cryOnsetAt)} 哭过，点开处理',
        excludeSemantics: true,
        child: GestureDetector(
          key: const Key('sleep-wake-bar'),
          onTap: ctl.expand,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: c.statusBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.runBorder),
            ),
            child: Row(
              children: [
                const HhIcon(AppIcon.careSleep, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('宝宝 ${hm(p.cryOnsetAt)} 哭过 · 还在睡觉计时', style: TextStyle(fontSize: 14, color: c.statusInk)),
                ),
                Text(
                  '处理',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.peachDeep),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      child = Semantics(
        key: const ValueKey('card'),
        container: true,
        liveRegion: true,
        label: '宝宝好像哭醒了',
        child: Container(
          key: const Key('sleep-wake-card'),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.line),
            boxShadow: c.cardShadows,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const ExcludeSemantics(child: HhIcon(AppIcon.careSleep, size: 28)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '宝宝好像哭醒了',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('${hm(p.cryOnsetAt)} 开始哭，睡觉还在计时', style: TextStyle(fontSize: 13, color: c.sub)),
              const SizedBox(height: 12),
              HhButton(
                key: const Key('sleep-wake-end'),
                label: '结束睡眠 · 醒于 ${hm(p.cryOnsetAt)}',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ctl.endSleep();
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: HhButton(
                      key: const Key('sleep-wake-still'),
                      label: '还在睡',
                      primary: false,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        ctl.stillAsleep();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HhButton(
                      key: const Key('sleep-wake-listen'),
                      label: '听听为什么哭',
                      primary: false,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        ctl.dismiss();
                        widget.onListen();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (_still(context)) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (w, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .15), end: Offset.zero).animate(a),
          child: w,
        ),
      ),
      child: child,
    );
  }
}

/// 结束睡眠后的 8 秒提示：撤销 / 改时间
class SleepEndedToast extends ConsumerWidget {
  const SleepEndedToast({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(sleepWakeProvider.select((s) => s.ended));
    final ctl = ref.read(sleepWakeProvider.notifier);
    final c = context.hh;
    final child = e == null
        ? const SizedBox.shrink(key: ValueKey('none'))
        : Semantics(
            key: ValueKey(e.logId),
            container: true,
            liveRegion: true,
            child: Container(
              key: const Key('sleep-ended-toast'),
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.line),
                boxShadow: const [BoxShadow(color: Color(0x263C2814), blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已结束睡眠 · 醒于 ${hm(e.endedAt)}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                  ),
                  TextButton(
                    key: const Key('sleep-ended-undo'),
                    style: TextButton.styleFrom(minimumSize: const Size(56, 48)),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ctl.undo();
                    },
                    child: Text(
                      '撤销',
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.peachDeep),
                    ),
                  ),
                  TextButton(
                    key: const Key('sleep-ended-edit'),
                    style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                    onPressed: () => ctl.editTime(context),
                    child: Text(
                      '改时间',
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.peachDeep),
                    ),
                  ),
                ],
              ),
            ),
          );
    if (_still(context)) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}

/// 结果页的睡眠卡：睡觉计时中时提供"结束睡眠"
class SleepResultCard extends ConsumerWidget {
  const SleepResultCard({super.key, this.fallbackAt});

  /// 没有哭醒提示时用的"醒于"时间（这次哭声的时间）
  final DateTime? fallbackAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionsProvider).value ?? const <CareLog>[];
    final sleep = active.where((l) => l.type == CareLogType.sleep.name).firstOrNull;
    if (sleep == null) return const SizedBox.shrink();
    final p = ref.watch(sleepWakeProvider.select((s) => s.prompt));
    final at = (p != null && p.sleepId == sleep.id) ? p.cryOnsetAt : (fallbackAt ?? AppClock.now());
    final c = context.hh;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        container: true,
        child: HhCard(
          key: const Key('sleep-result-card'),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    iconSpan(AppIcon.careSleep, size: 20),
                    const TextSpan(text: '睡觉还在计时'),
                  ],
                ),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
              ),
              const SizedBox(height: 4),
              Text('宝宝醒了的话，可以把睡眠结束在开始哭的时候', style: TextStyle(fontSize: 13, color: c.sub)),
              const SizedBox(height: 12),
              HhButton(
                key: const Key('sleep-result-end'),
                label: '结束睡眠 · 醒于 ${hm(at)}',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.read(sleepWakeProvider.notifier).endSleep(sleepId: sleep.id, at: at);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
