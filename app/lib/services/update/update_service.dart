import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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

  /// 本站（honghong.hczhw.com）的安装包地址，已解析为绝对地址；为 null 时直接用 [apkUrl]。
  /// 只作为下载地址用。校验永远用 [sha256]，而 [sha256] 只来自 GitHub 原件（见 [UpdateService.check]）。
  final String? localApkUrl;

  ReleaseInfo withLocalApkUrl(String? url) => ReleaseInfo(
        versionName: versionName,
        versionCode: versionCode,
        apkUrl: apkUrl,
        sha256: sha256,
        size: size,
        changelog: changelog,
        force: force,
        minSupportedVersionCode: minSupportedVersionCode,
        channel: channel,
        publishedAt: publishedAt,
        localApkUrl: url,
      );

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
      localApkUrl: resolveLocal(j['localApkUrl'], source),
    );
  }

  /// localApkUrl 可以是相对路径（相对 version.json 的来源）或 https 绝对地址；其它情况一律忽略，不影响解析。
  static String? resolveLocal(Object? v, Uri? source) {
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

/// 连不上 GitHub（原件和镜像都失败）。这时不会改用本站的 version.json，因为哈希只认 GitHub 原件。
class GithubUnreachableException extends UpdateException {
  GithubUnreachableException(this.stage, this.cause)
      : super(stage == 'check'
            ? '暂时连不上 GitHub，无法确认安装包是否可信，请稍后重试（也可以到 GitHub 的 honghong-releases 手动下载）'
            : '下载失败：暂时连不上 GitHub，请稍后重试');
  final String stage;
  final Object? cause;
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
    this.siteSource = defaultSiteSource,
    this.mirrorPrefixes = defaultMirrors,
    this.interval = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _now = clock ?? AppClock.now;

  static const releasesRepo = 'JiHe021499/honghong-releases';

  /// 版本信息和 sha256 的唯一来源：GitHub 原件（读不到时走 GitHub 镜像）。
  static const defaultSources = ['https://raw.githubusercontent.com/$releasesRepo/main/version.json'];

  /// 本站副本：只从里面取 localApkUrl（下载地址），其它字段（包括 sha256）一概不用。
  static const defaultSiteSource = 'https://honghong.hczhw.com/download/data/version.json';

  static const metricsKey = 'update_metrics_v1';
  static const metricsKeepDays = 30;

  /// GitHub 访问不了时的镜像前缀（ghproxy 风格：前缀 + 原始 URL），按顺序尝试，可改
  static const defaultMirrors = ['https://ghfast.top/', 'https://gh-proxy.com/'];

  static const lastCheckKey = 'update_last_check';
  static const skippedKey = 'update_skipped_code';

  final Dio dio;
  final SharedPreferences prefs;
  final int currentCode;
  final List<String> sources;
  final String? siteSource;
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

  Future<String> _getText(String url) async {
    final r = await dio.get<String>(
      url,
      queryParameters: {'t': _now().millisecondsSinceEpoch ~/ 60000}, // 绕过 CDN 缓存（按分钟）
      options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 10)),
    );
    return r.data ?? '';
  }

  /// 检查更新。[manual] 为 false 时受节流限制，没到点返回 null。
  ///
  /// 1. 读 GitHub 原件（含镜像）得到版本信息和 sha256；全部失败就抛 [GithubUnreachableException] 并记一次埋点，
  ///    **不会**改用本站副本。
  /// 2. 再读本站副本，只取同一版本（versionCode 和 apkUrl 都一致）的 localApkUrl 作为优先下载地址；
  ///    本站读不到或对不上就忽略，从 GitHub 下载。
  Future<UpdateCheck?> check({bool manual = false}) async {
    if (!manual && !due) return null;
    ReleaseInfo? info;
    Object? lastError;
    for (final src in sources) {
      for (final url in candidates(src)) {
        try {
          info = ReleaseInfo.parse(Map<String, dynamic>.from(jsonDecode(await _getText(url)) as Map))
              .withLocalApkUrl(null); // 原件里即使出现 localApkUrl 也不用
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (info != null) break;
    }
    if (info == null) {
      await recordGithubUnreachable('check', lastError);
      throw GithubUnreachableException('check', lastError);
    }
    info = info.withLocalApkUrl(await _localApkUrlFor(info));
    await prefs.setInt(lastCheckKey, _now().millisecondsSinceEpoch);
    return UpdateCheck(info, currentCode);
  }

  /// 从本站副本里找与 GitHub 原件同一版本的本站下载地址。只比对 versionCode 和 apkUrl，不读本站的 sha256。
  Future<String?> _localApkUrlFor(ReleaseInfo gh) async {
    final site = siteSource;
    if (site == null) return null;
    try {
      final j = Map<String, dynamic>.from(jsonDecode(await _getText(site)) as Map);
      final entries = <Map>[j, ...((j['channels'] as Map?)?.values.whereType<Map>() ?? const <Map>[])];
      for (final e in entries) {
        final code = e['versionCode'];
        if ((code is num ? code.toInt() : int.tryParse('$code')) == gh.versionCode && e['apkUrl'] == gh.apkUrl) {
          return ReleaseInfo.resolveLocal(e['localApkUrl'], Uri.parse(site));
        }
      }
    } catch (_) {
      // 本站不可用不影响更新，直接从 GitHub 下载
    }
    return null;
  }

  /// 本机埋点：按天累计「GitHub 不可达导致更新失败」的次数（check / download 两个阶段），保留 30 天。
  /// 目前 App 没有上报通道，只存在本机（SharedPreferences: [metricsKey]），并打一行日志。
  Future<void> recordGithubUnreachable(String stage, Object? cause) async {
    debugPrint('[update] github_unreachable stage=$stage cause=${cause.runtimeType}');
    try {
      final all = Map<String, dynamic>.from(jsonDecode(prefs.getString(metricsKey) ?? '{}') as Map);
      final t = _now();
      String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final day = Map<String, dynamic>.from((all[ymd(t)] as Map?) ?? {});
      final k = 'github_unreachable_$stage';
      day[k] = ((day[k] as num?) ?? 0).toInt() + 1;
      all[ymd(t)] = day;
      final cutoff = ymd(t.subtract(const Duration(days: metricsKeepDays)));
      all.removeWhere((d, _) => d.compareTo(cutoff) < 0);
      await prefs.setString(metricsKey, jsonEncode(all));
    } catch (_) {}
  }

  /// 读出本机埋点：{日期: {github_unreachable_check: n, github_unreachable_download: n}}
  Map<String, Map<String, int>> get metrics {
    try {
      final all = jsonDecode(prefs.getString(metricsKey) ?? '{}') as Map;
      return all.map((d, v) => MapEntry('$d', Map<String, int>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  /// 用户点了"稍后"：这个版本自动检查时不再弹（强制更新除外）
  Future<void> skip(int versionCode) => prefs.setInt(skippedKey, versionCode);
  bool isSkipped(UpdateCheck c) => !c.forced && prefs.getInt(skippedKey) == c.info.versionCode;

  /// 下载安装包（带进度），用 [ReleaseInfo.sha256]（来自 GitHub 原件）校验，返回文件。
  /// 校验通过后交给系统安装，系统还会校验 APK 签名与已安装版本一致。
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
    await recordGithubUnreachable('download', lastError);
    throw GithubUnreachableException('download', lastError);
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

