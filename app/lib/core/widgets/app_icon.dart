import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 手绘图标（assets/icons，说明见 assets/icons/icons.md）。
/// 同一个 emoji 按语义拆成不同图标：例如喂奶 [careFeed] 和哭因"饿了" [causeHungry]。
enum AppIcon {
  careFeed('care_feed'),
  careSleep('care_sleep'),
  careDiaper('care_diaper'),
  careBurp('care_burp'),
  careAwake('care_awake'),
  causeHungry('cause_hungry'),
  causeSleepy('cause_sleepy'),
  causeGas('cause_gas'),
  causeUncomfortable('cause_uncomfortable'),
  causeHoldMe('cause_hold_me'),
  causeUnsure('cause_unsure'),
  tabHome('tab_home'),
  tabInsights('tab_insights'),
  tabFamily('tab_family'),
  tabMe('tab_me'),
  nightMode('night_mode'),
  dayMode('day_mode'),
  autoListen('auto_listen'),
  export('export'),
  checkUpdate('check_update'),
  settings('settings'),
  avatarBaby('avatar_baby'),
  avatarMom('avatar_mom'),
  avatarDad('avatar_dad'),
  avatarGrandma('avatar_grandma'),
  tip('tip'),
  soothed('soothed'),
  waveHello('wave_hello'),
  voice('voice'),
  insightDusk('insight_dusk'),
  insightTarget('insight_target'),
  checkDone('check_done'),
  phone('phone'),
  signalError('signal_error'),
  checkSmall('check_small'),
  stop('stop'),
  add('add'),
  remove('remove'),
  close('close'),
  chevronLeft('chevron_left'),
  chevronRight('chevron_right'),
  chevronUp('chevron_up'),
  chevronDown('chevron_down'),
  arrowForward('arrow_forward'),
  // 妈咪日记（设计稿内联 SVG 导出，见 docs/design/mommy-diary/export_icons.py）
  diary('diary'),
  keyboard('keyboard'),
  edit('edit');

  const AppIcon(this.file);
  final String file;
  String get asset => 'assets/icons/$file.png';
}

/// 显示一个手绘图标。夜间模式下略微调暗，避免刺眼。
class HhIcon extends StatelessWidget {
  const HhIcon(this.icon, {super.key, this.size = 24, this.dim});
  final AppIcon icon;
  final double size;
  final bool? dim;

  @override
  Widget build(BuildContext context) {
    final night = dim ?? context.hh.night;
    final img = Image.asset(icon.asset, width: size, height: size, filterQuality: FilterQuality.medium, semanticLabel: icon.file);
    return night ? Opacity(opacity: .78, child: img) : img;
  }
}

/// 行内图标（放进 Text.rich），和文字基线居中对齐
WidgetSpan iconSpan(AppIcon icon, {double size = 18, double gap = 4}) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(padding: EdgeInsets.only(right: gap), child: HhIcon(icon, size: size)),
    );
