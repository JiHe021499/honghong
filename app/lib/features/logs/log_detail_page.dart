import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/care_detail.dart';
import '../../domain/models/care_log_type.dart';
import '../care/care_actions.dart';
import '../cry/recording_page.dart';

/// 全部记录：按天分组，点条目修改，左滑删除
class LogDetailPage extends ConsumerWidget {
  const LogDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final logs = ref.watch(recentLogsProvider);
    final actions = CareActions(ref);
    final day = DateFormat('M月d日 EEEE', 'zh_CN');
    final hm = DateFormat('HH:mm');
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: SizedBox(
              height: 52,
              child: Stack(alignment: Alignment.center, children: [
                Align(alignment: Alignment.centerLeft, child: CircleBack(onTap: () => Navigator.of(context).maybePop())),
                Text('全部记录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
              ]),
            ),
          ),
          Expanded(
            child: logs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('出错了：$e')),
              data: (list) {
                if (list.isEmpty) return Center(child: Text('还没有记录，在首页点一下就能记', style: TextStyle(color: c.sub)));
                final groups = <DateTime, List<CareLog>>{};
                for (final l in list) {
                  groups.putIfAbsent(DateUtils.dateOnly(l.startedAt), () => []).add(l);
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    for (final g in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 8),
                        child: Text(day.format(g.key), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.sub)),
                      ),
                      HhCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(children: [
                          for (final l in g.value)
                            Dismissible(
                              key: ValueKey(l.id),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => ref.read(careLogRepositoryProvider).delete(l.id),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: const Color(0xFFFFD9CC),
                                child: Text('删除', style: TextStyle(color: c.peachDeep, fontWeight: FontWeight.w700)),
                              ),
                              child: ListTile(
                                onTap: () => actions.editLog(context, l),
                                leading: IconTile(CareLogType.values.byName(l.type).icon, bg: typeTint(c, l.type)),
                                title: Text(
                                  l.endedAt == null
                                      ? CareLogType.values.byName(l.type).runningLabel
                                      : describeLog(CareLogType.values.byName(l.type), l.startedAt, l.endedAt, l.detail),
                                  style: TextStyle(fontSize: 14, color: c.ink),
                                ),
                                trailing: Text(
                                  l.endedAt == null || l.endedAt == l.startedAt
                                      ? hm.format(l.startedAt)
                                      : '${hm.format(l.startedAt)}–${hm.format(l.endedAt!)}',
                                  style: TextStyle(fontSize: 12, color: c.sub),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
