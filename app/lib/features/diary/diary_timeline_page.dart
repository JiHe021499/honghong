import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/diary_repository.dart';
import '../../domain/diary/diary_card_db.dart';
import '../logs/record_editor_sheet.dart';
import 'diary_edit_sheet.dart';
import 'diary_entry_row.dart';
import 'diary_flow.dart' show diaryClockProvider;
import 'diary_widgets.dart';

/// 进入时间线时带的参数：刚保存了几条（屏 16 的提示条）
class DiaryDayArgs {
  const DiaryDayArgs({this.savedCount});
  final int? savedCount;
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// 时间线排序：单次记录按时间倒序（最新在上），汇总卡放最后（设计稿 17）
List<TimelineEntry> timelineOrder(List<TimelineEntry> entries, {Set<String> aggregates = const {}}) {
  final list = [...entries];
  list.sort((a, b) {
    final ag = aggregates.contains(a.id) ? 1 : 0, bg = aggregates.contains(b.id) ? 1 : 0;
    if (ag != bg) return ag - bg;
    return b.sortTime.compareTo(a.sortTime);
  });
  return list;
}

final dayTimelineProvider = StreamProvider.autoDispose.family<List<TimelineEntry>, DateTime>((ref, day) async* {
  final baby = await ref.watch(currentBabyProvider.future);
  yield* ref.watch(diaryRepositoryProvider).watchTimeline(baby.id, day);
});

/// 当天的汇总卡 id（排序放最后）
final aggregateIdsProvider = StreamProvider.autoDispose.family<Set<String>, DateTime>((ref, day) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.diaryCards)..where((c) => c.kind.equals('aggregate') & c.deleted.not() & c.diaryDate.equals(day)))
      .watch()
      .map((rows) => rows.map((r) => r.id).toSet());
});

final daySummaryProvider = FutureProvider.autoDispose.family<DailySummary?, DateTime>((ref, day) async {
  ref.watch(dayTimelineProvider(day));
  final baby = await ref.watch(currentBabyProvider.future);
  final s = await ref.watch(diaryRepositoryProvider).summaryOf(baby.id, day);
  return s?.status == 'ready' && (s?.content?.isNotEmpty ?? false) ? s : null;
});

/// 日记时间线（屏 16–20）：某一天的照护记录 + 日记卡，顶部近 5 天切换和今日小结。
class DiaryTimelinePage extends ConsumerStatefulWidget {
  const DiaryTimelinePage({super.key, this.date, this.args});
  final DateTime? date;
  final DiaryDayArgs? args;
  @override
  ConsumerState<DiaryTimelinePage> createState() => _DiaryTimelinePageState();
}

