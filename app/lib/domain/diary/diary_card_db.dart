import 'dart:convert';

import '../../data/db/app_database.dart';
import 'diary_card.dart';

/// 已保存的 diary_cards 行 → 展示用模型
DiaryCardDraftUi cardFromDb(DiaryCard r) {
  Map<String, Object?> attrs;
  try {
    attrs = Map<String, Object?>.from(jsonDecode(r.attributes) as Map);
  } catch (_) {
    attrs = {};
  }
  return DiaryCardDraftUi(
    category: DiaryCategory.parse(r.category),
    aggregate: r.kind == 'aggregate',
    eventTime: r.eventTime,
    period: DiaryPeriod.parse(r.timePeriod),
    diaryDate: r.diaryDate,
    sortTime: r.sortTime,
    attributes: attrs,
    intensity: r.intensity,
    note: r.note,
    confidence: r.confidence ?? 1,
  );
}
