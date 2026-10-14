import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/care_log_repository.dart';
import '../../data/repositories/diary_repository.dart';
import '../models/care_detail.dart';
import '../models/care_log_type.dart';
import 'diary_card.dart';
import 'parse_result.dart';

/// 卡片 → 落库映射与事务保存（架构 §3.4）。
class DiaryService {
  DiaryService(AppDatabase db) : _repo = DiaryRepository(db), _logs = CareLogRepository(db);
  final DiaryRepository _repo;
  final CareLogRepository _logs;

  static CareLogType? careType(DiaryCategory c) => switch (c) {
        DiaryCategory.feeding => CareLogType.feed,
        DiaryCategory.sleep => CareLogType.sleep,
        DiaryCategory.diaper => CareLogType.diaper,
        _ => null,
      };

  /// 会写 care_logs 的卡：喂奶/睡眠/尿布的单次事件
  static bool writesCareLog(DiaryCardDraftUi c) => c.category.isCare && !c.aggregate;

  /// 确认页展示前的检查：重复提醒（D1，默认取消勾选）、睡眠进行中（D4）。
  Future<void> prepare(String babyId, ParseResult r) async {
    final activeSleep = await _logs.activeSession(babyId, CareLogType.sleep);
    for (final c in r.cards) {
      final t = careType(c.category);
      c.duplicate = false;
      c.sleepOngoing = false;
      c.sleepConflict = false;
      if (t == null || c.aggregate) continue;
      final at = c.eventTime ?? c.sortTime;
      if ((await _repo.possibleDuplicates(babyId, t, at)).isNotEmpty) {
        c.duplicate = true;
        c.selected = false;
      }
      if (t == CareLogType.sleep && _isOngoingSleep(c)) {
        if (activeSleep != null) {
          c.sleepConflict = true;
        } else {
          c.sleepOngoing = true;
        }
      }
    }
  }

  /// 只有开始时间（没有结束时间和时长）的睡眠 → 进行中（D4）
  static bool _isOngoingSleep(DiaryCardDraftUi c) => c.eventTime != null && c.endTime == null && c.intAttr('duration_min') == null;

  CareLogsCompanion? _careLog(String babyId, DiaryCardDraftUi c) {
    final t = careType(c.category);
    if (t == null || c.aggregate) return null;
    final dur = c.intAttr('duration_min');
    // 只有时长没有开始时间：按“到排序时间为止”倒推，避免结束时间落到未来
    final start = c.eventTime ?? (dur != null && c.endTime == null ? c.sortTime.subtract(Duration(minutes: dur)) : c.sortTime);
    DateTime? end;
    switch (t) {
      case CareLogType.sleep:
        if (c.sleepConflict) return null; // 已有进行中的睡眠：只存卡片，不新开
        end = c.endTime ?? (dur != null ? start.add(Duration(minutes: dur)) : null);
        if (end == null && !c.sleepOngoing) {
          if (c.eventTime == null) return null; // 没时间也没时长：只存卡片，不造会话
        }
      case CareLogType.feed:
        end = c.endTime ?? (dur != null ? start.add(Duration(minutes: dur)) : start);
      default:
        end = start;
    }
    final detail = switch (t) {
      CareLogType.feed => CareDetail(method: c.feedMethod, side: c.feedSide, ml: c.intAttr('ml')),
      CareLogType.diaper => CareDetail(diaper: c.diaperKind ?? DiaperKind.unknown),
      _ => null,
    };
    return CareLogsCompanion(
      babyId: Value(babyId),
      type: Value(t.name),
      startedAt: Value(start),
      endedAt: Value(end),
      detail: Value(detail?.encode()),
    );
  }

  /// 事务保存勾选的卡片。返回保存的条数。
  Future<int> save({required String babyId, required int ageInDays, required ParseResult r}) async {
    final picked = r.cards.where((c) => c.selected).toList();
    if (picked.isEmpty) return 0;
    final drafts = [
      for (final c in picked)
        DiaryCardDraft(
          DiaryCardsCompanion(
            babyId: Value(babyId),
            category: Value(c.category.name),
            kind: Value(c.aggregate ? 'aggregate' : 'event'),
            eventTime: Value(c.eventTime),
            timePeriod: Value(c.period?.wire),
            sortTime: Value(c.eventTime ?? c.sortTime),
            diaryDate: Value(c.diaryDate),
            attributes: Value(jsonEncode(c.attributes)),
            intensity: Value(c.intensity),
            note: Value(c.note),
            confidence: Value(c.confidence),
            editedByUser: Value(c.edited),
          ),
          careLog: _careLog(babyId, c),
        ),
    ];
    await _repo.saveInput(
      DiaryInputsCompanion(
        babyId: Value(babyId),
        inputType: Value(r.inputType),
        rawText: Value(r.rawText),
        ageInDays: Value(ageInDays),
        parseStatus: Value(r.status),
        promptVersion: Value(r.promptVersion),
        modelVersion: Value(r.model),
        latencyMs: Value(r.latencyMs),
        createdAt: Value(r.createdAt),
      ),
      drafts,
    );
    return picked.length;
  }
}
