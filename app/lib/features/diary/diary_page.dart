import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/repositories/diary_repository.dart';
import '../../domain/diary/parse_result.dart';
import 'confirm_page.dart' show kEditRaw;
import 'diary_entry_row.dart';
import 'diary_timeline_page.dart' show DiaryDayArgs, aggregateIdsProvider, timelineOrder;
import 'diary_flow.dart';
import 'diary_providers.dart';
import 'diary_sheets.dart';
import 'diary_widgets.dart';
import '../../services/diary/voice_capture.dart';

enum MicState { idle, recording, cancelZone, processing }

/// 妈咪日记主页（设计稿 3–9、16 的提示条）
class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key});
  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends ConsumerState<DiaryPage> {
  MicState mic = MicState.idle;
  String live = '';
  DateTime? _startedAt;
  Duration elapsed = Duration.zero;
  Timer? _tick;
  Offset? _down;
  bool _starting = false;

  /// 本机识别这次打开里已经失败/不可用过：之后（已同意时）直接走联网识别
  bool _systemBroken = false;

  /// 当前这次按住用的是哪个识别
  VoiceCapture? _capture;

  /// 上滑超过这个距离进入“松手取消”
  static const cancelDy = 80.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAskGender();
      ref.read(summaryTriggerProvider).kick();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (mic == MicState.recording || mic == MicState.cancelZone) (_capture ?? ref.read(voiceCaptureProvider))!.cancel();
    super.dispose();
  }

  Future<void> _maybeAskGender() async {
    final prefs = ref.read(prefsProvider);
    if (prefs.getBool(kDiaryGenderPrompted) ?? false) return;
    final baby = await ref.read(currentBabyProvider.future);
    if (baby.gender != null || !mounted) return;
    final days = DateTime.now().difference(baby.birthDate).inDays;
    final g = await showGenderSheet(context, nickname: baby.nickname, days: days);
    await prefs.setBool(kDiaryGenderPrompted, true);
    if (g != null) {
      await ref.read(babyRepositoryProvider).updateGender(baby.id, g);
      ref.invalidate(currentBabyProvider);
    }
  }

  DateTime _now() => ref.read(diaryClockProvider)();

  // ── 按住说话 ──
  Future<void> _pressDown(Offset pos) async {
    if (mic != MicState.idle || _starting) return;
    _starting = true;
    _down = pos;
    setState(() {
      mic = MicState.recording;
      live = '';
      elapsed = Duration.zero;
      _startedAt = _now();
    });
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && _startedAt != null) setState(() => elapsed = _now().difference(_startedAt!));
    });
    final cloud = ref.read(cloudVoiceCaptureProvider);
    final useCloud = _systemBroken && cloud != null && _consent == true;
    final VoiceCapture cap = useCloud ? cloud : ref.read(voiceCaptureProvider);
    _capture = cap;
    final ok = await cap.start(onPartial: (t) {
      if (mounted) setState(() => live = t);
    });
    _starting = false;
    if (!ok && mounted) {
      _reset();
      await _recognizerFailed(cap);
    }
  }

  void _move(Offset pos) {
    if (_down == null || (mic != MicState.recording && mic != MicState.cancelZone)) return;
    final up = _down!.dy - pos.dy;
    final next = up > cancelDy ? MicState.cancelZone : MicState.recording;
    if (next != mic) setState(() => mic = next);
  }

  Future<void> _release() async {
    final VoiceCapture voice = _capture ?? ref.read(voiceCaptureProvider);
    final started = _startedAt;
    if (mic == MicState.cancelZone) {
      await voice.cancel();
      _reset();
      return;
    }
    if (mic != MicState.recording) return;
    final held = started == null ? Duration.zero : _now().difference(started);
    _tick?.cancel();
    if (held < const Duration(seconds: 1)) {
      await voice.cancel();
      _reset();
      _snack('说长一点试试');
      return;
    }
    setState(() => mic = MicState.processing);
    final text = await voice.stop();
    if (!mounted) return;
    if (text.isEmpty) {
      _reset();
      return voice.failed ? _recognizerFailed(voice) : _voiceFailed();
    }
    setState(() => live = text);
    await _process(text, 'voice');
  }

  void _reset() {
    _tick?.cancel();
    _down = null;
    _startedAt = null;
    if (mounted) setState(() => mic = MicState.idle);
  }

  bool? get _consent => ref.read(cloudAsrConsentProvider);

  /// 识别引擎不可用/出错：本机的 → 联网识别兜底（首次先告知）；联网的 → 屏 9。
  Future<void> _recognizerFailed(VoiceCapture cap) async {
    final cloud = ref.read(cloudVoiceCaptureProvider);
    if (identical(cap, cloud) || cloud == null) return _voiceFailed();
    final firstSwitch = !_systemBroken;
    _systemBroken = true;
    switch (_consent) {
      case null:
        final ok = await showCloudAsrConsentSheet(context);
        if (!mounted) return;
        if (ok == true) {
          await ref.read(cloudAsrConsentProvider.notifier).set(true);
          _snack('已换成联网识别，请再按住说一次');
        } else {
          if (ok == false) await ref.read(cloudAsrConsentProvider.notifier).set(false);
          await _openText();
        }
      case true:
        if (firstSwitch) {
          _snack('本机识别不可用，已换成联网识别，请再说一次');
        } else {
          await _voiceFailed();
        }
      case false:
        await _voiceFailed();
    }
  }

  Future<void> _voiceFailed() async {
    final toText = await showVoiceErrorSheet(context);
    if (toText == true && mounted) await _openText();
  }

  Future<void> _process(String text, String inputType) async {
    final out = await ref.read(diaryFlowProvider).process(text, inputType: inputType);
    if (!mounted) return;
    _reset();
    switch (out) {
      case NetworkDraft(:final text):
        _snack('网络不太好，文字已保留，稍后再试');
        await _openText(initial: text);
      case GoConfirm(:final result):
        await _confirm(result);
    }
  }

  Future<void> _confirm(ParseResult r) async {
    final saved = await context.push<int>(Routes.diaryConfirm, extra: r);
    if (saved == kEditRaw) return _openText(initial: r.rawText);
    if (saved != null && saved > 0) _afterSave(saved);
  }

  Future<void> _openText({String? initial}) async {
    final saved = await context.push<int>(Routes.diaryText, extra: initial);
    if (saved != null && saved > 0) _afterSave(saved);
  }

  /// 保存成功 → 进入当日时间线并提示（屏 16）
  void _afterSave(int n) {
    if (!mounted) return;
    context.push(Routes.diaryDay, extra: DiaryDayArgs(savedCount: n));
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final baby = ref.watch(currentBabyProvider).value;
    final days = baby == null ? null : DateTime.now().difference(baby.birthDate).inDays;
    final entries = ref.watch(todayDiaryProvider).value ?? const <TimelineEntry>[];
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
            DiaryHeader(title: '妈咪日记', onBack: () => context.canPop() ? context.pop() : context.go(Routes.home)),
            if (baby != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${baby.nickname} · 出生第 $days 天', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.sub)),
              ),
            _MicArea(
              state: mic,
              live: live,
              elapsed: elapsed,
              onDown: _pressDown,
              onMove: _move,
              onUp: _release,
            ),
            if (mic == MicState.idle) _AltButton(onTap: () => _openText()),
            const SizedBox(height: 14),
            _TodayList(entries: entries),
          ]),
        ]),
      ),
    );
  }
}

