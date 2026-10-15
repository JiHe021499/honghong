import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../domain/diary/diary_card.dart';
import '../../domain/models/care_detail.dart';
import '../cry/recording_page.dart' show CircleBack;

/// 二级页标题栏：圆形返回 + 居中标题（设计稿 .hd + .md-hdt）
class DiaryHeader extends StatelessWidget {
  const DiaryHeader({super.key, required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return SizedBox(
      height: 52,
      child: Stack(alignment: Alignment.center, children: [
        Align(alignment: Alignment.centerLeft, child: CircleBack(key: const Key('diary-back'), onTap: onBack)),
        Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.dn(c.ink, c.peachDeep))),
      ]),
    );
  }
}

/// 分类图标与底色（设计稿 CAT）
({AppIcon icon, Color bg}) categoryStyle(BuildContext context, DiaryCategory cat) {
  final c = context.hh;
  return (icon: _icons[cat]!, bg: c.dn(_bgs[cat]!, c.peachL));
}

const _icons = {
  DiaryCategory.feeding: AppIcon.careFeed,
  DiaryCategory.sleep: AppIcon.careSleep,
  DiaryCategory.diaper: AppIcon.careDiaper,
  DiaryCategory.mood: AppIcon.causeHoldMe,
  DiaryCategory.other: AppIcon.tip,
};
const _bgs = {
  DiaryCategory.feeding: Color(0xFFFFE7DB),
  DiaryCategory.sleep: Color(0xFFE3EEF8),
  DiaryCategory.diaper: Color(0xFFE6F4EA),
  DiaryCategory.mood: Color(0xFFFFF0C9),
  DiaryCategory.other: Color(0xFFF3EAE1),
};

/// 程度词高亮（设计稿 mark）
const markBg = Color(0xFFFFF0C9);
const markInk = Color(0xFF9A6A1E);

InlineSpan markSpan(String text) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: markBg, borderRadius: BorderRadius.circular(5)),
        child: Text(text, style: const TextStyle(color: markInk, fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );

/// 小标签：快捷记录 / 汇总 / 进行中（设计稿 .md-tag）
class DiaryTag extends StatelessWidget {
  const DiaryTag(this.text, {super.key, this.quick = false});
  final String text;
  final bool quick;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: quick ? c.seg : c.blueL, borderRadius: BorderRadius.circular(9)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: quick ? c.sub : c.blueInk)),
    );
  }
}

/// 黄/蓝提示条（设计稿 .md-warn / .md-blue）
class DiaryWarn extends StatelessWidget {
  const DiaryWarn({super.key, required this.text, this.blue = false});
  final String text;
  final bool blue;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: blue ? c.blueL : c.dn(markBg, c.peachL), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        HhIcon(blue ? AppIcon.tip : AppIcon.signalError, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  fontWeight: blue ? FontWeight.w700 : FontWeight.w400,
                  color: blue ? c.dn(const Color(0xFF3F6A94), c.blueInk) : c.dn(const Color(0xFF7A5A20), c.ink))),
        ),
      ]),
    );
  }
}

/// 顶部提示条（设计稿 .toast）：已保存 N 条
class DiaryToast extends StatelessWidget {
  const DiaryToast({super.key, required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Container(
      key: const Key('diary-toast'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
        boxShadow: const [BoxShadow(color: Color(0x263C2814), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(children: [
        const HhIcon(AppIcon.checkDone, size: 28),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
          Text(subtitle, style: TextStyle(fontSize: 12, color: c.sub)),
        ]),
      ]),
    );
  }
}

final _hm = DateFormat('HH:mm');

/// 卡片右侧的时间标签：钟点 / 时段 / 当日 / 刚刚
String cardTimeLabel(DiaryCardDraftUi c) {
  if (c.aggregate) return '当日';
  if (c.eventTime != null) return _hm.format(c.eventTime!);
  if (c.period != null) return c.period!.label;
  return '刚刚';
}

String _dur(int min) => min < 60 ? '$min 分钟' : (min % 60 == 0 ? '${min ~/ 60} 小时' : '${min ~/ 60} 小时 ${min % 60} 分');

/// 卡片标题（分类 · 要点）与副标题，按设计稿 11 的写法
({List<InlineSpan> main, String sub}) cardText(DiaryCardDraftUi c) {
  final parts = <String>[];
  final subs = <String>[];
  String quote() => c.note == null || c.note!.isEmpty ? '' : '原话“${c.note}”';
  switch (c.category) {
    case DiaryCategory.feeding:
      final n = c.intAttr('count');
      if (n != null) parts.add('$n 次');
      if (c.feedMethod != null) parts.add(c.feedMethod!.label);
      if (c.feedSide != null) parts.add(c.feedSide!.label);
      if (c.intAttr('ml') != null) parts.add('${c.intAttr('ml')} ml');
      if (c.intAttr('duration_min') != null) parts.add(_dur(c.intAttr('duration_min')!));
      if (c.aggregate) subs.add('今天汇总');
      if (c.feedMethod == null && c.intAttr('ml') == null) subs.add('未提到方式和奶量');
    case DiaryCategory.sleep:
      if (c.intAttr('duration_min') != null) parts.add(_dur(c.intAttr('duration_min')!));
      if (c.eventTime != null && c.endTime != null) parts.add('${_hm.format(c.eventTime!)}–${_hm.format(c.endTime!)}');
      if (c.intAttr('night_wakings') != null) parts.add('夜醒 ${c.intAttr('night_wakings')} 次');
      if (c.sleepOngoing) parts.add('进行中');
      subs.add(quote());
    case DiaryCategory.diaper:
      final k = c.diaperKind;
      if (k != null) parts.add(switch (k) { DiaperKind.pee => '小便', DiaperKind.poo => '便便', DiaperKind.both => '尿和便', _ => k.label });
      if (c.strAttr('texture_note') != null) parts.add(c.strAttr('texture_note')!);
      subs.add(c.intAttr('count') != null ? '${c.intAttr('count')} 次' : quote());
    case DiaryCategory.mood:
      if (c.strAttr('type') != null) parts.add(c.strAttr('type')!);
      subs.add(quote());
    case DiaryCategory.other:
      if (c.strAttr('topic') != null) parts.add(c.strAttr('topic')!);
      subs.add(quote());
  }
  final main = <InlineSpan>[TextSpan(text: c.category.label)];
  for (final p in parts) {
    main.add(TextSpan(text: ' · $p'));
  }
  if (c.intensity != null && c.intensity!.isNotEmpty) {
    main
      ..add(const TextSpan(text: ' · '))
      ..add(markSpan(c.intensity!));
  }
  if (parts.isEmpty && c.intensity == null && c.category == DiaryCategory.other) main.add(const TextSpan(text: ' · 原话已保留'));
  return (main: main, sub: subs.where((s) => s.isNotEmpty).join(' · '));
}

/// 分类图标小方块
class CategoryTile extends StatelessWidget {
  const CategoryTile(this.cat, {super.key, this.size = 34});
  final DiaryCategory cat;
  final double size;
  @override
  Widget build(BuildContext context) {
    final s = categoryStyle(context, cat);
    return IconTile(s.icon, size: size, bg: s.bg, fontSize: 17);
  }
}
