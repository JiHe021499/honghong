import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../domain/models/cry_cause.dart';

/// 4 哄好反馈：点一下即完成，这就是训练标注
class FeedbackPage extends ConsumerWidget {
  const FeedbackPage({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> submit(CryCause? c) async {
      await ref.read(feedbackRepositoryProvider).save(eventId, c);
      ref.invalidate(cryPredictorProvider); // 更新个性化先验
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('谢谢！哄哄又更懂宝宝一点了')));
      context.go(Routes.home);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('最后是什么起作用了？')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final c in CryCause.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18)),
                onPressed: () => submit(c),
                child: Text(c.label, style: const TextStyle(fontSize: 18)),
              ),
            ),
          TextButton(onPressed: () => submit(null), child: const Text('不确定')),
        ],
      ),
    );
  }
}
