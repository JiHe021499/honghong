import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../services/update/update_service.dart';
import '../cry/recording_page.dart';
import 'update_providers.dart';

String formatSize(int bytes) => bytes <= 0 ? '未知' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

/// 新版本弹窗（启动自动检查发现新版本时）。强制更新不能关闭。
Future<void> showUpdateDialog(BuildContext context, UpdateCheck check, UpdateService service) {
  final c = context.hh;
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: !check.forced,
    builder: (ctx) => PopScope(
      canPop: !check.forced,
      child: Dialog(
        backgroundColor: c.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/brand/mark-1024.png', width: 44, height: 44)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(check.forced ? '需要更新到新版本' : '哄哄有新版本啦', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.ink)),
                  Text('${check.info.versionName} · ${formatSize(check.info.size)}', style: TextStyle(fontSize: 12, color: c.sub)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(child: Text(check.info.changelog, style: TextStyle(fontSize: 13, color: c.ink, height: 1.6))),
            ),
            const SizedBox(height: 18),
            Row(children: [
              if (!check.forced) ...[
                Expanded(
                  child: HhButton(
                    label: '稍后',
                    primary: false,
                    onPressed: () {
                      service.skip(check.info.versionCode);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: HhButton(
                  label: '立即更新',
                  onPressed: () {
                    Navigator.pop(ctx);
                    GoRouter.of(context).push('/update', extra: check);
                  },
                ),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
}

/// 检查更新页（我的 → 检查更新）：版本对比、更新内容、下载进度、安装
class UpdatePage extends ConsumerStatefulWidget {
  const UpdatePage({super.key, this.initial});
  final UpdateCheck? initial;

  @override
  ConsumerState<UpdatePage> createState() => _UpdatePageState();
}

enum _Phase { checking, upToDate, available, downloading, downloaded, error }

class _UpdatePageState extends ConsumerState<UpdatePage> {
  UpdateCheck? _check;
  _Phase _phase = _Phase.checking;
  double _progress = 0;
  String? _error;
  String? _apkPath;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _check = widget.initial;
    if (_check != null) {
      _phase = _check!.hasUpdate ? _Phase.available : _Phase.upToDate;
    } else if (inAppUpdateSupported) {
      _runCheck();
    }
  }

  Future<void> _runCheck() async {
    setState(() {
      _phase = _Phase.checking;
      _error = null;
    });
    try {
      final s = await ref.read(updateServiceProvider.future);
      final r = await s.check(manual: true);
      if (!mounted) return;
      setState(() {
        _check = r;
        _phase = r!.hasUpdate ? _Phase.available : _Phase.upToDate;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '$e';
      });
    }
  }

  Future<void> _download() async {
    final info = _check!.info;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _error = null;
    });
    _cancel = CancelToken();
    try {
      final s = await ref.read(updateServiceProvider.future);
      final dir = await getTemporaryDirectory();
      final f = await s.download(info, dir, cancel: _cancel, onProgress: (r, t) {
        final total = t > 0 ? t : info.size;
        if (mounted && total > 0) setState(() => _progress = (r / total).clamp(0.0, 1.0));
      });
      if (!mounted) return;
      setState(() {
        _apkPath = f.path;
        _phase = _Phase.downloaded;
      });
      await _install();
    } catch (e) {
      final cancelled = e is DioException && CancelToken.isCancel(e);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.available;
        _error = cancelled ? '已取消下载' : '$e';
      });
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;
    // Android 8+：需要允许"安装未知应用"，没开就跳到系统设置
    var st = await Permission.requestInstallPackages.status;
    if (!st.isGranted) st = await Permission.requestInstallPackages.request();
    if (!st.isGranted) {
      if (mounted) setState(() => _error = '需要允许哄哄"安装未知应用"，开启后再点"安装"');
      return;
    }
    final r = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done && mounted) setState(() => _error = '打开安装程序失败：${r.message}');
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final current = ref.watch(packageInfoProvider).value;
    final forced = _check?.forced ?? false;
    final info = _check?.info;

    Widget body;
    if (!inAppUpdateSupported) {
      body = _center(c, AppIcon.phone, 'iOS 暂不支持应用内更新', '请通过 TestFlight 或 App Store 更新');
    } else if (_phase == _Phase.checking) {
      body = const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()));
    } else if (_phase == _Phase.error) {
      body = Column(children: [
        _center(c, AppIcon.signalError, '检查更新失败', _error ?? ''),
        HhButton(label: '重试', onPressed: _runCheck),
      ]);
    } else if (_phase == _Phase.upToDate) {
      body = Column(children: [
        _center(c, AppIcon.checkDone, '已经是最新版本', '当前 ${current?.version ?? ''}（${current?.buildNumber ?? ''}）'),
        HhButton(label: '再检查一次', primary: false, onPressed: _runCheck),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HhCard(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _ver(c, '当前版本', current == null ? '…' : '${current.version}（${current.buildNumber}）'),
              const HhIcon(AppIcon.arrowForward, size: 24),
              _ver(c, '新版本', '${info!.versionName}（${info.versionCode}）', highlight: true),
            ]),
            const SizedBox(height: 12),
            Text('安装包 ${formatSize(info.size)} · ${info.channel == 'stable' ? '正式版' : '开发版'}', style: TextStyle(fontSize: 12, color: c.sub)),
          ]),
        ),
        const SizedBox(height: 14),
        HhCard(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('更新内容', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 8),
            Text(info.changelog.isEmpty ? '例行更新' : info.changelog, style: TextStyle(fontSize: 13, color: c.ink, height: 1.7)),
          ]),
        ),
        if (forced)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('这个版本需要更新后才能继续使用', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.peachDeep, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 20),
        if (_phase == _Phase.downloading) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: LinearProgressIndicator(value: _progress, minHeight: 14, color: c.peach2, backgroundColor: c.peachL),
          ),
          const SizedBox(height: 8),
          Text('正在下载 ${(_progress * 100).round()}%', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.sub)),
          const SizedBox(height: 12),
          HhButton(label: '取消', primary: false, onPressed: () => _cancel?.cancel()),
        ] else if (_phase == _Phase.downloaded)
          HhButton(label: '安装', onPressed: _install)
        else ...[
          HhButton(label: '立即更新', onPressed: _download),
          if (!forced) ...[
            const SizedBox(height: 10),
            HhButton(
              label: '稍后',
              primary: false,
              onPressed: () async {
                (await ref.read(updateServiceProvider.future)).skip(info.versionCode);
                if (context.mounted) context.pop();
              },
            ),
          ],
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.peachDeep)),
          ),
      ]);
    }

    return PopScope(
      canPop: !forced,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              SizedBox(
                height: 52,
                child: Stack(alignment: Alignment.center, children: [
                  if (!forced) Align(alignment: Alignment.centerLeft, child: CircleBack(onTap: () => context.pop())),
                  Text('检查更新', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
                ]),
              ),
              const SizedBox(height: 18),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Container(color: const Color(0xFFFFF8F0), padding: const EdgeInsets.all(6), child: Image.asset('assets/brand/mark-1024.png', width: 84, height: 84)),
                ),
              ),
              const SizedBox(height: 18),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _ver(Hh c, String label, String v, {bool highlight = false}) => Expanded(
        child: Column(children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.sub)),
          const SizedBox(height: 4),
          Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: highlight ? c.peach2 : c.ink)),
        ]),
      );

  Widget _center(Hh c, AppIcon icon, String title, String sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(children: [
          HhIcon(icon, size: 60),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.ink)),
          const SizedBox(height: 6),
          Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.sub)),
        ]),
      );
}
