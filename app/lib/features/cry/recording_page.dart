import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/providers.dart';
import '../../core/router/app_router.dart';

/// 2 录音：16kHz 单声道 WAV，最长 10 秒。
/// 没有麦克风权限时仍可"跳过录音"，只用记录推断。
class RecordingPage extends ConsumerStatefulWidget {
  const RecordingPage({super.key});

  @override
  ConsumerState<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends ConsumerState<RecordingPage> {
  static const maxSeconds = 10;
  final _recorder = AudioRecorder();
  final _startedAt = DateTime.now();
  Timer? _timer;
  int _elapsed = 0;
  bool _recording = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) return;
      final dir = Directory(
          p.join((await getApplicationDocumentsDirectory()).path, 'cries'));
      await dir.create(recursive: true);
      await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: p.join(dir.path, '${_startedAt.millisecondsSinceEpoch}.wav'),
      );
      setState(() => _recording = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsed++);
        if (_elapsed >= maxSeconds) _finish();
      });
    } catch (_) {
      // 录音失败时退化为仅用记录推断
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    _busy = true;
    _timer?.cancel();
    String? path;
    if (_recording) path = await _recorder.stop();
    final id = await ref.read(cryFlowProvider).analyze(
          startedAt: _startedAt,
          durationMs: _elapsed * 1000,
          audioPath: path,
        );
    if (mounted) context.pushReplacement(Routes.result(id));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('正在听…')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_recording ? Icons.mic : Icons.mic_off, size: 96),
            const SizedBox(height: 16),
            Text(_recording
                ? '录音中 $_elapsed / $maxSeconds 秒'
                : '未开始录音（可能没有麦克风权限）'),
            // TODO: 用 audio_waveforms 显示实时波形
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _finish,
              child: Text(_recording ? '完成，帮我判断' : '跳过录音，直接判断'),
            ),
          ],
        ),
      ),
    );
  }
}
