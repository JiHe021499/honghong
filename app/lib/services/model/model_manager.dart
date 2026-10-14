import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../data/db/app_database.dart';
import '../../domain/predictor/model_meta.dart';
import '../../domain/predictor/model_predictor.dart';
import '../cloud/cloud_api.dart';
import '../../core/app_clock.dart';

/// 把 .tflite 字节变成可推理的分类头（真实实现用 tflite_flutter，测试里用假的）
abstract class HeadLoader {
  Future<CryHead> fromBytes(Uint8List bytes, ModelMeta meta);
}

class TfliteHeadLoader implements HeadLoader {
  @override
  Future<CryHead> fromBytes(Uint8List bytes, ModelMeta meta) async => _TfliteHead(Interpreter.fromBuffer(bytes), meta.classes.length);
}

class _TfliteHead implements CryHead {
  _TfliteHead(this._it, this._k);
  final Interpreter _it;
  final int _k;
  @override
  List<double> run(Float32List features) {
    final out = [List<double>.filled(_k, 0)];
    _it.run([features], out);
    return out[0];
  }

  @override
  void close() => _it.close();
}

class LoadedModel {
  LoadedModel(this.head, this.meta, this.source);
  final CryHead head;
  final ModelMeta meta;
  final String source; // installed | bundled
}

/// 分类模型的安装、校验、热切换与回滚。
/// - 内置一个基线模型（assets/models/cry_head.*），没联网也能用；
/// - 云端 eligible_model('classifier') 有新版本时下载 → 校验 sha256 → 加载并跑自检样本 → 写入 ModelVersions 设为当前；
/// - 加载或推理失败的版本记入黑名单，自动退回上一个可用版本，最后退回内置模型，再不行只用规则。
class ModelManager {
  ModelManager(this._db, this._prefs, this._loader, {required this.dir, this.bundledTflite = 'assets/models/cry_head.tflite', this.bundledMeta = 'assets/models/cry_head.json', this.keep = 2});

  final AppDatabase _db;
  final SharedPreferences _prefs;
  final HeadLoader _loader;
  final Future<Directory> Function() dir;
  final String bundledTflite, bundledMeta;
  final int keep;

  static const kBad = 'model_bad_versions';
  static const kLastCheck = 'model_last_check';

  Set<String> get badVersions => (_prefs.getStringList(kBad) ?? const []).toSet();
  Future<void> _markBad(String v) => _prefs.setStringList(kBad, {...badVersions, v}.toList());

  static String sha256Hex(List<int> b) => sha256.convert(b).toString();

  /// 校验并加载：sha256 一致、能加载、自检样本输出在容差内
  Future<CryHead> verify(Uint8List bytes, ModelMeta meta, {String? expectedSha}) async {
    final sha = sha256Hex(bytes);
    if (sha != meta.sha256 || (expectedSha != null && sha != expectedSha)) {
      throw StateError('sha256 mismatch');
    }
    final head = await _loader.fromBytes(bytes, meta);
    try {
      final input = meta.selftestInput, expected = meta.selftestExpected;
      if (input != null && expected != null) {
        final out = head.run(Float32List.fromList(input));
        for (var i = 0; i < expected.length; i++) {
          if ((out[i] - expected[i]).abs() > meta.selftestTol) throw StateError('selftest failed');
        }
      }
      return head;
    } catch (_) {
      head.close();
      rethrow;
    }
  }

  Future<List<ModelVersion>> installed() => (_db.select(_db.modelVersions)
        ..where((m) => m.kind.equals('classifier'))
        ..orderBy([(m) => OrderingTerm.desc(m.active), (m) => OrderingTerm.desc(m.installedAt), (_) => OrderingTerm.desc(const CustomExpression<int>('rowid'))]))
      .get();

