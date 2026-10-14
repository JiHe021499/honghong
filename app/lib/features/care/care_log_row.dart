import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/care_detail.dart';
import '../../domain/models/care_log_type.dart';
import '../../core/app_clock.dart';

/// 首页「今天的记录」和「全部记录」共用的记录行（设计稿 19）：
/// 图标 | 第一行 类型 · 关键细节（加粗）/ 第二行 次要信息（时长、侧别、奶量、尿布类型）| 右侧时间列右对齐
/// 计时类显示 起–止，换尿布显示时刻；进行中显示"07:27 开始"和走秒徽章并高亮。
class CareLogRow extends ConsumerWidget {
  const CareLogRow({super.key, required this.log, this.last = false, this.fresh = false, this.onTap, this.now});
  final CareLog log;
  final bool last, fresh;
  final VoidCallback? onTap;

  /// 测试用固定时钟
  final DateTime Function()? now;

  static final _hm = DateFormat('HH:mm');

  static String timeLabel(CareLog l) {
    if (l.endedAt == null) return '${_hm.format(l.startedAt)} 开始';
    if (l.endedAt == l.startedAt) return _hm.format(l.startedAt);
    return '${_hm.format(l.startedAt)}–${_hm.format(l.endedAt!)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final t = CareLogType.values.byName(log.type);
    final live = log.endedAt == null;
    if (live) ref.watch(secondTickerProvider);
    final highlight = live || fresh;
    final lines = live ? (title: t.runningLabel, subtitle: '') : logLines(t, log.startedAt, log.endedAt, log.detail);
    final badge = live
        ? _Badge('计时 ${formatTimer((now?.call() ?? AppClock.now()).difference(log.startedAt))}', c.peachL, c.peach2)
        : fresh
            ? _Badge('刚刚', const Color(0xFFD4EDDC), c.greenInk)
            : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: !highlight ? null : (fresh ? c.greenL : c.liveRow),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: highlight || last ? null : Border(bottom: BorderSide(color: c.line))),
          child: LayoutBuilder(builder: (context, box) {
            final timeStyle = TextStyle(fontSize: 13, color: c.sub, fontFeatures: const [FontFeature.tabularFigures()]);
            final timeText = timeLabel(log);
            final tp = TextPainter(
              text: TextSpan(text: '00:00–00:00', style: DefaultTextStyle.of(context).style.merge(timeStyle)), // 按最宽的起止时间判断，保证每行一致
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            // 图标 + 间距约 64；时间列超过剩余宽度的 45%（大字号/窄屏）时所有行都改成时间单独一行
            final stacked = tp.width > (box.maxWidth - 64) * 0.45;
            tp.dispose();
            final time = Text(timeText, key: const Key('row-time'), textAlign: TextAlign.right, maxLines: 1, style: timeStyle);
            return Row(children: [
              IconTile(t.icon, bg: typeTint(c, log.type)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(lines.title,
                      key: const Key('row-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
                  if (badge != null || lines.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                      if (badge != null) ...[badge, if (lines.subtitle.isNotEmpty) const SizedBox(width: 6)],
                      if (lines.subtitle.isNotEmpty)
                        Flexible(
                          child: Text(lines.subtitle,
                              key: const Key('row-subtitle'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: c.sub)),
                        ),
                    ]),
                  ],
                  if (stacked) ...[const SizedBox(height: 2), time],
                ]),
              ),
              if (!stacked) ...[const SizedBox(width: 10), time],
            ]);
          }),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.bg, this.fg);
  final String text;
  final Color bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
      );
}
