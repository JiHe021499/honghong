import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import 'diary_providers.dart';

/// 首页入口卡（屏 1；21:00 后小结已生成时为屏 2 的蓝色样式）。夜间模式跟时间线一起隐藏。
class DiaryEntryCard extends ConsumerWidget {
  const DiaryEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    final summary = ref.watch(todaySummaryReadyProvider);
    // 失败满 3 次：只提示“小结未生成”，不放重试按钮，点卡片进小结页再重试
    final failed = !summary && ref.watch(todaySummaryFailedProvider);
    return GestureDetector(
      key: const Key('diary-entry'),
      onTap: () => context.push(summary || failed ? Routes.diarySummary : Routes.diary),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: summary ? const [Color(0xFFE3EEF8), Color(0xFFF2F7FC)] : const [Color(0xFFFFF4EE), Color(0xFFFFE7DB)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: summary ? const Color(0x808FB8DE) : const Color(0x59FF9874)),
          boxShadow: const [BoxShadow(color: Color(0x14A0785A), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: const HhIcon(AppIcon.diary, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('妈咪日记', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: c.peach2, borderRadius: BorderRadius.circular(8)),
                  child: const Text('新', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                  summary
                      ? '今日小结已生成 · 点开看看'
                      : failed
                          ? '小结未生成'
                          : '说一句话，帮你把今天记下来',
                  key: const Key('diary-entry-sub'), style: TextStyle(fontSize: 12, color: c.sub)),
            ]),
          ),
          const HhIcon(AppIcon.chevronRight, size: 18),
        ]),
      ),
    );
  }
}