class _DiaryTimelinePageState extends ConsumerState<DiaryTimelinePage> {
  late DateTime today = _day(ref.read(diaryClockProvider)());
  late DateTime day = widget.date == null || _day(widget.date!).isAfter(today) ? today : _day(widget.date!);
  int? saved;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    saved = widget.args?.savedCount;
    if (saved != null) {
      _toastTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => saved = null);
      });
    }
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  String get _title {
    final d = today.difference(day).inDays;
    if (d == 0) return '今天的日记';
    if (d == 1) return '昨天的日记';
    return '${day.month} 月 ${day.day} 日的日记';
  }

  Future<void> _open(TimelineEntry e) async {
    final diary = ref.read(diaryRepositoryProvider);
    final logs = ref.read(careLogRepositoryProvider);
    if (e.isQuick) {
      // 首页快捷记录：只读，跳到“全部记录”里改
      await context.push(Routes.logs);
      return;
    }
    if (e.isCareLog) {
      final log = await logs.byId(e.id);
      if (log == null || !mounted) return;
      final baby = await ref.read(currentBabyProvider.future);
      if (!mounted) return;
      final r = await showRecordEditor(context, log: log, overlaps: (t, a, b) => logs.overlapping(baby.id, t, a, b, excludeId: log.id));
      if (r == null) return;
      if (r.delete) {
        // 编辑面板里已二次确认；日记来源的同时软删对应卡片
        await diary.deleteCareLog(log.id);
        return;
      }
      await logs.updateRecord(log.id, start: r.start!, end: r.end, detail: r.detail);
      final card = await diary.cardForCareLog(log.id);
      if (card != null) {
        await diary.updateCard(card.id, DiaryCardsCompanion(eventTime: Value(r.start), sortTime: Value(r.start!), diaryDate: Value(_day(r.start!))));
      }
      return;
    }
    final row = await diary.cardById(e.id);
    if (row == null || !mounted) return;
    final input = row.inputId == null ? null : await diary.inputById(row.inputId!);
    if (!mounted) return;
    final card = cardFromDb(row);
    final r = await showDiaryCardSheet(context, card: card, rawText: input?.rawText);
    if (r == null || !mounted) return;
    if (r.delete) {
      final ok = await confirmDiaryDelete(context, what: _describe(row));
      if (ok) await diary.deleteCard(row.id);
      return;
    }
    await diary.updateCard(row.id, r.patch!);
  }

  /// 确认框里的那一行：情绪 · 下午哭得厉害（有原话片段时用原话）
  String _describe(DiaryCard row) {
    final d = cardFromDb(row);
    if (d.note != null && d.note!.isNotEmpty) return '${d.category.label} · ${d.note}';
    final t = entryPlainText(d);
    return d.intensity == null ? t : '$t · ${d.intensity}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final entries = ref.watch(dayTimelineProvider(day)).value;
    final aggs = ref.watch(aggregateIdsProvider(day)).value ?? const {};
    final summary = ref.watch(daySummaryProvider(day)).value;
    final rows = entries == null ? null : timelineOrder(entries, aggregates: aggs);
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
            DiaryHeader(title: _title, onBack: () => context.canPop() ? context.pop() : context.go(Routes.diary)),
            const SizedBox(height: 4),
            _DayStrip(today: today, selected: day, onPick: (d) => setState(() => day = d)),
            const SizedBox(height: 12),
            if (summary != null) _SummaryCard(summary: summary),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                    child: Text('${day.month} 月 ${day.day} 日 · ${rows?.length ?? 0} 条',
                        key: const Key('tl-count'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink))),
                Text('按时间排序', style: TextStyle(fontSize: 12, color: c.sub)),
              ]),
            ),
            if (rows == null)
              const SizedBox(height: 120)
            else if (rows.isEmpty)
              _Empty(onTap: () => context.canPop() ? context.pop() : context.go(Routes.diary))
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
                child: Column(children: [
                  for (var i = 0; i < rows.length; i++)
                    DiaryEntryRow(key: Key('tl-${rows[i].id}'), entry: rows[i], last: i == rows.length - 1, onTap: () => _open(rows[i])),
                ]),
              ),
          ]),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            top: saved == null ? -120 : 8,
            left: 20,
            right: 20,
            child: saved == null ? const SizedBox() : DiaryToast(title: '已保存 $saved 条', subtitle: '在日记里可以随时修改'),
          ),
        ]),
      ),
    );
  }
}

/// 近 5 天切换（设计稿 .md-days）
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.today, required this.selected, required this.onPick});
  final DateTime today, selected;
  final ValueChanged<DateTime> onPick;
  static const _wk = ['一', '二', '三', '四', '五', '六', '日'];
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final days = [for (var i = 4; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    return Row(children: [
      for (var i = 0; i < days.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            key: Key('day-${days.length - 1 - i}'),
            onTap: () => onPick(days[i]),
            child: Builder(builder: (_) {
              final on = days[i] == selected;
              final ink = on ? Colors.white : c.ink;
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(color: on ? c.peach2 : c.card, borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  Text(_wk[days[i].weekday - 1], style: TextStyle(fontSize: 11, color: on ? Colors.white : c.sub)),
                  Text(days[i] == today ? '今天' : '${days[i].day}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink)),
                ]),
              );
            }),
          ),
        ),
      ],
    ]);
  }
}

/// 时间线顶部的今日小结（设计稿 .md-sum）；点开小结页在 P5
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final DailySummary summary;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final at = summary.generatedAt == null ? '' : ' · ${DateFormat('HH:mm').format(summary.generatedAt!)}';
    return Container(
      key: const Key('tl-summary'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: c.night ? null : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE7DB), Color(0xFFFFF1E8)]),
        color: c.night ? const Color(0xFF24130F) : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        const HhIcon(AppIcon.nightMode, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('今日小结$at', style: TextStyle(fontSize: 12, color: c.night ? const Color(0xFF8A4A42) : c.sub)),
            const SizedBox(height: 2),
            Text(summary.content ?? '',
                style: TextStyle(fontSize: 14, height: 1.55, fontWeight: FontWeight.w700, color: c.night ? const Color(0xFFE07A67) : c.ink)),
          ]),
        ),
      ]),
    );
  }
}

/// 空状态（屏 20）
class _Empty extends StatelessWidget {
  const _Empty({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return GestureDetector(
      key: const Key('tl-empty'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 36),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const HhIcon(AppIcon.soothed, size: 52),
          const SizedBox(height: 12),
          Text('这天还没有日记', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 4),
          Text('回到上一页按住说话，说一句就能记', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.sub)),
        ]),
      ),
    );
  }
}
