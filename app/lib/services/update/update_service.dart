import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_clock.dart';

/// 公开发布仓库里的 version.json（由 CI 生成，见 .github/workflows/android.yml）
class ReleaseInfo {
  const ReleaseInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.size,
    this.changelog = '',
    this.force = false,
    this.minSupportedVersionCode = 0,
    this.channel = 'dev',
    this.publishedAt,
    this.localApkUrl,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String sha256;
  final int size;
  final String changelog;
  final bool force;
  final int minSupportedVersionCode;
  final String channel;
  final DateTime? publishedAt;

  /// 本站（honghong.hczhw.com）同步并校验过的安装包地址，已解析为绝对地址。
  /// 只有服务器上的 version.json 副本才有；GitHub 上的原件没有这个字段，为 null 时直接用 [apkUrl]。
  final String? localApkUrl;

  /// 解析 version.json。[channel] 指定时优先取 channels[channel]，否则取顶层（最新一次发布）。
  /// [source] 是 version.json 的来源地址，用来解析相对的 localApkUrl。
  static ReleaseInfo parse(Map<String, dynamic> json, {String? channel, Uri? source}) {
    var j = json;
    final chans = json['channels'];
    if (channel != null && chans is Map && chans[channel] is Map) {
      j = Map<String, dynamic>.from(chans[channel] as Map);
    }
    int toInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final name = j['versionName'];
    final code = toInt(j['versionCode']);
    final url = j['apkUrl'];
    final sha = j['sha256'];
    if (name is! String || code <= 0 || url is! String || sha is! String || sha.length != 64) {
      throw const FormatException('version.json 缺少必要字段');
    }
    return ReleaseInfo(
      versionName: name,
      versionCode: code,
      apkUrl: url,
      sha256: sha.toLowerCase(),
      size: toInt(j['size']),
      changelog: (j['changelog'] as String?) ?? '',
      force: j['force'] == true,
      minSupportedVersionCode: toInt(j['minSupportedVersionCode']),
      channel: (j['channel'] as String?) ?? 'dev',
      publishedAt: DateTime.tryParse('${j['publishedAt']}'),
      localApkUrl: _resolveLocal(j['localApkUrl'], source),
    );
  }

  /// localApkUrl 可以是相对路径（相对 version.json 的来源）或 https 绝对地址；其它情况一律忽略，不影响解析。
  static String? _resolveLocal(Object? v, Uri? source) {
    if (v is! String || v.isEmpty) return null;
    final u = Uri.tryParse(v);
    if (u == null) return null;
    final abs = u.hasScheme ? u : source?.resolveUri(u);
    if (abs == null || abs.scheme != 'https' || abs.host.isEmpty || !abs.path.endsWith('.apk')) return null;
    return abs.toString();
  }
}

class UpdateCheck {
  const UpdateCheck(this.info, this.currentCode);
  final ReleaseInfo info;
  final int currentCode;

  bool get hasUpdate => info.versionCode > currentCode;

  /// 强制更新：新版标了 force，或者当前版本低于最低支持版本
  bool get forced => hasUpdate && (info.force || currentCode < info.minSupportedVersionCode);
}

class ShaMismatchException implements Exception {
  ShaMismatchException(this.expected, this.actual);
  final String expected, actual;
  @override
  String toString() => '安装包校验失败（sha256 不一致），可能下载不完整，请重试';
}

