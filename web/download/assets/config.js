/* 哄哄 分发页配置
 * 版本号、更新说明、下载链接、大小、日期都不写在这里：页面运行时去拉 honghong-releases 的公开 version.json，
 *   channels.stable → /download（正式版，来自 v* 标签）
 *   channels.dev    → /download/beta（测试版，来自在 master 上手动触发的 -dev 版）
 * 这个文件只放不随发版变化的内容。
 */
window.HH_CONFIG = {
  // 按顺序尝试，第一个成功的为准。
  // 1）同源镜像：服务器上的定时任务把公开 version.json 拉到 /download/data/version.json（国内访问稳定，不需要任何密钥）
  // 2）直接读 GitHub 公开仓库（raw.githubusercontent.com 支持跨域）
  sources: [
    "/download/data/version.json",
    "https://raw.githubusercontent.com/JiHe021499/honghong-releases/main/version.json"
  ],
  release: {
    channel: "stable",
    minOS: "Android 7.0+",
    testflightUrl: "",   // 还没有 TestFlight，留空时显示「即将上线」
    pageUrl: "https://honghong.hczhw.com/download"
  },
  beta: {
    channel: "dev",
    minOS: "Android 7.0+",
    testflightUrl: "",
    pageUrl: "https://honghong.hczhw.com/download/beta"
  }
};
