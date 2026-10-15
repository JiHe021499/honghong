import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/care_detail.dart';
import '../../domain/models/care_log_type.dart';
import '../../services/audio/auto_listen.dart';
import '../care/care_actions.dart';
import '../care/care_log_row.dart';
import '../care/sleep_wake_prompt.dart';
import '../diary/diary_entry_card.dart';
import '../diary/diary_providers.dart' show summaryTriggerProvider;
import '../../core/app_clock.dart';

/// 首页（设计稿 01/02/04/06/08/10，夜间 14）
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// 刚记下的换尿布（显示 toast、"已记"状态和"刚刚"标签）
  String? _justDiaperId;
  Timer? _toastTimer;
  bool _toastVisible = false;

  /// 刚保存的记录 id（时间线提示"已写入 · 可点条目修改"）
  String? _justSavedId;

  late final actions = CareActions(ref);

  @override
  void initState() {
    super.initState();
    // 今日小结前台触发（21:00 后 / 补生成昨天，架构 §5.4）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(summaryTriggerProvider).kick();
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _tapType(CareLogType t, List<CareLog> active) async {
    if (t == CareLogType.diaper) {
      final id = await actions.logDiaper();
      _toastTimer?.cancel();
      setState(() {
        _justDiaperId = id;
        _toastVisible = true;
      });
      _toastTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _toastVisible = false);
      });
      return;
    }
    final running = active.where((l) => l.type == t.name).firstOrNull;
    if (running != null) return _end(running);
    await actions.start(t);
  }

  Future<void> _end(CareLog log) async {
    await actions.end(context, log);
    final after = await ref.read(careLogRepositoryProvider).byId(log.id);
    if (mounted && after?.endedAt != null) setState(() => _justSavedId = log.id);
  }

  Future<void> _editDiaper() async {
    final id = _justDiaperId;
    if (id == null) return;
    setState(() => _toastVisible = false);
    final log = await ref.read(careLogRepositoryProvider).byId(id);
    if (log != null && mounted) await actions.editDiaper(context, log);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final night = c.night;
    final active = ref.watch(activeSessionsProvider).value ?? const <CareLog>[];
    ref.watch(autoListenControllerProvider); // 开关打开时在首页监听哭声
    ref.listen(cryDetectedProvider, (_, next) {
      // 睡觉计时中不自动跳录音页（改由哭醒提示卡处理）
      final sleeping = (ref.read(activeSessionsProvider).value ?? const <CareLog>[]).any((l) => l.type == CareLogType.sleep.name);
      if (next != null && !sleeping && GoRouterState.of(context).uri.path == Routes.home) {
        context.push('${Routes.recording}?auto=1');
      }
    });

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const _Header(),
        _StatusBar(active: active),
        _CryButton(onTap: () => context.push(Routes.recording)),
        if (!night) const _AutoListenToggle(),
        const SizedBox(height: 18),
        _QuickGrid(active: active, justDiaper: _toastVisible, onTap: (t) => _tapType(t, active), onEnd: _end),
        if (night)
          const _VoiceHint()
        else ...[
          const SizedBox(height: 6),
          const DiaryEntryCard(),
          _Timeline(
            active: active,
            justDiaperId: _toastVisible ? _justDiaperId : null,
            justSavedId: _justSavedId,
            onTap: (log) => actions.editLog(context, log),
          ),
        ],
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            body,
            AnimatedPositioned(
              // 进入 220ms easeOutCubic，退出 180ms easeIn；减少动态时直接出现/消失
              duration: _reduceMotion(context) ? Duration.zero : Duration(milliseconds: _toastVisible ? 220 : 180),
              curve: _toastVisible ? Curves.easeOutCubic : Curves.easeIn,
              top: _toastVisible ? 8 : -120,
              left: 20,
              right: 20,
              child: _DiaperToast(onTap: _editDiaper, visible: _toastVisible),
            ),
            const Positioned(left: 20, right: 20, top: 8, child: SleepEndedToast()),
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: SleepWakeCard(onListen: () => context.push(Routes.recording)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    // 用开关状态本身驱动图标，与整页主题插值同时开始（c.night 要到动画过半才翻转）
    final nightOn = ref.watch(nightModeProvider);
    final baby = ref.watch(currentBabyProvider).value;
    final days = baby == null ? null : AppClock.now().difference(DateUtils.dateOnly(baby.birthDate)).inDays;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.dn(c.peachL, c.card), shape: BoxShape.circle),
            child: const HhIcon(AppIcon.avatarBaby, size: 30),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  baby?.nickname ?? '',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.dn(c.ink, c.peachDeep)),
                ),
                Text(c.night ? '夜间模式 · 亮度已调低' : (days == null ? '' : '出生第 $days 天'), style: TextStyle(fontSize: 12, color: c.sub)),
              ],
            ),
          ),
          Semantics(
            button: true,
            toggled: nightOn,
            label: '夜间模式',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => ref.read(nightModeProvider.notifier).toggle(),
              child: Container(
                key: const Key('night-toggle'),
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.dn(Colors.white, c.card),
                  shape: BoxShape.circle,
                  boxShadow: c.dnShadows(const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))], null),
                ),
                child: _NightIcon(night: nightOn),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _ago(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m分钟';
  return '$h小时$m分';
}

