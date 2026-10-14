import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';

const diaryDisclaimer = '妈咪日记仅用于记录宝宝日常情况，不提供医疗诊断或建议。如宝宝出现发热、持续哭闹、精神差等异常情况，请及时咨询专业医生。';

Widget _disc(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(diaryDisclaimer, style: TextStyle(fontSize: 11, height: 1.6, color: context.hh.sub)),
    );

/// 屏 3：首次进入，沿用宝宝资料，只补问性别（可跳过，D5）。返回 'boy' / 'girl' / null(跳过)。
Future<String?> showGenderSheet(BuildContext context, {required String nickname, required int days}) =>
    showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (_) => _GenderSheet(nickname: nickname, days: days),
    );

class _GenderSheet extends StatefulWidget {
  const _GenderSheet({required this.nickname, required this.days});
  final String nickname;
  final int days;
  @override
  State<_GenderSheet> createState() => _GenderSheetState();
}

class _GenderSheetState extends State<_GenderSheet> {
  String? gender;
  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const SheetGrab(),
        Row(children: [
          IconTile(AppIcon.diary, size: 48, radius: 16, fontSize: 22, bg: c.peachL),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('欢迎使用妈咪日记', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: 2),
              Text('已沿用宝宝资料：${widget.nickname} · 出生第 ${widget.days} 天', style: TextStyle(fontSize: 13, color: c.sub)),
            ]),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text('还差一项：宝宝性别（可跳过）', style: TextStyle(fontSize: 13, color: c.sub)),
        ),
        HhSegmented<String>(
          key: const Key('gender-seg'),
          values: const ['boy', 'girl'],
          label: (v) => v == 'boy' ? '男宝宝' : '女宝宝',
          selected: gender,
          onChanged: (v) => setState(() => gender = v),
        ),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: HhButton(key: const Key('gender-skip'), label: '以后再说', primary: false, onPressed: () => Navigator.pop(context))),
          const SizedBox(width: 10),
          Expanded(child: HhButton(key: const Key('gender-start'), label: '开始记录', onPressed: () => Navigator.pop(context, gender))),
        ]),
        _disc(context),
      ]),
    );
  }
}

/// 屏 9：语音识别失败兜底。返回 true=改用文字输入，false=再说一次。
Future<bool?> showVoiceErrorSheet(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (ctx) {
        final c = ctx.hh;
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetGrab(),
            const HhIcon(AppIcon.signalError, size: 52),
            const SizedBox(height: 8),
            Text('没听清，再试一次？', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 6),
            Text('周围有点吵，或者说得太快了。宝宝睡着时，也可以直接打字。',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.5, color: c.sub)),
            const SizedBox(height: 18),
            HhButton(key: const Key('voice-err-text'), label: '改用文字输入', onPressed: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 10),
            HhButton(key: const Key('voice-err-retry'), label: '再说一次', primary: false, onPressed: () => Navigator.pop(ctx, false)),
          ]),
        );
      },
    );

/// 联网识别告知（首次需要走讯飞时弹一次）。返回 true=同意，false=不同意（退回文字输入），null=关掉没选。
Future<bool?> showCloudAsrConsentSheet(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isDismissible: false,
      isScrollControlled: true,
      builder: (ctx) {
        final c = ctx.hh;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetGrab(),
            const HhIcon(AppIcon.voice, size: 52),
            const SizedBox(height: 8),
            Text('换成联网识别？', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 6),
            Text('这台手机自带的语音识别暂时用不了。同意后，按住说话时的录音会加密发送给科大讯飞，只用来转成文字。',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.5, color: c.sub)),
            const SizedBox(height: 12),
            Container(
              key: const Key('cloud-asr-points'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final t in const ['录音识别完就丢弃，哄哄和讯飞都不保存', '不会用于训练任何模型', '只发送你按住说话的那几秒，每次最长 1 分钟'])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('· ', style: TextStyle(fontSize: 13, color: c.peach2, fontWeight: FontWeight.w700)),
                      Expanded(child: Text(t, style: TextStyle(fontSize: 13, height: 1.5, color: c.ink))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 18),
            HhButton(key: const Key('cloud-asr-agree'), label: '同意，用联网识别', onPressed: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 10),
            HhButton(key: const Key('cloud-asr-decline'), label: '不用了，打字记录', primary: false, onPressed: () => Navigator.pop(ctx, false)),
            const SizedBox(height: 10),
            Text('详见隐私政策中的“第三方处理方”。', style: TextStyle(fontSize: 12, color: c.sub)),
          ]),
        );
      },
    );
