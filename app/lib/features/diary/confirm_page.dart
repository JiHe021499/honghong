import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../domain/diary/diary_card.dart';
import '../../domain/diary/parse_result.dart';
import 'diary_providers.dart';
import '../../services/diary/diary_metrics.dart';
import 'diary_widgets.dart';
import '../../core/app_clock.dart';

/// 确认页返回这个值表示“改原文”
const kEditRaw = -1;

/// 屏 11–15：确认页。卡片默认全选、就地编辑、全不选置灰、失败 other、风险提示。返回保存条数。
class ConfirmPage extends ConsumerStatefulWidget {
  const ConfirmPage({super.key, required this.result});
  final ParseResult result;
  @override
  ConsumerState<ConfirmPage> createState() => _ConfirmPageState();
}

class _ConfirmPageState extends ConsumerState<ConfirmPage> {
  ParseResult get r => widget.result;
  int? open;
  bool saving = false;

  int get picked => r.cards.where((c) => c.selected).length;

  Future<void> _save() async {
    if (picked == 0 || saving) return;
    setState(() => saving = true);
    try {
      final baby = await ref.read(currentBabyProvider.future);
      final age = r.createdAt.difference(baby.birthDate).inDays.clamp(0, 3 * 366);
      final n = await ref.read(diaryServiceProvider).save(babyId: baby.id, ageInDays: age, r: r);
      final changed = r.cards.where((c) => c.edited || !c.selected).length;
      final m = ref.read(diaryMetricsProvider);
      await m.add(DiaryMetric.save);
      if (changed == 0) await m.add(DiaryMetric.saveOneTap);
      await m.add(DiaryMetric.cards, r.cards.length);
      await m.add(DiaryMetric.cardsChanged, changed);
      if (mounted) context.pop(n);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存没成功，请再试一次')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), children: [
            DiaryHeader(title: '帮你整理好了', onBack: () => context.pop()),
            const SizedBox(height: 8),
            _RawBox(text: r.rawText, onEdit: () => context.pop(kEditRaw)),
            if (r.offline)
              const DiaryWarn(text: '还没开通自动整理，原话先存成一条“其他”，可点开改分类和内容。')
            else if (r.failed)
              const DiaryWarn(text: '这次没能自动整理，原话先存成一条“其他”，不会丢。'),
            if (r.risk) const DiaryWarn(key: Key('risk-warn'), text: '如有担心，请及时就医。', blue: true),
            for (var i = 0; i < r.cards.length; i++)
              _ConfirmCard(
                key: Key('card-$i'),
                card: r.cards[i],
                open: open == i,
                onToggle: () => setState(() => r.cards[i].selected = !r.cards[i].selected),
                onOpen: () => setState(() => open = open == i ? null : i),
                onChanged: () => setState(() => r.cards[i].edited = true),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('点卡片可就地修改 · 取消勾选的不会保存', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.sub)),
            ),
          ]),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0, .35], colors: [c.bg.withValues(alpha: 0), c.bg]),
              ),
              child: picked == 0
                  ? Container(
                      key: const Key('save-disabled'),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(color: c.dn(const Color(0xFFEDE5DC), c.card), borderRadius: BorderRadius.circular(16)),
                      child: Text('请至少勾选一条',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.dn(const Color(0xFFB3A99F), c.sub))),
                    )
                  : HhButton(key: const Key('save'), label: saving ? '正在保存…' : '保存 $picked 条', onPressed: saving ? null : _save),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RawBox extends StatelessWidget {
  const _RawBox({required this.text, required this.onEdit});
  final String text;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final ink = c.dn(const Color(0xFF4E7FAE), c.blueInk);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: c.blueL, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('你说的是', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink)),
        Text.rich(TextSpan(children: [
          TextSpan(text: '“$text”'),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              key: const Key('edit-raw'),
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text('改原文', style: TextStyle(fontSize: 12, color: ink, decoration: TextDecoration.underline, decorationColor: ink)),
              ),
            ),
          ),
        ]), style: TextStyle(fontSize: 14, height: 1.6, color: c.ink)),
      ]),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({super.key, required this.card, required this.open, required this.onToggle, required this.onOpen, required this.onChanged});
  final DiaryCardDraftUi card;
  final bool open;
  final VoidCallback onToggle, onOpen, onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final t = cardText(card);
    final badges = <Widget>[
      if (card.needsReview) const _Badge('请核对'),
      if (card.duplicate) const _Badge('首页已记过一次，是否还要保存？'),
      if (card.sleepConflict) const _Badge('已有进行中的睡眠，请核对'),
    ];
    final head = Opacity(
      opacity: card.selected ? 1 : .45,
      child: Row(children: [
        GestureDetector(
          key: const Key('check'),
          onTap: onToggle,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: card.selected ? c.peach2 : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: card.selected ? c.peach2 : const Color(0xFFD8CEC4), width: 2),
            ),
            child: card.selected ? const Text('✓', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, height: 1)) : null,
          ),
        ),
        const SizedBox(width: 10),
        CategoryTile(card.category),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: t.main), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
              if (t.sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(t.sub, style: TextStyle(fontSize: 12, color: c.sub))),
              for (final b in badges) Padding(padding: const EdgeInsets.only(top: 4), child: b),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        Text(cardTimeLabel(card), style: TextStyle(fontSize: 12, color: c.sub)),
        if (!open) ...[const SizedBox(width: 6), GestureDetector(onTap: onOpen, child: const HhIcon(AppIcon.edit, size: 16))],
      ]),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: open ? c.peach : Colors.transparent, width: 2),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(children: [head, if (open) _Editor(card: card, onChanged: onChanged, onFold: onOpen)]),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: markBg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: markInk)),
      );
}

