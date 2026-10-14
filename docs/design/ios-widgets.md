# iOS 小组件、锁屏、灵动岛和控制中心

和安卓的「桌面小部件 + 下拉快捷开关 + 锁屏常驻通知」对应，规则完全相同（喂奶/睡觉/拍嗝是 开始→进行中→结束，换尿布是一次性记录）。

| 安卓 | iOS | 最低系统 |
|---|---|---|
| 桌面小部件 | 主屏幕小组件 small / medium（交互按钮 AppIntent） | iOS 17 |
| 锁屏常驻通知 | 锁屏小组件 accessoryRectangular / Circular + 实时活动 | 17 / 16.2 |
| 通知里的计时 | 实时活动：锁屏卡片 + 灵动岛，带「结束」按钮（LiveActivityIntent） | 16.2（按钮 17） |
| 下拉快捷开关 | 控制中心控件 喂奶 / 睡觉 / 换尿布（ControlWidget） | 18 |

App 本身最低 iOS 15；小组件扩展最低 iOS 17。

## 数据怎么流动

- 共享容器：App Group `group.com.honghong.honghong`（UserDefaults）。
- App → 小组件：每次数据变化，Dart 侧写入和安卓相同的 `hh_*` 快照键（`widgetData()`），然后 `WidgetCenter.reloadTimelines`；同时通过 MethodChannel `honghong/live_activity` 的 `sync` 让实时活动和进行中的计时一致（每个进行中的类型一个活动，结束即移除）。
- 小组件 → App：扩展里**不跑 Flutter、不碰数据库**。按钮只把动作追加到队列 `hh_pending`（`[{id, a: "start:feed", t: 毫秒}]`），并乐观地更新快照，让小组件立刻显示新状态。App 启动或回到前台时按时间顺序执行队列，用的就是安卓共用的 `runQuickAction(db, a, now: t)`：写库、标记待同步、刷新所有入口。执行完只删掉处理过的条目（期间新追加的保留）。
- 时间以按下按钮的时刻为准，所以就算隔了几小时才打开 App，记录时间也是对的。

为什么不在扩展里直接写数据库：drift 数据库在 App 沙盒里，挪进 App Group 会牵动迁移和备份；扩展内存上限很小，起 Flutter 引擎不现实。队列方案代价是：App 没打开前，云端和家人看不到这条记录。

## 视觉

- 小组件用和 App 相同的手绘图标（`care_feed / sleep / burp / diaper`，从 assets/icons 拷贝的 PNG），米白纸底、深棕描边文字。
- 计时用 `Text(timerInterval:)`，系统自己走秒，不需要频繁刷新时间线（时间线 30 分钟刷新一次兜底）。
- 控制中心控件只能用 SF Symbols（系统限制），选了最接近的：`waterbottle`、`moon.zzz`、`arrow.triangle.2.circlepath`。

## 不需要的东西

- 后台模式：不开。自动监听只在前台工作，实时活动由 App 在前台更新、由 Intent 结束，不需要 audio / fetch 后台模式（也避免审核问题）。
- 应用内 APK 更新：iOS 上隐藏（`inAppUpdateSupported` 只对安卓为真）。
- Supabase 深链：目前登录是匿名的，没有邮件链接，不需要；只注册了 `honghong://` 让小组件点击打开 App。

## 需要 Apple 开发者账号之后才能验证

App Group、实时活动、交互小组件在**未签名**的包里都编得过，但真机运行需要：开发者账号、为 App 和扩展注册 Bundle ID 并开启 App Groups、描述文件签名；之后才能 TestFlight。
