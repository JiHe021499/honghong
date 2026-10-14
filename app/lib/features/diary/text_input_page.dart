import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/prefs.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hh_widgets.dart';
import 'diary_flow.dart';
import 'diary_providers.dart';
import 'diary_widgets.dart';

/// 屏 10：打字记录。和语音走同一个整理流程。保存后返回保存条数。
class TextInputPage extends ConsumerStatefulWidget {
  const TextInputPage({super.key, this.initial});
  final String? initial;
  @override
  ConsumerState<TextInputPage> createState() => _TextInputPageState();
}

class _TextInputPageState extends ConsumerState<TextInputPage> {
  late final ctl = TextEditingController(text: widget.initial ?? ref.read(prefsProvider).getString(kDiaryDraft) ?? '');
  bool busy = false;

  static const quick = ['喂了…', '睡了…', '换了尿布', '哭闹'];

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  void _insert(String s) {
    final t = s.replaceAll('…', '');
    final cur = ctl.text;
    final sep = cur.isEmpty || RegExp(r'[，,。\s]$').hasMatch(cur) ? '' : '，';
    ctl.text = '$cur$sep$t';
    ctl.selection = TextSelection.collapsed(offset: ctl.text.length);
    setState(() {});
  }

  Future<void> _submit() async {
    final text = ctl.text.trim();
    if (text.isEmpty || busy) return;
    setState(() => busy = true);
    final out = await ref.read(diaryFlowProvider).process(text, inputType: 'text');
    if (!mounted) return;
    setState(() => busy = false);
    switch (out) {
      case NetworkDraft():
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('网络不太好，文字已保留，稍后再试')));
      case GoConfirm(:final result):
        final saved = await context.push<int>(Routes.diaryConfirm, extra: result);
        if (!mounted) return;
        if (saved != null && saved > 0) {
          await ref.read(prefsProvider).remove(kDiaryDraft);
          if (mounted) context.pop(saved);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
          DiaryHeader(title: '打字记录', onBack: () => context.pop()),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 120),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.peach, width: 1.5)),
            child: TextField(
              key: const Key('diary-text'),
              controller: ctl,
              autofocus: true,
              maxLines: null,
              minLines: 4,
              maxLength: 500,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 16, height: 1.6, color: c.ink),
              decoration: InputDecoration(
                border: InputBorder.none,
                counterText: '',
                hintText: '比如：中午睡了一个多小时，上午拉了一次黄色软便',
                hintStyle: TextStyle(color: c.sub.withValues(alpha: .6)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final q in quick) HhChip(label: q, on: false, onTap: () => _insert(q))]),
          const SizedBox(height: 18),
          HhButton(key: const Key('diary-text-submit'), label: busy ? '正在整理…' : '整理成卡片', onPressed: ctl.text.trim().isEmpty || busy ? null : _submit),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('和语音走同一个整理流程', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.sub)),
          ),
        ]),
      ),
    );
  }
}
