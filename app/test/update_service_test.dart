import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/services/update/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 按 URL 前缀返回固定内容的假网络
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes);
  final Map<String, Object> routes; // 值为 String/bytes 或 int（状态码）
  final hits = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final url = o.uri.toString();
    hits.add(url);
    for (final e in routes.entries) {
      if (url.startsWith(e.key)) {
        final v = e.value;
        if (v is int) return ResponseBody.fromString('err', v);
        final bytes = v is String ? utf8.encode(v) : v as List<int>;
        return ResponseBody.fromBytes(bytes, 200, headers: {
          Headers.contentLengthHeader: ['${bytes.length}'],
        });
      }
    }
    throw DioException.connectionError(requestOptions: o, reason: 'no route');
  }

  @override
  void close({bool force = false}) {}
}

const src = 'https://raw.githubusercontent.com/JiHe021499/honghong-releases/main/version.json';
const apkUrl = 'https://github.com/JiHe021499/honghong-releases/releases/download/v0.1.42/honghong-0.1.42.apk';
final apkBytes = List<int>.generate(5000, (i) => i % 251);
final apkSha = sha256.convert(apkBytes).toString();

Map<String, Object?> versionJson({int code = 42, bool force = false, int min = 0, String? sha}) => {
      'versionName': '0.1.$code',
      'versionCode': code,
      'channel': 'dev',
      'apkUrl': apkUrl,
      'apkName': 'honghong-0.1.$code.apk',
      'sha256': sha ?? apkSha,
      'size': apkBytes.length,
      'changelog': '- 修复了一些问题',
      'force': force,
      'minSupportedVersionCode': min,
      'publishedAt': '2026-10-13T14:00:00Z',
      'channels': {
        'stable': {
          'versionName': '0.1.0', 'versionCode': 30, 'apkUrl': apkUrl, 'sha256': apkSha, 'size': 1, 'channel': 'stable',
        },
      },
    };

