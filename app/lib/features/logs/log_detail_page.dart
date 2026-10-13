import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../domain/models/care_log_type.dart';

/// 5 记录详情：时间线，左滑删除
class LogDetailPage extends ConsumerWidget {
  const LogDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(recentLogsProvider);
    final fmt = DateFormat('MM-dd HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('记录')),
      body: logs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('出错了：$e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('还没有记录，在首页点一下就能记'))
            : ListView(
                children: [
                  for (final l in list)
                    Dismissible(
                      key: ValueKey(l.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) =>
                          ref.read(careLogRepositoryProvider).delete(l.id),
                      background: Container(color: Colors.red),
                      child: ListTile(
                        title: Text(CareLogType.values.byName(l.type).label),
                        subtitle: Text(l.endedAt == null
                            ? fmt.format(l.startedAt)
                            : '${fmt.format(l.startedAt)} – ${fmt.format(l.endedAt!)}'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
