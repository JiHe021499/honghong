import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cry/recording_page.dart';
import '../../features/cry/result_page.dart';
import '../../features/feedback/feedback_page.dart';
import '../../features/home/home_page.dart';
import '../../features/insights/insights_page.dart';
import '../../features/logs/log_detail_page.dart';
import '../../features/settings/settings_page.dart';

class Routes {
  static const home = '/';
  static const recording = '/cry/record';
  static String result(String id) => '/cry/result/$id';
  static String feedback(String id) => '/feedback/$id';
  static const logs = '/logs';
  static const insights = '/insights';
  static const settings = '/settings';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(path: Routes.home, builder: (_, _) => const HomePage()),
      GoRoute(path: Routes.recording, builder: (_, _) => const RecordingPage()),
      GoRoute(
        path: '/cry/result/:id',
        builder: (_, s) => ResultPage(eventId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/feedback/:id',
        builder: (_, s) => FeedbackPage(eventId: s.pathParameters['id']!),
      ),
      GoRoute(path: Routes.logs, builder: (_, _) => const LogDetailPage()),
      GoRoute(path: Routes.insights, builder: (_, _) => const InsightsPage()),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsPage()),
    ],
  );
});