class _MicArea extends StatelessWidget {
  const _MicArea({required this.state, required this.live, required this.elapsed, required this.onDown, required this.onMove, required this.onUp});
  final MicState state;
  final String live;
  final Duration elapsed;
  final void Function(Offset) onDown, onMove;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final top = switch (state) {
      MicState.idle => const SizedBox(),
      MicState.recording => _Bubble(children: [
          const _Wave(),
          Text('${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
              key: const Key('rec-timer'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.ink, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 4),
          Text(live.isEmpty ? '正在听…' : '“$live…”', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.5, color: c.sub)),
        ]),
      MicState.cancelZone => Container(
          key: const Key('cancel-zone'),
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.night ? c.peachL : const Color(0xFFF8E6E0),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE0A08E), width: 1.5),
          ),
          child: Column(children: [
            const HhIcon(AppIcon.close, size: 32),
            const SizedBox(height: 4),
            const Text('松手取消', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFFB4573F))),
            Text('这句话不会被记录', style: TextStyle(fontSize: 13, color: c.sub)),
          ]),
        ),
      MicState.processing => _Bubble(children: [
          Text('“$live”', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.5, color: c.ink)),
          const SizedBox(height: 12),
          const _Dots(),
          const SizedBox(height: 8),
          Text('正在帮你整理成卡片…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.sub)),
        ]),
    };
    final big = state == MicState.idle;
    final gray = state == MicState.cancelZone || state == MicState.processing;
    final label = switch (state) {
      MicState.idle => '按住说话',
      MicState.recording => '松开 结束',
      MicState.cancelZone => '松开 取消',
      MicState.processing => '整理中',
    };
    final size = big ? 200.0 : 150.0;
    final ring = c.night ? const Color(0xFFA03228) : c.peach2;
    final button = Listener(
      key: const Key('diary-mic'),
      onPointerDown: (e) => onDown(e.position),
      onPointerMove: (e) => onMove(e.position),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: gray ? (c.night ? c.card : const Color(0xFFE6DDD3)) : null,
          gradient: gray ? null : RadialGradient(center: const Alignment(-.3, -.4), radius: .9, colors: [c.cryFrom, c.cryTo]),
          boxShadow: gray
              ? null
              : [
                  if (!c.night && big) const BoxShadow(color: Color(0x59FF7850), blurRadius: 30, offset: Offset(0, 14)),
                  BoxShadow(color: ring.withValues(alpha: big ? .08 : .1), spreadRadius: big ? 32 : 44),
                  BoxShadow(color: ring.withValues(alpha: big ? .15 : .22), spreadRadius: big ? 16 : 22),
                ],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: c.night ? const Color(0xFF2A1814) : const Color(0xFFFFF8F0), shape: BoxShape.circle),
            child: HhIcon(AppIcon.voice, size: big ? 40 : 36),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: big ? 24 : 17, fontWeight: FontWeight.w700, color: gray ? c.sub : c.cryInk)),
          if (big)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                width: 150,
                child: Text('比如“上午喂了两次奶，拉了一次”',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.4, color: c.cryInk.withValues(alpha: .95))),
              ),
            ),
        ]),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 318),
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          top,
          if (state == MicState.recording) Padding(padding: const EdgeInsets.only(top: 14), child: Text('↑ 上滑取消', style: TextStyle(fontSize: 13, color: c.sub))),
          SizedBox(height: state == MicState.idle ? 40 : 30),
          button,
          SizedBox(height: big ? 34 : 46),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: c.shadow, blurRadius: 12, offset: const Offset(0, 3))]),
      child: Column(children: children),
    );
  }
}