  /// 当前可用的模型：已安装的（当前优先，其次最近装的）→ 内置 → null（只用规则）
  Future<LoadedModel?> load() async {
    final bad = badVersions;
    for (final row in await installed()) {
      if (bad.contains(row.version)) continue;
      try {
        final meta = ModelMeta.decode(await File('${row.localPath}.json').readAsString());
        final head = await verify(await File(row.localPath).readAsBytes(), meta, expectedSha: row.sha256);
        if (!row.active) await _activate(row.version);
        return LoadedModel(head, meta, 'installed');
      } catch (_) {
        await _remove(row, bad: true);
      }
    }
    try {
      final meta = ModelMeta.decode(await rootBundle.loadString(bundledMeta));
      if (bad.contains(meta.version)) return null;
      final data = await rootBundle.load(bundledTflite);
      final head = await verify(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), meta);
      return LoadedModel(head, meta, 'bundled');
    } catch (_) {
      return null;
    }
  }

  /// 推理出错：拉黑这个版本，下次 load() 自动回退
  Future<void> reportFailure(String version) async {
    await _markBad(version);
    final rows = await (_db.select(_db.modelVersions)..where((m) => m.version.equals(version))).get();
    for (final r in rows) {
      await _remove(r, bad: true);
    }
  }

  /// 检查云端新版本。返回新装的版本号；没有更新或失败返回 null（失败的版本会拉黑，不会反复下载）。
  Future<String?> checkForUpdate(CloudApi api, {String? currentVersion}) async {
    final Map<String, dynamic>? row;
    try {
      row = await api.eligibleModel('classifier');
    } on CloudException {
      return null;
    }
    await _prefs.setString(kLastCheck, AppClock.now().toIso8601String());
    if (row == null) return null;
    final version = row['version'] as String;
    if (version == currentVersion || badVersions.contains(version)) return null;
    if ((await installed()).any((m) => m.version == version)) return null;
    final metaJson = row['meta'];
    if (metaJson == null) return null;
    final meta = ModelMeta.fromJson((metaJson is String ? jsonDecode(metaJson) : metaJson as Map).cast<String, dynamic>());
    if (meta.version != version) {
      await _markBad(version);
      return null;
    }
    final d = Directory(p.join((await dir()).path, 'models'));
    await d.create(recursive: true);
    final path = p.join(d.path, '$version.tflite');
    try {
      final bytes = await api.downloadModel(row['storage_path'] as String);
      final head = await verify(bytes, meta, expectedSha: row['sha256'] as String?);
      head.close();
      await File(path).writeAsBytes(bytes, flush: true);
      await File('$path.json').writeAsString(jsonEncode(meta.raw), flush: true);
      await _db.into(_db.modelVersions).insertOnConflictUpdate(ModelVersionsCompanion.insert(
          version: version, kind: 'classifier', localPath: path, sha256: meta.sha256, installedAt: Value(AppClock.now())));
      await _activate(version);
      await _prune();
      return version;
    } on CloudException {
      return null; // 网络问题：下次再试
    } catch (_) {
      await _markBad(version);
      for (final f in [File(path), File('$path.json')]) {
        if (await f.exists()) await f.delete();
      }
      return null;
    }
  }

  Future<void> _activate(String version) => _db.transaction(() async {
        await (_db.update(_db.modelVersions)..where((m) => m.kind.equals('classifier'))).write(const ModelVersionsCompanion(active: Value(false)));
        await (_db.update(_db.modelVersions)..where((m) => m.version.equals(version))).write(const ModelVersionsCompanion(active: Value(true)));
      });

  /// 只保留当前 + 上一个版本（回滚用）
  Future<void> _prune() async {
    final rows = await installed();
    for (final r in rows.skip(keep)) {
      await _remove(r);
    }
  }

  Future<void> _remove(ModelVersion r, {bool bad = false}) async {
    if (bad) await _markBad(r.version);
    await (_db.delete(_db.modelVersions)..where((m) => m.version.equals(r.version))).go();
    for (final f in [File(r.localPath), File('${r.localPath}.json')]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
