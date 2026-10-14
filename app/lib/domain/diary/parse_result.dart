import 'diary_card.dart';
import 'risk_words.dart';

/// 一次输入的整理结果（网关返回 + 客户端二次校验后），确认页的数据来源。
class ParseResult {
  ParseResult({
    required this.rawText,
    required this.inputType,
    required this.status,
    required this.cards,
    required this.risk,
    required this.createdAt,
    this.promptVersion = 'none',
    this.model,
    this.latencyMs,
    this.failed = false,
    this.offline = false,
  });

  final String rawText;

  /// voice | text
  final String inputType;

  /// ok | partial | failed
  final String status;
  final List<DiaryCardDraftUi> cards;
  final bool risk;
  final DateTime createdAt;
  final String promptVersion;
  final String? model;
  final int? latencyMs;

  /// AI 整理失败：原话存为一张“其他”（屏 14）
  final bool failed;

  /// 未配置 AI 网关：只能手动选分类保存
  final bool offline;

  /// 整理失败 / 未配置时的兜底：原话一张 other 卡
  factory ParseResult.fallback(String text, {required String inputType, required DateTime now, bool offline = false}) => ParseResult(
        rawText: text,
        inputType: inputType,
        status: 'failed',
        failed: true,
        offline: offline,
        risk: hasRiskWords(text),
        createdAt: now,
        cards: [
          DiaryCardDraftUi(
              category: DiaryCategory.other,
              aggregate: false,
              diaryDate: DateTime(now.year, now.month, now.day),
              sortTime: now,
              note: text.length > 200 ? text.substring(0, 200) : text,
              confidence: 0.3),
        ],
      );

  /// 解析网关响应并做客户端二次校验（架构 §5.2），时间按 [now] 组装。
  factory ParseResult.fromGateway(Map<String, dynamic> j,
      {required String text, required String inputType, required DateTime now, int? latencyMs}) {
    final raw = j['cards'];
    final cards = <DiaryCardDraftUi>[];
    if (raw is List) {
      for (final c in raw.take(10)) {
        if (c is Map) cards.add(cardFromJson(Map<String, dynamic>.from(c), now: now, rawText: text));
      }
    }
    if (cards.isEmpty) return ParseResult.fallback(text, inputType: inputType, now: now);
    final risk = j['risk'];
    return ParseResult(
      rawText: text,
      inputType: inputType,
      status: j['status'] == 'partial' ? 'partial' : 'ok',
      cards: cards,
      risk: (risk is Map && risk['hit'] == true) || hasRiskWords(text),
      createdAt: now,
      promptVersion: j['prompt_version'] as String? ?? 'unknown',
      model: j['model'] as String?,
      latencyMs: latencyMs,
    );
  }
}

const _attrKeys = {
  DiaryCategory.feeding: {'count': (1, 30), 'method': null, 'side': null, 'ml': (1, 400), 'duration_min': (1, 180)},
  DiaryCategory.sleep: {'duration_min': (1, 960), 'night_wakings': (0, 20)},
  DiaryCategory.diaper: {'type': null, 'count': (1, 30), 'texture_note': null},
  DiaryCategory.mood: {'type': null},
  DiaryCategory.other: {'topic': null},
};
const _enums = {'method': ['breast', 'bottle_breast', 'formula'], 'side': ['left', 'right', 'both'], 'type@diaper': ['pee', 'poo', 'both']};

/// 客户端二次校验：不认识的键丢弃、越界置空并标“请核对”
Map<String, Object?> sanitizeAttributes(DiaryCategory cat, Object? attrs, void Function() flag) {
  final out = <String, Object?>{};
  if (attrs is! Map) return out;
  final rules = _attrKeys[cat]!;
  attrs.forEach((k, v) {
    if (k is! String || !rules.containsKey(k) || v == null) return;
    final range = rules[k];
    if (range != null) {
      if (v is int && v >= range.$1 && v <= range.$2) {
        out[k] = v;
      } else {
        flag();
      }
      return;
    }
    final allowed = _enums[cat == DiaryCategory.diaper && k == 'type' ? 'type@diaper' : k];
    if (allowed != null) {
      if (allowed.contains(v)) {
        out[k] = v;
      } else {
        flag();
      }
      return;
    }
    if (v is String && v.trim().isNotEmpty && v.length <= 30) out[k] = v.trim();
  });
  return out;
}

final _hhmm = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

