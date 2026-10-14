import 'dart:async';

import 'package:flutter/material.dart';
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
import '../diary/diary_entry_card.dart';

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
      if (next != null && GoRouterState.of(context).uri.path == Routes.home) {
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
        _QuickGrid(
          active: active,
          justDiaper: _toastVisible,
          onTap: (t) => _tapType(t, active),
          onEnd: _end,
        ),
        if (night) const _VoiceHint() else ...[
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
        child: Stack(children: [
          body,
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            top: _toastVisible ? 8 : -120,
            left: 20,
            right: 20,
            child: _DiaperToast(onTap: _editDiaper),
          ),
        ]),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final baby = ref.watch(currentBabyProvider).value;
    final days = baby == null ? null : DateTime.now().difference(DateUtils.dateOnly(baby.birthDate)).inDays;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.night ? c.card : c.peachL, shape: BoxShape.circle),
          child: const HhIcon(AppIcon.avatarBaby, size: 30),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(baby?.nickname ?? '', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.night ? c.peachDeep : c.ink)),
            Text(c.night ? '夜间模式 · 亮度已调低' : (days == null ? '' : '出生第 $days 天'),
                style: TextStyle(fontSize: 12, color: c.sub)),
          ]),
        ),
        GestureDetector(
          onTap: () => ref.read(nightModeProvider.notifier).toggle(),
          child: Container(
            key: const Key('night-toggle'),
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.night ? c.card : Colors.white,
              shape: BoxShape.circle,
              boxShadow: c.night ? null : const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: HhIcon(c.night ? AppIcon.dayMode : AppIcon.nightMode, size: 24),
          ),
        ),
      ]),
    );
  }
}

String _ago(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m分钟';
  return '$h小时$m分';
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar({required this.active});
  final List<CareLog> active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final emStyle = TextStyle(fontWeight: FontWeight.w700, color: active.isEmpty ? c.blueInk : (c.night ? c.peachDeep : c.peach2));
    final base = TextStyle(fontSize: 14, color: c.statusInk, height: 1.3);

    if (active.isNotEmpty) {
      ref.watch(secondTickerProvider);
      final now = DateTime.now();
      final first = active.first;
      final t = CareLogType.values.byName(first.type);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: c.night ? null : const LinearGradient(colors: [Color(0xFFFFE7DB), Color(0xFFFFF1E8)]),
          color: c.night ? c.statusBg : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.night ? const Color(0xFF4A221C) : const Color(0x59FF9874)),
        ),
        child: Row(children: [
          const PulseDot(),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(style: base, children: [
                if (!c.night) iconSpan(t.icon, size: 18),
                TextSpan(text: '${t.runningLabel} · ${c.night ? '' : '已进行 '}'),
                TextSpan(text: formatTimer(now.difference(first.startedAt)), style: emStyle),
                if (!c.night) const TextSpan(text: ' · 点「结束」保存'),
                if (active.length > 1) TextSpan(text: '  +${active.length - 1}'),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      );
    }

    ref.watch(clockProvider);
    final latest = ref.watch(latestLogsProvider).value ?? const {};
    final now = DateTime.now();
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
      spans.addAll([
        iconSpan(AppIcon.careAwake),
        const TextSpan(text: '已醒 '),
        TextSpan(text: _ago(now.difference(sleep!.endedAt!)), style: emStyle),
      ]);
    }
    if (spans.isEmpty) spans.addAll([iconSpan(AppIcon.waveHello), const TextSpan(text: '还没有记录，喂奶、睡觉点一下就开始计时')]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: c.statusBg, borderRadius: BorderRadius.circular(16)),
      child: Text.rich(TextSpan(style: base, children: spans), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _CryButton extends StatelessWidget {
  const _CryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final size = c.night ? 230.0 : 200.0;
    final ring = c.night ? const Color(0xFFA03228) : c.peach2;
    return Padding(
      padding: EdgeInsets.only(top: c.night ? 44 : 38, bottom: c.night ? 40 : 0),
      child: Center(
        child: GestureDetector(
          key: const Key('cry-button'),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(center: const Alignment(-.3, -.4), radius: .9, colors: [c.cryFrom, c.cryTo]),
              boxShadow: [
                if (!c.night) const BoxShadow(color: Color(0x59FF7850), blurRadius: 30, offset: Offset(0, 14)),
                BoxShadow(color: ring.withValues(alpha: c.night ? .06 : .08), spreadRadius: c.night ? 36 : 32),
                BoxShadow(color: ring.withValues(alpha: c.night ? .12 : .15), spreadRadius: c.night ? 18 : 16),
              ],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('宝宝在哭', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.cryInk)),
              const SizedBox(height: 6),
              Text(c.night ? '轻点就开始听' : '点一下，帮你听听',
                  style: TextStyle(fontSize: 13, color: c.cryInk.withValues(alpha: .9))),
            ]),
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
      child: GestureDetector(
        onTap: () => ref.read(autoListenProvider.notifier).set(!on),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _MiniSwitch(on: on),
          const SizedBox(width: 10),
          Text('自动监听哭声 · $text', style: TextStyle(fontSize: 13, color: c.sub)),
        ]),
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
      child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
    );
  }
}

