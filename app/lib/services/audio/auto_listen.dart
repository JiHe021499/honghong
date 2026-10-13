import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/prefs.dart';
import 'cry_detector.dart';

enum AutoListenStatus { off, starting, listening, paused, noPermission, unavailable }

/// 最近一次自动检测到哭声的时间；首页监听它，跳到录音页（auto=1）。
class CryDetectedNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void fire(DateTime t) => state = t;
}

final cryDetectedProvider = NotifierProvider<CryDetectedNotifier, DateTime?>(CryDetectedNotifier.new);

/// 自动监听：开关打开时持续读麦克风 PCM 流，用 YAMNet 每 0.5 秒打一次分，
/// 判定为哭声就暂停监听并通知首页开始录音。录音页结束时调用 [resume]。
/// 注意：只在 App 前台时有效（没有前台服务）。
class AutoListenController extends Notifier<AutoListenStatus> {
  AudioRecorder? _rec;
  StreamSubscription<Uint8List>? _sub;
  CryDetector? _detector;
  final _buffer = FrameBuffer();
  final _trigger = CryTrigger();
  bool _paused = false;

  /// 测试或无原生环境时关闭真实麦克风
  static bool enabledInThisEnv = !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  AutoListenStatus build() {
    final on = ref.watch(autoListenProvider);
    ref.onDispose(_stop);
    if (!on) {
      _stop();
      return AutoListenStatus.off;
    }
    if (!enabledInThisEnv) return AutoListenStatus.unavailable;
    if (_paused) return AutoListenStatus.paused;
    Future.microtask(_start);
    return AutoListenStatus.starting;
  }

  Future<void> _start() async {
    if (_sub != null) return;
    try {
      final rec = _rec ??= AudioRecorder();
      if (!await rec.hasPermission()) {
        state = AutoListenStatus.noPermission;
        return;
      }
      _detector ??= await CryDetector.load();
      final stream = await rec.startStream(const RecordConfig(
          encoder: AudioEncoder.pcm16bits, sampleRate: CryDetector.sampleRate, numChannels: 1));
      _sub = stream.listen(_onPcm);
      state = AutoListenStatus.listening;
    } catch (e) {
      debugPrint('auto listen failed: $e');
      state = AutoListenStatus.unavailable;
    }
  }

  void _onPcm(Uint8List bytes) {
    final d = _detector;
    if (d == null || _paused) return;
    for (final f in _buffer.add(pcm16ToFloat(bytes))) {
      final now = DateTime.now();
      if (_trigger.add(d.score(f), now)) {
        pause();
        ref.read(cryDetectedProvider.notifier).fire(now);
        return;
      }
    }
  }

  /// 录音页占用麦克风前调用
  Future<void> pause() async {
    _paused = true;
    await _stop();
    if (state != AutoListenStatus.off) state = AutoListenStatus.paused;
  }

  /// 录音页关闭后调用
  void resume() {
    _paused = false;
    if (ref.read(autoListenProvider) && enabledInThisEnv) {
      state = AutoListenStatus.starting;
      _start();
    }
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      if (await _rec?.isRecording() ?? false) await _rec?.stop();
    } catch (_) {}
  }
}

final autoListenControllerProvider =
    NotifierProvider<AutoListenController, AutoListenStatus>(AutoListenController.new);
