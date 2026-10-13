import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cry/recording_page.dart';
import '../../features/cry/result_page.dart';
import '../../features/family/family_page.dart';
import '../../features/feedback/feedback_page.dart';
import '../../features/home/home_page.dart';
import '../../features/insights/insights_page.dart';
import '../../features/logs/log_detail_page.dart';
import '../../features/settings/settings_page.dart';
import '../theme/app_theme.dart';

class Routes {
  static const home = '/';
  static const recording = '/cry/record';
  static String result(String id) => '/cry/result/$id';
  static String feedback(String id) => '/feedback/$id';
  static const logs = '/logs';
  static const insights = '/insights';
  static const family = '/family';
  static const settings = '/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => TabShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomePage())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.insights, builder: (_, _) => const InsightsPage())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.family, builder: (_, _) => const FamilyPage())]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.settings, builder: (_, _) => const SettingsPage())]),
        ],
      ),
      GoRoute(
        path: Routes.recording,
        builder: (_, s) => RecordingPage(auto: s.uri.queryParameters['auto'] == '1'),
      ),
      GoRoute(path: '/cry/result/:id', builder: (_, s) => ResultPage(eventId: s.pathParameters['id']!)),
      GoRoute(path: '/feedback/:id', builder: (_, s) => FeedbackPage(eventId: s.pathParameters['id']!)),
      GoRoute(path: Routes.logs, builder: (_, _) => const LogDetailPage()),
    ],
  );
});

/// 底部四个标签：首页 / 规律 / 家庭 / 我的（设计稿 .tab）
class TabShell extends StatelessWidget {
  const TabShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const tabs = [('🏠', '首页'), ('📊', '规律'), ('👨‍👩‍👧', '家庭'), ('⚙️', '我的')];

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: c.tabBg, border: Border(top: BorderSide(color: c.night ? const Color(0xFF2A1714) : c.line))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: GestureDetector(
                    key: Key('tab-$i'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Opacity(
                        opacity: c.night ? .55 : 1,
                        child: Text(tabs[i].$1, style: const TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(height: 3),
                      Text(tabs[i].$2,
                          style: TextStyle(
                            fontSize: 11,
                            color: i == shell.currentIndex ? c.tabOn : c.tabInk,
                            fontWeight: i == shell.currentIndex ? FontWeight.w600 : FontWeight.w400,
                          )),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
