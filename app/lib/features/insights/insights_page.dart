import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../domain/insights.dart';
import '../../domain/models/care_log_type.dart';
import '../../domain/models/cry_cause.dart';
import '../../domain/predictor/cry_predictor.dart';
import '../family/family_card.dart';

class InsightsData {
  const InsightsData({required this.cries, required this.trend, required this.sleepHours, required this.causes, required this.fromFeedback, required this.agreement});
  final HourlyCry cries;
  final FeedTrend trend;
  final double? sleepHours;
  final List<(CryCause, double)> causes;
  final bool fromFeedback;
  final ({int total, int hits}) agreement;
}

/// 近 7 天的规律，全部从本地记录实时计算
final insightsProvider = FutureProvider<InsightsData>((ref) async {
  ref.watch(recentLogsProvider); // 记录变化时重算
  final baby = await ref.watch(currentBabyProvider.future);
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 7));
  final logs = await ref.read(careLogRepositoryProvider).since(baby.id, from);
  final cries = await ref.read(cryEventRepositoryProvider).since(baby.id, from);
  final fb = ref.read(feedbackRepositoryProvider);
  final points = [for (final l in logs) LogPoint(CareLogType.values.byName(l.type), l.startedAt, l.endedAt)];
  var causes = causeShare(await fb.causeCounts(baby.id));
  var fromFeedback = true;
  if (causes.isEmpty && cries.isNotEmpty) {
    // 还没有反馈时，用每次判断的第一名代替
    final counts = <String, int>{};
    for (final e in cries) {
      final top = Prediction.topCauseFromJson(e.predictionJson);
      if (top != null) counts[top] = (counts[top] ?? 0) + 1;
    }
    causes = causeShare(counts);
    fromFeedback = false;
  }
  return InsightsData(
    cries: cryByHour([for (final e in cries) e.startedAt]),
    trend: feedTrend(points, now),
    sleepHours: avgSleepHoursPerDay(points, now),
    causes: causes,
    fromFeedback: fromFeedback,
    agreement: await fb.top1Agreement(baby.id),
  );
});

/// 宝宝规律（设计稿 15）
class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final name = ref.watch(currentBabyProvider).value?.nickname ?? '宝宝';
    final data = ref.watch(insightsProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$name的规律', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.ink)),
              const Spacer(),
              Text('近 7 天', style: TextStyle(fontSize: 13, color: c.sub)),
            ]),
            const SizedBox(height: 16),
            ...data.when(
              loading: () => [const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))],
              error: (e, _) => [Text('出错了：$e')],
              data: (d) => _cards(context, d),
            ),
            const SizedBox(height: 10),
            const FamilyCard(linkToFamily: true),
          ],
        ),
      ),
    );
  }

  List<Widget> _cards(BuildContext context, InsightsData d) {
    final c = context.hh;
    Widget ins(AppIcon icon, String title, String sub, [Widget? extra]) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: HhCard(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                HhIcon(icon, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
                    const SizedBox(height: 4),
                    Text(sub, style: TextStyle(fontSize: 13, color: c.sub, height: 1.6)),
                  ]),
                ),
              ]),
              ?extra,
            ]),
          ),
        );

    String h1(double v) => v.toStringAsFixed(1);
    final peak = d.cries.peakHour;
    final cards = <Widget>[];

    // 1 闹的时段
    final maxCount = d.cries.counts.fold<int>(0, (a, b) => a > b ? a : b);
    cards.add(ins(
      AppIcon.insightDusk,
      peak == null ? '闹的时段：还在学习' : '通常${_period(peak)} ${_h12(peak)} 点前后闹${peak >= 15 || peak < 6 ? '觉' : ''}',
      peak == null ? '用"宝宝在哭"记下几次哭声后，这里会显示他通常几点闹' : '可以在 ${_h12((peak + 23) % 24)}:30 左右提前调暗环境、开始哄睡',
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(children: [
          SizedBox(
            height: 100,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < d.cries.hours.length; i++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    height: 22 + 78 * (maxCount == 0 ? .2 + .3 * (i % 3) / 2 : d.cries.counts[i] / maxCount),
                    decoration: BoxDecoration(
                      color: d.cries.hours[i] == peak ? c.peach : c.blueL,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text('${d.cries.hours.first}点', style: TextStyle(fontSize: 11, color: c.sub)),
            const Spacer(),
            Text('${d.cries.hours[d.cries.hours.length ~/ 2]}点', style: TextStyle(fontSize: 11, color: c.sub)),
            const Spacer(),
            Text('${d.cries.hours.last}点', style: TextStyle(fontSize: 11, color: c.sub)),
          ]),
        ]),
      ),
    ));

    // 2 喂奶间隔
    final t = d.trend;
    if (t.recent != null && t.before != null) {
      final diff = t.recent! - t.before!;
      cards.add(ins(AppIcon.careFeed, diff.abs() < .2 ? '吃奶间隔很稳定' : (diff > 0 ? '吃奶间隔在变长' : '吃奶间隔在变短'),
          '平均 ${h1(t.before!)} 小时 → ${h1(t.recent!)} 小时${diff > 0 ? '，属于正常成长变化' : ''}'));
    } else if ((t.recent ?? t.before) != null) {
      cards.add(ins(AppIcon.careFeed, '平均 ${h1((t.recent ?? t.before)!)} 小时吃一次奶', '再记几天，就能看出间隔是变长还是变短'));
    } else {
      cards.add(ins(AppIcon.careFeed, '吃奶间隔：还在学习', '记两次以上喂奶后，这里会显示平均间隔'));
    }

    // 3 最常见哭因
    if (d.causes.isNotEmpty) {
      final top = d.causes.first;
      final rest = d.causes.skip(1).take(2).map((e) => '${e.$1.label.split('/').first}（${(e.$2 * 100).round()}%）').join('与');
      cards.add(ins(AppIcon.insightTarget, '最常见的哭因：${top.$1.label.split('/').first}（${(top.$2 * 100).round()}%）',
          [if (rest.isNotEmpty) '其次是$rest', if (!d.fromFeedback) '（来自判断结果，多点反馈会更准）'].join(' ')));
    } else {
      cards.add(ins(AppIcon.insightTarget, '最常见的哭因：还在学习', '每次哄好后点一下"是什么起作用了"，这里就会越来越准'));
    }

    // 4 睡眠
    if (d.sleepHours != null) {
      cards.add(ins(AppIcon.careSleep, '平均每天记录睡眠 ${h1(d.sleepHours!)} 小时', '按已结束的睡觉记录统计，漏记会偏少'));
    }

    // 5 猜中率（核心指标）
    if (d.agreement.total > 0) {
      cards.add(ins(AppIcon.checkDone, '哄哄猜中率 ${(d.agreement.hits * 100 / d.agreement.total).round()}%',
          '第一名和你的反馈一致 ${d.agreement.hits} / ${d.agreement.total} 次'));
    }
    return cards;
  }

  static int _h12(int h) => h > 12 ? h - 12 : (h == 0 ? 12 : h);
  static String _period(int h) => h < 6 ? '凌晨' : h < 11 ? '上午' : h < 13 ? '中午' : h < 19 ? '下午' : '晚上';
}