/// 录音波形（设计稿 .wave，10 根竖条）
class _Wave extends StatefulWidget {
  const _Wave();
  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  static const _h = [18.0, 34, 52, 30, 58, 40, 22, 48, 28, 16];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.hh.peach2;
    return SizedBox(
      height: 60,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < _h.length; i++)
            Container(
              width: 5,
              height: _h[i] * (.6 + .4 * math.sin(_c.value * 2 * math.pi + i)).abs(),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
            ),
        ]),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots();
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 0; i < 3; i++)
        Container(width: 9, height: 9, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: c.peach2, shape: BoxShape.circle)),
    ]);
  }
}

class _AltButton extends StatelessWidget {
  const _AltButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Center(
      child: GestureDetector(
        key: const Key('diary-type'),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 18, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const HhIcon(AppIcon.keyboard, size: 20),
            const SizedBox(width: 8),
            Text('不方便出声？打字记录', style: TextStyle(fontSize: 13, color: c.ink)),
          ]),
        ),
      ),
    );
  }
}

/// 今天的日记：日记卡 + 首页快捷记录（标“快捷记录”）
class _TodayList extends ConsumerWidget {
  const _TodayList({required this.entries});
  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final title = Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Text('今天的日记', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink))),
        if (entries.isNotEmpty)
          GestureDetector(
            key: const Key('diary-all'),
            onTap: () => context.push(Routes.diaryDay),
            child: Text('查看全部 ›', style: TextStyle(fontSize: 12, color: c.sub)),
          ),
      ]),
    );
    if (entries.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        title,
        Container(
          key: const Key('diary-empty'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const HhIcon(AppIcon.soothed, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '今天还没有日记\n', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
                const TextSpan(text: '按住上面的按钮，说一句宝宝的情况'),
              ]), style: TextStyle(fontSize: 13, height: 1.5, color: c.sub)),
            ),
          ]),
        ),
      ]);
    }
    final now = DateTime.now();
    final aggs = ref.watch(aggregateIdsProvider(DateTime(now.year, now.month, now.day))).value ?? const <String>{};
    final rows = timelineOrder(entries, aggregates: aggs).take(2).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title,
      Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [for (var i = 0; i < rows.length; i++) DiaryEntryRow(entry: rows[i], last: i == rows.length - 1)]),
      ),
    ]);
  }
}

