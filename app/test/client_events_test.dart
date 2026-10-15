import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/log/client_events.dart';
import 'package:honghong/features/diary/diary_flow.dart';
import 'package:honghong/features/diary/diary_providers.dart';
import 'package:honghong/services/diary/cloud_voice_capture.dart';
import 'package:honghong/services/diary/voice_capture.dart';

import 'cloud_voice_test.dart' show FakeSocket;
import 'diary_flow_test.dart' show FakeApi, FakeVoice, Clock, okJson;
import 'helpers.dart';

const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSJ9.c2lnbmF0dXJl';

/// 断言上报内容里不含任何敏感内容
void expectRedacted(Object payload) {
  final s = jsonEncode(payload);
  for (final bad in ['小明', '今天吃奶', '刚才喂了奶', 'ABC123', _jwt, 'eyJ', 'Bearer', 'audio', 'text', 'nickname', 'invite']) {
    expect(s.contains(bad), isFalse, reason: '上报里出现了 "$bad"：$s');
  }
}

class _Pcm implements PcmSource {
  bool permission = true;
  bool throwOnStart = false;
  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<Stream<Uint8List>> start() async {
    if (throwOnStart) throw StateError('mic busy');
    return Stream.fromIterable([Uint8List(320)]);
  }

  @override
  Future<void> stop() async {}
}

/// 收到 end 后不回结果（模拟讯飞超时）
class _SilentSocket implements AsrSocket {
  final _c = StreamController<dynamic>();
  @override
  Stream<dynamic> get messages => _c.stream;
  @override
  void add(Object data) {}
  @override
  Future<void> close() async => _c.close();
}

