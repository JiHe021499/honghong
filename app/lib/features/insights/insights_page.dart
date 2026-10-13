import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

final _agreementProvider = FutureProvider((ref) async {
  final baby = await ref.watch(currentBabyProvider.future);
  return ref.watch(feedbackRepositoryProvider).top1Agreement(baby.id);
});

/// 7 宝宝规律：v1 先显示猜中率，规律分析待数据积累后实现
class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(_agreementProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('宝宝规律')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('哄哄猜中率'),
              subtitle: a.when(
                loading: () => const Text('计算中…'),
                error: (e, _) => Text('$e'),
                data: (r) => Text(r.total == 0
                    ? '还没有反馈'
                    : '${r.hits} / ${r.total}（${(r.hits * 100 / r.total).round()}%）'),
              ),
            ),
          ),
          const Card(
            child: ListTile(
              title: Text('闹觉时段、喂奶间隔趋势'),
              subtitle: Text('攒够一周记录后显示'),
            ),
          ),
        ],
      ),
    );
  }
}
