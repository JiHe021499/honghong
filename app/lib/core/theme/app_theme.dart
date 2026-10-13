import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 夜间模式开关：夜间模式只是切换一套暗红色调主题。
final nightModeProvider = StateProvider<bool>((ref) => false);

class AppTheme {
  static final day = ThemeData(
    colorSchemeSeed: const Color(0xFFFF8A65),
    useMaterial3: true,
  );

  static final night = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFB71C1C),
      surface: Color(0xFF120808),
      onSurface: Color(0xFFE57373),
    ),
  );
}
