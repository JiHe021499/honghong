import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../domain/insights.dart';
import '../../domain/models/cause_ui.dart';
import '../../domain/models/cry_cause.dart';

final feedbackCountProvider = FutureProvider<int>((ref) => ref.watch(feedbackRepositoryProvider).count());

/// 反馈页的一个选项；cause 为 null 表示"不确定"
class _Opt {
  const _Opt(this.emoji, this.label, this.cause);
  final String emoji, label;
  final CryCause? cause;
}

/// 哄好反馈（设计稿 13）：点一下选中，"完成"保存，这就是训练标注
class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends ConsumerState<FeedbackPage> {
  static final _opts = [
    for (final c in [CryCause.hungry, CryCause.sleepy, CryCause.gas, CryCause.diaper, CryCause.holdMe]) _Opt(c.emoji, c.action, c),
    const _Opt('🤷', '不确定', null),
  ];
  int? _sel;
  bool _saving = false;

  Future<void> _submit() async {
    if (_sel == null || _saving) return;
    _saving = true;
    await ref.read(feedbackRepositoryProvider).save(widget.eventId, _opts[_sel!].cause);
    ref.invalidate(cryPredictorProvider); // 更新个性化先验
    ref.invalidate(feedbackCountProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('谢谢！哄哄又更懂宝宝一点了'), duration: Duration(seconds: 2)));
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final count = ref.watch(feedbackCountProvider).value ?? 0;
    final name = ref.watch(currentBabyProvider).value?.nickname ?? '宝宝';
    final learned = count + (_sel == null ? 0 : 1);
    final progress = learningProgress(learned);
    final toNext = (10 - learned % 10);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
          children: [
            const Center(child: Text('🥰', style: TextStyle(fontSize: 64))),
            const SizedBox(height: 14),
            Text('辛苦啦，宝宝不哭了', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.ink)),
            const SizedBox(height: 6),
            Text('最后是什么起作用了？点一下就好', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.sub)),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.45,
              children: [
                for (var i = 0; i < _opts.length; i++)
                  GestureDetector(
                    key: Key('fb-$i'),
                    onTap: () => setState(() => _sel = i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _sel == i ? const Color(0xFFFFF4EE) : c.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _sel == i ? c.peach2 : Colors.transparent, width: 2),
                        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 10, offset: const Offset(0, 3))],
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(_opts[i].emoji, style: const TextStyle(fontSize: 30)),
                        const SizedBox(height: 6),
                        Text(_opts[i].label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
                      ]),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            HhCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('已经更懂你家宝宝了', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                  const Spacer(),
                  Text('${(progress * 100).round()}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.blueInk)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    height: 14,
                    child: Stack(children: [
                      Container(color: const Color(0xFFF5EDE5)),
                      FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [c.blue, c.green]))),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Text('已学习 $learned 次哭声 · 再反馈 $toNext 次，判断会更贴合$name', style: TextStyle(fontSize: 12, color: c.sub)),
              ]),
            ),
            const SizedBox(height: 18),
            HhButton(label: '完成', onPressed: _sel == null ? null : _submit),
            Center(
              child: TextButton(
                onPressed: () => context.go(Routes.home),
                child: Text('跳过', style: TextStyle(fontSize: 13, color: c.sub)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
