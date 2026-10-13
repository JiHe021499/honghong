import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/models/cry_cause.dart';
import '../../domain/predictor/cry_predictor.dart';

final _eventPredictionProvider =
    FutureProvider.family<Prediction?, String>((ref, id) async {
  final e = await ref.watch(cryEventRepositoryProvider).byId(id);
  return e == null ? null : Prediction.decode(e.predictionJson);
});

const causeTips = {
  CryCause.hungry: '先试试喂奶。饿的信号：转头找奶、吮手。',
  CryCause.sleepy: '调暗灯光、包裹、轻拍或白噪音哄睡。',
  CryCause.gas: '竖抱拍嗝，或顺时针揉肚子、做蹬自行车动作。',
  CryCause.diaper: '检查尿布，看看是否太热太冷、衣服勒不勒。',
  CryCause.holdMe: '抱起来贴身安抚，轻声说话或轻摇。',
};

/// 3 判断结果：前三原因 + 概率 + 解释 + 建议
class ResultPage extends ConsumerWidget {
  const ResultPage({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pred = ref.watch(_eventPredictionProvider(eventId));
    return Scaffold(
      appBar: AppBar(title: const Text('可能的原因')),
      body: pred.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('出错了：$e')),
        data: (p) => p == null
            ? const Center(child: Text('找不到这次记录'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final s in p.top(3))
                    Card(
                      child: ListTile(
                        title: Text(
                            '${s.cause.label}  ${(s.probability * 100).round()}%'),
                        subtitle: Text('${s.reason}\n${causeTips[s.cause]}'),
                        isThreeLine: true,
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text('仅供参考，不能替代医生。如持续尖声哭闹、发热或精神差，请及时就医。',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        context.pushReplacement(Routes.feedback(eventId)),
                    child: const Text('哄好了，告诉哄哄是什么起作用'),
                  ),
                ],
              ),
      ),
    );
  }
}