/// 检查更新与下载。只在 Android 上使用。
class UpdateService {
  UpdateService({
    required this.dio,
    required this.prefs,
    required this.currentCode,
    this.sources = defaultSources,
    this.mirrorPrefixes = defaultMirrors,
    this.interval = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _now = clock ?? AppClock.now;

  static const releasesRepo = 'JiHe021499/honghong-releases';

  /// 先读本站副本（带 localApkUrl，国内访问稳定），失败再读 GitHub 原件（没有 localApkUrl）。
  static const siteSource = 'https://honghong.hczhw.com/download/data/version.json';
  static const defaultSources = [siteSource, 'https://raw.githubusercontent.com/$releasesRepo/main/version.json'];

  /// GitHub 访问不了时的镜像前缀（ghproxy 风格：前缀 + 原始 URL），按顺序尝试，可改
  static const defaultMirrors = ['https://ghfast.top/', 'https://gh-proxy.com/'];

  static const lastCheckKey = 'update_last_check';
  static const skippedKey = 'update_skipped_code';

  final Dio dio;
  final SharedPreferences prefs;
  final int currentCode;
  final List<String> sources;
  final List<String> mirrorPrefixes;
  final Duration interval;
  final DateTime Function() _now;

  /// 自动检查是否到点（默认每 6 小时一次）
  bool get due {
    final last = prefs.getInt(lastCheckKey);
    if (last == null) return true;
    return _now().difference(DateTime.fromMillisecondsSinceEpoch(last)) >= interval;
  }

  /// 依次尝试的地址：原地址，再加各镜像（镜像只代理 GitHub 的地址）
  List<String> candidates(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    final github = host == 'github.com' || host.endsWith('.github.com') || host.endsWith('githubusercontent.com');
    return [url, if (github) for (final m in mirrorPrefixes) '$m$url'];
  }

  /// 下载安装包依次尝试的地址：本站（有的话）→ GitHub → GitHub 镜像
  List<String> apkCandidates(ReleaseInfo info) =>
      [if (info.localApkUrl != null && info.localApkUrl != info.apkUrl) info.localApkUrl!, ...candidates(info.apkUrl)];

  /// 检查更新。[manual] 为 false 时受节流限制，没到点返回 null。
  Future<UpdateCheck?> check({bool manual = false}) async {
    if (!manual && !due) return null;
    Object? lastError;
    for (final src in sources) {
      for (final url in candidates(src)) {
        try {
          final r = await dio.get<String>(
            url,
            queryParameters: {'t': _now().millisecondsSinceEpoch ~/ 60000}, // 绕过 CDN 缓存（按分钟）
            options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 10)),
          );
          final info = ReleaseInfo.parse(Map<String, dynamic>.from(jsonDecode(r.data ?? '') as Map), source: Uri.parse(src));
          await prefs.setInt(lastCheckKey, _now().millisecondsSinceEpoch);
          return UpdateCheck(info, currentCode);
        } catch (e) {
          lastError = e;
        }
      }
    }
    throw UpdateException('检查更新失败：${lastError ?? '没有可用地址'}');
  }

  /// 用户点了"稍后"：这个版本自动检查时不再弹（强制更新除外）
  Future<void> skip(int versionCode) => prefs.setInt(skippedKey, versionCode);
  bool isSkipped(UpdateCheck c) => !c.forced && prefs.getInt(skippedKey) == c.info.versionCode;

  /// 下载安装包（带进度），校验 sha256，返回文件
  Future<File> download(ReleaseInfo info, Directory dir,
      {void Function(int received, int total)? onProgress, CancelToken? cancel}) async {
    await dir.create(recursive: true);
    final file = File('${dir.path}/honghong-${info.versionName}.apk');
    if (await file.exists() && await verify(file, info.sha256)) return file; // 已经下好了
    Object? lastError;
    ShaMismatchException? mismatch;
    for (final url in apkCandidates(info)) {
      try {
        await dio.download(url, file.path, onReceiveProgress: onProgress, cancelToken: cancel);
        if (!await verify(file, info.sha256)) {
          final actual = await sha256Of(file);
          await file.delete();
          throw ShaMismatchException(info.sha256, actual);
        }
        return file;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        lastError = e;
        if (await file.exists()) await file.delete(); // 下了一半的不留，换下一个地址重下
      } on ShaMismatchException catch (e) {
        mismatch = e;
      }
    }
    if (mismatch != null) throw mismatch;
    throw UpdateException('下载失败：$lastError');
  }

  static Future<String> sha256Of(File f) async => (await sha256.bind(f.openRead()).first).toString();

  static Future<bool> verify(File f, String expected) async => (await sha256Of(f)) == expected.toLowerCase();
}

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

