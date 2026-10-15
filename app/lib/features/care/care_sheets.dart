import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/care_detail.dart';
import '../../domain/models/care_log_type.dart';

class SessionEndResult {
  const SessionEndResult.resume() : resume = true, duration = Duration.zero, detail = null;
  const SessionEndResult.save(this.duration, this.detail) : resume = false;
  final bool resume;
  final Duration duration;
  final CareDetail? detail;
}

/// 喂奶/睡觉/拍嗝结束面板（设计稿 03 / 05 / 09）
Future<SessionEndResult?> showSessionEndSheet(BuildContext context, CareLog log, DateTime stoppedAt,
    {CareDetail? previous, bool editing = false}) {
  return showModalBottomSheet<SessionEndResult>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => SessionEndSheet(log: log, stoppedAt: stoppedAt, previous: previous, editing: editing),
  );
}

class SessionEndSheet extends StatefulWidget {
  const SessionEndSheet({super.key, required this.log, required this.stoppedAt, this.previous, this.editing = false});
  final CareLog log;
  final DateTime stoppedAt;
  final CareDetail? previous;
  final bool editing;

  @override
  State<SessionEndSheet> createState() => _SessionEndSheetState();
}

class _SessionEndSheetState extends State<SessionEndSheet> {
  late final type = CareLogType.values.byName(widget.log.type);
  late Duration duration = widget.stoppedAt.difference(widget.log.startedAt);
  late final CareDetail initial = widget.log.detail != null ? CareDetail.decode(widget.log.detail) : (widget.previous ?? const CareDetail());
  late FeedMethod method = initial.method ?? FeedMethod.breast;
  late FeedSide side = initial.side ?? FeedSide.left;
  late int? ml = initial.ml;
  late String? note = initial.note ?? (type == CareLogType.sleep ? _defaultSleepNote() : null);

  String _defaultSleepNote() {
    final h = widget.log.startedAt.hour;
    return (h >= 19 || h < 6) ? '夜间长觉' : '小睡';
  }

  void _adjust(int minutes) {
    final next = duration + Duration(minutes: minutes);
    setState(() => duration = next.isNegative ? Duration.zero : next);
  }

  CareDetail get _detail => switch (type) {
        CareLogType.feed => CareDetail(method: method, side: method == FeedMethod.breast ? side : null, ml: method == FeedMethod.breast ? null : ml),
        _ => CareDetail(note: note),
      };

