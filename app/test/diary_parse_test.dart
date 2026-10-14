import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/diary/diary_card.dart';
import 'package:honghong/domain/diary/parse_result.dart';
import 'package:honghong/domain/diary/risk_words.dart';
import 'package:honghong/services/diary/diary_api.dart';

/// 假网关：不发真实请求
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions o, String body) handler;
  RequestOptions? last;
  String? lastBody;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async {
    last = o;
    lastBody = body == null ? '' : String.fromCharCodes((await body.toList()).expand((e) => e));
    return handler(o, lastBody!);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(String s, [int code = 200]) =>
    ResponseBody.fromString(s, code, headers: {Headers.contentTypeHeader: ['application/json; charset=utf-8']});

void main() {
  final now = DateTime(2026, 10, 14, 10, 30);

  group('assembleTime', () {
    test('普通时间落在今天', () {
      final t = assembleTime(now: now, eventTime: '08:00');
      expect(t.event, DateTime(2026, 10, 14, 8));
      expect(t.diaryDate, DateTime(2026, 10, 14));
    });
    test('晚于 now+10 分钟视为前一天', () {
      final t = assembleTime(now: now, eventTime: '23:00');
      expect(t.event, DateTime(2026, 10, 13, 23));
      expect(t.diaryDate, DateTime(2026, 10, 13));
    });
    test('结束早于开始：跨天；跨到未来则置空', () {
      final a = assembleTime(now: DateTime(2026, 10, 14, 7), eventTime: '22:00', endTime: '05:00');
      expect(a.event, DateTime(2026, 10, 13, 22));
      expect(a.end, DateTime(2026, 10, 14, 5));
    });
    test('只有时段用默认小时，不晚于 now', () {
      expect(assembleTime(now: now, period: DiaryPeriod.morning).sort, DateTime(2026, 10, 14, 9));
      expect(assembleTime(now: now, period: DiaryPeriod.afternoon).sort, now);
    });
    test('昨天无时间排到 23:59', () {
      final t = assembleTime(now: now, dayOffset: -1);
      expect(t.sort, DateTime(2026, 10, 13, 23, 59));
      expect(t.diaryDate, DateTime(2026, 10, 13));
    });
    test('非法时间不猜', () {
      expect(assembleTime(now: now, eventTime: '25:99').event, isNull);
    });
  });

  group('cardFromJson 二次校验', () {
    test('越界数值置空并标请核对，未知键丢弃', () {
      final c = cardFromJson({
        'category': 'feeding', 'kind': 'event', 'event_time': '08:00', 'confidence': 0.9,
        'attributes': {'ml': 9999, 'method': 'formula', 'foo': 1},
      }, now: now, rawText: '八点喝了奶粉');
      expect(c.category, DiaryCategory.feeding);
      expect(c.attributes, {'method': 'formula'});
      expect(c.needsReview, isTrue);
    });
    test('未知分类归为其他', () {
      final c = cardFromJson({'category': 'bath', 'confidence': 0.9}, now: now, rawText: '洗澡');
      expect(c.category, DiaryCategory.other);
      expect(c.needsReview, isTrue);
    });
    test('原话没有的诊断词从备注里去掉', () {
      final c = cardFromJson({'category': 'diaper', 'note': '可能是感染', 'confidence': 0.9}, now: now, rawText: '便便有点绿');
      expect(c.note ?? '', isNot(contains('感染')));
    });
  });

  test('风险词', () {
    expect(hasRiskWords('宝宝发烧 39.2 度'), isTrue);
    expect(hasRiskWords('体温 37.5'), isFalse);
    expect(hasRiskWords('吃了两次奶'), isFalse);
  });

  test('网关没有有效卡片：回落为原话一张其他', () {
    final r = ParseResult.fromGateway({'status': 'ok', 'cards': []}, text: '随便说说', inputType: 'text', now: now);
    expect(r.failed, isTrue);
    expect(r.cards.single.category, DiaryCategory.other);
    expect(r.cards.single.note, '随便说说');
  });

  group('HttpDiaryApi（假数据）', () {
    late FakeAdapter adapter;
    HttpDiaryApi api(ResponseBody Function(RequestOptions, String) h) {
      adapter = FakeAdapter(h);
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/ai/'))..httpClientAdapter = adapter;
      return HttpDiaryApi(baseUrl: 'https://example.test/ai/', token: () async => 'jwt-x', dio: dio);
    }

    test('小结：请求只含聚合统计与幂等键；429 → rateLimited', () async {
      final a = api((o, b) => json('{"content":"今天喂奶 2 次。","prompt_version":"sum-v1"}'));
      final r = await a.summary(date: '2026-10-14', ageInDays: 60, stats: const {'feed': {'count': 2}}, idempotencyKey: 'sid-1');
      expect(adapter.last!.uri.toString(), 'https://example.test/ai/diary-summary');
      expect(adapter.lastBody, contains('"idempotency_key":"sid-1"'));
      expect(adapter.lastBody, contains('"age_in_days":60'));
      expect(adapter.lastBody, isNot(contains('raw_text')));
      expect(r.content, '今天喂奶 2 次。');
      expect(r.promptVersion, 'sum-v1');
      await expectLater(api((o, b) => json('{}', 429)).summary(date: '2026-10-14', ageInDays: 1, stats: const {}, idempotencyKey: 'k'),
          throwsA(isA<DiaryApiException>().having((e) => e.kind, 'kind', DiaryApiError.rateLimited)));
    });

    test('请求格式与成功解析', () async {
      final a = api((o, b) => json('{"status":"ok","prompt_version":"parse-v2","model":"deepseek-chat",'
          '"cards":[{"category":"feeding","kind":"event","event_time":"08:00","attributes":{"ml":120,"method":"formula"},"confidence":0.95}],'
          '"risk":{"hit":false}}'));
      final r = await a.parse(text: '八点喝了120奶粉', inputType: 'voice', ageInDays: 30, now: now);
      expect(adapter.last!.uri.toString(), 'https://example.test/ai/diary-parse');
      expect(adapter.last!.headers['authorization'], 'Bearer jwt-x');
      expect(adapter.lastBody, contains('"now":"2026-10-14T10:30:00'));
      expect(adapter.lastBody, contains('"input_type":"voice"'));
      expect(r.status, 'ok');
      expect(r.promptVersion, 'parse-v2');
      expect(r.cards.single.intAttr('ml'), 120);
      expect(r.cards.single.eventTime, DateTime(2026, 10, 14, 8));
    });
    test('风险由网关或本地命中', () async {
      final a = api((o, b) => json('{"status":"ok","cards":[{"category":"other","confidence":0.9}],"risk":{"hit":true}}'));
      expect((await a.parse(text: 'x', inputType: 'text', ageInDays: 1, now: now)).risk, isTrue);
    });
    test('429 → rateLimited；502 → failed', () async {
      await expectLater(api((o, b) => json('{}', 429)).parse(text: 'x', inputType: 'text', ageInDays: 1, now: now),
          throwsA(isA<DiaryApiException>().having((e) => e.kind, 'kind', DiaryApiError.rateLimited)));
      await expectLater(api((o, b) => json('{"error":"bad_output"}', 502)).parse(text: 'x', inputType: 'text', ageInDays: 1, now: now),
          throwsA(isA<DiaryApiException>().having((e) => e.kind, 'kind', DiaryApiError.failed)));
    });
    test('连不上 → network', () async {
      final a = api((o, b) => throw DioException.connectionError(requestOptions: o, reason: 'offline'));
      await expectLater(a.parse(text: 'x', inputType: 'text', ageInDays: 1, now: now),
          throwsA(isA<DiaryApiException>().having((e) => e.kind, 'kind', DiaryApiError.network)));
    });
  });
}
