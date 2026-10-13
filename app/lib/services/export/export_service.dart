import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../data/db/app_database.dart';

/// 导出录音和标注：data.json（宝宝、护理记录、哭声事件、反馈）+ recordings/*.wav，打成一个 zip。
/// 用于第三阶段拿自家宝宝的数据训练模型。
class ExportService {
  ExportService(this._db);
  final AppDatabase _db;

  static const formatVersion = 1;

  Future<Map<String, Object?>> buildJson({DateTime? now}) async {
    String? iso(DateTime? d) => d?.toIso8601String();
    final babies = await _db.select(_db.babies).get();
    final logs = await _db.select(_db.careLogs).get();
    final cries = await _db.select(_db.cryEvents).get();
    final fbs = await _db.select(_db.feedbacks).get();
    Object? js(String? s) {
      if (s == null) return null;
      try {
        return jsonDecode(s);
      } catch (_) {
        return s;
      }
    }

    return {
      'format': 'honghong-export',
      'format_version': formatVersion,
      'exported_at': iso(now ?? DateTime.now()),
      'babies': [
        for (final b in babies) {'id': b.id, 'nickname': b.nickname, 'birth_date': iso(b.birthDate)},
      ],
      'care_logs': [
        for (final l in logs)
          {
            'id': l.id,
            'baby_id': l.babyId,
            'type': l.type,
            'started_at': iso(l.startedAt),
            'ended_at': iso(l.endedAt),
            'detail': js(l.detail),
          },
      ],
      'cry_events': [
        for (final e in cries)
          {
            'id': e.id,
            'baby_id': e.babyId,
            'started_at': iso(e.startedAt),
            'duration_ms': e.durationMs,
            'audio_file': e.audioPath == null ? null : 'recordings/${p.basename(e.audioPath!)}',
            'cry_confidence': e.cryConfidence,
            'auto_triggered': e.autoTriggered,
            'context': js(e.contextJson),
            'prediction': js(e.predictionJson),
            'predictor_version': e.predictorVersion,
          },
      ],
      'feedbacks': [
        for (final f in fbs)
          {
            'id': f.id,
            'cry_event_id': f.cryEventId,
            'resolved_cause': f.resolvedCause,
            'minutes_to_soothe': f.minutesToSoothe,
            'note': f.note,
            'created_at': iso(f.createdAt),
          },
      ],
    };
  }

  /// 生成 zip，返回文件路径和录音数量
  Future<({String path, int recordings, int bytes})> writeZip(Directory outDir, {DateTime? now}) async {
    now ??= DateTime.now();
    final json = await buildJson(now: now);
    final archive = Archive()
      ..addFile(ArchiveFile.string('data.json', const JsonEncoder.withIndent('  ').convert(json)));
    var n = 0;
    for (final e in await _db.select(_db.cryEvents).get()) {
      final path = e.audioPath;
      if (path == null) continue;
      final f = File(path);
      if (!await f.exists()) continue;
      archive.addFile(ArchiveFile.bytes('recordings/${p.basename(path)}', await f.readAsBytes()));
      n++;
    }
    final bytes = ZipEncoder().encode(archive);
    await outDir.create(recursive: true);
    final out = File(p.join(outDir.path, 'honghong-export-${DateFormat('yyyyMMdd-HHmm').format(now)}.zip'));
    await out.writeAsBytes(bytes);
    return (path: out.path, recordings: n, bytes: bytes.length);
  }
}