bool _reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 每秒刷新的计时数字：单独成小组件，只有它随 secondTicker 重建（不做动画，保持等宽数字）
class _Ticker extends ConsumerWidget {
  const _Ticker({required this.since, this.style});
  final DateTime since;
  final TextStyle? style;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(secondTickerProvider);
    return ExcludeSemantics(
      child: Text(
        formatTimer(AppClock.now().difference(since)),
        style: (style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.active});
  final List<CareLog> active;

  @override
  Widget build(BuildContext context) {
    final still = _reduceMotion(context);
    final key = active.isEmpty ? 'idle' : '${active.first.id}/${active.length}';
    return Semantics(
      liveRegion: true,
      container: true,
      child: AnimatedSwitcher(
        duration: still ? Duration.zero : const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeOut,
        layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?cur]),
        child: _StatusBarBody(key: ValueKey(key), active: active),
      ),
    );
  }
}

class _StatusBarBody extends ConsumerWidget {
  const _StatusBarBody({super.key, required this.active});
  final List<CareLog> active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final emStyle = TextStyle(fontWeight: FontWeight.w700, color: active.isEmpty ? c.blueInk : c.dn(c.peach2, c.peachDeep));
    final base = TextStyle(fontSize: 14, color: c.statusInk, height: 1.3);

