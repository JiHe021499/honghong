import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../services/cloud/cloud_providers.dart';
import '../../services/export/export_service.dart';
import '../update/update_providers.dart';

/// 我的：宝宝信息、夜间模式、自动监听、全部记录、导出
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final r = await ExportService(ref.read(databaseProvider)).writeZip(dir);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(r.path, mimeType: 'application/zip')],
        subject: '哄哄数据导出',
        text: '哄哄导出：记录和标注 + ${r.recordings} 段录音',
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _rename(String id, String current) async {
    final ctl = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('宝宝小名'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 10),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    await ref.read(babyRepositoryProvider).updateNickname(id, v);
    ref.invalidate(currentBabyProvider);
  }

  static const privacyText = '开启后，在连着 Wi-Fi 时上传你标注过的哭声片段（16kHz 单声道，最长 30 秒）和标注，'
      '用来训练更准的识别模型。\n\n'
      '· 匿名：不需要注册，不收集手机号、姓名，宝宝只传月龄，不传生日和小名\n'
      '· 只上传你点过"什么起作用了"的哭声，护理记录只随哭声带上"距离上次喂奶多久"这类时间信息\n'
      '· 随时可以关闭，也可以在这里一键删除已经上传的全部数据';

  Future<void> _toggleResearch(bool v) async {
    if (v) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('参与改进'),
          content: const Text(privacyText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('先不了')),
            TextButton(key: const Key('research-agree'), onPressed: () => Navigator.pop(ctx, true), child: const Text('同意并开启')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(researchOptInProvider.notifier).set(v);
  }

  Future<void> _deleteResearch() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除我上传的数据？'),
        content: const Text('会删除云端这台手机上传过的全部哭声片段和标注，并关闭"参与改进"。手机上的记录不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(researchUploaderProvider)!.deleteMine();
      ref.invalidate(researchOptInProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除云端数据')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败，请连网后再试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final cloud = ref.watch(researchUploaderProvider) != null;
    final research = ref.watch(researchOptInProvider);
    final sync = ref.watch(syncStatusProvider);
    final night = ref.watch(nightModeProvider);
    final auto = ref.watch(autoListenProvider);
    final baby = ref.watch(currentBabyProvider).value;

    Widget tile(String title, {String? sub, Widget? trailing, VoidCallback? onTap, Key? key, AppIcon? icon}) => ListTile(
          key: key,
          leading: icon == null ? null : HhIcon(icon, size: 30),
          title: Text(title, style: TextStyle(fontSize: 15, color: c.ink)),
          subtitle: sub == null ? null : Text(sub, style: TextStyle(fontSize: 12, color: c.sub)),
          trailing: trailing ?? (onTap == null ? null : const HhIcon(AppIcon.chevronRight, size: 20)),
          onTap: onTap,
        );
    Widget group(List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: HhCard(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)),
        );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Text('我的', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.ink)),
            const SizedBox(height: 16),
            group([
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: const Color(0xFFFFF8F0),
                      padding: const EdgeInsets.all(4),
                      child: Image.asset('assets/brand/mark-1024.png', width: 52, height: 52),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('哄哄', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.ink)),
                    Text('第二阶段 · 本地规则版', style: TextStyle(fontSize: 12, color: c.sub)),
                  ]),
                ]),
              ),
            ]),
            group([
              tile('宝宝小名', icon: AppIcon.avatarBaby, sub: baby?.nickname, onTap: baby == null ? null : () => _rename(baby.id, baby.nickname)),
              tile('宝宝生日',
                  sub: baby == null ? '…' : DateFormat('yyyy-MM-dd').format(baby.birthDate),
                  onTap: baby == null
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: baby.birthDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 1000)),
                            lastDate: DateTime.now(),
                          );
                          if (d == null) return;
                          await ref.read(babyRepositoryProvider).updateBirthDate(baby.id, d);
                          ref.invalidate(currentBabyProvider);
                        }),
            ]),
            group([
              tile('夜间模式', icon: night ? AppIcon.dayMode : AppIcon.nightMode, sub: '暗红色调，半夜不刺眼', trailing: Switch(value: night, onChanged: (v) => ref.read(nightModeProvider.notifier).set(v))),
              tile('自动监听哭声',
                  icon: AppIcon.autoListen,
                  sub: 'App 在前台时听到哭声自动开始录音（本地识别，不上传）',
                  trailing: Switch(value: auto, onChanged: (v) => ref.read(autoListenProvider.notifier).set(v))),
            ]),
            group([
              tile('全部记录', sub: '查看、修改或删除历史记录', onTap: () => context.push(Routes.logs)),
              tile('导出录音和标注',
                  icon: AppIcon.export,
                  key: const Key('export'),
                  sub: '打包成 zip：记录、哭声判断、反馈和录音',
                  trailing: _exporting ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  onTap: _exporting ? null : _export),
            ]),
            group([
              tile('参与改进（上传匿名数据）',
                  key: const Key('research'),
                  sub: !cloud
                      ? '这个版本未连接云端，暂不可用'
                      : !research
                          ? '默认关闭。只在 Wi-Fi 下上传标注过的哭声'
                          : sync.error ?? '已上传 ${sync.uploaded} 条 · 等待上传 ${sync.pendingUploads} 条（仅 Wi-Fi）',
                  trailing: Switch(value: research, onChanged: cloud ? _toggleResearch : null)),
              if (cloud)
                tile('删除我的数据', key: const Key('research-delete'), sub: '删除云端上传过的哭声片段和标注', onTap: _deleteResearch),
            ]),
            group([
              tile('检查更新',
                  icon: AppIcon.checkUpdate,
                  key: const Key('check-update'),
                  sub: inAppUpdateSupported
                      ? '当前版本 ${ref.watch(packageInfoProvider).value?.version ?? '…'}'
                      : 'iOS 暂不支持应用内更新',
                  onTap: inAppUpdateSupported ? () => context.push(Routes.update) : null),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('哄哄的判断仅供参考，不能替代医生。数据默认只保存在这台手机上，加入家庭或开启参与改进后才会上传。',
                  style: TextStyle(fontSize: 12, color: c.sub, height: 1.6), textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
