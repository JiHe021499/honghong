import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/care_detail.dart';
import '../../domain/models/care_log_type.dart';
import '../../data/repositories/care_log_repository.dart';

/// 补记 / 修改面板的结果
class RecordEditResult {
  const RecordEditResult.save(this.type, this.start, this.end, this.detail) : delete = false;
  const RecordEditResult.delete()
      : delete = true,
        type = CareLogType.feed,
        start = null,
        end = null,
        detail = null;
  final bool delete;
  final CareLogType type;
  final DateTime? start;
  final DateTime? end;
  final CareDetail? detail;
}

typedef OverlapCheck = Future<List<CareLog>> Function(CareLogType type, DateTime start, DateTime end);

/// 全部记录里的「补记」（log == null）和「修改」（含时间、删除）。设计稿 18。
Future<RecordEditResult?> showRecordEditor(BuildContext context,
    {CareLog? log, required OverlapCheck overlaps, DateTime? now}) {
  return showModalBottomSheet<RecordEditResult>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => RecordEditorSheet(log: log, overlaps: overlaps, now: now),
  );
}

class RecordEditorSheet extends StatefulWidget {
  const RecordEditorSheet({super.key, this.log, required this.overlaps, this.now});
  final CareLog? log;
  final OverlapCheck overlaps;
  final DateTime? now;

  @override
  State<RecordEditorSheet> createState() => _RecordEditorSheetState();
}

class _RecordEditorSheetState extends State<RecordEditorSheet> {
  bool get editing => widget.log != null;
  DateTime get _now => widget.now ?? DateTime.now();

  static Duration _defaultLen(CareLogType t) => switch (t) {
        CareLogType.feed => const Duration(minutes: 20),
        CareLogType.sleep => const Duration(hours: 1),
        CareLogType.burp => const Duration(minutes: 10),
        CareLogType.diaper => Duration.zero,
      };

  late CareLogType type;
  late DateTime start;
  late DateTime end;
  late FeedMethod method;
  late FeedSide side;
  int? ml;
  String? note;
  late DiaperKind diaper;
  List<CareLog> clashes = const [];

  @override
  void initState() {
    super.initState();
    final l = widget.log;
    final n = _now;
    final minute = DateTime(n.year, n.month, n.day, n.hour, n.minute);
    type = l == null ? CareLogType.feed : CareLogType.values.byName(l.type);
    end = l?.endedAt ?? minute;
    start = l?.startedAt ?? (type.isTimed ? end.subtract(_defaultLen(type)) : end);
    final d = CareDetail.decode(l?.detail);
    method = d.method ?? FeedMethod.breast;
    side = d.side ?? FeedSide.left;
    ml = d.ml;
    note = d.note;
    diaper = d.diaper == null || d.diaper == DiaperKind.unknown ? DiaperKind.pee : d.diaper!;
    _check();
  }

  String? get error => CareLogRepository.validateTimes(type, start, type.isTimed ? end : null, now: _now);

  Future<void> _check() async {
    if (error != null) {
      if (mounted) setState(() => clashes = const []);
      return;
    }
    final (a, b) = type.isTimed
        ? (start, end)
        : (start.subtract(const Duration(minutes: 5)), start.add(const Duration(minutes: 5)));
    final r = await widget.overlaps(type, a, b);
    if (mounted) setState(() => clashes = r.where((x) => x.id != widget.log?.id).toList());
  }

