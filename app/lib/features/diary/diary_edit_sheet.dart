import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/diary/diary_card.dart';
import 'diary_widgets.dart';

/// 时间线 · 编辑日记卡（屏 18）的结果：保存的改动，或删除
class CardEditResult {
  const CardEditResult.save(this.patch) : delete = false;
  const CardEditResult.delete()
      : delete = true,
        patch = null;
  final bool delete;
  final DiaryCardsCompanion? patch;
}

const moodTypes = ['哭闹', '哄不好', '开心'];
const intensities = ['一点', '明显', '厉害'];
const periods = [DiaryPeriod.morning, DiaryPeriod.afternoon, DiaryPeriod.evening, DiaryPeriod.night];

/// 不落 care_logs 的日记卡（情绪、其他、汇总、只存卡片的睡眠）在时间线上的编辑面板。
/// 版式沿用补记 sheet：图标 + 标题 + 来源原话，分段选择，底部“删除 / 保存修改”。
Future<CardEditResult?> showDiaryCardSheet(BuildContext context, {required DiaryCardDraftUi card, String? rawText}) {
  return showModalBottomSheet<CardEditResult>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DiaryCardSheet(card: card, rawText: rawText),
  );
}

class DiaryCardSheet extends StatefulWidget {
  const DiaryCardSheet({super.key, required this.card, this.rawText});
  final DiaryCardDraftUi card;
  final String? rawText;
  @override
  State<DiaryCardSheet> createState() => _DiaryCardSheetState();
}

class _DiaryCardSheetState extends State<DiaryCardSheet> {
  late final DiaryCardDraftUi c = widget.card;
  late final Map<String, Object?> attrs = Map.of(c.attributes);
  late String? intensity = c.intensity;
  late DiaryPeriod? period = c.period;
  late String? note = c.note;
  late bool customMood = c.category == DiaryCategory.mood && attrs['type'] is String && !moodTypes.contains(attrs['type']);

  CardEditResult _result() {
    DateTime? sort;
    if (c.eventTime == null && !c.aggregate && period != null && period != c.period) {
      final d = c.diaryDate;
      sort = DateTime(d.year, d.month, d.day, period!.defaultHour);
    }
    return CardEditResult.save(DiaryCardsCompanion(
      attributes: Value(jsonEncode(attrs..removeWhere((_, v) => v == null || (v is String && v.trim().isEmpty)))),
      intensity: Value(intensity == null || intensity!.trim().isEmpty ? null : intensity!.trim()),
      note: Value(note == null || note!.trim().isEmpty ? null : note!.trim()),
      timePeriod: Value(c.aggregate ? c.period?.wire : period?.wire),
      sortTime: sort == null ? const Value.absent() : Value(sort),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hh;
    final st = categoryStyle(context, c.category);
    final from = c.note ?? widget.rawText;
    Widget lab(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(t, style: TextStyle(fontSize: 13, color: h.sub)));
    final fields = <Widget>[];
    switch (c.category) {
      case DiaryCategory.mood:
        fields
          ..add(lab('情绪'))
          ..add(Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in moodTypes)
              HhChip(key: Key('mood-$m'), label: m, on: !customMood && attrs['type'] == m, onTap: () => setState(() {
                    customMood = false;
                    attrs['type'] = m;
                  })),
            HhChip(key: const Key('mood-custom'), label: '自定义', on: customMood, onTap: () => setState(() => customMood = true)),
          ]));
        if (customMood) {
          fields.add(Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _Field(key: const Key('mood-text'), initial: moodTypes.contains(attrs['type']) ? '' : (attrs['type'] as String? ?? ''), hint: '比如：烦躁', max: 10, onChanged: (v) => attrs['type'] = v.trim()),
          ));
        }
        fields
          ..add(lab('程度'))
          ..add(HhSegmented<String>(
              key: const Key('intensity'), values: intensities, label: (s) => s, selected: intensities.contains(intensity) ? intensity : null, onChanged: (v) => setState(() => intensity = v)));
      case DiaryCategory.other:
        fields
          ..add(lab('内容'))
          ..add(_Field(key: const Key('topic'), initial: attrs['topic'] as String? ?? '', hint: '比如：洗澡、辅食、体温', max: 10, onChanged: (v) => attrs['topic'] = v.trim()));
      case DiaryCategory.feeding:
      case DiaryCategory.diaper:
        fields
          ..add(lab(c.aggregate ? '今天共几次' : '次数'))
          ..add(_Num(key: const Key('count'), initial: attrs['count'] as int?, unit: '次', max: 30, onChanged: (v) => attrs['count'] = v));
      case DiaryCategory.sleep:
        fields
          ..add(lab('时长'))
          ..add(_Num(key: const Key('duration'), initial: attrs['duration_min'] as int?, unit: '分钟', max: 960, onChanged: (v) => attrs['duration_min'] = v));
        if (c.aggregate) {
          fields
            ..add(lab('夜醒'))
            ..add(_Num(key: const Key('wakings'), initial: attrs['night_wakings'] as int?, unit: '次', max: 20, onChanged: (v) => attrs['night_wakings'] = v));
        }
    }
    if (!c.aggregate && c.eventTime == null) {
      fields
        ..add(lab('时段'))
        ..add(HhSegmented<DiaryPeriod>(key: const Key('period'), values: periods, label: (p) => p.label, selected: period, onChanged: (v) => setState(() => period = v)));
    }
    if (c.category != DiaryCategory.mood) {
      fields
        ..add(lab('备注'))
        ..add(_Field(key: const Key('card-note'), initial: note ?? '', hint: '想补充点什么', max: 200, onChanged: (v) => note = v));
    }
    return Container(
      decoration: BoxDecoration(color: h.bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const SheetGrab(),
          const SizedBox(height: 14),
          Row(children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: h.night ? h.peachL : const Color(0xFFFFE7DB), borderRadius: BorderRadius.circular(16)),
              child: HhIcon(st.icon, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.aggregate ? '${c.category.label} · 汇总' : c.category.label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: h.ink)),
                if (from != null && from.isNotEmpty)
                  Text('来自：“$from”', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: h.sub)),
              ]),
            ),
          ]),
          ...fields,
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: _DeleteButton(onTap: () => Navigator.pop(context, const CardEditResult.delete()))),
            const SizedBox(width: 10),
            Expanded(child: HhButton(key: const Key('card-save'), label: '保存修改', onPressed: () => Navigator.pop(context, _result()))),
          ]),
        ]),
      ),
    );
  }
}