    if (active.isNotEmpty) {
      final first = active.first;
      final t = CareLogType.values.byName(first.type);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: c.statusGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.dn(const Color(0x59FF9874), const Color(0xFF4A221C))),
        ),
        child: Row(
          children: [
            const ExcludeSemantics(child: RepaintBoundary(child: PulseDot())),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: base,
                  children: [
                    if (!c.night) iconSpan(t.icon, size: 18),
                    TextSpan(text: '${t.runningLabel} · ${c.night ? '' : '已进行 '}'),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _Ticker(since: first.startedAt, style: base.merge(emStyle)),
                    ),
                    if (!c.night) const TextSpan(text: ' · 点「结束」保存'),
                    if (active.length > 1) TextSpan(text: '  +${active.length - 1}'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    ref.watch(clockProvider);
    final latest = ref.watch(latestLogsProvider).value ?? const {};
    final now = AppClock.now();
    final feed = latest[CareLogType.feed];
    final sleep = latest[CareLogType.sleep];
    final spans = <InlineSpan>[];
    if (feed != null) {
      spans.addAll([
        iconSpan(AppIcon.careFeed),
        const TextSpan(text: '上次喂奶 '),
        TextSpan(text: _ago(now.difference(feed.startedAt)), style: emStyle),
        const TextSpan(text: ' 前'),
      ]);
    }
    if (sleep?.endedAt != null) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' · '));
      spans.addAll([iconSpan(AppIcon.careAwake), const TextSpan(text: '已醒 '), TextSpan(text: _ago(now.difference(sleep!.endedAt!)), style: emStyle)]);
    }
    if (spans.isEmpty) spans.addAll([iconSpan(AppIcon.waveHello), const TextSpan(text: '还没有记录，喂奶、睡觉点一下就开始计时')]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: c.statusBg, borderRadius: BorderRadius.circular(16)),
      child: Text.rich(
        TextSpan(style: base, children: spans),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 「宝宝在哭」主按钮：按下缩放 + 呼吸光环（只驱动光环层）
class _CryButton extends StatefulWidget {
  const _CryButton({required this.onTap});
  final Future<void> Function() onTap;

  @override
  State<_CryButton> createState() => _CryButtonState();
}

class _CryButtonState extends State<_CryButton> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  bool _pressed = false;
  bool _away = false; // 已推到录音页
  bool _background = false;
  bool _still = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = _reduceMotion(context);
    _breath.duration = Duration(milliseconds: context.hh.night ? 4000 : 3200);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background = state != AppLifecycleState.resumed;
    _sync();
  }

  /// 减少动态 / 推到录音页 / 切到别的 tab（TickerMode 关闭）/ 后台：停呼吸
  void _sync() {
    final run = !_still && !_away && !_background && TickerMode.valuesOf(context).enabled;
    if (run && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!run && _breath.isAnimating) {
      _breath.stop();
    }
    if (_still) _breath.value = 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _breath.dispose();
    super.dispose();
  }

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  Future<void> _tap() async {
    HapticFeedback.lightImpact();
    _away = true;
    _sync();
    await widget.onTap();
    if (!mounted) return;
    _away = false;
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final size = c.dnd(200, 230);
    final ring = c.ring;
    final face = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(center: const Alignment(-.3, -.4), radius: .9, colors: [c.cryFrom, c.cryTo]),
        // 投影固定，不逐帧改 blur
        boxShadow: [
          BoxShadow(color: c.dn(const Color(0x59FF7850), const Color(0x00FF7850)), blurRadius: 30, offset: const Offset(0, 14)),
          BoxShadow(
            color: ring.withValues(alpha: c.dnd(.08, .06)),
            spreadRadius: c.dnd(32, 36),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '宝宝在哭',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.cryInk),
          ),
          const SizedBox(height: 6),
          Text(c.night ? '轻点就开始听' : '点一下，帮你听听', style: TextStyle(fontSize: 13, color: c.cryInk.withValues(alpha: .9))),
        ],
      ),
    );
    // 呼吸光环：只有这一层随动画重绘；spread 16↔22，不透明度 .15↔.08，无 blur
    final ringLayer = ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          key: const Key('cry-ring'),
          animation: _breath,
          child: SizedBox.square(dimension: size),
          builder: (_, child) {
            final t = Curves.easeInOutSine.transform(_breath.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: ring.withValues(alpha: .15 - .07 * t),
                    spreadRadius: 16 + 6 * t,
                  ),
                ],
              ),
              child: child,
            );
          },
        ),
      ),
    );
    final pressed = _still
        ? AnimatedOpacity(opacity: _pressed ? .85 : 1, duration: Duration.zero, child: face)
        : AnimatedScale(
            scale: _pressed ? .96 : 1,
            duration: Duration(milliseconds: _pressed ? 100 : 180),
            curve: _pressed ? Curves.easeOut : Curves.easeOutCubic,
            child: face,
          );
    return Padding(
      padding: EdgeInsets.only(top: c.dnd(38, 44), bottom: c.dnd(0, 40)),
      child: Center(
        child: Semantics(
          button: true,
          label: '宝宝在哭，开始听哭声',
          excludeSemantics: true,
          child: GestureDetector(
            key: const Key('cry-button'),
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            onTap: _tap,
            child: Stack(alignment: Alignment.center, children: [ringLayer, pressed]),
          ),
        ),
      ),
    );
  }
}

class _AutoListenToggle extends ConsumerWidget {
  const _AutoListenToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final on = ref.watch(autoListenProvider);
    final status = ref.watch(autoListenControllerProvider);
    final text = !on
        ? '已关闭'
        : switch (status) {
            AutoListenStatus.listening => '已开启',
            AutoListenStatus.noPermission => '需要麦克风权限',
            AutoListenStatus.unavailable => '本机暂不支持',
            _ => '已开启',
          };
    return Padding(
      padding: const EdgeInsets.only(top: 38),
      child: Semantics(
        toggled: on,
        label: '自动监听哭声',
        value: text,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => ref.read(autoListenProvider.notifier).set(!on),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MiniSwitch(on: on),
              const SizedBox(width: 10),
              Text('自动监听哭声 · $text', style: TextStyle(fontSize: 13, color: c.sub)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return AnimatedContainer(
      key: const Key('auto-listen-switch'),
      duration: const Duration(milliseconds: 150),
      width: 42,
      height: 24,
      padding: const EdgeInsets.all(3),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(color: on ? c.green : const Color(0xFFDDD5CC), borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 18,
        height: 18,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.active, required this.justDiaper, required this.onTap, required this.onEnd});
  final List<CareLog> active;
  final bool justDiaper;
  final ValueChanged<CareLogType> onTap;
  final ValueChanged<CareLog> onEnd;

  /// 进行中时同排显示哪些按钮：换尿布总在；另一个跟当前事最相关的
  static List<CareLogType> _companions(CareLogType running) => switch (running) {
    CareLogType.feed => [CareLogType.sleep, CareLogType.diaper],
    _ => [CareLogType.feed, CareLogType.diaper],
  };

  /// 布局只随"进行中"的组合变化；开始失败时组合不变 → 不触发切换动画
  String get _layoutKey => active.isEmpty ? 'idle' : active.map((l) => l.type).join('+');

  @override
  Widget build(BuildContext context) {
    final still = _reduceMotion(context);
    // 减少动态：直接切换布局（AnimatedSize 的零时长有布局问题，干脆不包）
    if (still) return _grid(context);
    const d = Duration(milliseconds: 260);
    return AnimatedSize(
      duration: d,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: d,
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        layoutBuilder: (cur, prev) => Stack(
          alignment: Alignment.topCenter,
          children: [
            for (final p in prev) Positioned(left: 0, right: 0, top: 0, child: p),
            ?cur,
          ],
        ),
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(a), child: child),
        ),
        child: KeyedSubtree(key: ValueKey(_layoutKey), child: _grid(context)),
      ),
    );
  }

