import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/domain/predictor/model_meta.dart';
import 'package:honghong/domain/predictor/model_predictor.dart';
import 'package:honghong/services/model/model_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud.dart';

/// 假加载器：字节以 CRASH 开头加载失败，以 BAD 开头自检输出不对，其余输出自检期望值
class FakeLoader implements HeadLoader {
  @override
  Future<CryHead> fromBytes(Uint8List bytes, ModelMeta meta) async {
    final tag = ascii.decode(bytes.take(5).toList(), allowInvalid: true);
    if (tag.startsWith('CRASH')) throw StateError('cannot load');
    return _Head(tag.startsWith('BAD') ? List.filled(meta.classes.length, 0.25) : (meta.selftestExpected ?? List.filled(meta.classes.length, 0.25)));
  }
}

class _Head implements CryHead {
  _Head(this.out);
  final List<double> out;
  @override
  List<double> run(Float32List f) => out;
  @override
  void close() {}
}

Map<String, dynamic> metaFor(String version, Uint8List bytes) => {
      'version': version,
      'kind': 'classifier',
      'classes': ['hungry', 'sleepy', 'gas', 'diaper'],
      'sha256': ModelManager.sha256Hex(bytes),
      'input': {'embedding': {'dim': 1024}, 'context': []},
      'blend': {'weight': 0},
      'selftest': {'input': List.filled(1024, 0.0), 'expected': [0.7, 0.1, 0.1, 0.1], 'tol': 1e-3},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late SharedPreferences prefs;
  late Directory tmp;
  late ModelManager mgr;
  late FakeServer server;
  late FakeCloud api;

  void publish(String version, Uint8List bytes, {String? sha, Map<String, dynamic>? meta}) {
    server.models['classifier/$version.tflite'] = bytes;
    server.eligible = {
      'version': version,
      'storage_path': 'classifier/$version.tflite',
      'sha256': sha ?? ModelManager.sha256Hex(bytes),
      'meta': meta ?? metaFor(version, bytes),
    };
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.memory();
    tmp = await Directory.systemTemp.createTemp('hh-model');
    mgr = ModelManager(db, prefs, FakeLoader(), dir: () async => tmp);
    server = FakeServer();
    api = FakeCloud(server, 'u1');
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('没装过：用内置模型（sha256 + 自检通过）', () async {
    final m = await mgr.load();
    expect(m!.source, 'bundled');
    expect(m.meta.version, 'cls-1');
  });

  test('云端新版本：下载 → 校验 → 写入并设为当前；同版本不重复下载', () async {
    publish('cls-2', Uint8List.fromList(utf8.encode('GOOD-model-2')));
    expect(await mgr.checkForUpdate(api, currentVersion: 'cls-1'), 'cls-2');
    final rows = await mgr.installed();
    expect(rows.single.active, isTrue);
    expect(File(rows.single.localPath).existsSync(), isTrue);
    final m = await mgr.load();
    expect((m!.source, m.meta.version), ('installed', 'cls-2'));
    expect(await mgr.checkForUpdate(api, currentVersion: 'cls-2'), isNull);
  });

  test('sha256 不一致 / 自检失败 / 加载失败：不安装、拉黑、不再重复下载，继续用原来的', () async {
    final good = Uint8List.fromList(utf8.encode('GOOD-x'));
    publish('cls-3', good, sha: 'deadbeef');
    expect(await mgr.checkForUpdate(api), isNull);
    expect(mgr.badVersions, contains('cls-3'));
    publish('cls-4', Uint8List.fromList(utf8.encode('BAD-selftest')));
    expect(await mgr.checkForUpdate(api), isNull);
    publish('cls-5', Uint8List.fromList(utf8.encode('CRASH')));
    expect(await mgr.checkForUpdate(api), isNull);
    expect(mgr.badVersions, containsAll(['cls-3', 'cls-4', 'cls-5']));
    expect(await mgr.installed(), isEmpty);
    expect(tmp.listSync(recursive: true).whereType<File>(), isEmpty);
    expect((await mgr.load())!.source, 'bundled');
  });

  test('离线：不拉黑，下次再试', () async {
    publish('cls-6', Uint8List.fromList(utf8.encode('GOOD-6')));
    api.offline = true;
    expect(await mgr.checkForUpdate(api), isNull);
    expect(mgr.badVersions, isEmpty);
    api.offline = false;
    expect(await mgr.checkForUpdate(api), 'cls-6');
  });

  test('推理出错 / 文件损坏：回滚到上一个版本，再回到内置', () async {
    publish('cls-2', Uint8List.fromList(utf8.encode('GOOD-2')));
    await mgr.checkForUpdate(api);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    publish('cls-3', Uint8List.fromList(utf8.encode('GOOD-3')));
    await mgr.checkForUpdate(api);
    expect((await mgr.load())!.meta.version, 'cls-3');

    await mgr.reportFailure('cls-3');
    final m = await mgr.load();
    expect(m!.meta.version, 'cls-2');
    expect((await mgr.installed()).single.active, isTrue);

    // 磁盘上的文件被改坏：sha256 校验失败，回到内置
    await File((await mgr.installed()).single.localPath).writeAsString('corrupted');
    expect((await mgr.load())!.source, 'bundled');
    expect(mgr.badVersions, containsAll(['cls-2', 'cls-3']));
  });

  test('只保留当前 + 上一个版本', () async {
    for (final v in ['a', 'b', 'c']) {
      publish('cls-$v', Uint8List.fromList(utf8.encode('GOOD-$v')));
      await mgr.checkForUpdate(api);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect((await mgr.installed()).map((r) => r.version), ['cls-c', 'cls-b']);
  });
}
