import 'package:honghong/core/env.dart';
import 'package:honghong/core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
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

  // 回归：0.1.39-dev 发布构建只注入了 SUPABASE_URL，没注入 AI_GATEWAY_URL → 网关地址为空，
  // 联网识别和整理整体被关掉，按住说话本机识别一失败就只能报错。
  test('网关地址：未显式注入时取 Supabase 同域 /ai/', () {
    expect(resolveAiGatewayUrl('', 'https://hh.example.com'), 'https://hh.example.com/ai/');
    expect(resolveAiGatewayUrl('', 'https://hh.example.com/'), 'https://hh.example.com/ai/');
    expect(resolveAiGatewayUrl('https://gw.example.com/ai/', 'https://hh.example.com'), 'https://gw.example.com/ai/');
    expect(resolveAiGatewayUrl('', ''), '');
    expect(asrUrl(resolveAiGatewayUrl('', 'https://hh.example.com')).toString(), 'wss://hh.example.com/ai/diary-asr');
  });

  test('CloudVoiceCapture：发 PCM 二进制帧 + end，拿到 final', () async {
    final sock = FakeSocket();
    String? jwt;
    final cap = CloudVoiceCapture(source: FakePcm(), token: () async => 'jwt-x', connect: (t, _) async {
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
    final cap = CloudVoiceCapture(source: FakePcm(), token: () async => 'j', connect: (_, _) async => FakeSocket(error: true));
    await cap.start(onPartial: (_) {});
    expect(await cap.stop(), '');
    expect(cap.failed, isTrue);
    final noMic = CloudVoiceCapture(source: FakePcm()..permission = false, token: () async => 'j', connect: (_, _) async => FakeSocket());
    expect(await noMic.start(onPartial: (_) {}), isFalse);
  });

  test('CloudVoiceCapture：连不上网关 → start=false', () async {
    final cap = CloudVoiceCapture(source: FakePcm(), token: () async => 'j', connect: (_, _) async => throw Exception('offline'));
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
  
  group('设置：联网语音识别开关', () {
    late FakeVoice system, cloud;
    Future<SharedPreferences> boot(WidgetTester tester, Map<String, Object> prefs) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      system = FakeVoice(ok: false);
      cloud = FakeVoice(text: '联网识别的一句话');
      await pumpApp(tester, prefs: {kDiaryGenderPrompted: true, ...prefs}, overrides: [
        diaryApiProvider.overrideWithValue(FakeApi(json: okJson)),
        voiceCaptureProvider.overrideWithValue(system),
        cloudVoiceCaptureProvider.overrideWithValue(cloud),
        diaryClockProvider.overrideWithValue(Clock().call),
      ]);
      return SharedPreferences.getInstance();
    }

    Future<void> go(WidgetTester tester, String loc) async {
      GoRouter.of(tester.element(find.byType(Scaffold).last)).go(loc);
      await settle(tester, 10);
    }

    bool switchOn(WidgetTester tester) => tester.widget<Switch>(find.byKey(const Key('cloud-asr-switch'))).value;
    Future<void> toggle(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('cloud-asr-switch')));
      await tester.tap(find.byKey(const Key('cloud-asr-switch')));
      await settle(tester);
    }

    Future<void> hold(WidgetTester tester) async {
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
      await settle(tester, 3);
      await g.up();
      await settle(tester, 10);
    }

    testWidgets('未问过：开关默认关；打开后日记里不再弹告知，直接改用联网识别', (tester) async {
      final sp = await boot(tester, const {});
      await go(tester, Routes.settings);
      expect(find.text('联网语音识别'), findsOneWidget);
      expect(switchOn(tester), isFalse);
      await toggle(tester);
      expect(switchOn(tester), isTrue);
      expect(sp.getBool(kDiaryCloudAsrConsent), isTrue);
      await go(tester, Routes.diary);
      await hold(tester);
      expect(find.byKey(const Key('cloud-asr-agree')), findsNothing);
      expect(find.text('本机识别不可用，已换成联网识别，请再说一次'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('首次告知里同意 → 设置显示已开；关掉后日记退回屏 9，不再弹告知', (tester) async {
      final sp = await boot(tester, const {});
      await go(tester, Routes.diary);
      await hold(tester);
      await tester.tap(find.byKey(const Key('cloud-asr-agree')));
      await settle(tester, 10);
      await tester.pump(const Duration(seconds: 3));
      await go(tester, Routes.settings);
      expect(switchOn(tester), isTrue);
      await toggle(tester);
      expect(switchOn(tester), isFalse);
      expect(sp.getBool(kDiaryCloudAsrConsent), isFalse);
      await go(tester, Routes.diary);
      await hold(tester);
      expect(find.byKey(const Key('cloud-asr-agree')), findsNothing);
      expect(find.byKey(const Key('voice-err-text')), findsOneWidget);
      expect(cloud.cancels, 0);
      await unmount(tester);
    });

    testWidgets('已关闭联网识别：本机不可用 → 打字页显示淡色提示，点击跳到设置该项', (tester) async {
      await boot(tester, const {kDiaryCloudAsrConsent: false});
      await go(tester, Routes.diary);
      await hold(tester);
      expect(find.byKey(const Key('cloud-asr-agree')), findsNothing); // 不再弹窗重问
      await tester.tap(find.byKey(const Key('voice-err-text')));
      await settle(tester, 10);
      expect(find.byKey(const Key('diary-text')), findsOneWidget);
      expect(find.text('可在设置中开启联网语音识别'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloud-asr-hint')));
      await settle(tester, 10);
      expect(find.byKey(const Key('cloud-asr-switch')), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('cloud-asr-switch'))).top < 2532 / 3, isTrue);
      expect(switchOn(tester), isFalse);
      await unmount(tester);
    });

    testWidgets('本机识别正常时打字页不显示提示', (tester) async {
      await boot(tester, const {kDiaryCloudAsrConsent: false});
      await go(tester, Routes.diary);
      await tester.tap(find.byKey(const Key('diary-type')));
      await settle(tester, 10);
      expect(find.byKey(const Key('diary-text')), findsOneWidget);
      expect(find.byKey(const Key('cloud-asr-hint')), findsNothing);
      await unmount(tester);
    });

    testWidgets('首次告知里拒绝 → 设置显示关', (tester) async {
      await boot(tester, const {kDiaryCloudAsrConsent: false});
      await go(tester, Routes.settings);
      expect(switchOn(tester), isFalse);
      await unmount(tester);
    });
  });
});
}
