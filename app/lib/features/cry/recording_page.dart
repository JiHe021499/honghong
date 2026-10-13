import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../services/audio/auto_listen.dart';

/// 录音（设计稿 11）：16kHz 单声道 WAV，最长 10 秒，实时波形 + 倒计时圆环。
/// 没有麦克风权限时仍可"现在就分析"，只用记录推断。
class RecordingPage extends ConsumerStatefulWidget {
  const RecordingPage({super.key, this.auto = false});
  final bool auto;

  @override
  ConsumerState<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends ConsumerState<RecordingPage> {
  static const maxSeconds = 10;
  static const bars = 26;
  AudioRecorder? _recorder;
  final _startedAt = DateTime.now();
  final _levels = List<double>.filled(bars, .08);
  Timer? _timer;
  StreamSubscription<Amplitude>? _amp;
  int _elapsedMs = 0;
  bool _recording = false;
  bool _denied = false;
  bool _busy = false;
  late final AutoListenController _auto;

  @override
  void initState() {
    super.initState();
    _auto = ref.read(autoListenControllerProvider.notifier);
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsedMs += 100);
      if (_elapsedMs >= maxSeconds * 1000) _finish();
    });
    _start();
  }

  Future<void> _start() async {
    if (!AutoListenController.enabledInThisEnv) return; // 测试环境没有麦克风
    try {
      await _auto.pause();
      final rec = _recorder = AudioRecorder();
      if (!await rec.hasPermission()) {
        if (mounted) setState(() => _denied = true);
        return;
      }
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'cries'));
      await dir.create(recursive: true);
      await rec.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: p.join(dir.path, '${_startedAt.millisecondsSinceEpoch}.wav'),
      );
      _amp = rec.onAmplitudeChanged(const Duration(milliseconds: 90)).listen((a) {
        // dBFS：-60 安静 … 0 最大
        final v = ((a.current + 60) / 60).clamp(0.06, 1.0);
        if (!mounted) return;
        setState(() {
          _levels.removeAt(0);
          _levels.add(v);
        });
      });
      if (mounted) setState(() => _recording = true);
    } catch (_) {
      // 录音失败时退化为仅用记录推断
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    _busy = true;
    _timer?.cancel();
    await _amp?.cancel();
    String? path;
    if (_recording) path = await _recorder?.stop();
    final id = await ref.read(cryFlowProvider).analyze(
          startedAt: _startedAt,
          durationMs: _elapsedMs,
          audioPath: path,
          autoTriggered: widget.auto,
        );
    if (mounted) context.pushReplacement(Routes.result(id));
  }

  Future<void> _cancel() async {
    _busy = true;
    _timer?.cancel();
    await _amp?.cancel();
    if (_recording) {
      final path = await _recorder?.stop();
      if (path != null) File(path).delete().ignore();
    }
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amp?.cancel();
    _recorder?.dispose();
    _auto.resume();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final remain = (maxSeconds - _elapsedMs / 1000).ceil().clamp(0, maxSeconds);
    final progress = (_elapsedMs / (maxSeconds * 1000)).clamp(0.0, 1.0);
    // 没有真实音量时（无权限/测试）用一段平缓的假波形，保持界面一致
    final levels = _recording
        ? _levels
        : [for (var i = 0; i < bars; i++) .25 + .2 * math.sin(i * .9 + _elapsedMs / 300).abs()];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(children: [
            SizedBox(
              height: 52,
              child: Stack(alignment: Alignment.center, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _CircleIcon(icon: AppIcon.close, onTap: _cancel),
                ),
                Text('正在听宝宝哭声', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
              ]),
            ),
            const SizedBox(height: 14),
            Text(_denied ? '没有麦克风权限，这次只参考记录来判断' : '把手机靠近宝宝，约 30 厘米', style: TextStyle(fontSize: 14, color: c.sub)),
            const SizedBox(height: 26),
            SizedBox(
              height: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final l in levels)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      width: 6,
                      height: 12 + 128 * l,
                      margin: const EdgeInsets.symmetric(horizontal: 3.5),
                      decoration: BoxDecoration(color: c.peach2, borderRadius: BorderRadius.circular(3)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            SizedBox.square(
              dimension: 210,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 16,
                    strokeCap: StrokeCap.butt,
                    color: c.peach2,
                    backgroundColor: c.peachL,
                  ),
                ),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '$remain', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800)),
                  const TextSpan(text: '秒', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ]), style: TextStyle(color: c.peach2)),
              ]),
            ),
            const SizedBox(height: 26),
            Text('再录几秒就能给出判断', style: TextStyle(fontSize: 14, color: c.sub)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: c.blueL, borderRadius: BorderRadius.circular(20)),
              child: Text('同时参考：喂奶 · 睡眠 · 尿布记录', style: TextStyle(fontSize: 13, color: c.blueInk)),
            ),
            const Spacer(),
            HhButton(label: '现在就分析', onPressed: _finish),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.onTap});
  final AppIcon icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: c.card,
          shape: BoxShape.circle,
          boxShadow: c.night ? null : const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 2))],
        ),
        child: Center(child: HhIcon(icon, size: 24)),
      ),
    );
  }
}

/// 结果页、反馈页共用的圆形返回按钮
class CircleBack extends StatelessWidget {
  const CircleBack({super.key, required this.onTap, this.icon = AppIcon.chevronLeft});
  final VoidCallback onTap;
  final AppIcon icon;
  @override
  Widget build(BuildContext context) => _CircleIcon(icon: icon, onTap: onTap);
}
