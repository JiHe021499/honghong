import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_clock.dart';

/// 妈咪日记内测埋点（架构 P6）：只在本机按天累计次数，不上传（架构 §7：
/// 上报准确率需单独同意，后续再做）。内测用户可在设置里查看/复制给我们。
enum DiaryMetric {
  /// 一次有效的按住说话（≥1 秒且未取消），或启动识别失败
  voice('voice'),

  /// 识别失败：启动不了、或识别结果为空
  voiceFail('voice_fail'),

  /// 确认页保存
  save('save'),

  /// 确认页未改任何卡片、未取消勾选，直接保存
  saveOneTap('save_1tap'),

  /// 保存时整理出的卡片数（含取消勾选的）
  cards('cards'),

  /// 被修改/取消勾选/删除的卡片（确认页 + 之后在时间线上改/删，每张最多计 1 次）
  cardsChanged('cards_changed'),

  /// 当天打开了已生成的小结（每天最多计 1 次）
  summaryView('summary_view');

  const DiaryMetric(this.wire);
  final String wire;
}

class DiaryMetrics {
  DiaryMetrics(this._prefs);
  final SharedPreferences _prefs;
  static const key = 'diary_metrics_v1';
  static const keepDays = 30;

  Map<String, Map<String, int>> _load() {
    try {
      final raw = jsonDecode(_prefs.getString(key) ?? '{}') as Map<String, dynamic>;
      return raw.map((d, v) => MapEntry(d, Map<String, int>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  static String _ymd(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  Future<void> add(DiaryMetric m, [int n = 1]) async {
    if (n <= 0) return;
    final all = _load();
    final now = AppClock.now();
    final day = all.putIfAbsent(_ymd(now), () => {});
    if (m == DiaryMetric.summaryView && (day[m.wire] ?? 0) > 0) return;
    day[m.wire] = (day[m.wire] ?? 0) + n;
    final cutoff = _ymd(now.subtract(const Duration(days: keepDays)));
    all.removeWhere((d, _) => d.compareTo(cutoff) < 0);
    await _prefs.setString(key, jsonEncode(all));
  }

  /// 最近 [days] 天合计
  Map<DiaryMetric, int> totals({int days = 7}) {
    final now = AppClock.now();
    final from = _ymd(now.subtract(Duration(days: days - 1)));
    final out = {for (final m in DiaryMetric.values) m: 0};
    _load().forEach((d, v) {
      if (d.compareTo(from) < 0) return;
      for (final m in DiaryMetric.values) {
        out[m] = out[m]! + (v[m.wire] ?? 0);
      }
    });
    return out;
  }

  /// 三个核心比率（分母为 0 时为 null）
  static ({double? oneTap, double? cardChange, double? voiceFail}) rates(Map<DiaryMetric, int> t) {
    double? r(int a, int b) => b == 0 ? null : a / b;
    return (
      oneTap: r(t[DiaryMetric.saveOneTap]!, t[DiaryMetric.save]!),
      cardChange: r(t[DiaryMetric.cardsChanged]!, t[DiaryMetric.cards]!),
      voiceFail: r(t[DiaryMetric.voiceFail]!, t[DiaryMetric.voice]!),
    );
  }

  /// 给内测用户复制发回的纯文本（只有次数，无任何内容）
  String report({int days = 7}) {
    final t = totals(days: days);
    final r = rates(t);
    String p(double? v) => v == null ? '—' : '${(v * 100).round()}%';
    return [
      '妈咪日记内测数据（近 $days 天，仅次数）',
      '一键保存率 ${p(r.oneTap)}（${t[DiaryMetric.saveOneTap]}/${t[DiaryMetric.save]}）',
      '卡片修改率 ${p(r.cardChange)}（${t[DiaryMetric.cardsChanged]}/${t[DiaryMetric.cards]}）',
      '识别失败率 ${p(r.voiceFail)}（${t[DiaryMetric.voiceFail]}/${t[DiaryMetric.voice]}）',
      '查看小结 ${t[DiaryMetric.summaryView]} 天',
    ].join('\n');
  }
}