  Future<void> _custom({required bool amount}) async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(amount ? '奶量（ml）' : '备注'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: amount ? TextInputType.number : TextInputType.text,
          inputFormatters: amount ? [FilteringTextInputFormatter.digitsOnly] : null,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    setState(() => amount ? ml = int.tryParse(v) : note = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final hm = DateFormat('HH:mm');
    final end = widget.log.startedAt.add(duration);
    final title = '${type.label}${widget.editing ? '记录' : '结束'}';
    final hint = switch (type) {
      CareLogType.sleep => '醒来了吗?',
      _ => widget.editing ? '可修改' : '计时已写入，可改',
    };
    final resumeLabel = switch (type) {
      CareLogType.feed => '继续喂',
      CareLogType.sleep => '还在睡',
      _ => '继续拍',
    };
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(s, style: TextStyle(fontSize: 13, color: c.sub)),
        );

    final mins = duration.inMinutes, secs = duration.inSeconds % 60;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetGrab(),
          Row(children: [
            IconTile(type.icon, size: 48, radius: 16, fontSize: 26, bg: typeTint(c, type.name)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: 2),
                Text('${hm.format(widget.log.startedAt)} – ${hm.format(end)} · $hint', style: TextStyle(fontSize: 13, color: c.sub)),
              ]),
            ),
          ]),
          if (!widget.editing)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: c.greenL, borderRadius: BorderRadius.circular(20)),
              child: Text.rich(TextSpan(children: [iconSpan(AppIcon.checkSmall, size: 14, gap: 3), const TextSpan(text: '已停止计时')]), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.greenInk)),
            ),
          if (type == CareLogType.feed) ...[
            label('方式'),
            HhSegmented<FeedMethod>(values: FeedMethod.values, label: (m) => m.label, selected: method, onChanged: (m) => setState(() => method = m)),
            if (method == FeedMethod.breast) ...[
              label('哪一侧'),
              HhSegmented<FeedSide>(values: FeedSide.values, label: (s) => s.label, selected: side, onChanged: (s) => setState(() => side = s)),
            ],
          ],
          label(type == CareLogType.sleep ? '睡眠时长（可微调）' : '时长（可微调）'),
          Row(children: [
            _RoundBtn(icon: AppIcon.remove, onTap: () => _adjust(-1), key: const Key('dur-minus')),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$mins', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800)),
                  TextSpan(text: ' 分 ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.sub)),
                  TextSpan(text: '$secs', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  TextSpan(text: ' 秒', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.sub)),
                ]),
                key: const Key('duration-text'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.ink, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            _RoundBtn(icon: AppIcon.add, onTap: () => _adjust(1), key: const Key('dur-plus')),
          ]),
          if (type == CareLogType.feed && method != FeedMethod.breast) ...[
            label('奶量（瓶喂时填写）'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in CareDetail.feedAmounts) HhChip(label: '${a}ml', on: ml == a, onTap: () => setState(() => ml = a)),
              HhChip(
                  label: ml != null && !CareDetail.feedAmounts.contains(ml) ? '${ml}ml' : '自定义',
                  on: ml != null && !CareDetail.feedAmounts.contains(ml),
                  onTap: () => _custom(amount: true)),
            ]),
          ],
          if (type != CareLogType.feed) ...[
            label('备注（可选）'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in type == CareLogType.sleep ? CareDetail.sleepNotes : CareDetail.burpNotes)
                HhChip(label: n, on: note == n, onTap: () => setState(() => note = note == n ? null : n)),
              HhChip(
                label: note != null && !(type == CareLogType.sleep ? CareDetail.sleepNotes : CareDetail.burpNotes).contains(note) ? note! : '自定义',
                on: note != null && !(type == CareLogType.sleep ? CareDetail.sleepNotes : CareDetail.burpNotes).contains(note),
                onTap: () => _custom(amount: false),
              ),
            ]),
          ],
          const SizedBox(height: 26),
          Row(children: [
            Expanded(
              flex: 9,
              child: HhButton(
                label: widget.editing ? '取消' : resumeLabel,
                primary: false,
                onPressed: () => Navigator.pop(context, widget.editing ? null : const SessionEndResult.resume()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 11,
              child: HhButton(label: '保存记录', onPressed: () => Navigator.pop(context, SessionEndResult.save(duration, _detail))),
            ),
          ]),
          if (!widget.editing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(child: Text('关掉面板等于"${resumeLabel.replaceAll('还在', '继续')}"，不会丢计时。', style: TextStyle(fontSize: 12, color: c.sub))),
            ),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({super.key, required this.icon, required this.onTap});
  final AppIcon icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Material(
      color: c.card,
      shape: const CircleBorder(),
      elevation: c.dnd(1, 0),
      shadowColor: const Color(0x22000000),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(dimension: 56, child: Center(child: HhIcon(icon, size: 28))),
      ),
    );
  }
}

/// 换尿布补充（设计稿 07）。返回 null 表示保持原样。
Future<DiaperKind?> showDiaperSheet(BuildContext context, CareLog log) {
  return showModalBottomSheet<DiaperKind>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => _DiaperSheet(log: log),
  );
}

class _DiaperSheet extends StatefulWidget {
  const _DiaperSheet({required this.log});
  final CareLog log;
  @override
  State<_DiaperSheet> createState() => _DiaperSheetState();
}

class _DiaperSheetState extends State<_DiaperSheet> {
  late DiaperKind kind = () {
    final k = CareDetail.decode(widget.log.detail).diaper;
    return k == null || k == DiaperKind.unknown ? DiaperKind.pee : k;
  }();

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetGrab(),
          Row(children: [
            IconTile(AppIcon.careDiaper, size: 48, radius: 16, fontSize: 26, bg: c.greenL),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('换尿布', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: 2),
              Text('已记在 ${DateFormat('HH:mm').format(widget.log.startedAt)} · 可改类型，也可跳过', style: TextStyle(fontSize: 13, color: c.sub)),
            ]),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 10),
            child: Text('类型', style: TextStyle(fontSize: 13, color: c.sub)),
          ),
          HhSegmented<DiaperKind>(
            values: const [DiaperKind.pee, DiaperKind.poo, DiaperKind.both, DiaperKind.dry],
            label: (k) => k.label,
            selected: kind,
            onChanged: (k) => setState(() => kind = k),
          ),
          const SizedBox(height: 26),
          Row(children: [
            Expanded(flex: 9, child: HhButton(label: '保持原样', primary: false, onPressed: () => Navigator.pop(context))),
            const SizedBox(width: 12),
            Expanded(flex: 11, child: HhButton(label: '更新', onPressed: () => Navigator.pop(context, kind))),
          ]),
          const SizedBox(height: 12),
          Center(child: Text('默认一点即记、不打断；想补细节再点 toast 或时间线条目。', style: TextStyle(fontSize: 12, color: c.sub))),
        ],
      ),
    );
  }
}
