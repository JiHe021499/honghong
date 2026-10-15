import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 按住说话的识别来源：优先手机自带识别（SystemVoiceCapture），
/// 没有或失败时、经用户同意后走讯飞联网识别（CloudVoiceCapture，D9 修订）。
abstract class VoiceCapture {
  /// 开始识别。返回 false 表示不可用（无权限/不支持），界面走屏 9 兜底。
  Future<bool> start({required void Function(String partial) onPartial, void Function(double level)? onLevel});

  /// 松手：结束并返回最终文本（可能为空）
  Future<String> stop();

  /// 上滑取消：丢弃，不产生任何记录
  Future<void> cancel();

  /// 上一次是识别引擎本身出错/不可用（而不是没说话）。为 true 时走联网识别兜底。
  bool get failed;

  /// 上一次失败的分类码（[a-z0-9_]，不含任何用户内容），用于失败统计上报
  String? get errorCode;

  /// 上一次会话的 request id（联网识别时与网关日志对应）
  String? get requestId => null;
}

/// 把引擎给的错误名规整成安全的错误码：小写、只留 [a-z0-9_]、最长 48
String errCode(String s) {
  final c = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_').replaceAll(RegExp(r'_+'), '_');
  return c.length > 48 ? c.substring(0, 48) : c;
}

class SystemVoiceCapture implements VoiceCapture {
  SystemVoiceCapture({this.onDeviceOnly = true});

  /// 只用端上识别（D9 音频不出机）。设备不支持时会失败 → 屏 9 改用文字输入。
  final bool onDeviceOnly;
  final _stt = SpeechToText();
  String _text = '';
  bool _ready = false;
  bool _error = false;
  String? _code;

  @override
  String? get errorCode => _code;

  @override
  String? get requestId => null;

  @override
  Future<bool> start({required void Function(String partial) onPartial, void Function(double level)? onLevel}) async {
    _text = '';
    _error = false;
    _code = null;
    try {
      _ready = _ready ||
          await _stt.initialize(onError: (SpeechRecognitionError e) {
            _error = true;
            _code = errCode('system_${e.errorMsg}'); // 例如 system_error_no_match / system_error_language_unavailable
          });
      if (!_ready) {
        _error = true;
        _code = 'system_unavailable';
        return false;
      }
      await _stt.listen(
        onResult: (r) {
          _text = r.recognizedWords;
          onPartial(_text);
        },
        onSoundLevelChange: onLevel,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          onDevice: onDeviceOnly,
          cancelOnError: true,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 8),
          localeId: 'zh_CN',
        ),
      );
      return true;
    } catch (e) {
      _error = true;
      _code = errCode('system_${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<String> stop() async {
    await _stt.stop();
    // 系统识别在 stop 后还会回调一次最终结果
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return _error && _text.isEmpty ? '' : _text.trim();
  }

  @override
  Future<void> cancel() async {
    await _stt.cancel();
    _text = '';
  }

  @override
  bool get failed => _error;
}