/// 设计稿 .btn.ghost.md-red：白底红字
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final h = context.hh;
    return GestureDetector(
      key: const Key('card-delete'),
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: h.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: h.line, width: 1.5)),
        child: const Text('删除', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFC0503C))),
      ),
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({super.key, required this.initial, required this.hint, required this.max, required this.onChanged});
  final String initial, hint;
  final int max;
  final ValueChanged<String> onChanged;
  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final ctl = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hh;
    return TextField(
      controller: ctl,
      maxLength: widget.max,
      onChanged: widget.onChanged,
      style: TextStyle(fontSize: 15, color: h.ink),
      decoration: InputDecoration(
        hintText: widget.hint,
        counterText: '',
        isDense: true,
        filled: true,
        fillColor: h.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: h.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: h.line)),
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num({super.key, required this.initial, required this.unit, required this.max, required this.onChanged});
  final int? initial;
  final String unit;
  final int max;
  final ValueChanged<int?> onChanged;
  @override
  Widget build(BuildContext context) {
    final h = context.hh;
    return TextFormField(
      initialValue: initial?.toString() ?? '',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
      onChanged: (v) {
        final n = int.tryParse(v);
        onChanged(n == null || n < 0 || n > max ? null : n);
      },
      style: TextStyle(fontSize: 15, color: h.ink),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: h.card,
        suffixText: unit,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: h.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: h.line)),
      ),
    );
  }
}

/// 删除二次确认（屏 19）
Future<bool> confirmDiaryDelete(BuildContext context, {required String what}) async {
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierColor: const Color(0x663D3A45),
    builder: (ctx) {
      final h = ctx.hh;
      return Dialog(
        backgroundColor: h.bg,
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('删除这条日记？', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: h.ink)),
            const SizedBox(height: 8),
            Text('$what\n已生成的今日小结不会自动改写', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.6, color: h.sub)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: HhButton(key: const Key('del-cancel'), label: '再想想', primary: false, onPressed: () => Navigator.pop(ctx, false))),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  key: const Key('del-confirm'),
                  onTap: () => Navigator.pop(ctx, true),
                  child: Container(
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFE46E58), borderRadius: BorderRadius.circular(16)),
                    child: const Text('删除', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      );
    },
  );
  return ok ?? false;
}