void main() {
  group('sanitizeClientEvent / ClientEvent 脱敏', () {
    test('只保留白名单字段，敏感字段全部丢掉', () {
      final m = sanitizeClientEvent({
        'event': 'voice.asr.fail',
        'outcome': 'fail',
        'engine': 'cloud',
        'err_code': 'ws_handshake_rejected',
        'chars': 0,
        'text': '今天吃奶6次',
        'nickname': '小明',
        'invite_code': 'ABC123',
        'jwt': _jwt,
        'authorization': 'Bearer $_jwt',
        'audio': [1, 2, 3],
        'diary': '刚才喂了奶',
      });
      expect(m.keys.toSet(), {'event', 'outcome', 'engine', 'err_code', 'chars'});
      expectRedacted(m);
    });

    test('格式不对的值丢掉：不能借合法字段夹带文本或 JWT', () {
      final m = sanitizeClientEvent({'event': 'voice.fail', 'err_code': '今天吃奶', 'request_id': _jwt, 'app_ver': 'x' * 40, 'os': 'android 小明', 'outcome': 'meh'});
      expect(m, {'event': 'voice.fail'});
    });

    test('ClientEvent.toJson 只有白名单字段', () {
      final j = const ClientEvent('voice.asr.end', outcome: 'ok', engine: 'system', chars: 12, ms: 2000, consentCloud: false)
          .toJson(appVer: '0.1.39-dev', os: 'android', ts: DateTime.utc(2026, 10, 15));
      expect(j.keys.toSet(), {'event', 'outcome', 'engine', 'chars', 'ms', 'consent_cloud', 'app_ver', 'os', 'ts'});
      expect(j['chars'], 12);
    });

    test('errCode 规整：小写、只留 [a-z0-9_]', () {
      expect(errCode('system_error_No-Match'), 'system_error_no_match');
      expect(errCode('a' * 60).length, 48);
    });
  });

  group('ClientEventsReporter', () {
    test('未同意：不发送', () async {
      final sent = <Map<String, Object?>>[];
      final r = ClientEventsReporter(consent: () => false, send: (b) async => sent.add(b));
      r.report(const ClientEvent('voice.asr.end', outcome: 'fail', errCode: 'perm_denied'));
      await r.flush();
      expect(sent, isEmpty);
    });

    test('同意后：发送 {events:[…]}，内容已脱敏', () async {
      final sent = <Map<String, Object?>>[];
      final r = ClientEventsReporter(consent: () => true, send: (b) async => sent.add(b), appVer: '0.1.39', os: 'android');
      r.report(const ClientEvent('voice.asr.end', outcome: 'fail', engine: 'cloud', errCode: 'ws_connect_timeout', requestId: '3f2b6c1e-8d4a-4c3b-9e7f-0a1b2c3d4e5f'));
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));
      final ev = (sent.single['events'] as List).single as Map;
      expect(ev['err_code'], 'ws_connect_timeout');
      expect(ev['request_id'], '3f2b6c1e-8d4a-4c3b-9e7f-0a1b2c3d4e5f');
      expectRedacted(sent);
    });

    test('发送失败不抛异常', () async {
      final r = ClientEventsReporter(consent: () => true, send: (_) async => throw const SocketException('offline'));
      r.report(const ClientEvent('voice.asr.end', outcome: 'fail'));
      await r.flush();
    });
  });

  group('CloudVoiceCapture 失败分类', () {
    Future<CloudVoiceCapture> started({PcmSource? src, Future<String> Function()? token, Future<AsrSocket> Function(String, String)? connect}) async {
      final cap = CloudVoiceCapture(source: src ?? _Pcm(), token: token ?? () async => _jwt, connect: connect ?? (_, _) async => FakeSocket(), finalTimeout: const Duration(milliseconds: 50));
      await cap.start(onPartial: (_) {});
      return cap;
    }

    test('无麦克风权限 → perm_denied', () async {
      expect((await started(src: _Pcm()..permission = false)).errorCode, 'perm_denied');
    });
    test('拿不到 token → token_failed', () async {
      expect((await started(token: () async => throw StateError('no session'))).errorCode, 'token_failed');
    });
    test('连接超时 / 握手被拒 / 断网', () async {
      expect((await started(connect: (_, _) async => throw TimeoutException('x'))).errorCode, 'ws_connect_timeout');
      expect((await started(connect: (_, _) async => throw const WebSocketException('not upgraded'))).errorCode, 'ws_handshake_rejected');
      expect((await started(connect: (_, _) async => throw const SocketException('dns'))).errorCode, 'network');
    });
    test('麦克风启动失败 → mic_start_failed', () async {
      expect((await started(src: _Pcm()..throwOnStart = true)).errorCode, 'mic_start_failed');
    });
    test('网关 error 帧 → asr_error_<原因>；等不到 final → final_timeout', () async {
      final a = await started(connect: (_, _) async => FakeSocket(error: true));
      await a.stop();
      expect(a.errorCode, 'asr_error_upstream');
      final b = await started(connect: (_, _) async => _SilentSocket());
      await b.stop();
      expect(b.errorCode, 'final_timeout');
    });
    test('request id 透传给连接（作为 x-request-id）', () async {
      String? rid;
      final cap = await started(connect: (_, r) async {
        rid = r;
        return FakeSocket();
      });
      expect(rid, isNotNull);
      expect(cap.requestId, rid);
      expect(rid, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });
  });

  group('日记页上报（组件）', () {
    late List<Map<String, Object?>> sent;
    Future<void> open(WidgetTester tester, {required bool consent, required VoiceCapture system, VoiceCapture? cloud}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      sent = [];
      final clock = Clock();
      await pumpApp(tester, prefs: {kDiaryGenderPrompted: true, kClientEventsConsent: consent, kDiaryCloudAsrConsent: false}, overrides: [
        diaryApiProvider.overrideWithValue(FakeApi(json: okJson)),
        voiceCaptureProvider.overrideWithValue(system),
        cloudVoiceCaptureProvider.overrideWithValue(cloud),
        diaryClockProvider.overrideWithValue(clock.call),
        clientEventsReporterProvider.overrideWith((ref) => ClientEventsReporter(
              consent: () => ref.read(clientEventsConsentProvider),
              send: (b) async => sent.add(b),
              appVer: '0.1.39-dev',
              os: 'android',
            )),
      ]);
      await tester.ensureVisible(find.byKey(const Key('diary-entry')));
      await tester.tap(find.byKey(const Key('diary-entry')));
      await settle(tester, 10);
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
      await settle(tester, 3);
      clock.t = clock.t.add(const Duration(seconds: 2));
      await g.up();
      await settle(tester, 10);
    }

    List<Map> events() => [for (final b in sent) ...(b['events'] as List).cast<Map>()];

    testWidgets('同意后：本机识别不可用 → 上报 voice.asr.start fail + 错误码，不含任何内容', (tester) async {
      await open(tester, consent: true, system: FakeVoice(ok: false), cloud: FakeVoice());
      final e = events().firstWhere((e) => e['event'] == 'voice.asr.start');
      expect(e['outcome'], 'fail');
      expect(e['engine'], 'system');
      expect(e['err_code'], 'system_unavailable');
      expectRedacted(sent);
      await unmount(tester);
    });

    testWidgets('同意后：识别成功只报字数，不报文字', (tester) async {
      await open(tester, consent: true, system: FakeVoice(text: '小明今天吃奶6次'));
      final e = events().firstWhere((e) => e['event'] == 'voice.asr.end');
      expect(e['outcome'], 'ok');
      expect(e['chars'], 8);
      expectRedacted(sent);
      await unmount(tester);
    });

    testWidgets('默认（未同意）：什么都不发', (tester) async {
      await open(tester, consent: false, system: FakeVoice(ok: false), cloud: FakeVoice());
      expect(sent, isEmpty);
      await unmount(tester);
    });
  });
}
