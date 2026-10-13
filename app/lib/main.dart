import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/home/home_page.dart';

void main() {
  runApp(const ProviderScope(child: HonghongApp()));
}

class HonghongApp extends ConsumerWidget {
  const HonghongApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    return MaterialApp(
      title: '哄哄',
      theme: AppTheme.day,
      darkTheme: AppTheme.night,
      themeMode: night ? ThemeMode.dark : ThemeMode.light,
      home: const HomePage(),
    );
  }
}
