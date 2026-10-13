import '../../core/widgets/app_icon.dart';
import 'cry_cause.dart';

/// 结果页、反馈页里每个原因的展示文案
extension CryCauseUi on CryCause {
  AppIcon get icon => switch (this) {
        CryCause.hungry => AppIcon.causeHungry,
        CryCause.sleepy => AppIcon.causeSleepy,
        CryCause.gas => AppIcon.causeGas,
        CryCause.diaper => AppIcon.causeUncomfortable,
        CryCause.holdMe => AppIcon.causeHoldMe,
      };

  /// "饿了"、"困了"
  String get title => switch (this) {
        CryCause.hungry => '饿了',
        CryCause.sleepy => '困了',
        CryCause.gas => '胀气',
        CryCause.diaper => '不舒服',
        CryCause.holdMe => '想要抱',
      };

  /// 对应的安抚动作（反馈页选项、建议卡片）
  String get action => switch (this) {
        CryCause.hungry => '喂奶',
        CryCause.sleepy => '哄睡',
        CryCause.gas => '拍嗝',
        CryCause.diaper => '换尿布',
        CryCause.holdMe => '抱一抱',
      };

  String get howToTell => switch (this) {
        CryCause.hungry => '转头找奶、吮手指、咂嘴，哭声短促有节奏。',
        CryCause.sleepy => '揉眼睛、打哈欠、眼神发直，哭声拖长、越哭越烦躁。',
        CryCause.gas => '蹬腿、身体扭动、脸憋红，哭声尖、断断续续。',
        CryCause.diaper => '扭动不安，尿布鼓胀或有便便；也可能是太热、衣服勒。',
        CryCause.holdMe => '一抱起来就不哭，放下又哭，哭声不急。',
      };

  String get howToSoothe => switch (this) {
        CryCause.hungry => '先喂奶；吃奶途中可停下拍嗝一次。',
        CryCause.sleepy => '调暗灯光、包裹、轻拍或白噪音，帮他入睡。',
        CryCause.gas => '竖抱拍嗝，或顺时针揉肚子、做蹬自行车动作。',
        CryCause.diaper => '检查并更换尿布，摸摸后颈看冷热，松一松衣服。',
        CryCause.holdMe => '抱起来贴身安抚，轻声说话或轻轻摇晃。',
      };
}
