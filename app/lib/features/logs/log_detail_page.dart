import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../care/care_actions.dart';
import '../cry/recording_page.dart';
import 'record_editor_sheet.dart';
import '../care/care_log_row.dart';

/// 全部记录：按天分组，右上角「补记」，点条目修改时间/细节或删除，左滑删除
class LogDetailPage extends ConsumerWidget {
  const LogDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final logs = ref.watch(recentLogsProvider);
    final actions = CareActions(ref);
    final day = DateFormat('M月d日 EEEE', 'zh_CN');
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
                Align(
                  alignment: Alignment.centerRight,
                  child: Material(
                    color: c.peachL,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      key: const Key('backfill-add'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => openRecordEditor(context, ref),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Text('＋ 补记', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.peachDeep)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: logs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('出错了：$e')),
              data: (list) {
                if (list.isEmpty) return Center(child: Text('还没有记录，在首页点一下就能记，\n忘了点也可以右上角「补记」', textAlign: TextAlign.center, style: TextStyle(color: c.sub)));
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
                              child: CareLogRow(
                                log: l,
                                last: l == g.value.last,
                                onTap: () => l.endedAt == null ? actions.end(context, l) : openRecordEditor(context, ref, log: l),
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

/// 打开补记（log == null）或修改面板，并把结果写进数据库。
/// 写入都会标记 dirty，加入家庭时自动同步；小部件/锁屏/快捷开关监听数据库自动刷新。
Future<void> openRecordEditor(BuildContext context, WidgetRef ref, {CareLog? log}) async {
  final repo = ref.read(careLogRepositoryProvider);
  final baby = await ref.read(currentBabyProvider.future);
  if (!context.mounted) return;
  final r = await showRecordEditor(context,
      log: log, overlaps: (t, a, b) => repo.overlapping(baby.id, t, a, b, excludeId: log?.id));
  if (r == null) return;
  if (r.delete) {
    if (log != null) await repo.delete(log.id);
    return;
  }
  if (log == null) {
    await repo.backfill(baby.id, r.type, start: r.start!, end: r.end, detail: r.detail);
  } else {
    await repo.updateRecord(log.id, start: r.start!, end: r.end, detail: r.detail);
  }
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(log == null ? '已补记${r.type.label}' : '已保存修改')));
  }
}