/// 时间组装（架构 §3.5、§5.2-3）
({DateTime? event, DateTime? end, DateTime sort, DateTime diaryDate, bool flagged}) assembleTime({
  required DateTime now,
  String? eventTime,
  String? endTime,
  int dayOffset = 0,
  DiaryPeriod? period,
}) {
  var flagged = false;
  final today = DateTime(now.year, now.month, now.day);
  final base = DateTime(today.year, today.month, today.day + (dayOffset == -1 ? -1 : 0));
  DateTime? at(String? hhmm) {
    final m = hhmm == null ? null : _hhmm.firstMatch(hhmm);
    if (m == null) return null;
    var t = DateTime(base.year, base.month, base.day, int.parse(m[1]!), int.parse(m[2]!));
    if (t.isAfter(now.add(const Duration(minutes: 10)))) t = DateTime(t.year, t.month, t.day - 1, t.hour, t.minute); // 视为前一天
    if (t.isBefore(now.subtract(const Duration(hours: 48)))) {
      flagged = true;
      return null;
    }
    return t;
  }

  final event = at(eventTime);
  var end = at(endTime);
  if (event != null && end != null && !end.isAfter(event)) {
    end = DateTime(end.year, end.month, end.day + 1, end.hour, end.minute);
    if (end.isAfter(now.add(const Duration(minutes: 10)))) end = null; // 跨天后跑到未来：不猜
  }
  DateTime sort;
  if (event != null) {
    sort = event;
  } else if (period != null && period != DiaryPeriod.allDay) {
    // 凌晨补记“夜里” → 03:00（当天凌晨），归属日期仍按 day_offset 计
    final earlyMorning = now.hour < 5;
    sort = period == DiaryPeriod.night && earlyMorning
        ? DateTime(today.year, today.month, today.day, 3)
        : DateTime(base.year, base.month, base.day, period.defaultHour);
    if (sort.isAfter(now)) sort = now;
  } else {
    sort = dayOffset == -1 ? DateTime(base.year, base.month, base.day, 23, 59) : now;
  }
  final ref = event ?? (dayOffset == -1 ? base : sort);
  final diaryDate = dayOffset == -1 ? base : DateTime(ref.year, ref.month, ref.day);
  return (event: event, end: end, sort: sort, diaryDate: diaryDate, flagged: flagged);
}

final _diagnosis = RegExp('生病|病了|不正常|异常|需要用药|吃药|用药|诊断|感染|严重|危险|可能是');

DiaryCardDraftUi cardFromJson(Map<String, dynamic> c, {required DateTime now, required String rawText}) {
  var flagged = false;
  final catRaw = c['category'];
  final cat = DiaryCategory.parse(catRaw);
  if (catRaw != cat.name) flagged = true;
  final aggregate = c['kind'] == 'aggregate';
  final period = DiaryPeriod.parse(c['time_period']) ?? (aggregate ? DiaryPeriod.allDay : null);
  final t = assembleTime(
    now: now,
    eventTime: c['event_time'] as String?,
    endTime: c['end_time'] as String?,
    dayOffset: c['day_offset'] == -1 ? -1 : 0,
    period: period,
  );
  final attrs = sanitizeAttributes(cat, c['attributes'], () => flagged = true);
  String? note = c['note'] is String ? (c['note'] as String).trim() : null;
  if (note != null && note.length > 200) note = note.substring(0, 200);
  if (note != null && _diagnosis.hasMatch(note) && !_diagnosis.hasMatch(rawText)) {
    note = rawText.length > 200 ? rawText.substring(0, 200) : rawText;
    flagged = true;
  }
  String? intensity = c['intensity'] is String ? (c['intensity'] as String).trim() : null;
  if (intensity != null && (intensity.isEmpty || intensity.length > 20 || (_diagnosis.hasMatch(intensity) && !_diagnosis.hasMatch(rawText)))) {
    intensity = null;
  }
  var conf = c['confidence'] is num ? (c['confidence'] as num).toDouble().clamp(0.0, 1.0) : 0.5;
  if (flagged || t.flagged) conf = conf < 0.5 ? conf : 0.5;
  return DiaryCardDraftUi(
    category: cat,
    aggregate: aggregate,
    eventTime: t.event,
    endTime: t.end,
    period: period,
    diaryDate: t.diaryDate,
    sortTime: t.sort,
    attributes: attrs,
    intensity: intensity,
    note: note,
    confidence: conf,
  );
}
