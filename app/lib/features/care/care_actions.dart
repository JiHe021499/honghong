import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/care_detail.dart';
import '../../domain/models/care_log_type.dart';
import 'care_sheets.dart';
import '../../core/app_clock.dart';

/// 首页快捷记录的交互：开始计时 / 结束（弹面板）/ 换尿布一点即记
class CareActions {
  CareActions(this.ref);
  final WidgetRef ref;

  Future<void> start(CareLogType t) async {
    final baby = await ref.read(currentBabyProvider.future);
    await ref.read(careLogRepositoryProvider).startSession(baby.id, t);
  }

  /// 点"结束"：先停表写入结束时间，再弹出详情面板。
  Future<void> end(BuildContext context, CareLog log) async {
    final repo = ref.read(careLogRepositoryProvider);
    final stoppedAt = AppClock.now();
    await repo.stopSession(log.id, at: stoppedAt);
    final previous = await _previousDetail(log);
    if (!context.mounted) return;
    final result = await showSessionEndSheet(context, log, stoppedAt, previous: previous);
    // "继续"或直接关掉面板：回到进行中，避免误结束
    if (result == null || result.resume) {
      await repo.resumeSession(log.id);
      return;
    }
    await repo.saveSession(log.id, duration: result.duration, detail: result.detail);
  }

  Future<CareDetail?> _previousDetail(CareLog log) async {
    if (log.type != CareLogType.feed.name) return null;
    final latest = await ref.read(careLogRepositoryProvider).latestByType(log.babyId);
    final prev = latest[CareLogType.feed];
    if (prev == null || prev.id == log.id) return null;
    return CareDetail.decode(prev.detail);
  }

  Future<String> logDiaper() async {
    final baby = await ref.read(currentBabyProvider.future);
    return ref.read(careLogRepositoryProvider).logDiaper(baby.id);
  }

  Future<void> editDiaper(BuildContext context, CareLog log) async {
    final kind = await showDiaperSheet(context, log);
    if (kind == null) return;
    await ref.read(careLogRepositoryProvider).updateDetail(log.id, CareDetail(diaper: kind));
  }

  /// 时间线条目点击：换尿布改类型；已结束的计时记录改时长和细节
  Future<void> editLog(BuildContext context, CareLog log) async {
    if (log.type == CareLogType.diaper.name) return editDiaper(context, log);
    if (log.endedAt == null) return end(context, log);
    final result = await showSessionEndSheet(context, log, log.endedAt!, editing: true);
    if (result == null || result.resume) return;
    await ref.read(careLogRepositoryProvider).saveSession(log.id, duration: result.duration, detail: result.detail);
  }
}