  Widget _grid(BuildContext context) {
    final c = context.hh;
    final gap = SizedBox(width: c.dnd(10, 12));
    final activeTypes = {for (final l in active) CareLogType.values.byName(l.type)};

    Widget plain(CareLogType t, {bool muted = false}) {
      final done = t == CareLogType.diaper && justDiaper;
      return _QBox(
        key: Key('quick-${t.name}'),
        onTap: () => onTap(t),
        muted: muted,
        color: done ? c.greenL : null,
        border: done ? const Color(0xFFA8D5B5) : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HhIcon(t.icon, size: c.dnd(34, 36)),
            const SizedBox(height: 4),
            Text(
              done ? '已记' : t.label,
              style: TextStyle(fontSize: c.dnd(13, 16), fontWeight: FontWeight.w600, color: c.ink),
            ),
          ],
        ),
      );
    }

    Widget runRow(CareLog log, List<CareLogType> companions) {
      final t = CareLogType.values.byName(log.type);
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 16,
              child: _QBox(
                key: Key('running-${t.name}'),
                onTap: () => onEnd(log),
                gradient: c.runGradient,
                border: c.runBorder,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          iconSpan(t.icon, size: 18),
                          TextSpan(text: t.runningLabel),
                        ],
                      ),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.peachDeep),
                    ),
                    const SizedBox(height: 4),
                    _Ticker(
                      since: log.startedAt,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.dn(c.ink, const Color(0xFFF0C0B4))),
                    ),
                  ],
                ),
              ),
            ),
            gap,
            Expanded(
              flex: 9,
              child: _QBox(
                key: Key('end-${t.name}'),
                onTap: () => onEnd(log),
                color: c.endBg,
                border: c.endBg,
                shadow: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HhIcon(AppIcon.stop, size: 30, dim: false),
                    Text(
                      '结束',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.endInk),
                    ),
                  ],
                ),
              ),
            ),
            for (final o in companions) ...[gap, Expanded(flex: 9, child: plain(o, muted: o == CareLogType.sleep && t == CareLogType.feed))],
          ],
        ),
      );
    }

    if (active.isEmpty) {
      return Row(
        children: [
          for (final t in CareLogType.values) ...[if (t != CareLogType.feed) gap, Expanded(child: plain(t))],
        ],
      );
    }
    if (active.length == 1) {
      final t = CareLogType.values.byName(active.first.type);
      final comps = c.night ? [CareLogType.diaper] : _companions(t);
      return runRow(active.first, comps);
    }
    // 同时有多个进行中：每个一行，剩下的类型放最后一行
    final rest = CareLogType.values.where((t) => !activeTypes.contains(t)).toList();
    return Column(
      children: [
        for (final l in active) Padding(padding: const EdgeInsets.only(bottom: 10), child: runRow(l, const [])),
        Row(
          children: [
            for (final t in rest) ...[if (t != rest.first) gap, Expanded(child: plain(t))],
          ],
        ),
      ],
    );
  }
}

