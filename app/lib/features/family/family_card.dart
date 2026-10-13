import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/care_log_type.dart';
import '../../services/cloud/cloud_api.dart';
import '../../services/cloud/cloud_providers.dart';

/// 家人最近一次记录
final familyActivityProvider = StreamProvider<CareLog?>((ref) => ref.watch(careLogRepositoryProvider).watchLatestByFamily());

String agoText(DateTime t, DateTime now) {
  final m = now.difference(t).inMinutes;
  if (m < 1) return '刚刚';
  if (m < 60) return '$m 分钟前';
  if (m < 60 * 24) return '${m ~/ 60} 小时前';
  return '${m ~/ (60 * 24)} 天前';
}

/// 家庭共享卡（设计稿 15「家庭共享 · 邀请家人＋ · 3 位家人同步中 · 爸爸 15 分钟前记录了换尿布」）
/// 三种状态：未连接云端 / 还没有家庭 / 已加入。
class FamilyCard extends ConsumerWidget {
  const FamilyCard({super.key, this.linkToFamily = false});

  /// 在「规律」页上显示标题行，点击跳到家庭页
  final bool linkToFamily;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final cloud = ref.watch(familySyncProvider) != null;
    final fid = ref.watch(familyIdProvider);
    final members = fid == null ? const <FamilyMember>[] : (ref.watch(familyMembersProvider).value ?? const <FamilyMember>[]);
    final activity = fid == null ? null : ref.watch(familyActivityProvider).value;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final status = ref.watch(syncStatusProvider);

    final bgs = [c.peachL, c.blueL, c.greenL];
    final avatars = members.isEmpty
        ? const [AppIcon.avatarMom, AppIcon.avatarDad, AppIcon.avatarGrandma]
        : [for (final m in members.take(3)) _avatar(m.avatar)];
    Widget av(int i) => Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bgs[i % 3], shape: BoxShape.circle, border: Border.all(color: c.card, width: 3)),
          child: HhIcon(avatars[i], size: 28),
        );

    String title, sub;
    if (!cloud) {
      title = '家人一起记录';
      sub = '这个版本还没连上云端，记录只保存在这台手机上';
    } else if (fid == null) {
      title = '家人一起记录';
      sub = '创建家庭，把邀请码发给家人，交班不用口头说';
    } else {
      title = members.isEmpty ? '家人同步中' : '${members.length} 位家人同步中';
      final who = activity == null ? null : members.where((m) => m.userId == activity.updatedBy).firstOrNull;
      if (status.offline) {
        sub = '没有网络，联网后自动同步';
      } else if (activity != null && activity.updatedAt != null) {
        final what = CareLogType.values.byName(activity.type).label;
        sub = '${who?.name ?? '家人'} ${agoText(activity.updatedAt!, now)}记录了$what';
      } else {
        sub = status.lastFamilySync == null ? '等待第一次同步' : '上次同步 ${agoText(status.lastFamilySync!, now)}';
      }
    }

    final card = HhCard(
      key: const Key('family-card'),
      padding: const EdgeInsets.all(20),
      onTap: linkToFamily ? () => context.go('/family') : null,
      child: Row(children: [
        SizedBox(
          width: 40.0 + 30 * (avatars.length - 1),
          height: 40,
          child: Stack(children: [for (var i = 0; i < avatars.length; i++) Positioned(left: 30.0 * i, child: av(i))]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 13, color: c.sub)),
          ]),
        ),
      ]),
    );
    if (!linkToFamily) return card;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text('家庭共享', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink))),
          if (cloud)
            GestureDetector(
              onTap: () => context.go('/family'),
              child: Text(fid == null ? '邀请家人 ＋' : '管理', style: TextStyle(fontSize: 13, color: c.peachDeep, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
      card,
    ]);
  }

  static AppIcon _avatar(String a) => switch (a) {
        'mom' => AppIcon.avatarMom,
        'grandma' => AppIcon.avatarGrandma,
        'baby' => AppIcon.avatarBaby,
        _ => AppIcon.avatarDad,
      };
}