  void _setType(CareLogType t) {
    setState(() {
      type = t;
      note = null;
      if (t.isTimed) {
        start = end.subtract(_defaultLen(t));
      } else {
        start = end;
      }
    });
    _check();
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _now.subtract(const Duration(days: 365)),
      lastDate: _now,
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _pickStart() async {
    final v = await _pick(start);
    if (v == null) return;
    setState(() {
      final len = end.difference(start);
      start = v;
      if (!type.isTimed) {
        end = v;
      } else if (!end.isAfter(v)) {
        end = v.add(len > Duration.zero ? len : _defaultLen(type));
        if (end.isAfter(_now)) end = DateTime(_now.year, _now.month, _now.day, _now.hour, _now.minute);
      }
    });
    _check();
  }

  Future<void> _pickEnd() async {
    final v = await _pick(end);
    if (v == null) return;
    setState(() => end = v);
    _check();
  }

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

  CareDetail get _detail => switch (type) {
        CareLogType.feed => CareDetail(
            method: method, side: method == FeedMethod.breast ? side : null, ml: method == FeedMethod.breast ? null : ml),
        CareLogType.diaper => CareDetail(diaper: diaper),
        _ => CareDetail(note: note),
      };

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('加入家庭时，家人那边也会一起删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(key: const Key('confirm-delete'), onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, const RecordEditResult.delete());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final fmt = DateFormat('M月d日 HH:mm');
    final hm = DateFormat('HH:mm');
    final err = error;
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(s, style: TextStyle(fontSize: 13, color: c.sub)),
        );
    Widget timeRow(String name, DateTime v, VoidCallback onTap, Key key) => InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
                color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line, width: 1.5)),
            child: Row(children: [
              Text(name, style: TextStyle(fontSize: 14, color: c.sub)),
              const Spacer(),
              Text(fmt.format(v), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
              Text('  ›', style: TextStyle(fontSize: 16, color: c.sub)),
            ]),
          ),
        );
    final len = end.difference(start);
    final notes = type == CareLogType.sleep ? CareDetail.sleepNotes : CareDetail.burpNotes;
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
                Text(editing ? '修改${type.label}记录' : '补记一条', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: 2),
                Text(editing ? '可改时间和细节' : '忘了点？选好类型和时间补上', style: TextStyle(fontSize: 13, color: c.sub)),
              ]),
            ),
          ]),
          if (!editing) ...[
            label('类型'),
            HhSegmented<CareLogType>(
              values: const [CareLogType.feed, CareLogType.sleep, CareLogType.burp, CareLogType.diaper],
              label: (t) => t.label,
              selected: type,
              onChanged: _setType,
            ),
          ],
          label(type.isTimed ? '时间' : '换的时间'),
          timeRow(type.isTimed ? '开始' : '时间', start, _pickStart, const Key('pick-start')),
          if (type.isTimed) timeRow('结束', end, _pickEnd, const Key('pick-end')),
          if (type.isTimed && err == null)
            Text('共 ${len.inHours > 0 ? '${len.inHours} 小时 ' : ''}${len.inMinutes % 60} 分钟',
                key: const Key('backfill-len'), style: TextStyle(fontSize: 13, color: c.sub)),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(err, key: const Key('backfill-error'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.peachDeep)),
            ),
          if (err == null && clashes.isNotEmpty)
            Container(
              key: const Key('backfill-overlap'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFFFF1C9), borderRadius: BorderRadius.circular(12)),
              child: Text(
                type.isTimed
                    ? '和已有的${type.label}（${clashes.map((x) => '${hm.format(x.startedAt)}–${x.endedAt == null ? '进行中' : hm.format(x.endedAt!)}').join('、')}）时间重叠，确认不是重复再保存'
                    : '${hm.format(clashes.first.startedAt)} 已经记过一次换尿布，确认不是重复再保存',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A6A12)),
              ),
            ),
          if (type == CareLogType.feed) ...[
            label('方式'),
            HhSegmented<FeedMethod>(values: FeedMethod.values, label: (m) => m.label, selected: method, onChanged: (m) => setState(() => method = m)),
            if (method == FeedMethod.breast) ...[
              label('哪一侧'),
              HhSegmented<FeedSide>(values: FeedSide.values, label: (s) => s.label, selected: side, onChanged: (s) => setState(() => side = s)),
            ] else ...[
              label('奶量'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in CareDetail.feedAmounts) HhChip(label: '${a}ml', on: ml == a, onTap: () => setState(() => ml = a)),
                HhChip(
                    label: ml != null && !CareDetail.feedAmounts.contains(ml) ? '${ml}ml' : '自定义',
                    on: ml != null && !CareDetail.feedAmounts.contains(ml),
                    onTap: () => _custom(amount: true)),
              ]),
            ],
          ],
          if (type == CareLogType.diaper) ...[
            label('尿布类型'),
            HhSegmented<DiaperKind>(
              values: const [DiaperKind.pee, DiaperKind.poo, DiaperKind.both, DiaperKind.dry],
              label: (k) => k.label,
              selected: diaper,
              onChanged: (k) => setState(() => diaper = k),
            ),
          ],
          if (type == CareLogType.sleep || type == CareLogType.burp) ...[
            label('备注（可选）'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in notes) HhChip(label: n, on: note == n, onTap: () => setState(() => note = note == n ? null : n)),
              HhChip(
                label: note != null && !notes.contains(note) ? note! : '自定义',
                on: note != null && !notes.contains(note),
                onTap: () => _custom(amount: false),
              ),
            ]),
          ],
          const SizedBox(height: 26),
          Row(children: [
            Expanded(flex: 9, child: HhButton(label: '取消', primary: false, onPressed: () => Navigator.pop(context))),
            const SizedBox(width: 12),
            Expanded(
              flex: 11,
              child: HhButton(
                key: const Key('backfill-save'),
                label: editing ? '保存修改' : '补记',
                onPressed: err != null
                    ? null
                    : () => Navigator.pop(context, RecordEditResult.save(type, start, type.isTimed ? end : start, _detail)),
              ),
            ),
          ]),
          if (editing)
            Center(
              child: TextButton(
                key: const Key('record-delete'),
                onPressed: _delete,
                child: Text('删除这条记录', style: TextStyle(color: c.peachDeep, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}
