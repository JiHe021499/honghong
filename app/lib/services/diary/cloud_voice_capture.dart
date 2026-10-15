import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'voice_capture.dart';

/// 16k/16bit/单声道 PCM 来源（麦克风）。测试里换成假的。
abstract class PcmSource {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
}

class MicPcmSource implements PcmSource {
  final _rec = AudioRecorder();
  @override
  Future<bool> hasPermission() => _rec.hasPermission();
  @override
  Future<Stream<Uint8List>> start() =>
      _rec.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1, echoCancel: false, noiseSuppress: true));
  @override
  Future<void> stop() async {
    await _rec.stop();
  }
}

/// 与网关 /diary-asr 的 WebSocket。测试里换成假的。
abstract class AsrSocket {
  Stream<dynamic> get messages;
  void add(Object data);
  Future<void> close();
}

class IoAsrSocket implements AsrSocket {
  IoAsrSocket(this._ws);
  final WebSocket _ws;
  static Future<AsrSocket> connect(Uri url, String jwt, {String? requestId}) async => IoAsrSocket(await WebSocket.connect(url.toString(),
          headers: {'authorization': 'Bearer $jwt', 'x-request-id': ?requestId}).timeout(const Duration(seconds: 5)));
  @override
  Stream<dynamic> get messages => _ws;
  @override
  void add(Object data) => _ws.add(data);
  @override
  Future<void> close() => _ws.close(1000);
}

/// 网关地址（https://host/ai/）→ wss://host/ai/diary-asr
Uri asrUrl(String gatewayUrl) {
  final u = Uri.parse(gatewayUrl.endsWith('/') ? gatewayUrl : '$gatewayUrl/');
  return u.replace(scheme: u.scheme == 'http' ? 'ws' : 'wss').resolve('diary-asr');
}

/// 讯飞联网识别（经网关中转）。录 16k PCM 边录边发，松手发 end，等 final。
/// 音频不在本机落盘，也不在网关落盘。
class CloudVoiceCapture implements VoiceCapture {
  CloudVoiceCapture({required this.connect, required this.token, PcmSource? source, this.finalTimeout = const Duration(seconds: 6)})
      : source = source ?? MicPcmSource();

  /// 连接网关；[requestId] 作为 x-request-id 头传给网关，网关日志里是同一个 id
  final Future<AsrSocket> Function(String jwt, String requestId) connect;
  final Future<String> Function() token;
  final PcmSource source;
  final Duration finalTimeout;

  AsrSocket? _ws;
  StreamSubscription<Uint8List>? _mic;
  StreamSubscription<dynamic>? _sub;
  Completer<String>? _final;
  String _text = '';
  bool _failed = false;
  String? _code;
  String? _rid;

  @override
  bool get failed => _failed;

  @override
  String? get errorCode => _code;

  @override
  String? get requestId => _rid;

  void _fail(String code) {
    _failed = true;
    _code ??= code;
  }

  /// 连接/握手异常 → 错误码（不含异常 message）
  static String classify(Object e) => switch (e) {
        TimeoutException() => 'ws_connect_timeout',
        WebSocketException() => 'ws_handshake_rejected',
        SocketException() => 'network',
        HandshakeException() => 'tls_handshake',
        HttpException() => 'ws_http_error',
        _ => errCode('ws_${e.runtimeType}'),
      };

  @override
  Future<bool> start({required void Function(String partial) onPartial, void Function(double level)? onLevel}) async {
    _text = '';
    _failed = false;
    _code = null;
    _rid = const Uuid().v4();
    _final = Completer<String>();
    try {
      if (!await source.hasPermission()) {
        _fail('perm_denied');
        return false;
      }
      final String jwt;
      try {
        jwt = await token();
      } catch (_) {
        _fail('token_failed');
        return false;
      }
      final AsrSocket ws;
      try {
        ws = _ws = await connect(jwt, _rid!);
      } catch (e) {
        _fail(classify(e));
        return false;
      }
      _sub = ws.messages.listen((m) {
        if (m is! String) return;
        final j = jsonDecode(m);
        if (j is! Map) return;
        switch (j['type']) {
          case 'partial':
            _text = (j['text'] as String?) ?? _text;
            onPartial(_text);
          case 'final':
            _text = (j['text'] as String?) ?? _text;
            if (!_final!.isCompleted) _final!.complete(_text);
          case 'error':
            final reason = j['error'];
            _fail(errCode('asr_error_${reason is String ? reason : 'unknown'}'));
            if (!_final!.isCompleted) _final!.complete('');
        }
      }, onDone: () {
        if (!_final!.isCompleted) _final!.complete(_text);
      }, onError: (_) {
        _fail('ws_dropped');
        if (!_final!.isCompleted) _final!.complete('');
      });
      final Stream<Uint8List> pcm;
      try {
        pcm = await source.start();
      } catch (_) {
        _fail('mic_start_failed');
        await _teardown();
        return false;
      }
      _mic = pcm.listen((chunk) => _ws?.add(chunk));
      return true;
    } catch (e) {
      _fail(errCode('start_${e.runtimeType}'));
      await _teardown();
      return false;
    }
  }

  @override
  Future<String> stop() async {
    await _mic?.cancel();
    _mic = null;
    await source.stop();
    _ws?.add(jsonEncode({'type': 'end'}));
    final f = _final;
    final text = f == null
        ? ''
        : await f.future.timeout(finalTimeout, onTimeout: () {
            _fail('final_timeout');
            return '';
          });
    await _teardown();
    return text.trim();
  }

  @override
  Future<void> cancel() async {
    await _mic?.cancel();
    _mic = null;
    await source.stop();
    _text = '';
    await _teardown(); // 直接断开：网关不再等结果
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    final ws = _ws;
    _ws = null;
    await ws?.close();
  }
}
