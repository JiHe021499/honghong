import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/prefs.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  final prefs = await SharedPreferences.getInstance();
  if (cloudConfigured) {
    try {
      await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
    } catch (_) {
      // 云端不可用时照常离线使用
    }
  }
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const HonghongApp(),
  ));
}

class HonghongApp extends ConsumerWidget {
  const HonghongApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeProvider);
    return MaterialApp.router(
      title: '哄哄',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.day,
      darkTheme: AppTheme.night,
      themeMode: night ? ThemeMode.dark : ThemeMode.light,
      // 日夜切换：整页颜色 400ms easeInOut 插值（与首页日夜图标同步）；系统"减少动态"时瞬切
      themeAnimationDuration: MediaQueryData.fromView(View.of(context)).disableAnimations ? Duration.zero : const Duration(milliseconds: 400),
      themeAnimationCurve: Curves.easeInOut,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
