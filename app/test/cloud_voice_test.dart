import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/features/diary/diary_flow.dart';
import 'package:honghong/features/diary/diary_providers.dart';
import 'package:honghong/services/diary/cloud_voice_capture.dart';

import 'diary_flow_test.dart' show FakeApi, FakeVoice, Clock, okJson;
import 'helpers.dart';

/// 假网关连接：收到 end 后回 partial + final（模拟讯飞经网关返回）
class FakeSocket implements AsrSocket {
  FakeSocket({this.finalText = '刚才喂了奶，换了尿布', this.error = false});
  final String finalText;
  final bool error;
  final _in = StreamController<dynamic>();
  final sent = <Object>[];
  bool closed = false;
  @override
  Stream<dynamic> get messages => _in.stream;
  @override
  void add(Object data) {
    sent.add(data);
    if (data is String && jsonDecode(data)['type'] == 'end') {
      if (error) {
        _in.add(jsonEncode({'type': 'error', 'error': 'upstream'}));
      } else {
        _in.add(jsonEncode({'type': 'partial', 'text': '刚才'}));
        _in.add(jsonEncode({'type': 'final', 'text': finalText}));
      }
      _in.close();
    }
  }

  @override
  Future<void> close() async => closed = true;
}

class FakePcm implements PcmSource {
  bool permission = true;
  final _c = StreamController<Uint8List>();
  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<Stream<Uint8List>> start() async {
    scheduleMicrotask(() {
      for (var i = 0; i < 3; i++) {
        _c.add(Uint8List(3200));
      }
    });
    return _c.stream;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  test('asrUrl：https 网关 → wss://…/ai/diary-asr', () {
    expect(asrUrl('https://honghong.hczhw.com/ai/').toString(), 'wss://honghong.hczhw.com/ai/diary-asr');
    expect(asrUrl('http://127.0.0.1:8787').toString(), 'ws://127.0.0.1:8787/diary-asr');
  });

  test('CloudVoiceCapture：发 PCM 二进制帧 + end，拿到 final', () async {
    final sock = FakeSocket();
    String? jwt;
    final cap = CloudVoiceCapture(source: FakePcm(), token: () async => 'jwt-x', connect: (t) async {
      jwt = t;
      return sock;
    });
    final partials = <String>[];
    expect(await cap.start(onPartial: partials.add), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(await cap.stop(), '刚才喂了奶，换了尿布');
    expect(jwt, 'jwt-x');
    expect(sock.sent.whereType<Uint8List>().length, 3);
    expect(sock.sent.last, jsonEncode({'type': 'end'}));
    expect(partials, contains('刚才'));
    expect(cap.failed, isFalse);
    expect(sock.closed, isTrue);
  });

  test('CloudVoiceCapture：网关报错 → 空文本且 failed；无麦克风权限 → start=false', () async {
    final cap = CloudVoiceCapture(source: FakePcm(), token: () async => 'j', connect: (_) async => FakeSocket(error: true));
    await cap.start(onPartial: (_) {});
    expect(await cap.stop(), '');
    expect(cap.failed, isTrue);
    final noMic = CloudVoiceCapture(source: FakePcm()..permission = false, token: () async => 'j', connect: (_) async => FakeSocket());
    expect(await noMic.start(onPartial: (_) {}), isFalse);
  });

  test('CloudVoiceCapture：连不上网关 → start=false', () async {
    final cap = CloudVoiceCapture(source: FakePcm(), token: () async => 'j', connect: (_) async => throw Exception('offline'));
    expect(await cap.start(onPartial: (_) {}), isFalse);
    expect(cap.failed, isTrue);
  });

  group('本机识别不可用 → 联网识别兜底', () {
    late FakeVoice system, cloud;
    late FakeApi api;
    late Clock clock;
    Future<void> open(WidgetTester tester, {Map<String, Object> prefs = const {kDiaryGenderPrompted: true}}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      clock = Clock();
      await pumpApp(tester, prefs: prefs, overrides: [
        diaryApiProvider.overrideWithValue(api),
        voiceCaptureProvider.overrideWithValue(system),
        cloudVoiceCaptureProvider.overrideWithValue(cloud),
        diaryClockProvider.overrideWithValue(clock.call),
      ]);
      await tester.ensureVisible(find.byKey(const Key('diary-entry')));
      await tester.tap(find.byKey(const Key('diary-entry')));
      await settle(tester, 10);
    }

    Future<void> hold(WidgetTester tester) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
      await settle(tester, 3);
      clock.t = clock.t.add(const Duration(seconds: 2));
      await g.up();
      await settle(tester, 10);
    }

    setUp(() {
      system = FakeVoice(ok: false);
      cloud = FakeVoice(text: '联网识别的一句话');
      api = FakeApi(json: okJson);
    });

    testWidgets('首次弹告知 → 同意 → 再按住走联网识别', (tester) async {
      await open(tester);
      await hold(tester);
      expect(find.byKey(const Key('cloud-asr-agree')), findsOneWidget);
      expect(find.textContaining('科大讯飞'), findsOneWidget);
      expect(find.textContaining('不会用于训练'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloud-asr-agree')));
      await settle(tester, 10);
      expect(find.text('已换成联网识别，请再按住说一次'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await hold(tester);
      expect(api.calls, ['voice:联网识别的一句话']);
      expect(find.byKey(const Key('card-0')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('拒绝 → 退回文字输入，且记住不再自动弹', (tester) async {
      await open(tester);
      await hold(tester);
      await tester.tap(find.byKey(const Key('cloud-asr-decline')));
      await settle(tester, 10);
      expect(find.byKey(const Key('diary-text')), findsOneWidget);
      await tester.tap(find.byKey(const Key('diary-back')));
      await settle(tester, 10);
      await hold(tester);
      expect(find.byKey(const Key('cloud-asr-agree')), findsNothing);
      expect(find.byKey(const Key('voice-err-text')), findsOneWidget); // 屏 9
      expect(cloud.cancels, 0);
      await unmount(tester);
    });

    testWidgets('已同意过：本机识别出错（空结果）后提示并改用联网识别，不再弹告知', (tester) async {
      system = FakeVoice(ok: true, text: '');
      await open(tester, prefs: const {kDiaryGenderPrompted: true, kDiaryCloudAsrConsent: true});
      system.failed = false;
      // 本机返回空且标记出错
      system.text = '';
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
      await settle(tester, 3);
      system.failed = true;
      clock.t = clock.t.add(const Duration(seconds: 2));
      await g.up();
      await settle(tester, 10);
      expect(find.byKey(const Key('cloud-asr-agree')), findsNothing);
      expect(find.text('本机识别不可用，已换成联网识别，请再说一次'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await hold(tester);
      expect(api.calls, ['voice:联网识别的一句话']);
      await unmount(tester);
    });

    testWidgets('联网识别也失败 → 屏 9', (tester) async {
      cloud = FakeVoice(ok: false);
      await open(tester, prefs: const {kDiaryGenderPrompted: true, kDiaryCloudAsrConsent: true});
      await hold(tester); // 本机不可用 → 提示切换
      await tester.pump(const Duration(seconds: 3));
      await hold(tester); // 联网也不行
      expect(find.byKey(const Key('voice-err-text')), findsOneWidget);
      await unmount(tester);
    });
  });
}
