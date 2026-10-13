import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/baby_repository.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/data/repositories/cry_event_repository.dart';
import 'package:honghong/data/repositories/feedback_repository.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/domain/models/cry_cause.dart';
import 'package:honghong/domain/models/cry_context.dart';
import 'package:honghong/domain/predictor/cry_predictor.dart';
import 'package:honghong/domain/predictor/rule_based_predictor.dart';
import 'package:honghong/services/export/export_service.dart';

void main() {
  test('导出 zip：data.json 含记录/哭声/反馈，录音放在 recordings/', () async {
    final db = AppDatabase.memory();
    final tmp = await Directory.systemTemp.createTemp('hhx');
    final wav = File('${tmp.path}/123.wav')..writeAsBytesSync(List.filled(100, 7));
    final baby = await BabyRepository(db).ensureDefault();
    final logs = CareLogRepository(db);
    final s = await logs.startSession(baby.id, CareLogType.feed, at: DateTime(2026, 10, 13, 8));
    await logs.saveSession(s.id, duration: const Duration(minutes: 12));
    await logs.logDiaper(baby.id);
    final ctx = CryContext(at: DateTime(2026, 10, 13, 9), babyAgeMonths: 1);
    final pred = await RuleBasedPredictor().predict(const AudioFeatures(), ctx);
    final eid = await CryEventRepository(db).save(
        babyId: baby.id, startedAt: ctx.at, durationMs: 8000, context: ctx, prediction: pred, audioPath: wav.path);
    await FeedbackRepository(db).save(eid, CryCause.gas);

    final r = await ExportService(db).writeZip(Directory('${tmp.path}/out'), now: DateTime(2026, 10, 13, 21, 30));
    expect(r.path, endsWith('honghong-export-20261013-2130.zip'));
    expect(r.recordings, 1);
    final zip = ZipDecoder().decodeBytes(File(r.path).readAsBytesSync());
    expect(zip.files.map((f) => f.name), containsAll(['data.json', 'recordings/123.wav']));
    final json = jsonDecode(utf8.decode(zip.findFile('data.json')!.content as List<int>)) as Map<String, dynamic>;
    expect((json['care_logs'] as List).length, 2);
    final ev = (json['cry_events'] as List).single as Map<String, dynamic>;
    expect(ev['audio_file'], 'recordings/123.wav');
    expect((ev['context'] as Map)['baby_age_months'], 1);
    expect(((json['feedbacks'] as List).single as Map)['resolved_cause'], 'gas');
    await db.close();
    await tmp.delete(recursive: true);
  });
}
