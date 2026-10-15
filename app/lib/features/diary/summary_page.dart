import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/diary/diary_card.dart';
import 'diary_providers.dart';
import 'diary_sheets.dart' show diaryDisclaimer;
import '../../services/diary/diary_metrics.dart';
import '../../domain/diary/summary_service.dart';
import 'diary_widgets.dart';

const _nightInk = Color(0xFFE07A67);
const _nightSub = Color(0xFF8A4A42);
const _wk = ['一', '二', '三', '四', '五', '六', '日'];

/// 今日小结（屏 21–23）。夜间模式沿用暗红夜间配色（屏 22）。
class SummaryPage extends ConsumerWidget {
  const SummaryPage({super.key, this.date});
  final DateTime? date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final n = ref.watch(summaryClockProvider)();
    final day = DateTime((date ?? n).year, (date ?? n).month, (date ?? n).day);
    final isToday = day == DateTime(n.year, n.month, n.day);
    final s = ref.watch(summaryRowProvider(day));
    final row = s.value;
    final sub = c.dn(c.sub, _nightSub);
    void goDay() => context.push('${Routes.diaryDay}?date=${DateFormat('yyyy-MM-dd').format(day)}');
    final body = <Widget>[
      DiaryHeader(title: isToday ? '今日小结' : '${day.month} 月 ${day.day} 日小结', onBack: () => context.canPop() ? context.pop() : context.go(Routes.diary)),
    ];
    if (s.isLoading && row == null) {
      body.add(const SizedBox(height: 300));
    } else if (row?.status == 'empty') {
      // 屏 23：当天无记录
      body.addAll([
        const _Moon(icon: AppIcon.soothed),
        Text('${day.month} 月 ${day.day} 日 · ${_time(row)}', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: sub)),
        _Big(isToday ? '今天没有日记也没关系，照顾好宝宝和自己就是最重要的事。' : '这天没有日记也没关系，照顾好宝宝和自己就是最重要的事。'),
        HhButton(key: const Key('sum-add'), label: '补记一句', onPressed: () => context.push(Routes.diary)),
      ]);
    } else if (row?.status == 'ready') {
      if (isToday) Future.microtask(() => ref.read(diaryMetricsProvider).add(DiaryMetric.summaryView));
      final stats = _stats(row!);
      final n = (jsonDecode(row.sourceIds) as List?)?.length ?? 0;
      body.addAll([
        const _Moon(icon: AppIcon.nightMode),
        Text('${day.month} 月 ${day.day} 日 · 星期${_wk[day.weekday - 1]} · ${_time(row)}',
            key: const Key('sum-date'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: sub)),
        _Big(row.content ?? '', key: const Key('sum-content')),
        _Facts(facts: summaryFacts(stats)),
        const SizedBox(height: 10),
        Text('只根据${isToday ? '今天' : '这天'}保存的 $n 条记录生成', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.5, color: sub)),
        const SizedBox(height: 16),
        HhButton(key: const Key('sum-day'), label: isToday ? '看今天的日记' : '看这天的日记', primary: false, onPressed: goDay),
        const SizedBox(height: 12),
        Text(diaryDisclaimer,
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, height: 1.6, color: sub)),
      ]);
    } else if (SummaryService.needsManualRetry(row)) {
      body.addAll([
        const _Moon(icon: AppIcon.nightMode),
        const _Big('小结暂时没生成好', key: Key('sum-failed')),
        HhButton(key: const Key('sum-retry'), label: '点此重试', onPressed: () => ref.read(summaryTriggerProvider).retry(day)),
        const SizedBox(height: 12),
        HhButton(key: const Key('sum-day'), label: isToday ? '看今天的日记' : '看这天的日记', primary: false, onPressed: goDay),
      ]);
    } else {
      // 还没生成 / 生成失败（不显示错误，只说还在整理，架构 §5.3）
      body.addAll([
        const _Moon(icon: AppIcon.nightMode),
        _Big(isToday ? '今晚小结还在整理' : '这天的小结还在整理', key: const Key('sum-pending')),
        Text(isToday ? '每天 21:00 后打开哄哄，会自动帮你写好今天的小结' : '下次打开哄哄时会再试一次', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.5, color: sub)),
        const SizedBox(height: 16),
        HhButton(key: const Key('sum-day'), label: isToday ? '看今天的日记' : '看这天的日记', primary: false, onPressed: goDay),
      ]);
    }
    return Scaffold(
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: body)),
    );
  }

  static String _time(DailySummary? r) => DateFormat('HH:mm').format(r?.generatedAt ?? DateTime(2000, 1, 1, 21));
  static Map<String, dynamic> _stats(DailySummary r) {
    try {
      return Map<String, dynamic>.from(jsonDecode(r.statsJson) as Map);
    } catch (_) {
      return const {};
    }
  }
}

