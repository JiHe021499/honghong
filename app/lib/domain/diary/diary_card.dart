import '../models/care_detail.dart';

/// 日记卡片分类（与网关 schema 一致）
enum DiaryCategory {
  feeding('喂奶'),
  sleep('睡眠'),
  diaper('尿布'),
  mood('情绪'),
  other('其他');

  const DiaryCategory(this.label);
  final String label;

  static DiaryCategory parse(Object? v) => DiaryCategory.values.where((c) => c.name == v).firstOrNull ?? DiaryCategory.other;

  /// 单次事件会写入 care_logs（架构 §3.4）
  bool get isCare => this == feeding || this == sleep || this == diaper;
}

enum DiaryPeriod {
  morning('上午', 9),
  afternoon('下午', 15),
  evening('晚上', 19),
  night('夜里', 23),
  allDay('当日', -1);

  const DiaryPeriod(this.label, this.defaultHour);
  final String label;
  final int defaultHour;

  static DiaryPeriod? parse(Object? v) => switch (v) {
        'morning' => morning,
        'afternoon' => afternoon,
        'evening' => evening,
        'night' => night,
        'all_day' => allDay,
        _ => null,
      };
  String get wire => this == allDay ? 'all_day' : name;
}

/// 确认页上的一张卡（可就地编辑）。时间由客户端根据 now 组装（架构 §3.5）。
class DiaryCardDraftUi {
  DiaryCardDraftUi({
    required this.category,
    required this.aggregate,
    this.eventTime,
    this.endTime,
    this.period,
    required this.diaryDate,
    required this.sortTime,
    Map<String, Object?>? attributes,
    this.intensity,
    this.note,
    this.confidence = 1,
    this.selected = true,
    this.duplicate = false,
    this.sleepOngoing = false,
    this.sleepConflict = false,
    this.edited = false,
  }) : attributes = attributes ?? {};

  DiaryCategory category;
  bool aggregate;
  DateTime? eventTime;
  DateTime? endTime;
  DiaryPeriod? period;
  DateTime diaryDate;
  DateTime sortTime;
  Map<String, Object?> attributes;
  String? intensity;
  String? note;
  double confidence;
  bool selected;

  /// ±15 分钟内首页已有同类记录（D1）：提示并默认取消勾选
  bool duplicate;

  /// 睡眠只有开始时间：记为进行中（D4）
  bool sleepOngoing;

  /// 已有进行中的睡眠：不新开，提示核对（D4）
  bool sleepConflict;
  bool edited;

  bool get needsReview => confidence < 0.6;

  int? intAttr(String k) => attributes[k] is int ? attributes[k] as int : null;
  String? strAttr(String k) => attributes[k] is String ? attributes[k] as String : null;

  FeedMethod? get feedMethod => switch (strAttr('method')) {
        'breast' => FeedMethod.breast,
        'bottle_breast' => FeedMethod.bottleBreast,
        'formula' => FeedMethod.formula,
        _ => null,
      };
  FeedSide? get feedSide => switch (strAttr('side')) {
        'left' => FeedSide.left,
        'right' => FeedSide.right,
        'both' => FeedSide.both,
        _ => null,
      };
  DiaperKind? get diaperKind => switch (strAttr('type')) {
        'pee' => DiaperKind.pee,
        'poo' => DiaperKind.poo,
        'both' => DiaperKind.both,
        _ => null,
      };
}
