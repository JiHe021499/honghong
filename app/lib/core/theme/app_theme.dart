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
  });

  final bool night;
  final Color bg, card, ink, sub, line;
  final Color peach, peach2, peachL, peachDeep;
  final Color blue, blueL, blueInk, green, greenL, greenInk, seg;
  final Color statusBg, statusInk, cryFrom, cryTo, cryInk;
  final Color runBg, runBorder, endBg, endInk;
  final Color tabBg, tabInk, tabOn, liveRow, shadow;

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
  );

  @override
  Hh copyWith() => this;

  @override
  Hh lerp(Hh? other, double t) => t < .5 ? this : (other ?? this);
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
