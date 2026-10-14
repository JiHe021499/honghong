# 哄哄 应用分发页

- `/download` → `index.html`（正式版，对应 `v*` 标签发出的 stable 版）
- `/download/beta` → `beta/index.html`（测试版，对应在 master 上手动触发的 `-dev` 版，noindex）
- 设计稿原件在 `docs/design/download-page/`，这里是接上真实数据的实现。

## 数据从哪来
页面不写死版本。运行时按 `assets/config.js` 里 `sources` 的顺序拉 `version.json`：
1. 同源 `/download/data/version.json`：服务器定时任务 `deploy/sync-version.sh` 从 honghong-releases 拉的副本；
2. `https://raw.githubusercontent.com/JiHe021499/honghong-releases/main/version.json`（公开、允许跨域）。

`channels.stable` 给正式版页，`channels.dev` 给测试版页。用到的字段是 versionName、versionCode、publishedAt（按北京时间显示）、size、apkUrl（GitHub Release 资产地址）、changelog（按行拆成更新说明，最多 8 条）。
这个 version.json 由 honghong-releases 的 publish.yml 在每次发版时更新，所以**发版后页面自动更新，不需要改 config，也不需要动 releases 仓库**。

- 还没有正式版时，正式版页显示「正式版即将发布」，下载按钮置灰。
- 两个地址都拉取失败时，页面显示「暂时获取不到版本信息，请稍后刷新」。
- `testflightUrl` 为空时，iOS 按钮置灰，显示「iOS 版即将上线」。有链接后填进 `config.js` 即可。

## 本地预览
```sh
mkdir -p /tmp/srv && ln -sfn "$PWD" /tmp/srv/download
(cd /tmp/srv && python3 -m http.server 8765)
# 打开 http://127.0.0.1:8765/download/?ua=android  （ua 可选 ios|android|wechat|desktop）
```
本地没有 `data/version.json` 时会自动退回去读 GitHub。`data/` 已加入 .gitignore。

## 部署
见 `docs/release.md`「分发页」一节。服务器只放 `index.html`、`beta/`、`assets/`，**不要上传 `deploy/` 和本 README**。
