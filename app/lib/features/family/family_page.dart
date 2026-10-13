import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../services/cloud/cloud_api.dart';
import '../../services/cloud/cloud_providers.dart';
import '../insights/insights_page.dart';

/// 家庭：一个家庭对应一个宝宝。创建者把邀请码给家人，家人输入 6 位码加入，
/// 之后护理记录、哭声判断和反馈在家人手机间同步（录音不共享）。
class FamilyPage extends ConsumerStatefulWidget {
  const FamilyPage({super.key});
  @override
  ConsumerState<FamilyPage> createState() => _FamilyPageState();
}

/// 我的身份（头像 + 默认称呼）
const roleChoices = [('mom', '妈妈', AppIcon.avatarMom), ('dad', '爸爸', AppIcon.avatarDad), ('grandma', '老人', AppIcon.avatarGrandma)];
AppIcon avatarIcon(String a) => switch (a) {
      'mom' => AppIcon.avatarMom,
      'grandma' => AppIcon.avatarGrandma,
      'baby' => AppIcon.avatarBaby,
      _ => AppIcon.avatarDad,
    };

class _FamilyPageState extends ConsumerState<FamilyPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f, {String? done}) async {
    setState(() => _busy = true);
    try {
      await f();
      ref.invalidate(familyIdProvider);
      ref.invalidate(familyMembersProvider);
      ref.invalidate(inviteCodeProvider);
      if (done != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is CloudException ? e.message : '网络不太好，请稍后再试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 选身份（+ 可选输入邀请码）
  Future<({String avatar, String name, String? code})?> _ask({required bool join}) {
    var avatar = join ? 'mom' : 'dad';
    final code = TextEditingController();
    return showModalBottomSheet<({String avatar, String name, String? code})>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.hh;
        final name = roleChoices.firstWhere((r) => r.$1 == avatar).$2;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SheetGrab(),
            const SizedBox(height: 12),
            Text(join ? '加入家庭' : '创建家庭', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.ink)),
            const SizedBox(height: 16),
            Text('我是', style: TextStyle(fontSize: 13, color: c.sub)),
            const SizedBox(height: 8),
            Row(children: [
              for (final r in roleChoices)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: HhChip(
                    key: Key('role-${r.$1}'),
                    label: r.$2,
                    on: avatar == r.$1,
                    onTap: () => set(() => avatar = r.$1),
                  ),
                ),
            ]),
            if (join) ...[
              const SizedBox(height: 16),
              Text('邀请码', style: TextStyle(fontSize: 13, color: c.sub)),
              TextField(
                key: const Key('invite-input'),
                controller: code,
                autofocus: true,
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w800, color: c.ink),
                decoration: const InputDecoration(hintText: '6 位', counterText: ''),
              ),
            ],
            const SizedBox(height: 20),
            HhButton(
              key: const Key('family-confirm'),
              label: join ? '加入' : '创建并生成邀请码',
              onPressed: () {
                final v = code.text.trim().toUpperCase();
                if (join && v.length != 6) return;
                Navigator.pop(ctx, (avatar: avatar, name: name, code: join ? v : null));
              },
            ),
          ]),
        );
      }),
    );
  }

  Future<void> _create() async {
    final r = await _ask(join: false);
    if (r == null) return;
    await _run(() => ref.read(familySyncProvider)!.create(name: r.name, avatar: r.avatar), done: '家庭已创建，把邀请码发给家人吧');
  }

  Future<void> _join() async {
    final r = await _ask(join: true);
    if (r == null) return;
    await _run(() => ref.read(familySyncProvider)!.join(code: r.code!, name: r.name, avatar: r.avatar),
        done: '已加入，记录会自动同步');
    ref.read(syncCoordinatorProvider).kick();
  }

  Future<bool> _confirm(String title, String body, String ok) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final sync = ref.watch(familySyncProvider);
    final fid = ref.watch(familyIdProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Text('家庭', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.ink)),
            const SizedBox(height: 16),
            if (sync == null) ...[
              const FamilyCard(),
              const SizedBox(height: 14),
              Text('这个版本还没连上云端，家庭共享暂不可用。所有记录都保存在这台手机上。',
                  style: TextStyle(fontSize: 13, color: c.sub, height: 1.6)),
            ] else if (fid == null)
              ..._noFamily(c)
            else
              ..._inFamily(c),
          ],
        ),
      ),
    );
  }

  List<Widget> _noFamily(Hh c) => [
        const FamilyCard(),
        const SizedBox(height: 14),
        Text('爸爸、妈妈、老人一起记录，交班不用口头说。一个家庭对应一个宝宝，录音不会共享。',
            style: TextStyle(fontSize: 13, color: c.sub, height: 1.6)),
        const SizedBox(height: 20),
        HhButton(key: const Key('family-create'), label: '创建家庭', onPressed: _busy ? null : _create),
        const SizedBox(height: 12),
        HhButton(key: const Key('family-join'), label: '输入邀请码加入', primary: false, onPressed: _busy ? null : _join),
        const SizedBox(height: 14),
        Text('加入别人的家庭后，这台手机上已有的记录会合并到那个宝宝名下。',
            style: TextStyle(fontSize: 12, color: c.sub, height: 1.6), textAlign: TextAlign.center),
      ];

  List<Widget> _inFamily(Hh c) {
    final code = ref.watch(inviteCodeProvider);
    final members = ref.watch(familyMembersProvider);
    final status = ref.watch(syncStatusProvider);
    final api = ref.read(cloudApiProvider)!;
    final me = api.userId;
    final iAmOwner = members.value?.any((m) => m.userId == me && m.isOwner) ?? false;
    return [
      HhCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('邀请家人', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 4),
          Text('家人在哄哄「家庭」里点"输入邀请码加入"，24 小时内有效',
              style: TextStyle(fontSize: 12, color: c.sub, height: 1.5)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(code.value ?? (code.isLoading ? '······' : '获取失败'),
                  key: const Key('invite-code'),
                  style: TextStyle(fontSize: 32, letterSpacing: 6, fontWeight: FontWeight.w800, color: c.peachDeep)),
            ),
            TextButton(
              onPressed: code.value == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: '来哄哄一起记录宝宝吧，邀请码：${code.value}'));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制邀请码')));
                    },
              child: const Text('复制'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await api.refreshInvite();
                      }),
              child: const Text('换一个'),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      HhCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          for (final m in members.value ?? const <FamilyMember>[])
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.peachL, shape: BoxShape.circle),
                child: HhIcon(avatarIcon(m.avatar), size: 28),
              ),
              title: Text(m.userId == me ? '${m.name}（我）' : m.name, style: TextStyle(fontSize: 15, color: c.ink)),
              subtitle: Text(m.isOwner ? '创建者' : '成员', style: TextStyle(fontSize: 12, color: c.sub)),
              trailing: iAmOwner && m.userId != me
                  ? IconButton(
                      key: Key('remove-${m.userId}'),
                      icon: const HhIcon(AppIcon.remove, size: 22),
                      onPressed: () async {
                        if (await _confirm('移除${m.name}？', '移除后对方看不到之后的新记录，已同步到对方手机上的记录会保留在对方手机上。', '移除')) {
                          await _run(() => api.removeMember(m.userId));
                        }
                      },
                    )
                  : null,
            ),
          if (members.isLoading) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        const HhIcon(AppIcon.checkSmall, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            status.running
                ? '正在同步…'
                : status.error ??
                    (status.lastFamilySync == null ? '还没同步过' : '上次同步 ${DateFormat('M月d日 HH:mm').format(status.lastFamilySync!)}'),
            style: TextStyle(fontSize: 12, color: c.sub),
          ),
        ),
        TextButton(onPressed: status.running ? null : () => ref.read(syncCoordinatorProvider).kick(), child: const Text('立即同步')),
      ]),
      const SizedBox(height: 20),
      HhButton(
        key: const Key('family-leave'),
        label: '退出家庭',
        primary: false,
        onPressed: _busy
            ? null
            : () async {
                final last = (members.value?.length ?? 1) <= 1;
                if (await _confirm('退出家庭？',
                    last ? '你是最后一位成员，退出后家庭和云端的共享记录会被删除。这台手机上的记录会保留。' : '退出后不再和家人同步，这台手机上的记录会保留。',
                    '退出')) {
                  await _run(() => ref.read(familySyncProvider)!.leave(), done: '已退出家庭');
                }
              },
      ),
    ];
  }
}
