import 'dart:convert';

import 'care_log_type.dart';

/// 喂奶方式
enum FeedMethod {
  breast('母乳'),
  bottleBreast('瓶喂母乳'),
  formula('配方奶');

  const FeedMethod(this.label);
  final String label;
}

enum FeedSide {
  left('左侧'),
  right('右侧'),
  both('两侧');

  const FeedSide(this.label);
  final String label;
}

enum DiaperKind {
  unknown('未分类'),
  pee('小便'),
  poo('大便'),
  both('都有'),
  dry('干爽');

  const DiaperKind(this.label);
  final String label;
}

/// care_logs.detail 字段的结构化表示（JSON）。
class CareDetail {
  const CareDetail({this.method, this.side, this.ml, this.note, this.diaper});

  final FeedMethod? method;
  final FeedSide? side;
  final int? ml;
  final String? note; // 睡觉/拍嗝备注，例如"小睡"
  final DiaperKind? diaper;

  static const feedAmounts = [60, 90, 120, 150];
  static const sleepNotes = ['小睡', '夜间长觉', '不易入睡'];
  static const burpNotes = ['打出来了', '没打出', '吐奶'];

  Map<String, Object?> toJson() => {
        if (method != null) 'method': method!.name,
        if (side != null) 'side': side!.name,
        if (ml != null) 'ml': ml,
        if (note != null && note!.isNotEmpty) 'note': note,
        if (diaper != null) 'diaper': diaper!.name,
      };

  String encode() => jsonEncode(toJson());

  static CareDetail decode(String? s) {
    if (s == null || s.isEmpty) return const CareDetail();
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      T? e<T extends Enum>(List<T> vs, Object? n) =>
          n is String ? vs.where((v) => v.name == n).firstOrNull : null;
      return CareDetail(
        method: e(FeedMethod.values, j['method']),
        side: e(FeedSide.values, j['side']),
        ml: (j['ml'] as num?)?.toInt(),
        note: j['note'] as String?,
        diaper: e(DiaperKind.values, j['diaper']),
      );
    } catch (_) {
      return const CareDetail();
    }
  }
}

/// 时长的人话格式："42 分钟"、"1 小时 5 分"、"40 秒"
String formatDuration(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds} 秒';
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m 分钟';
  return m == 0 ? '$h 小时' : '$h 小时 $m 分';
}

/// 计时器显示："3:20"、"1:05:09"
String formatTimer(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// 时间线条目文字，如"母乳 · 左侧 15 分钟"、"午睡 · 42 分钟"、"换尿布 · 小便"
String describeLog(CareLogType type, DateTime start, DateTime? end, String? detailJson) {
  final d = CareDetail.decode(detailJson);
  final dur = end?.difference(start);
  switch (type) {
    case CareLogType.feed:
      final parts = <String>[
        if (d.side != null && (d.method ?? FeedMethod.breast) == FeedMethod.breast)
          d.side!.label,
        if (dur != null) formatDuration(dur),
        if (d.ml != null) '${d.ml}ml',
      ];
      return '${(d.method ?? FeedMethod.breast).label} · ${parts.join(' ')}';
    case CareLogType.sleep:
      final name = d.note ?? (start.hour >= 19 || start.hour < 6 ? '夜睡' : (start.hour >= 11 && start.hour < 15 ? '午睡' : '小睡'));
      return dur == null ? name : '$name · ${formatDuration(dur)}';
    case CareLogType.burp:
      final t = dur == null ? '拍嗝' : '拍嗝 · ${formatDuration(dur)}';
      return d.note == null ? t : '$t · ${d.note}';
    case CareLogType.diaper:
      return '换尿布 · ${(d.diaper ?? DiaperKind.unknown).label}';
  }
}

extension CareLogTypeUi on CareLogType {
  String get emoji => switch (this) {
        CareLogType.feed => '🍼',
        CareLogType.sleep => '😴',
        CareLogType.diaper => '🧷',
        CareLogType.burp => '🫧',
      };

  /// 是否是"开始 → 结束"的计时类型
  bool get isTimed => this != CareLogType.diaper;

  String get runningLabel => switch (this) {
        CareLogType.feed => '喂奶中',
        CareLogType.sleep => '睡觉中',
        CareLogType.burp => '拍嗝中',
        CareLogType.diaper => '换尿布',
      };
}
