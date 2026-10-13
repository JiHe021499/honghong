import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/context_builder.dart';
import '../../domain/models/care_log_type.dart';

/// 1 首页：状态栏 + "宝宝在哭"大按钮 + 四个快捷记录
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('哄哄'),
        actions: [
          IconButton(
            tooltip: '夜间模式',
            icon: Icon(night ? Icons.wb_sunny_outlined : Icons.nightlight_round),
            onPressed: () => ref.read(nightModeProvider.notifier).toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.insights),
            onPressed: () => context.push(Routes.insights),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const _StatusBar(),
              const Spacer(),
              _CryButton(onTap: () => context.push(Routes.recording)),
              const Spacer(),
              const _QuickLogGrid(),
              TextButton(
                onPressed: () => context.push(Routes.logs),
                child: const Text('查看全部记录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockProvider);
    final latest = ref.watch(latestLogsProvider).value ?? const {};
    final now = DateTime.now();
    String line(CareLogType t) {
      final l = latest[t];
      if (l == null) return '${t.label}：暂无记录';
      if (t == CareLogType.sleep && l.endedAt == null) {
        return '正在睡，已睡 ${formatSince(now.difference(l.startedAt)).replaceAll('前', '')}';
      }
      return '上次${t.label}：${formatSince(now.difference(l.startedAt))}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final t in CareLogType.values) Text(line(t))],
        ),
      ),
    );
  }
}

class _CryButton extends StatelessWidget {
  const _CryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 200,
      child: FilledButton(
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: scheme.primary,
        ),
        onPressed: onTap,
        child: const Text('宝宝在哭', style: TextStyle(fontSize: 24)),
      ),
    );
  }
}

class _QuickLogGrid extends ConsumerWidget {
  const _QuickLogGrid();

  static const _icons = {
    CareLogType.feed: Icons.local_drink,
    CareLogType.sleep: Icons.bedtime,
    CareLogType.diaper: Icons.baby_changing_station,
    CareLogType.burp: Icons.air,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(latestLogsProvider).value ?? const {};
    final sleeping = latest[CareLogType.sleep]?.endedAt == null &&
        latest[CareLogType.sleep] != null;

    Future<void> log(CareLogType t) async {
      final baby = await ref.read(currentBabyProvider.future);
      final repo = ref.read(careLogRepositoryProvider);
      if (t == CareLogType.sleep && sleeping) {
        await repo.endSleep(baby.id);
      } else {
        await repo.add(baby.id, t);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t == CareLogType.sleep && sleeping ? '已记录醒来' : '已记录${t.label}'),
          duration: const Duration(seconds: 1),
        ));
      }
    }

    return Row(
      children: [
        for (final t in CareLogType.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () => log(t),
                child: Column(children: [
                  Icon(_icons[t]),
                  Text(t == CareLogType.sleep && sleeping ? '醒了' : t.label),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}
