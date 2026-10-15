import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../prefs.dart';

/// 夜间模式开关（持久化）：夜间模式切换一套暗红色调主题。
class NightModeNotifier extends Notifier<bool> {
  static const key = 'night_mode';
  @override
  bool build() => ref.watch(prefsProvider).getBool(key) ?? false;

  void toggle() => set(!state);
  void set(bool value) {
    state = value;
    ref.read(prefsProvider).setBool(key, value);
  }
}

final nightModeProvider =
    NotifierProvider<NightModeNotifier, bool>(NightModeNotifier.new);

/// 设计稿 v1.1 的颜色（docs/design/design.html 的 CSS 变量）
@immutable
class Hh extends ThemeExtension<Hh> {
  const Hh({
    required this.night,
    required this.bg,
    required this.card,
    required this.ink,
    required this.sub,
    required this.line,
    required this.peach,
    required this.peach2,
    required this.peachL,
    required this.peachDeep,
    required this.blue,
    required this.blueL,
    required this.blueInk,
    required this.green,
    required this.greenL,
    required this.greenInk,
    required this.seg,
    required this.statusBg,
    required this.statusInk,
    required this.cryFrom,
    required this.cryTo,
    required this.cryInk,
    required this.runBg,
    required this.runBorder,
    required this.endBg,
    required this.endInk,
    required this.tabBg,
    required this.tabInk,
    required this.tabOn,
    required this.liveRow,
    required this.shadow,
    required this.nightness,
    required this.ring,
    required this.statusGradient,
    required this.runGradient,
    required this.cardShadows,
    required this.primaryShadows,
  });

  final bool night;
  final Color bg, card, ink, sub, line;
  final Color peach, peach2, peachL, peachDeep;
  final Color blue, blueL, blueInk, green, greenL, greenInk, seg;
  final Color statusBg, statusInk, cryFrom, cryTo, cryInk;
  final Color runBg, runBorder, endBg, endInk;
  final Color tabBg, tabInk, tabOn, liveRow, shadow;

  /// 0 = 日间，1 = 夜间；日夜切换动画中间是小数。用来给"日夜各一套写死的值"做插值。
  final double nightness;

  /// 呼吸光环 / 日记大按钮的光圈色
  final Color ring;

  /// 状态条 / 小结卡片底（日间渐变，夜间纯色）
  final LinearGradient statusGradient;

  /// 进行中格子底
  final LinearGradient runGradient;

  /// 卡片阴影（夜间无阴影 = 空列表）
  final List<BoxShadow> cardShadows;

  /// 主按钮橙色投影（夜间为空）
  final List<BoxShadow> primaryShadows;