/// 就地编辑（屏 12）
class _Editor extends StatefulWidget {
  const _Editor({required this.card, required this.onChanged, required this.onFold});
  final DiaryCardDraftUi card;
  final VoidCallback onChanged, onFold;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  DiaryCardDraftUi get card => widget.card;

  void _set(void Function() f) {
    setState(f);
    widget.onChanged();
  }

  void _category(DiaryCategory cat) => _set(() {
        card.category = cat;
        card.attributes = sanitizeAttributes(cat, card.attributes, () {});
        if (!cat.isCare) card.aggregate = false;
      });

  ({String key, String label, String unit})? get _numField => switch (card.category) {
        DiaryCategory.feeding => (key: 'count', label: '次数', unit: '次'),
        DiaryCategory.sleep => (key: 'duration_min', label: '时长', unit: '分钟'),
        DiaryCategory.diaper => (key: 'count', label: '次数', unit: '次'),
        _ => null,
      };

  String get _timeText {
    final day = card.diaryDate.difference(DateTime(AppClock.now().year, AppClock.now().month, AppClock.now().day)).inDays == -1 ? '昨天' : '今天';
    if (card.aggregate) return '$day · 当日汇总';
    return '$day · ${cardTimeLabel(card)}';
  }

  Future<void> _pickTime() async {
    final init = card.eventTime ?? card.sortTime;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(init));
    if (t == null) return;
    final d = card.diaryDate;
    final at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    _set(() {
      card.eventTime = at;
      card.sortTime = at;
      card.aggregate = false;
      card.period = null;
    });
  }

  void _day(int offset) {
    final now = AppClock.now();
    final d = DateTime(now.year, now.month, now.day + offset);
    _set(() {
      DateTime move(DateTime t) => DateTime(d.year, d.month, d.day, t.hour, t.minute);
      card.diaryDate = d;
      if (card.eventTime != null) card.eventTime = move(card.eventTime!);
      card.sortTime = move(card.sortTime);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    Widget lab(String s) => Padding(padding: const EdgeInsets.only(top: 10, bottom: 6), child: Text(s, style: TextStyle(fontSize: 13, color: c.sub)));
    final nf = _numField;
    final isYesterday = card.diaryDate.isBefore(DateTime(AppClock.now().year, AppClock.now().month, AppClock.now().day));
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        lab('分类'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in DiaryCategory.values) HhChip(key: Key('cat-${k.name}'), label: k.label, on: k == card.category, onTap: () => _category(k)),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (nf != null) ...[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                lab(nf.label),
                _Input(
                  key: Key('num-${nf.key}'),
                  initial: card.intAttr(nf.key)?.toString() ?? '',
                  suffix: nf.unit,
                  number: true,
                  onChanged: (v) => _set(() {
                    final n = int.tryParse(v);
                    if (n == null || n <= 0) {
                      card.attributes.remove(nf.key);
                    } else {
                      card.attributes[nf.key] = n;
                    }
                  }),
                ),
              ]),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              lab('时间'),
              GestureDetector(key: const Key('pick-time'), onTap: _pickTime, child: _Box(text: _timeText)),
            ]),
          ),
        ]),
        lab('日期'),
        HhSegmented<int>(values: const [0, -1], label: (v) => v == 0 ? '今天' : '昨天', selected: isYesterday ? -1 : 0, onChanged: _day),
        lab('备注'),
        _Input(key: const Key('note'), initial: card.note ?? '', hint: '比如：亲喂为主', onChanged: (v) => _set(() => card.note = v.trim().isEmpty ? null : v.trim())),
        Center(
          child: TextButton(
            key: const Key('fold'),
            onPressed: widget.onFold,
            child: Text('完成，收起 ⌃', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.peach2)),
          ),
        ),
      ]),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.peach, width: 1.5)),
      child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
    );
  }
}

class _Input extends StatefulWidget {
  const _Input({super.key, required this.initial, required this.onChanged, this.suffix, this.hint, this.number = false});
  final String initial;
  final ValueChanged<String> onChanged;
  final String? suffix, hint;
  final bool number;
  @override
  State<_Input> createState() => _InputState();
}

class _InputState extends State<_Input> {
  late final ctl = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final filled = ctl.text.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: filled ? c.peach : c.line, width: 1.5)),
      child: TextField(
        controller: ctl,
        keyboardType: widget.number ? TextInputType.number : TextInputType.text,
        inputFormatters: widget.number ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)] : [LengthLimitingTextInputFormatter(200)],
        onChanged: (v) {
          setState(() {});
          widget.onChanged(v);
        },
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Color(0xFFC2B9B0), fontWeight: FontWeight.w400),
          suffixText: widget.suffix,
        ),
      ),
    );
  }
}
