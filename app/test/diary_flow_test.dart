import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/domain/diary/parse_result.dart';
import 'package:honghong/features/diary/diary_flow.dart';
import 'package:honghong/features/diary/diary_providers.dart';
import 'package:honghong/services/diary/diary_api.dart';
import 'package:honghong/services/diary/voice_capture.dart';

import 'helpers.dart';

/// 假网关：返回固定 JSON（与真实网关同一解析路径）
class FakeApi implements DiaryApi {
  FakeApi({this.json, this.error});
  Map<String, dynamic>? json;
  DiaryApiException? error;
  final calls = <String>[];
  @override
  Future<ParseResult> parse({required String text, required String inputType, required int ageInDays, required DateTime now}) async {
    calls.add('$inputType:$text');
    if (error != null) throw error!;
    return ParseResult.fromGateway(json!, text: text, inputType: inputType, now: now);
  }
}

class FakeVoice implements VoiceCapture {
  FakeVoice({this.text = '刚才喂了奶，换了尿布', this.ok = true});
  String text;
  bool ok;
  int cancels = 0;
  @override
  Future<bool> start({required void Function(String partial) onPartial, void Function(double level)? onLevel}) async {
    if (ok) onPartial('刚才喂了');
    return ok;
  }

  @override
  Future<String> stop() async => text;
  @override
  Future<void> cancel() async => cancels++;
}

class Clock {
  DateTime t = DateTime.now();
  DateTime call() => t;
}

final okJson = {
  'status': 'ok',
  'prompt_version': 'parse-v2',
  'cards': [
    {'category': 'feeding', 'kind': 'event', 'attributes': {'method': 'breast'}, 'confidence': 0.9},
    {'category': 'diaper', 'kind': 'event', 'attributes': {'type': 'pee'}, 'confidence': 0.9},
  ],
  'risk': {'hit': false},
};

void main() {
  late FakeApi api;
  late FakeVoice voice;
  late Clock clock;

  Future<AppDatabase> open(WidgetTester tester, {Map<String, Object> prefs = const {kDiaryGenderPrompted: true}, bool noApi = false}) async {
    clock = Clock();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = await pumpApp(tester, prefs: prefs, overrides: [
      diaryApiProvider.overrideWithValue(noApi ? null : api),
      voiceCaptureProvider.overrideWithValue(voice),
      diaryClockProvider.overrideWithValue(clock.call),
    ]);
    await tester.ensureVisible(find.byKey(const Key('diary-entry')));
    await tester.tap(find.byKey(const Key('diary-entry')));
    await settle(tester, 10);
    return db;
  }

  Future<void> hold(WidgetTester tester, Duration d, {double dragUp = 0}) async {
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
    await settle(tester, 3);
    if (dragUp > 0) {
      await g.moveBy(Offset(0, -dragUp));
      await settle(tester, 2);
    }
    clock.t = clock.t.add(d);
    await g.up();
    await settle(tester, 10);
  }

  setUp(() {
    api = FakeApi(json: okJson);
    voice = FakeVoice();
  });

  testWidgets('首页入口卡 → 首次进入补问性别，可跳过且不再问', (tester) async {
    await open(tester, prefs: const {});
    expect(find.text('说一句话，帮你把今天记下来'), findsNothing); // 已进入日记页
    expect(find.byKey(const Key('gender-skip')), findsOneWidget);
    await tester.tap(find.byKey(const Key('gender-skip')));
    await settle(tester, 10);
    expect(find.byKey(const Key('gender-skip')), findsNothing);
    expect(find.byKey(const Key('diary-mic')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('按住说话 → 确认页 → 保存事务 → 提示已保存', (tester) async {
    final db = await open(tester);
    await hold(tester, const Duration(seconds: 3));
    expect(api.calls, ['voice:刚才喂了奶，换了尿布']);
    expect(find.byKey(const Key('card-0')), findsOneWidget);
    expect(find.byKey(const Key('card-1')), findsOneWidget);
    expect(find.text('保存 2 条'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save')));
    await settle(tester, 10);
    expect(find.text('已保存 2 条'), findsOneWidget);
    expect(await tester.runAsync(() => db.select(db.diaryCards).get()), hasLength(2));
    final logs = await tester.runAsync(() => db.select(db.careLogs).get());
    expect(logs!.map((l) => l.source).toSet(), {'diary'});
    await unmount(tester);
  });

  testWidgets('不足 1 秒：提示说长一点；上滑松手：取消', (tester) async {
    await open(tester);
    await hold(tester, const Duration(milliseconds: 400));
    expect(find.text('说长一点试试'), findsOneWidget);
    await hold(tester, const Duration(seconds: 3), dragUp: 120);
    expect(api.calls, isEmpty);
    expect(voice.cancels, 2);
    await unmount(tester);
  });

  testWidgets('识别不可用 → 错误面板 → 改用文字输入 → 保存', (tester) async {
    voice.ok = false;
    final db = await open(tester);
    await hold(tester, const Duration(seconds: 2));
    expect(find.byKey(const Key('voice-err-text')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-err-text')));
    await settle(tester, 10);
    await tester.enterText(find.byKey(const Key('diary-text')), '下午一直哭');
    await settle(tester);
    await tester.tap(find.byKey(const Key('diary-text-submit')));
    await settle(tester, 10);
    expect(api.calls, ['text:下午一直哭']);
    // 取消勾选第二张
    await tester.tap(find.descendant(of: find.byKey(const Key('card-1')), matching: find.byKey(const Key('check'))));
    await settle(tester);
    expect(find.text('保存 1 条'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save')));
    await settle(tester, 10);
    expect(await tester.runAsync(() => db.select(db.diaryCards).get()), hasLength(1));
    await unmount(tester);
  });

  testWidgets('断网：文字保留为草稿并回到文字输入', (tester) async {
    api.error = const DiaryApiException(DiaryApiError.network);
    await open(tester);
    await hold(tester, const Duration(seconds: 2));
    expect(find.byKey(const Key('diary-text')), findsOneWidget);
    expect(find.text('刚才喂了奶，换了尿布'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('整理失败 / 未配置网关：原话存为一张“其他”', (tester) async {
    await open(tester, noApi: true);
    await tester.tap(find.byKey(const Key('diary-type')));
    await settle(tester, 10);
    await tester.enterText(find.byKey(const Key('diary-text')), '今天去打了疫苗');
    await settle(tester);
    await tester.tap(find.byKey(const Key('diary-text-submit')));
    await settle(tester, 10);
    expect(find.byKey(const Key('card-0')), findsOneWidget);
    expect(find.byKey(const Key('card-1')), findsNothing);
    expect(find.text('保存 1 条'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('风险词：确认页显示固定提示', (tester) async {
    voice.text = '宝宝发高烧了';
    await open(tester);
    await hold(tester, const Duration(seconds: 2));
    expect(find.byKey(const Key('risk-warn')), findsOneWidget);
    expect(find.text('如有担心，请及时就医。'), findsOneWidget);
    await unmount(tester);
  });
}
