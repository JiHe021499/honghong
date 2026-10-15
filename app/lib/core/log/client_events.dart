import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../prefs.dart';

/// 匿名错误统计开关（默认关）。只有用户在设置里打开后才上报 /client-events。
const kClientEventsConsent = 'client_events_consent';

class ClientEventsConsentNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(prefsProvider).getBool(kClientEventsConsent) ?? false;
  Future<void> set(bool v) async {
    await ref.read(prefsProvider).setBool(kClientEventsConsent, v);
    state = v;
  }
}

final clientEventsConsentProvider = NotifierProvider<ClientEventsConsentNotifier, bool>(ClientEventsConsentNotifier.new);

/// 一条失败/统计事件。**只有这些字段**，没有任何自由文本字段：
/// 绝不放音频、识别文字、日记正文、昵称、邀请码、JWT。
@immutable
class ClientEvent {
  const ClientEvent(this.event, {this.outcome, this.engine, this.errCode, this.ms, this.audioMs, this.chars, this.requestId, this.consentCloud});

  /// 点分事件名，如 voice.asr.end
  final String event;

  /// ok / fail / cancel / timeout
  final String? outcome;

  /// system / cloud
  final String? engine;

  /// 规整过的错误码（[a-z0-9_]）
  final String? errCode;
  final int? ms, audioMs;

  /// 识别结果的字数（只记长度，不记内容）
  final int? chars;
  final String? requestId;
  final bool? consentCloud;

  Map<String, Object?> toJson({String? appVer, String? os, DateTime? ts}) => sanitizeClientEvent({
        'event': event,
        'outcome': outcome,
        'engine': engine,
        'err_code': errCode,
        'ms': ms,
        'audio_ms': audioMs,
        'chars': chars,
        'request_id': requestId,
        'consent_cloud': consentCloud,
        'app_ver': appVer,
        'os': os,
        'ts': (ts ?? DateTime.now()).toUtc().toIso8601String(),
      });
}

final _patterns = {
  'event': RegExp(r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+){0,4}$'),
  'err_code': RegExp(r'^[a-z0-9_]{1,48}$'),
  'request_id': RegExp(r'^[0-9A-Za-z-]{8,64}$'),
  'app_ver': RegExp(r'^[0-9A-Za-z.+-]{1,32}$'),
  'os': RegExp(r'^(android|ios|other)( [0-9.]{1,10})?$'),
  'ts': RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'),
};
const _enums = {
  'outcome': ['ok', 'fail', 'cancel', 'timeout'],
  'engine': ['system', 'cloud'],
};
const _ints = ['ms', 'audio_ms', 'chars', 'count'];
const _bools = ['consent_cloud'];

/// 白名单过滤（与网关 src/client_events.js 同一套规则）：不在白名单或格式不对的字段一律丢弃
Map<String, Object?> sanitizeClientEvent(Map<String, Object?> m) {
  final out = <String, Object?>{};
  _patterns.forEach((k, re) {
    final v = m[k];
    if (v is String && v.length <= 64 && re.hasMatch(v)) out[k] = v;
  });
  _enums.forEach((k, vs) {
    if (vs.contains(m[k])) out[k] = m[k];
  });
  for (final k in _ints) {
    final v = m[k];
    if (v is int && v >= 0 && v <= 86400000) out[k] = v;
  }
  for (final k in _bools) {
    if (m[k] is bool) out[k] = m[k];
  }
  return out;
}

typedef ClientEventsSender = Future<void> Function(Map<String, Object?> body);

/// 上报器：未同意时什么都不做（不缓存、不发送）。同意后攒一小批立即发，失败就丢弃，不重试、不落盘。
class ClientEventsReporter {
  ClientEventsReporter({required this.consent, required this.send, this.appVer, this.os});

  final bool Function() consent;
  final ClientEventsSender? send;
  String? appVer;
  final String? os;
  static const maxBatch = 20;

  final _pending = <Map<String, Object?>>[];
  bool _flushing = false;

  void report(ClientEvent e) {
    if (!consent() || send == null) return;
    if (_pending.length >= maxBatch) _pending.removeAt(0);
    _pending.add(e.toJson(appVer: appVer, os: os));
    unawaited(flush());
  }

  Future<void> flush() async {
    if (_flushing || _pending.isEmpty || send == null) return;
    _flushing = true;
    final batch = List.of(_pending);
    _pending.clear();
    try {
      if (consent()) await send!({'events': batch});
    } catch (_) {
      // 上报失败不影响使用，直接丢弃
    } finally {
      _flushing = false;
    }
  }
}

String clientOs() => kIsWeb ? 'other' : (Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'other');

/// 发到网关 POST /client-events（带 JWT 与 x-request-id）
ClientEventsSender gatewaySender({required String baseUrl, required Future<String> Function() token, Dio? dio, String Function()? requestId}) {
  final d = dio ??
      Dio(BaseOptions(
        baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
      ));
  return (body) async {
    final jwt = await token();
    await d.post<void>('client-events',
        data: body, options: Options(headers: {'authorization': 'Bearer $jwt', if (requestId != null) 'x-request-id': requestId()}));
  };
}
