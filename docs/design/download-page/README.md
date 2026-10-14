# 哄哄 · 应用分发页设计稿

- 正式版：`index.html` → 部署到 `honghong.hczhw.com/download`（公开）
- 测试版：`beta/index.html` → 部署到 `/download/beta`（不公开链接，已加 `noindex,nofollow`）
- 预览：直接双击打开即可（纯静态、离线可用）。用 `?ua=ios|android|wechat|desktop` 强制切换平台，例如 `index.html?ua=wechat`。

## 设计说明
- 完全沿用哄哄现有视觉：奶油底 #FFF8F0、蜜桃主色 #FF9874、浅蓝辅色、深棕手绘描边按钮，logo / lockup 来自 `docs/brand/`，小图标来自 `app/assets/icons/svg/`（已复制到 `assets/`）。
- **手机**：按 UA 自动识别。iPhone 主按钮「通过 TestFlight 安装」+ 提示需先装 TestFlight；安卓主按钮「下载安卓版」直接下载 APK + 未知来源提示。另一平台以次级链接显示。下方是更新说明卡和「分享给家人」小二维码。
- **桌面**：二维码是主视觉（右侧大卡片，300px），左侧是卖点 + 更新说明；也保留 APK / TestFlight 直链。
- **微信内**（UA 含 MicroMessenger）：全屏深色遮罩 + 指向右上角 ··· 的手绘箭头，iOS 文案为「在 Safari 中打开」，安卓为「在浏览器中打开」；下载按钮置灰并移除链接，禁止直接下载。
- **测试版**：黄色「内测版 · 请勿外传」标签 + 内测提示条，显示最新 dev 版本号和构建时间；按钮文案为「加入 TestFlight 内测 / 下载内测版 APK」。
- 无 UA 但是移动设备时按安卓处理；iPadOS（伪装成 Mac 的触屏设备）按 iOS 处理。

## 如何配置数据
所有数据都在 **`assets/config.js`** 的 `window.HH_CONFIG` 里（`release` / `beta` 两组），标了 `PLACEHOLDER` 的都要替换：
`version`、`build`、`date`、`size`、`minOS`、`apkUrl`、`testflightUrl`、`pageUrl`（二维码内容）、`notes`（更新说明数组）。
建议 CI 发版时自动生成该文件（选 JS 而非 JSON 是为了 `file://` 直接打开也能读到；如改用 latest.json，需要 fetch 并且必须走 http）。

二维码用 `assets/qrcode.js`（qrcode-generator 2.0.4，MIT）在浏览器本地生成 SVG，无需联网。

## 部署注意
- 把整个目录作为静态站点上传：`/download/` 下放 `index.html`、`assets/`，`/download/beta/` 下放 `beta/index.html`（它通过 `../assets/` 引用资源）。
- APK 需返回 `Content-Type: application/vnd.android.package-archive`，并建议加 `Content-Disposition: attachment`。
- beta 页除 meta noindex 外，建议服务器同时加 `X-Robots-Tag: noindex`，并在 robots.txt 里不要列出该路径（列出反而暴露）。
- `config.js` 建议设置短缓存（如 `Cache-Control: max-age=60`），保证版本号及时更新。
- 重新截图：`python3 shot.py && python3 ov.py`；HTML 由 `gen.py` 生成。