void main() {
  late SharedPreferences prefs;
  var now = DateTime(2026, 10, 13, 22);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 10, 13, 22);
  });

  UpdateService svc(FakeAdapter a, {int current = 40}) =>
      UpdateService(dio: Dio()..httpClientAdapter = a, prefs: prefs, currentCode: current, clock: () => now);

  group('解析 version.json', () {
    test('顶层字段', () {
      final i = ReleaseInfo.parse(versionJson());
      expect(i.versionName, '0.1.42');
      expect(i.versionCode, 42);
      expect(i.sha256, apkSha);
      expect(i.size, 5000);
      expect(i.changelog, contains('修复'));
      expect(i.publishedAt, DateTime.utc(2026, 10, 13, 14));
    });
    test('指定渠道取 channels 里的', () {
      expect(ReleaseInfo.parse(versionJson(), channel: 'stable').versionCode, 30);
      expect(ReleaseInfo.parse(versionJson(), channel: 'beta').versionCode, 42, reason: '没有该渠道时用顶层');
    });
    test('缺字段或 sha 不对报错', () {
      expect(() => ReleaseInfo.parse({}), throwsFormatException);
      expect(() => ReleaseInfo.parse({...versionJson(), 'sha256': 'abc'}), throwsFormatException);
      expect(() => ReleaseInfo.parse({...versionJson(), 'versionCode': 0}), throwsFormatException);
      expect(ReleaseInfo.parse({...versionJson(), 'versionCode': '43'}).versionCode, 43, reason: '字符串数字也接受');
    });
  });

  group('版本比较', () {
    final info = ReleaseInfo.parse(versionJson());
    test('dev 版带 -dev 后缀：照常解析，只按 versionCode 比较', () {
      final dev = ReleaseInfo.parse({
        ...versionJson(),
        'versionName': '0.1.50-dev',
        'versionCode': 50,
        'apkUrl': 'https://github.com/JiHe021499/honghong-releases/releases/download/v0.1.50-dev/honghong-0.1.50-dev.apk',
        'apkName': 'honghong-0.1.50-dev.apk',
      });
      expect(dev.versionName, '0.1.50-dev');
      expect(UpdateCheck(dev, 49).hasUpdate, isTrue);
      expect(UpdateCheck(dev, 50).hasUpdate, isFalse);
      // 正式版 0.2.0（code 51）比 0.1.50-dev（code 50）新；名字里的后缀不参与比较
      final stable = ReleaseInfo.parse({...versionJson(), 'versionName': '0.2.0', 'versionCode': 51});
      expect(UpdateCheck(stable, 50).hasUpdate, isTrue);
    });
    test('versionCode 大才算新版本', () {
      expect(UpdateCheck(info, 40).hasUpdate, isTrue);
      expect(UpdateCheck(info, 42).hasUpdate, isFalse);
      expect(UpdateCheck(info, 50).hasUpdate, isFalse);
    });
    test('强制更新：force 或低于最低支持版本', () {
      expect(UpdateCheck(info, 40).forced, isFalse);
      expect(UpdateCheck(ReleaseInfo.parse(versionJson(force: true)), 40).forced, isTrue);
      expect(UpdateCheck(ReleaseInfo.parse(versionJson(min: 41)), 40).forced, isTrue);
      expect(UpdateCheck(ReleaseInfo.parse(versionJson(min: 41)), 41).forced, isFalse);
      expect(UpdateCheck(ReleaseInfo.parse(versionJson(force: true)), 42).forced, isFalse, reason: '已经是最新就不强制');
    });
  });

  group('检查', () {
    test('自动检查每 6 小时最多一次，手动不受限', () async {
      final a = FakeAdapter({src: jsonEncode(versionJson())});
      final s = svc(a);
      expect(s.due, isTrue);
      final r = await s.check();
      expect(r!.hasUpdate, isTrue);
      expect(await s.check(), isNull);
      now = now.add(const Duration(hours: 5, minutes: 59));
      expect(await s.check(), isNull);
      expect((await s.check(manual: true))?.info.versionCode, 42);
      now = now.add(const Duration(hours: 6));
      expect(await s.check(), isNotNull);
    });

    test('GitHub 不通时走镜像', () async {
      final a = FakeAdapter({src: 503, 'https://ghfast.top/$src': jsonEncode(versionJson())});
      final r = await svc(a).check(manual: true);
      expect(r!.info.versionCode, 42);
      expect(a.hits.last, startsWith('https://ghfast.top/'));
    });

    test('全都失败抛异常，且不记检查时间', () async {
      final s = svc(FakeAdapter({}));
      await expectLater(s.check(), throwsA(isA<UpdateException>()));
      expect(s.due, isTrue);
    });

    test('稍后：同一版本不再自动提醒，强制更新照样提醒', () async {
      final s = svc(FakeAdapter({}));
      final c = UpdateCheck(ReleaseInfo.parse(versionJson()), 40);
      await s.skip(42);
      expect(s.isSkipped(c), isTrue);
      expect(s.isSkipped(UpdateCheck(ReleaseInfo.parse(versionJson(code: 43)), 40)), isFalse);
      expect(s.isSkipped(UpdateCheck(ReleaseInfo.parse(versionJson(force: true)), 40)), isFalse);
    });
  });

  group('下载与校验', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('upd'));
    tearDown(() => dir.delete(recursive: true));

    test('下载并校验 sha256，有进度回调', () async {
      final s = svc(FakeAdapter({apkUrl: apkBytes}));
      var last = 0;
      final f = await s.download(ReleaseInfo.parse(versionJson()), dir, onProgress: (r, t) => last = r);
      expect(await f.readAsBytes(), apkBytes);
      expect(last, apkBytes.length);
    });

    test('sha256 不一致：删除文件并报错', () async {
      final wrong = 'f' * 64;
      final s = svc(FakeAdapter({apkUrl: apkBytes}));
      await expectLater(
        s.download(ReleaseInfo.parse(versionJson(sha: wrong)), dir),
        throwsA(isA<ShaMismatchException>().having((e) => e.actual, 'actual', apkSha)),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('原地址下坏了，镜像下对了就用镜像的', () async {
      final a = FakeAdapter({apkUrl: [1, 2, 3], 'https://ghfast.top/$apkUrl': apkBytes});
      final f = await svc(a).download(ReleaseInfo.parse(versionJson()), dir);
      expect(await UpdateService.verify(f, apkSha), isTrue);
    });

    test('已经下好的同版本不重复下载', () async {
      final a = FakeAdapter({apkUrl: apkBytes});
      final s = svc(a);
      await s.download(ReleaseInfo.parse(versionJson()), dir);
      await s.download(ReleaseInfo.parse(versionJson()), dir);
      expect(a.hits.length, 1);
    });
  });

  group('本站下载（localApkUrl）', () {
    const site = UpdateService.siteSource;
    const localPath = '/download/files/dev/honghong-0.1.42-42-aaaaaaaa.apk';
    const localUrl = 'https://honghong.hczhw.com$localPath';
    Map<String, Object?> siteJson() => {...versionJson(), 'localApkUrl': localPath};
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('upd'));
    tearDown(() => dir.delete(recursive: true));

    test('解析：相对路径按来源地址补全；没有字段时为 null（兼容 GitHub 原件）', () {
      expect(ReleaseInfo.parse(siteJson(), source: Uri.parse(site)).localApkUrl, localUrl);
      expect(ReleaseInfo.parse(versionJson(), source: Uri.parse(site)).localApkUrl, isNull);
      expect(ReleaseInfo.parse(siteJson()).localApkUrl, isNull, reason: '不知道来源就不猜');
    });
    test('解析：非法或非 https 的 localApkUrl 忽略，不影响其它字段', () {
      for (final bad in [123, '', 'http://honghong.hczhw.com/x.apk', 'ftp://a/b.apk', '/download/files/x.txt']) {
        final i = ReleaseInfo.parse({...versionJson(), 'localApkUrl': bad}, source: Uri.parse(site));
        expect(i.localApkUrl, isNull, reason: '$bad');
        expect(i.versionCode, 42);
      }
      expect(ReleaseInfo.parse({...versionJson(), 'localApkUrl': 'https://cdn.example.com/a.apk'}).localApkUrl,
          'https://cdn.example.com/a.apk');
    });
    test('检查更新先读本站副本，带上 localApkUrl', () async {
      final a = FakeAdapter({site: jsonEncode(siteJson()), src: jsonEncode(versionJson())});
      final r = await svc(a).check(manual: true);
      expect(r!.info.localApkUrl, localUrl);
      expect(a.hits.single, startsWith(site));
    });
    test('本站副本拿不到时读 GitHub：没有 localApkUrl，本站地址不走 GitHub 镜像', () async {
      final a = FakeAdapter({site: 502, src: jsonEncode(versionJson())});
      final r = await svc(a).check(manual: true);
      expect(r!.info.localApkUrl, isNull);
      expect(a.hits.where((h) => h.contains('ghfast') && h.contains('hczhw')), isEmpty);
    });
    test('下载优先本站，校验 sha256', () async {
      final a = FakeAdapter({localUrl: apkBytes, apkUrl: [9, 9, 9]});
      final info = ReleaseInfo.parse(siteJson(), source: Uri.parse(site));
      final f = await svc(a).download(info, dir);
      expect(await UpdateService.verify(f, apkSha), isTrue);
      expect(a.hits, [localUrl]);
    });
    test('本站失败（出错或哈希不对）回退 GitHub', () async {
      final info = ReleaseInfo.parse(siteJson(), source: Uri.parse(site));
      for (final local in <Object>[404, [1, 2, 3]]) {
        final d = await dir.createTemp();
        final a = FakeAdapter({localUrl: local, apkUrl: apkBytes});
        final f = await svc(a).download(info, d);
        expect(await UpdateService.verify(f, apkSha), isTrue, reason: '$local');
        expect(a.hits, [localUrl, apkUrl]);
      }
    });
    test('本站和 GitHub 都给了坏包：报校验失败，不留文件', () async {
      final info = ReleaseInfo.parse(siteJson(), source: Uri.parse(site));
      final a = FakeAdapter({localUrl: [1], apkUrl: [2], 'https://ghfast.top/': [3], 'https://gh-proxy.com/': [4]});
      await expectLater(svc(a).download(info, dir), throwsA(isA<ShaMismatchException>()));
      expect(dir.listSync(), isEmpty);
      expect(a.hits.first, localUrl);
      expect(a.hits.length, 4);
    });
    test('没有 localApkUrl 时下载顺序和原来一样', () {
      final s = svc(FakeAdapter({}));
      expect(s.apkCandidates(ReleaseInfo.parse(versionJson())), s.candidates(apkUrl));
      expect(s.candidates(localUrl), [localUrl]);
    });
  });
}
