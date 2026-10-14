import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../../domain/diary/parse_result.dart';
import '../../services/diary/diary_api.dart';
import 'diary_providers.dart';

sealed class FlowOutcome {}

/// 进入确认页（成功、部分成功、整理失败的原话 other 卡、未配置时手动保存）
class GoConfirm extends FlowOutcome {
  GoConfirm(this.result);
  final ParseResult result;
}

/// 断网：文字已存为草稿，提示重试（架构 §5.3）
class NetworkDraft extends FlowOutcome {
  NetworkDraft(this.text);
  final String text;
}

final diaryFlowProvider = Provider((ref) => DiaryFlow(ref));

/// 测试用固定时钟
final diaryClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class DiaryFlow {
  DiaryFlow(this.ref);
  final Ref ref;

  /// 一句话 → 确认页数据。语音和文字走同一流程。
  Future<FlowOutcome> process(String text, {required String inputType}) async {
    final now = ref.read(diaryClockProvider)();
    final baby = await ref.read(currentBabyProvider.future);
    final age = now.difference(baby.birthDate).inDays.clamp(0, 3 * 366);
    final api = ref.read(diaryApiProvider);
    ParseResult r;
    if (api == null) {
      r = ParseResult.fallback(
        text,
        inputType: inputType,
        now: now,
        offline: true,
      );
    } else {
      try {
        r = await api.parse(
          text: text,
          inputType: inputType,
          ageInDays: age,
          now: now,
        );
        await ref.read(prefsProvider).remove(kDiaryDraft);
      } on DiaryApiException catch (e) {
        if (e.kind == DiaryApiError.network) {
          await ref.read(prefsProvider).setString(kDiaryDraft, text);
          return NetworkDraft(text);
        }
        r = ParseResult.fallback(text, inputType: inputType, now: now);
      }
    }
    await ref.read(diaryServiceProvider).prepare(baby.id, r);
    return GoConfirm(r);
  }
}