/// 小结页四格（设计稿 .md-facts）：来自生成时的统计快照，之后删改记录不变（D8）。
List<({AppIcon icon, String value, String label})> summaryFacts(Map<String, dynamic> s) {
  final out = <({AppIcon icon, String value, String label})>[];
  final feed = s['feed'] as Map?;
  if (feed != null) {
    final n = (feed['count'] as int?) ?? 0;
    final agg = feed['aggregate_count'] as int?;
    out.add((icon: AppIcon.careFeed, value: n > 0 ? '$n 次' : '$agg 次', label: '喂奶'));
  }
  final sleep = s['sleep'] as Map?;
  final min = (sleep?['total_min'] as int?) ?? 0;
  if (min > 0) {
    final v = min < 60 ? '$min 分钟' : (min % 60 == 0 ? '${min ~/ 60} 小时' : '${min ~/ 60} 小时多');
    out.add((icon: AppIcon.careSleep, value: v, label: '睡眠'));
  }
  final diaper = s['diaper'] as Map?;
  if (diaper != null) {
    final poo = (diaper['poo'] as int?) ?? 0;
    out.add(poo > 0 ? (icon: AppIcon.careDiaper, value: '$poo 次', label: '便便') : (icon: AppIcon.careDiaper, value: '${diaper['count']} 次', label: '尿布'));
  }
  final mood = s['mood'] as List?;
  if (mood != null && mood.isNotEmpty) {
    final m = Map<String, dynamic>.from(mood.first as Map);
    final p = DiaryPeriod.parse(m['period']);
    out.add((icon: AppIcon.causeHoldMe, value: p == null || p == DiaryPeriod.allDay ? (m['intensity'] as String? ?? '有') : p.label, label: (m['type'] as String?) ?? '情绪'));
  }
  return out.take(4).toList();
}

class _Moon extends StatelessWidget {
  const _Moon({required this.icon});
  final AppIcon icon;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final inner = c.dn(const Color(0xFFFFE7DB), const Color(0xFF2A1814));
    final outer = c.dn(const Color(0x00FFE7DB), const Color(0x00120C0C));
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 24, bottom: 8),
        width: 140,
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [inner, outer], stops: const [0, .7])),
        child: HhIcon(icon, size: 84),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 20),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 21, height: 1.6, fontWeight: FontWeight.w700, color: c.dn(c.ink, _nightInk))),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.facts});
  final List<({AppIcon icon, String value, String label})> facts;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    if (facts.isEmpty) return const SizedBox();
    return Row(children: [
      for (var i = 0; i < 4; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: i >= facts.length
              ? const SizedBox()
              : Container(
                  key: Key('fact-$i'),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  decoration: BoxDecoration(
                    color: c.dn(c.card, const Color(0xFF1F1210)),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: c.dnShadows(const [BoxShadow(color: Color(0x0FA0785A), blurRadius: 10, offset: Offset(0, 3))], null),
                  ),
                  child: Column(children: [
                    HhIcon(facts[i].icon, size: 28),
                    const SizedBox(height: 4),
                    Text(facts[i].value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.dn(c.ink, _nightInk))),
                    Text(facts[i].label, style: TextStyle(fontSize: 11, color: c.dn(c.sub, _nightSub))),
                  ]),
                ),
        ),
      ],
    ]);
  }
}
