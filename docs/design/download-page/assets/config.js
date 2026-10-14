/* ==================== 哄哄 分发页配置（占位数据，上线前替换） ====================
 * 开发同学只需改这里（或由 CI 发版时生成这个文件）。所有字段都是 PLACEHOLDER。
 * release → /download        beta → /download/beta
 */
window.HH_CONFIG = {
  release: {
    version: "1.0.0",            // PLACEHOLDER 正式版版本号
    build: "100",                 // PLACEHOLDER 构建号
    date: "2026-10-14",           // PLACEHOLDER 发布日期
    size: "28.6 MB",              // PLACEHOLDER APK 大小
    minOS: "Android 8.0+ / iOS 15+",
    apkUrl: "https://honghong.hczhw.com/download/files/honghong-1.0.0.apk",   // PLACEHOLDER
    testflightUrl: "https://testflight.apple.com/join/XXXXXXXX",             // PLACEHOLDER
    pageUrl: "https://honghong.hczhw.com/download",  // 二维码内容（桌面端扫码用）
    notes: [                       // PLACEHOLDER 更新说明
      "哭声识别：录 10 秒，结合喂奶 / 睡觉 / 尿布记录猜出最可能的原因",
      "护理记录：喂奶、睡觉、拍嗝支持「开始 → 计时 → 结束」",
      "妈咪日记：按住说一句话，自动拆成多条记录",
      "夜间模式更柔和，半夜看也不刺眼"
    ]
  },
  beta: {
    version: "1.1.0-dev.23",       // PLACEHOLDER 最新 dev 版本号
    build: "123",
    date: "2026-10-14 21:30",
    size: "29.1 MB",
    minOS: "Android 8.0+ / iOS 15+",
    apkUrl: "https://honghong.hczhw.com/download/files/honghong-1.1.0-dev.23.apk", // PLACEHOLDER
    testflightUrl: "https://testflight.apple.com/join/YYYYYYYY",                   // PLACEHOLDER
    pageUrl: "https://honghong.hczhw.com/download/beta",
    notes: [
      "【测试】家庭共享：邀请家人一起记录",
      "【测试】iOS 锁屏小组件",
      "修复：夜间模式下时间线文字偏淡"
    ]
  }
};