  static const day = Hh(
    night: false,
    bg: Color(0xFFFFF8F0),
    card: Colors.white,
    ink: Color(0xFF3D3A45),
    sub: Color(0xFF8A8494),
    line: Color(0xFFF0E6DC),
    peach: Color(0xFFFFB89A),
    peach2: Color(0xFFFF9874),
    peachL: Color(0xFFFFE7DB),
    peachDeep: Color(0xFFC8603C),
    blue: Color(0xFF8FB8DE),
    blueL: Color(0xFFE3EEF8),
    blueInk: Color(0xFF4E7FAE),
    green: Color(0xFF8CC7A1),
    greenL: Color(0xFFE6F4EA),
    greenInk: Color(0xFF3D8A5A),
    seg: Color(0xFFF3EAE1),
    statusBg: Color(0xFFE3EEF8),
    statusInk: Color(0xFF3D3A45),
    cryFrom: Color(0xFFFFC9AF),
    cryTo: Color(0xFFFF9874),
    cryInk: Colors.white,
    runBg: Color(0xFFFFF4EE),
    runBorder: Color(0xFFFFB89A),
    endBg: Color(0xFFFF9874),
    endInk: Colors.white,
    tabBg: Color(0xEBFFFFFF),
    tabInk: Color(0xFF8A8494),
    tabOn: Color(0xFFFF9874),
    liveRow: Color(0xFFFFF4EE),
    shadow: Color(0x14A0785A),
    nightness: 0,
    ring: Color(0xFFFF9874),
    statusGradient: LinearGradient(colors: [Color(0xFFFFE7DB), Color(0xFFFFF1E8)]),
    runGradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF4EE), Color(0xFFFFE7DB)]),
    cardShadows: [BoxShadow(color: Color(0x14A0785A), blurRadius: 10, offset: Offset(0, 3))],
    primaryShadows: [BoxShadow(color: Color(0x47FF7850), blurRadius: 16, offset: Offset(0, 6))],
  );

  static const nightP = Hh(
    night: true,
    bg: Color(0xFF120C0C),
    card: Color(0xFF1F1210),
    ink: Color(0xFFC0665A),
    sub: Color(0xFF8A4A42),
    line: Color(0xFF2A1714),
    peach: Color(0xFF5A3028),
    peach2: Color(0xFFD0705F),
    peachL: Color(0xFF2A1814),
    peachDeep: Color(0xFFE07A67),
    blue: Color(0xFF5A3028),
    blueL: Color(0xFF24130F),
    blueInk: Color(0xFFD0705F),
    green: Color(0xFF6E3A33),
    greenL: Color(0xFF24130F),
    greenInk: Color(0xFFE07A67),
    seg: Color(0xFF24130F),
    statusBg: Color(0xFF24130F),
    statusInk: Color(0xFFA35A4E),
    cryFrom: Color(0xFF5A221B),
    cryTo: Color(0xFF3A1410),
    cryInk: Color(0xFFE07A67),
    runBg: Color(0xFF2A1814),
    runBorder: Color(0xFF5A3028),
    endBg: Color(0xFF8A3A30),
    endInk: Color(0xFFF8D8D0),
    tabBg: Color(0xFF170E0D),
    tabInk: Color(0xFF6E3A33),
    tabOn: Color(0xFFD0705F),
    liveRow: Color(0xFF24130F),
    shadow: Color(0x00000000),
    nightness: 1,
    ring: Color(0xFFA03228),
    statusGradient: LinearGradient(colors: [Color(0xFF24130F), Color(0xFF24130F)]),
    runGradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2A1814), Color(0xFF2A1814)]),
    cardShadows: [],
    primaryShadows: [],
  );

  @override
  Hh copyWith() => this;

  @override
  Hh lerp(Hh? other, double t) {
    final o = other;
    if (o == null) return this;
    if (t <= 0) return this;
    if (t >= 1) return o;
    return Hh(
      // 布尔值不能插值：过半跳变
      night: t < .5 ? night : o.night,
      bg: Color.lerp(bg, o.bg, t)!,
      card: Color.lerp(card, o.card, t)!,
      ink: Color.lerp(ink, o.ink, t)!,
      sub: Color.lerp(sub, o.sub, t)!,
      line: Color.lerp(line, o.line, t)!,
      peach: Color.lerp(peach, o.peach, t)!,
      peach2: Color.lerp(peach2, o.peach2, t)!,
      peachL: Color.lerp(peachL, o.peachL, t)!,
      peachDeep: Color.lerp(peachDeep, o.peachDeep, t)!,
      blue: Color.lerp(blue, o.blue, t)!,
      blueL: Color.lerp(blueL, o.blueL, t)!,
      blueInk: Color.lerp(blueInk, o.blueInk, t)!,
      green: Color.lerp(green, o.green, t)!,
      greenL: Color.lerp(greenL, o.greenL, t)!,
      greenInk: Color.lerp(greenInk, o.greenInk, t)!,
      seg: Color.lerp(seg, o.seg, t)!,
      statusBg: Color.lerp(statusBg, o.statusBg, t)!,
      statusInk: Color.lerp(statusInk, o.statusInk, t)!,
      cryFrom: Color.lerp(cryFrom, o.cryFrom, t)!,
      cryTo: Color.lerp(cryTo, o.cryTo, t)!,
      cryInk: Color.lerp(cryInk, o.cryInk, t)!,
      runBg: Color.lerp(runBg, o.runBg, t)!,
      runBorder: Color.lerp(runBorder, o.runBorder, t)!,
      endBg: Color.lerp(endBg, o.endBg, t)!,
      endInk: Color.lerp(endInk, o.endInk, t)!,
      tabBg: Color.lerp(tabBg, o.tabBg, t)!,
      tabInk: Color.lerp(tabInk, o.tabInk, t)!,
      tabOn: Color.lerp(tabOn, o.tabOn, t)!,
      liveRow: Color.lerp(liveRow, o.liveRow, t)!,
      shadow: Color.lerp(shadow, o.shadow, t)!,
      nightness: lerpDouble(nightness, o.nightness, t)!,
      ring: Color.lerp(ring, o.ring, t)!,
      statusGradient: LinearGradient.lerp(statusGradient, o.statusGradient, t)!,
      runGradient: LinearGradient.lerp(runGradient, o.runGradient, t)!,
      cardShadows: BoxShadow.lerpList(cardShadows, o.cardShadows, t)!,
      primaryShadows: BoxShadow.lerpList(primaryShadows, o.primaryShadows, t)!,
    );
  }

  /// 日/夜各写死一个颜色时用：按 [nightness] 插值
  Color dn(Color day, Color night) => nightness <= 0 ? day : nightness >= 1 ? night : Color.lerp(day, night, nightness)!;

  /// 日/夜各一个数值（透明度等）
  double dnd(double day, double night) => lerpDouble(day, night, nightness)!;

  /// 日/夜各一组阴影（null 视为无阴影）
  List<BoxShadow>? dnShadows(List<BoxShadow>? day, List<BoxShadow>? night) =>
      nightness <= 0 ? day : nightness >= 1 ? night : BoxShadow.lerpList(day, night, nightness);

  /// 日间渐变 → 夜间纯色：把纯色当成同方向的单色渐变来插值
  Gradient dnFill(LinearGradient day, Color night) => nightness <= 0
      ? day
      : LinearGradient.lerp(day, LinearGradient(begin: day.begin, end: day.end, colors: [night, night]), nightness)!;
}

extension HhX on BuildContext {
  Hh get hh => Theme.of(this).extension<Hh>() ?? Hh.day;
}

class AppTheme {
  static ThemeData _build(Hh c) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: c.night ? Brightness.dark : Brightness.light,
      fontFamilyFallback: const ['PingFang SC', 'Noto Sans CJK SC', 'Noto Sans SC', 'Noto Color Emoji'],
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.peach2,
        brightness: c.night ? Brightness.dark : Brightness.light,
        primary: c.peach2,
        surface: c.bg,
        onSurface: c.ink,
      ),
      extensions: [c],
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.night ? const Color(0xFF1A100E) : c.bg,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        showDragHandle: false,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.green : (c.night ? c.line : const Color(0xFFDDD5CC))),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dividerColor: c.line,
    );
  }

  static final day = _build(Hh.day);
  static final night = _build(Hh.nightP);
}
