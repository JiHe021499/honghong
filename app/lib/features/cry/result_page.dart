import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../domain/models/cause_ui.dart';
import '../../domain/models/cry_cause.dart';
import '../../domain/predictor/cry_predictor.dart';
import 'recording_page.dart';

final _eventPredictionProvider = FutureProvider.family<Prediction?, String>((ref, id) async {
  final e = await ref.watch(cryEventRepositoryProvider).byId(id);
  return e == null ? null : Prediction.decode(e.predictionJson);
});

/// 判断结果（设计稿 12）：前三原因 + 概率条 + 为什么 + 建议 + 可展开的判断/安抚方法
class ResultPage extends ConsumerWidget {
  const ResultPage({super.key, required this.eventId});
  final String eventId;

  static Color barColor(Hh c, int i) => [c.peach2, c.blue, const Color(0xFFC5B3E6)][i.clamp(0, 2)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final pred = ref.watch(_eventPredictionProvider(eventId));
    return Scaffold(
      body: SafeArea(
        child: pred.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('出错了：$e')),
          data: (p) {
            if (p == null) return const Center(child: Text('找不到这次记录'));
            final top = p.top(3);
            // 只展示前三，概率按前三重新归一，和设计一致加起来是 100%
            final sum = top.fold<double>(0, (a, s) => a + s.probability);
            int pct(CauseScore s) => (s.probability / sum * 100).round();
            final first = top.first;
            final second = top.length > 1 ? top[1] : null;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                SizedBox(
                  height: 52,
                  child: Stack(alignment: Alignment.center, children: [
                    Align(alignment: Alignment.centerLeft, child: CircleBack(onTap: () => context.go(Routes.home))),
                    Text('可能的原因', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
                  ]),
                ),
                const SizedBox(height: 14),
                HhCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      const TextSpan(text: '我们猜，宝宝'),
                      TextSpan(text: '可能', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                      const TextSpan(text: '是…'),
                    ]), style: TextStyle(fontSize: 14, color: c.sub)),
                    const SizedBox(height: 6),
                    for (var i = 0; i < top.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(children: [
                          SizedBox(
                            width: 86,
                            child: Text('${top[i].cause.emoji} ${top[i].cause.label.split('/').first}',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: pct(top[i]) / 100,
                                minHeight: 12,
                                color: barColor(c, i),
                                backgroundColor: const Color(0xFFF5EDE5),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text('${pct(top[i])}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    Text.rich(TextSpan(children: [
                      const TextSpan(text: '💡 为什么这么猜：'),
                      TextSpan(text: first.reason, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
                      TextSpan(text: '，${first.cause == CryCause.hungry ? '和宝宝以往饿的时候相似' : '结合宝宝以往的反馈综合判断'}。'),
                    ]), style: TextStyle(fontSize: 14, color: c.sub, height: 1.6)),
                  ]),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE7DB), Color(0xFFFFF1E8)]),
                  ),
                  child: Row(children: [
                    Text(first.cause.emoji, style: const TextStyle(fontSize: 34)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('建议先试${first.cause.action}', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: c.ink)),
                        const SizedBox(height: 4),
                        Text('如果 10 分钟内没好转，再试试${second?.cause.action ?? '抱一抱'}', style: TextStyle(fontSize: 12, color: c.sub)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < top.length; i++) _CauseTile(score: top[i], pct: pct(top[i]), initiallyOpen: i == 0),
                const SizedBox(height: 4),
                HhButton(
                  label: '宝宝不哭了，告诉我结果',
                  primary: false,
                  onPressed: () => context.pushReplacement(Routes.feedback(eventId)),
                ),
                const SizedBox(height: 16),
                Text('结果仅供参考，不能替代医生判断。若哭声异常尖锐、持续超过 2 小时或伴发烧，请及时就医。',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.sub, height: 1.6)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CauseTile extends StatefulWidget {
  const _CauseTile({required this.score, required this.pct, required this.initiallyOpen});
  final CauseScore score;
  final int pct;
  final bool initiallyOpen;
  @override
  State<_CauseTile> createState() => _CauseTileState();
}

class _CauseTileState extends State<_CauseTile> {
  late bool open = widget.initiallyOpen;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final cause = widget.score.cause;
    TextSpan row(String k, String v) => TextSpan(children: [
          TextSpan(text: '$k：', style: TextStyle(fontWeight: FontWeight.w700, color: c.peach2)),
          TextSpan(text: v),
        ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HhCard(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () => setState(() => open = !open),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${cause.emoji} ${cause.title} · ${widget.pct}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink))),
            Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: c.sub),
          ]),
          if (open) ...[
            const SizedBox(height: 8),
            Text.rich(row('怎么判断', cause.howToTell), style: TextStyle(fontSize: 14, color: c.ink, height: 1.6)),
            Text.rich(row('怎么安抚', cause.howToSoothe), style: TextStyle(fontSize: 14, color: c.ink, height: 1.6)),
          ],
        ]),
      ),
    );
  }
}