class _QBox extends StatelessWidget {
  const _QBox({super.key, required this.child, required this.onTap, this.color, this.gradient, this.border, this.muted = false, this.shadow = false});
  final Widget child;
  final VoidCallback onTap;
  final Color? color;
  final Gradient? gradient;
  final Color? border;
  final bool muted;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Opacity(
      opacity: muted ? .45 : 1,
      child: Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: _reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            constraints: BoxConstraints(minHeight: c.dnd(96, 116)),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            decoration: BoxDecoration(
              color: gradient == null ? (color ?? c.card) : null,
              gradient: gradient,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border ?? Colors.transparent, width: 2),
              // 日夜切换中阴影按 Hh 插值淡出（夜间为空列表）
              boxShadow: shadow ? c.primaryShadows : c.cardShadows,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.active, required this.justDiaperId, required this.justSavedId, required this.onTap});
  final List<CareLog> active;
  final String? justDiaperId;
  final String? justSavedId;
  final ValueChanged<CareLog> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final all = ref.watch(recentLogsProvider).value ?? const <CareLog>[];
    final today = DateUtils.dateOnly(AppClock.now());
    final done = all.where((l) => l.endedAt != null && !l.startedAt.isBefore(today)).toList();
    final rows = [...active, ...done];
    final hint = justDiaperId != null
        ? '换尿布不进入计时'
        : active.isNotEmpty
        ? '进行中的会置顶'
        : justSavedId != null
        ? '已写入 · 可点条目修改'
        : '喂奶 / 睡觉 / 拍嗝：开始后计时';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '今天的记录',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
              ),
              const Spacer(),
              Text(hint, style: TextStyle(fontSize: 12, color: c.sub)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text('今天还没有记录', style: TextStyle(fontSize: 13, color: c.sub)),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      _NewRowReveal(
                        key: ValueKey(rows[i].id),
                        isNew: rows[i].id == justDiaperId || rows[i].id == justSavedId,
                        child: CareLogRow(log: rows[i], last: i == rows.length - 1, fresh: rows[i].id == justDiaperId, onTap: () => onTap(rows[i])),
                      ),
                  ],
                ),
        ),
        Center(
          child: TextButton(
            onPressed: () => context.push(Routes.logs),
            child: Text('查看全部记录 ›', style: TextStyle(fontSize: 12, color: c.sub)),
          ),
        ),
      ],
    );
  }
}

class _DiaperToast extends StatelessWidget {
  const _DiaperToast({required this.onTap, required this.visible});
  final VoidCallback onTap;
  final bool visible;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    if (!visible) return ExcludeSemantics(child: _box(c));
    return Semantics(liveRegion: true, button: true, child: _box(c));
  }

  Widget _box(Hh c) {
    return GestureDetector(
      key: const Key('diaper-toast'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
          boxShadow: const [BoxShadow(color: Color(0x263C2814), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: Row(
          children: [
            const ExcludeSemantics(child: HhIcon(AppIcon.careDiaper, size: 30)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已记下换尿布',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                ),
                Text('刚刚 · 点这里可改成大便 / 小便', style: TextStyle(fontSize: 12, color: c.sub)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceHint extends StatelessWidget {
  const _VoiceHint();
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A221C)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            iconSpan(AppIcon.voice, size: 22),
            const TextSpan(text: '语音操作 '),
            TextSpan(
              text: '即将支持',
              style: TextStyle(fontWeight: FontWeight.w700, color: c.peachDeep),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: c.ink),
      ),
    );
  }
}

/// 日/夜切换图标：400ms easeInOut 交叉淡入 + 旋转 90°
/// （整页渐变需要 Hh 主题扩展真正插值，目前 Hh.lerp 是阶跃切换，所以只做图标）
class _NightIcon extends StatelessWidget {
  const _NightIcon({required this.night});
  final bool night;
  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 400),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: RotationTransition(turns: Tween(begin: -.25, end: 0.0).animate(a), child: child),
      ),
      child: HhIcon(night ? AppIcon.dayMode : AppIcon.nightMode, key: ValueKey(night), size: 24),
    );
  }
}

/// 时间线新记录：展开 240ms easeOutCubic，高亮停 1200ms 后 600ms 淡出。
/// 减少动态时直接出现，高亮静态保持（不闪）。
class _NewRowReveal extends StatefulWidget {
  const _NewRowReveal({super.key, required this.isNew, required this.child});
  final bool isNew;
  final Widget child;
  @override
  State<_NewRowReveal> createState() => _NewRowRevealState();
}

class _NewRowRevealState extends State<_NewRowReveal> {
  late bool _animateIn = widget.isNew;
  bool _glow = false;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    if (widget.isNew) _startGlow();
  }

  @override
  void didUpdateWidget(_NewRowReveal old) {
    super.didUpdateWidget(old);
    if (widget.isNew && !old.isNew) _startGlow();
  }

  void _startGlow() {
    _glow = true;
    _hold?.cancel();
    _hold = Timer(const Duration(milliseconds: 240 + 1200), () {
      if (mounted && !_reduceMotion(context)) setState(() => _glow = false);
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = _reduceMotion(context);
    final glow = still ? widget.isNew : _glow;
    final row = Stack(
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: AnimatedContainer(
              key: const Key('new-row-glow'),
              duration: still ? Duration.zero : const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: context.hh.peach2.withValues(alpha: glow ? .12 : 0),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
    if (!_animateIn || still) return row;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      onEnd: () => _animateIn = false,
      child: row,
      builder: (_, t, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: t,
          child: Opacity(opacity: t, child: child),
        ),
      ),
    );
  }
}
