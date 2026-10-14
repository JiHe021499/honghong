import 'package:dio/dio.dart';

import '../../domain/diary/parse_result.dart';

/// 网关调用失败的种类，决定界面怎么兜底（架构 §5.3）
enum DiaryApiError {
  /// 无网/连不上：保留文字草稿，提示重试
  network,

  /// 超时 / 5xx / 两次 schema 不合规：原话存成一张“其他”（屏 14）
  failed,

  /// 今天次数用完
  rateLimited,
}

class DiaryApiException implements Exception {
  const DiaryApiException(this.kind, [this.detail]);
  final DiaryApiError kind;
  final String? detail;
  @override
  String toString() => 'DiaryApiException($kind, $detail)';
}

abstract class DiaryApi {
  /// 一句话 → 卡片。只发文本、日龄、当前时间（含时区），不发小名/性别/宝宝 id（架构 §7）。
  Future<ParseResult> parse({required String text, required String inputType, required int ageInDays, required DateTime now});
}

/// 本地时间带时区偏移的 ISO 字符串，例如 2026-10-14T20:31:00+08:00
String isoWithOffset(DateTime t) {
  final o = t.timeZoneOffset;
  String two(int v) => v.abs().toString().padLeft(2, '0');
  final sign = o.isNegative ? '-' : '+';
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
      '$sign${two(o.inHours)}:${two(o.inMinutes % 60)}';
}

/// 调 ai-gateway（Supabase 匿名登录 JWT 鉴权）。
class HttpDiaryApi implements DiaryApi {
  HttpDiaryApi({required String baseUrl, required this.token, Dio? dio, this.clientVersion = ''})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 5),
            ));

  final Dio _dio;
  final Future<String> Function() token;
  final String clientVersion;

  @override
  Future<ParseResult> parse({required String text, required String inputType, required int ageInDays, required DateTime now}) async {
    final sw = Stopwatch()..start();
    final String jwt;
    try {
      jwt = await token();
    } catch (_) {
      throw const DiaryApiException(DiaryApiError.network, 'auth');
    }
    try {
      final r = await _dio.post<Map<String, dynamic>>('diary-parse',
          data: {'text': text, 'age_in_days': ageInDays, 'now': isoWithOffset(now), 'input_type': inputType, 'client_version': clientVersion},
          options: Options(headers: {'authorization': 'Bearer $jwt'}));
      return ParseResult.fromGateway(r.data ?? const {}, text: text, inputType: inputType, now: now, latencyMs: sw.elapsedMilliseconds);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 429) throw const DiaryApiException(DiaryApiError.rateLimited);
      if (code == null && (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.sendTimeout)) {
        throw DiaryApiException(DiaryApiError.network, e.type.name);
      }
      throw DiaryApiException(DiaryApiError.failed, code?.toString() ?? e.type.name);
    } catch (e) {
      if (e is DiaryApiException) rethrow;
      throw DiaryApiException(DiaryApiError.failed, '$e');
    }
  }
}
