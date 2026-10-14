import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/diary_repository.dart';
import '../../domain/diary/diary_card.dart';
import '../../domain/diary/diary_card_db.dart';
import 'diary_widgets.dart';

/// 时间线一行的展示数据（日记主页“今天的日记”和日记时间线共用）
typedef EntryDetail = ({String text, String? mark, String time, DiaryCategory cat, bool aggregate});

final entryDetailProvider = FutureProvider.autoDispose.family<EntryDetail, TimelineEntry>((ref, e) async {
  final db = ref.watch(databaseProvider);
  final hm = DateFormat('HH:mm');
  if (e.isCareLog) {
    final log = await ref.watch(careLogRepositoryProvider).byId(e.id);
    final cat = switch (e.type) {
      'feed' => DiaryCategory.feeding,
      'sleep' => DiaryCategory.sleep,
      'diaper' => DiaryCategory.diaper,
      _ => DiaryCategory.other,
    };
    if (log == null) return (text: cat.label, mark: null, time: hm.format(e.sortTime), cat: cat, aggregate: false);
    final card = await ref.watch(diaryRepositoryProvider).cardForCareLog(log.id);
    final d = DiaryCardDraftUi(
      category: cat,
      aggregate: false,
      eventTime: log.startedAt,
      endTime: log.endedAt == log.startedAt ? null : log.endedAt,
      diaryDate: log.startedAt,
      sortTime: log.startedAt,
      attributes: _attrsFromLog(e.type, log.detail, log.startedAt, log.endedAt),
      note: card?.note,
      intensity: card?.intensity,
    );
    return (text: entryPlainText(d), mark: d.intensity, time: hm.format(log.startedAt), cat: cat, aggregate: false);
  }
  final card = await (db.select(db.diaryCards)..where((x) => x.id.equals(e.id))).getSingleOrNull();
  final cat = DiaryCategory.parse(card?.category);
  if (card == null) return (text: cat.label, mark: null, time: '', cat: cat, aggregate: false);
  final d = cardFromDb(card);
  return (text: entryPlainText(d), mark: d.intensity, time: cardTimeLabel(d), cat: cat, aggregate: d.aggregate);
});

Map<String, Object?> _attrsFromLog(String type, String? detail, DateTime s, DateTime? e) {
  final m = <String, Object?>{};
  final j = detail == null ? null : _tryJson(detail);
  if (type == 'feed') {
    if (j?['method'] == 'breast') m['method'] = 'breast';
    if (j?['method'] == 'bottleBreast') m['method'] = 'bottle_breast';
    if (j?['method'] == 'formula') m['method'] = 'formula';
    if (j?['side'] is String) m['side'] = j!['side'];
    if (j?['ml'] is int) m['ml'] = j!['ml'];
  }
  if (type == 'diaper' && j?['diaper'] is String && ['pee', 'poo', 'both'].contains(j!['diaper'])) m['type'] = j['diaper'];
  if (e != null && e != s && (type == 'feed' || type == 'sleep')) m['duration_min'] = e.difference(s).inMinutes;
  return m;
}

Map<String, dynamic>? _tryJson(String s) {
  try {
    return Map<String, dynamic>.from(jsonDecode(s) as Map);
  } catch (_) {
    return null;
  }
}

String entryPlainText(DiaryCardDraftUi d) {
  final t = cardText(d);
  return t.main.whereType<TextSpan>().map((s) => s.text ?? '').join().replaceAll(RegExp(r' · $'), '');
}

class DiaryEntryRow extends ConsumerWidget {
  const DiaryEntryRow({super.key, required this.entry, required this.last, this.onTap});
  final VoidCallback? onTap;
  final TimelineEntry entry;
  final bool last;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final d = ref.watch(entryDetailProvider(entry)).value;
    if (d == null) return const SizedBox(height: 44);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            CategoryTile(d.cat, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: d.text),
                    if (d.mark != null) ...[const TextSpan(text: ' · '), markSpan(d.mark!)],
                    if (entry.isQuick) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: DiaryTag('快捷记录', quick: true)),
                    if (d.aggregate) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: DiaryTag('汇总')),
                  ],
                ),
                style: TextStyle(fontSize: 14, color: c.ink),
              ),
            ),
            Text(d.time, style: TextStyle(fontSize: 12, color: c.sub)),
          ],
        ),
      ),
    );
  }
}
