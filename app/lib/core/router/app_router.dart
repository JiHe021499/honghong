import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cry/recording_page.dart';
import '../../features/cry/result_page.dart';
import '../../domain/diary/parse_result.dart';
import '../../features/diary/confirm_page.dart';
import '../../features/diary/diary_page.dart';
import '../../features/diary/diary_timeline_page.dart';
import '../../features/diary/text_input_page.dart';
import '../../features/family/family_page.dart';
import '../../features/feedback/feedback_page.dart';
import '../../features/home/home_page.dart';
import '../../features/insights/insights_page.dart';
import '../../features/logs/log_detail_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/update/update_page.dart';
import '../../features/update/update_providers.dart';
import '../../services/audio/auto_listen.dart';
import '../../services/cloud/cloud_providers.dart';
import '../../services/lockscreen/lockscreen_controller.dart';
import '../../services/update/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';

class Routes {
  static const home = '/';
  static const recording = '/cry/record';
  static String result(String id) => '/cry/result/$id';
  static String feedback(String id) => '/feedback/$id';
  static const logs = '/logs';
  static const insights = '/insights';
  static const family = '/family';
  static const settings = '/settings';
  static const update = '/update';
  static const diary = '/diary';
  static const diaryText = '/diary/text';
  static const diaryConfirm = '/diary/confirm';
  static const diaryDay = '/diary/day';
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
      // 妈咪日记：顶层二级页，无底部标签栏
      GoRoute(path: Routes.diary, builder: (_, _) => const DiaryPage()),
      GoRoute(path: Routes.diaryText, builder: (_, s) => TextInputPage(initial: s.extra as String?)),
      GoRoute(
          path: Routes.diaryDay,
          builder: (_, s) => DiaryTimelinePage(
              date: DateTime.tryParse(s.uri.queryParameters['date'] ?? ''), args: s.extra as DiaryDayArgs?)),
      GoRoute(path: Routes.diaryConfirm, builder: (_, s) => ConfirmPage(result: s.extra! as ParseResult)),
      GoRoute(path: Routes.update, builder: (_, s) => UpdatePage(initial: s.extra as UpdateCheck?)),
    ],
  );
});

/// 底部四个标签：首页 / 规律 / 家庭 / 我的（设计稿 .tab）
class TabShell extends ConsumerStatefulWidget {
  const TabShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<TabShell> createState() => _TabShellState();
}

class _TabShellState extends ConsumerState<TabShell> {
  StatefulNavigationShell get shell => widget.shell;

  @override
  void initState() {
    super.initState();
    // 第二阶段：家庭同步和"参与改进"上传（未配置云端时什么都不做）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(syncCoordinatorProvider).start();
      // 锁屏快捷记录（只在安卓真机上；测试环境跳过）
      if (mounted && AutoListenController.enabledInThisEnv) ref.read(lockscreenControllerProvider).start();
    });
    // 启动后自动检查更新（每 6 小时最多一次，只在安卓真机上）
    if (inAppUpdateSupported && AutoListenController.enabledInThisEnv) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheck());
    }
  }

  Future<void> _autoCheck() async {
    try {
      final s = await ref.read(updateServiceProvider.future);
      final r = await s.check();
      if (r == null || !r.hasUpdate || s.isSkipped(r) || !mounted) return;
      await showUpdateDialog(context, r, s);
    } catch (_) {
      // 自动检查失败不打扰用户
    }
  }

  static const tabs = [(AppIcon.tabHome, '首页'), (AppIcon.tabInsights, '规律'), (AppIcon.tabFamily, '家庭'), (AppIcon.tabMe, '我的')];

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
                        opacity: i == shell.currentIndex ? 1 : (c.night ? .5 : .75),
                        child: HhIcon(tabs[i].$1, size: 26, dim: false),
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
