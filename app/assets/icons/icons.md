# 哄哄手绘图标

48dp 基准，透明底。Flutter 分辨率目录：`icons/<name>.png`（48px）、`icons/2.0x/<name>.png`（96px）、`icons/3.0x/<name>.png`（144px）；SVG 源文件在 `icons/svg/<name>.svg`。
描边深棕 #6E3A33，外圈奶油色描边，浅色和夜间底上都能看清。生成脚本：/workspace/hhbrand/icons.py、overview.py。路径都相对 app/lib。

| 文件名 | 原 emoji/图标 | 用途 | 来源 |
|---|---|---|---|
| `care_feed` | 🍼 | 护理·喂奶 | domain/models/care_detail.dart:120; features/home/home_page.dart:235 |
| `care_sleep` | 😴 | 护理·睡觉 | domain/models/care_detail.dart:121 |
| `care_diaper` | 🧷 | 护理·换尿布 | domain/models/care_detail.dart:122; features/care/care_sheets.dart:264; features/home/home_page.dart:623 |
| `care_burp` | 🫧 | 护理·拍嗝 | domain/models/care_detail.dart:123 |
| `care_awake` | 😴 已醒 | 醒了/已醒 | features/home/home_page.dart:243（'😴 已醒'，原代码复用睡觉 emoji） |
| `cause_hungry` | 🍼 | 哭因·饿了 | domain/models/cause_ui.dart:6 |
| `cause_sleepy` | 😴 | 哭因·困了 | domain/models/cause_ui.dart:7 |
| `cause_gas` | 🫧 | 哭因·胀气 | domain/models/cause_ui.dart:8 |
| `cause_uncomfortable` | 🧷 | 哭因·不舒服/尿布 | domain/models/cause_ui.dart:9 |
| `cause_hold_me` | 🤗 | 哭因·想要抱 | domain/models/cause_ui.dart:10 |
| `cause_unsure` | 🤷 | 反馈·不确定 | features/feedback/feedback_page.dart:34 |
| `tab_home` | 🏠 | 底部标签·首页 | core/router/app_router.dart:88 |
| `tab_insights` | 📊 | 底部标签·规律 | core/router/app_router.dart:88 |
| `tab_family` | 👨‍👩‍👧 | 底部标签·家庭 | core/router/app_router.dart:88 |
| `tab_me` | ⚙️ | 底部标签·我的 | core/router/app_router.dart:88 |
| `night_mode` | 🌙 | 切到夜间模式按钮/设置·夜间模式 | features/home/home_page.dart:171; features/settings/settings_page.dart:127（设置项无 emoji） |
| `day_mode` | ☀️ | 夜间时切回日间按钮 | features/home/home_page.dart:171 |
| `auto_listen` | (无) | 设置·自动监听哭声 | features/settings/settings_page.dart:128（无 emoji，新增） |
| `export` | (无) | 设置·导出录音和标注 | features/settings/settings_page.dart:134（无 emoji，新增） |
| `check_update` | (无) | 设置·检查更新 | features/settings/settings_page.dart:142（无 emoji，新增） |
| `settings` | ⚙️ | 设置(同 tab_me) | core/router/app_router.dart:88（⚙️，与 tab_me 同图） |
| `avatar_baby` | 👶 | 首页头像 | features/home/home_page.dart:149 |
| `avatar_mom` | 👩 | 规律页家庭头像 | features/insights/insights_page.dart:217 |
| `avatar_dad` | 👨 | 规律页家庭头像 | features/insights/insights_page.dart:218 |
| `avatar_grandma` | 👵 | 规律页家庭头像 | features/insights/insights_page.dart:219 |
| `tip` | 💡 | 结果页·为什么这么猜 | features/cry/result_page.dart:91 |
| `soothed` | 🥰 | 反馈完成 | features/feedback/feedback_page.dart:63 |
| `wave_hello` | 👋 | 首页空状态 | features/home/home_page.dart:247 |
| `voice` | 🎙️ | 首页·语音操作 | features/home/home_page.dart:649 |
| `insight_dusk` | 🌇 | 规律·闹的时段 | features/insights/insights_page.dart:124 |
| `insight_target` | 🎯 | 规律·最常见哭因 | features/insights/insights_page.dart:174,177 |
| `check_done` | ✅ | 猜中率/已是最新版本 | features/insights/insights_page.dart:187; features/update/update_page.dart:201 |
| `phone` | 📱 | 更新页·iOS 不支持 | features/update/update_page.dart:191 |
| `signal_error` | 📡 | 更新页·检查失败 | features/update/update_page.dart:196 |
| `check_small` | ✓ | 已停止计时 | features/care/care_sheets.dart:132 |
| `stop` | Icons.stop_rounded | 首页·结束计时 | features/home/home_page.dart:412 |
| `add` | Icons.add | 时长 + | features/care/care_sheets.dart:158 |
| `remove` | Icons.remove | 时长 − | features/care/care_sheets.dart:144 |
| `close` | Icons.close | 录音页关闭 | features/cry/recording_page.dart:139 |
| `chevron_left` | Icons.chevron_left | 返回 | features/cry/recording_page.dart:225 |
| `chevron_right` | Icons.chevron_right | 设置列表箭头 | features/settings/settings_page.dart:72 |
| `chevron_up` | Icons.keyboard_arrow_up | 结果页收起 | features/cry/result_page.dart:164 |
| `chevron_down` | Icons.keyboard_arrow_down | 结果页展开 | features/cry/result_page.dart:164 |
| `arrow_forward` | Icons.arrow_forward_rounded | 更新页版本箭头 | features/update/update_page.dart:211 |

备注：同一个 emoji 在代码里有多种含义（🍼 喂奶/饿了，😴 睡觉/困了/已醒，🫧 拍嗝/胀气，🧷 换尿布/不舒服），所以拆成了不同的图标，接入时请按语义选用。另外，`EmojiTile` 和 `.emoji` getter（care_detail.dart、cause_ui.dart）是动态渲染的入口。
