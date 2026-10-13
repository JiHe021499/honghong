import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

/// 设置：夜间模式（第 6 屏）、宝宝生日、导出（待实现）
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    final baby = ref.watch(currentBabyProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('夜间模式'),
            subtitle: const Text('暗红色调，半夜不刺眼'),
            value: night,
            onChanged: (v) => ref.read(nightModeProvider.notifier).set(v),
          ),
          ListTile(
            title: const Text('宝宝生日'),
            subtitle: Text(baby == null
                ? '…'
                : DateFormat('yyyy-MM-dd').format(baby.birthDate)),
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
                    await ref
                        .read(babyRepositoryProvider)
                        .updateBirthDate(baby.id, d);
                    ref.invalidate(currentBabyProvider);
                  },
          ),
          const ListTile(
            title: Text('导出录音和标注'),
            subtitle: Text('即将支持'),
            enabled: false,
          ),
          const ListTile(
            title: Text('参与改进（上传匿名数据）'),
            subtitle: Text('第二阶段开放，默认关闭'),
            enabled: false,
          ),
        ],
      ),
    );
  }
}