class _QuickGrid extends ConsumerWidget {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final gap = SizedBox(width: c.night ? 12 : 10);
    if (active.isNotEmpty) ref.watch(secondTickerProvider);
    final activeTypes = {for (final l in active) CareLogType.values.byName(l.type)};

    Widget plain(CareLogType t, {bool muted = false}) {
      final done = t == CareLogType.diaper && justDiaper;
      return _QBox(
        key: Key('quick-${t.name}'),
        onTap: () => onTap(t),
        muted: muted,
        color: done ? c.greenL : null,
        border: done ? const Color(0xFFA8D5B5) : null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          HhIcon(t.icon, size: c.night ? 36 : 34),
          const SizedBox(height: 4),
          Text(done ? '已记' : t.label, style: TextStyle(fontSize: c.night ? 16 : 13, fontWeight: FontWeight.w600, color: c.night ? c.ink : c.ink)),
        ]),
      );
    }

    Widget runRow(CareLog log, List<CareLogType> companions) {
      final t = CareLogType.values.byName(log.type);
      final elapsed = DateTime.now().difference(log.startedAt);
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 16,
            child: _QBox(
              key: Key('running-${t.name}'),
              onTap: () => onEnd(log),
              gradient: c.night ? null : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF4EE), Color(0xFFFFE7DB)]),
              color: c.night ? c.runBg : null,
              border: c.runBorder,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text.rich(TextSpan(children: [iconSpan(t.icon, size: 18), TextSpan(text: t.runningLabel)]), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.peachDeep)),
                const SizedBox(height: 4),
                Text(formatTimer(elapsed),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.night ? const Color(0xFFF0C0B4) : c.ink, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
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
              shadow: !c.night,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const HhIcon(AppIcon.stop, size: 30, dim: false),
                Text('结束', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.endInk)),
              ]),
            ),
          ),
          for (final o in companions) ...[gap, Expanded(flex: 9, child: plain(o, muted: o == CareLogType.sleep && t == CareLogType.feed))],
        ]),
      );
    }

    if (active.isEmpty) {
      return Row(children: [
        for (final t in CareLogType.values) ...[if (t != CareLogType.feed) gap, Expanded(child: plain(t))],
      ]);
    }
    if (active.length == 1) {
      final t = CareLogType.values.byName(active.first.type);
      final comps = c.night ? [CareLogType.diaper] : _companions(t);
      return runRow(active.first, comps);
    }
    // 同时有多个进行中：每个一行，剩下的类型放最后一行
    final rest = CareLogType.values.where((t) => !activeTypes.contains(t)).toList();
    return Column(children: [
      for (final l in active) Padding(padding: const EdgeInsets.only(bottom: 10), child: runRow(l, const [])),
      Row(children: [for (final t in rest) ...[if (t != rest.first) gap, Expanded(child: plain(t))]]),
    ]);
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
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: c.night ? 116 : 96),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          decoration: BoxDecoration(
            color: gradient == null ? (color ?? c.card) : null,
            gradient: gradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border ?? Colors.transparent, width: 2),
            boxShadow: c.night
                ? null
                : [
                    shadow
                        ? const BoxShadow(color: Color(0x47FF7850), blurRadius: 16, offset: Offset(0, 6))
                        : BoxShadow(color: c.shadow, blurRadius: 10, offset: const Offset(0, 3)),
                  ],
          ),
          child: child,
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
    final today = DateUtils.dateOnly(DateTime.now());
    final done = all.where((l) => l.endedAt != null && !l.startedAt.isBefore(today)).toList();
    final rows = [...active, ...done];
    final hint = justDiaperId != null
        ? '换尿布不进入计时'
        : active.isNotEmpty
            ? '进行中的会置顶'
            : justSavedId != null
                ? '已写入 · 可点条目修改'
                : '喂奶 / 睡觉 / 拍嗝：开始后计时';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('今天的记录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
          const Spacer(),
          Text(hint, style: TextStyle(fontSize: 12, color: c.sub)),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('今天还没有记录', style: TextStyle(fontSize: 13, color: c.sub))),
              )
            : Column(children: [
                for (var i = 0; i < rows.length; i++)
                  CareLogRow(
                    log: rows[i],
                    last: i == rows.length - 1,
                    fresh: rows[i].id == justDiaperId,
                    onTap: () => onTap(rows[i]),
                  ),
              ]),
      ),
      Center(
        child: TextButton(
          onPressed: () => context.push(Routes.logs),
          child: Text('查看全部记录 ›', style: TextStyle(fontSize: 12, color: c.sub)),
        ),
      ),
    ]);
  }
}

class _DiaperToast extends StatelessWidget {
  const _DiaperToast({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
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
        child: Row(children: [
          const HhIcon(AppIcon.careDiaper, size: 30),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('已记下换尿布', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
            Text('刚刚 · 点这里可改成大便 / 小便', style: TextStyle(fontSize: 12, color: c.sub)),
          ]),
        ]),
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
        TextSpan(children: [
          iconSpan(AppIcon.voice, size: 22),
          const TextSpan(text: '语音操作 '),
          TextSpan(text: '即将支持', style: TextStyle(fontWeight: FontWeight.w700, color: c.peachDeep)),
        ]),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: c.ink),
      ),
    );
  }
}
