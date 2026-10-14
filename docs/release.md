# 发布与版本规则

> 本文根据实际代码整理（2026-10-14）：`.github/workflows/android.yml`、`.github/workflows/ios.yml`、公开仓库 `JiHe021499/honghong-releases` 的 `.github/workflows/publish.yml`、`app/lib/services/update/update_service.dart`、`app/android/app/build.gradle.kts`、`backend/supabase/migrations/0001/0003`、`ml/src/publish_model.py`。改了这些文件请同步更新本文。

## 0. 什么时候发版（2026-10-14 起）

**提交到 master 不再发版。** push 或 PR 到 master 只跑测试和构建检查；只有打 `v*` 标签或在 master 上手动触发 Android 工作流，才会签名并发布到 honghong-releases。

| 事件 | 测试 | 构建 | 签名 | 发布到 honghong-releases |
|---|---|---|---|---|
| push 到 master（改了 `app/**` 或工作流本身） | ✅ | ✅ 产物是 debug 签名的 APK（只放在 Actions 构建产物里） | ❌ | ❌ |
| PR 到 master（同样的路径过滤） | ✅ | ✅ 同上 | ❌ | ❌ |
| 推送 `v*` 标签 | ✅ | ✅ | ✅ | ✅ stable |
| 手动 `workflow_dispatch`（只允许在 master 上，其他分支会直接报错） | ✅ | ✅ | ✅ | ✅ dev |

- 不发布的运行不读取任何 secret，所以构建产物里没有编入云端地址，App 是离线的。这个包不能覆盖安装正式签名的版本，只用来检查能不能编过。
- 合并 PR 就是一次 push 到 master，**不会发版**。
- 发布运行不会被后来的推送取消（`cancel-in-progress` 只对普通推送和 PR 生效）。
- iOS 只做未签名的构建检查，没有 TestFlight 或 App Store 步骤（见第 7 节）。
- AI 网关和 Supabase **没有任何自动部署**，仓库里没有对应的工作流，都是手动部署（见 `backend/README.md`）。

## 1. 版本号

| 场景 | versionName | versionCode | 渠道 |
|---|---|---|---|
| 推送 `v*` 标签 | 标签去掉 `v`，例如 `v0.2.0` → `0.2.0` | `github.run_number`（Android 工作流的运行序号） | `stable`（正式版） |
| 在 master 上手动触发 | `<pubspec 主.次>.<run_number>-dev`，例如 `0.1.42-dev` | 同上 | `dev`（预发布） |
| push 或 PR（不发布） | `<主.次>.<run_number>-ci`，只用于构建产物 | 同上 | — |

- 主.次取自 `app/pubspec.yaml` 的 `version:`（目前是 `0.1.0+1`，**只用前两段**，`+1` 和第三段不起作用）。要升到 0.2.x，就把 pubspec 改成 `0.2.0+1`。
- 打标签时，标签的主.次必须和 pubspec 一致（例如 pubspec 是 `0.2.0+1`，就只能打 `v0.2.x`），否则 CI **直接报错、终止发布**。
- versionCode 只增不减：同一工作流的 run_number 单调递增。不发布的运行（push 和 PR 的构建检查）也会消耗序号，所以发布出去的 versionCode **会跳号，这一点已确认可以接受**（2026-10-14 产品决定），新包一定能覆盖安装旧包。
- 带 `-dev` 后缀不影响更新判断：App 只用 versionCode（整数）比较新旧，versionName 只用于显示和安装包文件名；releases 仓库把 versionName 原样用在 tag（`v0.1.42-dev`）、Release 标题和下载地址里，这些都允许 `-`。dev 版和正式版因此不会再撞名。
- **iOS 版本号暂不统一**（产品决定）：iOS 仍然用它自己的 `0.1.<run_number>`，和 Android 对不上，也不响应标签。等上 TestFlight 时再统一。
- 构建命令显式传 `--build-name/--build-number`，App 内 `PackageInfo.buildNumber` 就是 versionCode，更新检查用它比较。

## 2. 什么会触发构建

**Android APK**（`android.yml`）：
- `push` 或 `pull_request` 到 `master`，且改动了 `app/**` 或 `.github/workflows/android.yml`：只做测试和构建。
- `push` 标签 `v*`（GitHub 对标签推送不看 paths 过滤）：发布 stable。
- 手动 `workflow_dispatch`：在 master 上发布 dev。
- 只改 `docs/`、`ml/`、`backend/`、README，不会触发构建。
- 普通推送或 PR 时，同一 ref 的新运行会取消正在跑的旧运行。

**iOS（未签名）**（`ios.yml`）：push 或 PR 到 `master` 且改了 `app/**` 或 `ios.yml`，或者手动触发。只做构建检查，见第 7 节。

## 3. Android 构建流程

以下第 2、4、5 步只在发布时执行（标签或手动）；push 和 PR 时只做第 1 步，再加一次不读 secret 的 debug 签名构建。

1. `flutter pub get` → `build_runner` → `flutter analyze` → `flutter test`（任何一步失败都不发布）。
2. 从 secrets 写出 keystore 和 `android/key.properties`，构建：
   `flutter build apk --release --target-platform android-arm64 --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`
   构建后立刻删除 keystore 和 key.properties。
3. **只发 arm64**：`--target-platform android-arm64`，并在 `build.gradle.kts` 里排除 `x86/x86_64/armeabi-v7a` 的 .so（还排除了 TFLite GPU 库、压缩 .so）。32 位手机装不了。
4. 生成 `meta.json`（见第 5 节），APK 也作为 Actions artifact 上传。
5. 用部署密钥把 `meta.json` + `honghong-<版本>.apk` 推到公开仓库 `honghong-releases` 的 `upload/v<版本>` 分支（基于其 main 创建）。
6. 公开仓库的 `publish.yml`（由 `upload/**` 推送触发，串行执行）：
   - 用自己的 `GITHUB_TOKEN` 创建 Release `v<版本>`（dev 标为 Pre-release；**同名 Release 已存在会先删掉再建**），上传 APK（失败重试 5 次）；
   - 更新 main 分支的 `version.json`；
   - 把 `version.json` 也上传到滚动 Release `latest`；
   - 删除上传分支。

为什么分两个仓库：源码仓库私有，安装包和 version.json 放公开仓库，App 不需要任何令牌就能下载。

### 签名与密钥（只写名字，不写内容）

| 名称 | 位置 | 用途 |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | honghong 仓库 Actions secret | 发布 keystore（base64），别名 `honghong` |
| `ANDROID_KEYSTORE_PASSWORD` | 同上 | store/key 密码（相同） |
| `RELEASES_DEPLOY_KEY` | 同上 | 对 `honghong-releases` 有写权限的 SSH 部署密钥（私钥）；公钥配在 honghong-releases 的 Deploy keys |
| `SUPABASE_URL`、`SUPABASE_ANON_KEY` | 同上 | 编进 App 的云端地址和 **anon key**（绝不放 service_role）；没配时 App 离线运行 |

- **备份**：keystore 和其属性文件备份在 box 的密钥目录 `/cursor/stores/store-48bb94bb-…/secrets/`（`honghong-release.jks`、`honghong-release.properties`），Supabase 配置在同目录 `supabase-nc_am.env`。**都不进仓库**。
- **keystore 丢了就再也不能发能覆盖安装的更新**（Android 要求签名一致），务必再离线备份一份（例如加密 U 盘/密码管理器）。
- 本地 `flutter build` 没有 `key.properties` 时自动退回 debug 签名，这种包不能覆盖装在已装正式签名版的手机上。

### 旧签名说明（中兴等真机）

固定发布签名是在提交 `862ebdf`（2026-10-13）引入的，在此之前 release 包用的是 debug 签名。手机上如果装的是那之前的包（例如最早在中兴手机上测试的版本），应用内更新会提示「安装包与已安装应用冲突」——**需要先卸载一次旧版再装新版**（本地数据会丢失，必要时先导出）。之后的版本签名不变，可以一直覆盖更新。

## 4. 强制更新标记

- 提交信息里含 `[强制更新]` 或 `[force]`（不区分大小写）。
- 更新说明（`changelog`）的来源按渠道不同：
  - **dev**：CI 取「上次已发布版本的 commit（version.json 里的 `commit`）..HEAD」之间、`app/` 目录相关的提交信息（最多 30 条）；`test:`/`ci:`/`chore:` 开头的条目**整条去掉**，其余**去掉 `feat:`/`fix(scope):`/`docs:` 等前缀和 scope**。强制更新标记按过滤前的完整提交信息判断。
  - **stable**：用**标签说明**（`git tag -a vX.Y.Z -F notes.md` 写进去的内容），由人工撰写。标签不是带说明的标签、或说明为空时，「发布前检查」直接报错，不会签名和发布。
- 更新说明里**只要任一行带标记**，本次发布就 `force: true`，并把 `minSupportedVersionCode` 设为本次 versionCode。正式版要强制更新，就把 `[强制更新]` 写进标签说明。
- App 端：`forced = 有更新 && (force || 当前 versionCode < minSupportedVersionCode)`。强制更新不能「稍后」，也不受「跳过此版本」影响。
- 注意：下一次不带标记的发布会把 `minSupportedVersionCode` 写回 0，也就是说强制只对「直接跳到那一版」有效，见第 10 节。

## 5. version.json 与应用内更新

地址：`https://raw.githubusercontent.com/JiHe021499/honghong-releases/main/version.json`（另在 Release `latest` 附一份）。

```json
{
  "versionName": "0.1.17", "versionCode": 17, "channel": "dev",
  "apkUrl": "https://github.com/JiHe021499/honghong-releases/releases/download/v0.1.17/honghong-0.1.17.apk",
  "apkName": "honghong-0.1.17.apk",
  "sha256": "<64 位小写十六进制>", "size": 23210662,
  "changelog": "- 提交信息…", "force": false, "minSupportedVersionCode": 0,
  "commit": "<源码 commit>", "publishedAt": "2026-10-14T03:10:03Z",
  "channels": { "dev": { …同上… }, "stable": { … } }
}
```

顶层 = 最近一次发布（不论渠道）；`channels.<渠道>` = 各渠道最新一次。

App（仅 Android，`inAppUpdateSupported`）：
- 启动后自动检查，**最多每 6 小时一次**；设置 →「检查更新」手动检查不受限制。
- 依次尝试：原地址 → `https://ghfast.top/` + 原地址 → `https://gh-proxy.com/` + 原地址（国内访问 GitHub 失败时的镜像）。请求带按分钟变化的 `t=` 参数绕过 CDN 缓存。
- 必填字段：versionName、versionCode>0、apkUrl、64 位 sha256，缺了算解析失败。
- 下载同样按原地址 → 镜像顺序；**下载后校验 sha256**，不一致删除文件、换下一个地址，全失败报「安装包校验失败」。已下载且校验通过的文件直接复用。
- 「稍后」会记住跳过该 versionCode（自动检查不再弹，强制更新除外）。

## 6. 发正式版（stable）步骤

0. 想先出个 dev 包测试：GitHub → Actions → Android APK → Run workflow，分支选 master。
1. 确认 master 最新的 dev 版已在真机上验证（至少一台中兴/一台其他品牌）。
2. 如果要升次版本，先改 `app/pubspec.yaml` 的 `version:`（例如 `0.2.0+1`）并合进 master（不会发版）。
3. 打标签并推送（标签名决定 versionName，**不要和已有 dev 版本号重名**，见第 10 节）：
   ```bash
   # notes.md 是给用户看的更新说明，每行一条，以「- 」开头，会原样显示在 App 更新弹窗和 /download 页面
   git tag -a v0.2.0 -F notes.md
   git push origin v0.2.0
   ```
4. 等 Android APK 工作流和 honghong-releases 的「发布安装包」都成功；检查 Release `v0.2.0`（非 Pre-release）和 `version.json` 的 `channels.stable`。
5. 需要所有人必须升级时，在标签所指提交（或这段区间里任一提交）的提交信息里带 `[强制更新]`。

## 7. iOS

- `ios.yml`：`macos-15` + 最新稳定版 Xcode，`flutter build ios --release --no-codesign`（同样传 Supabase dart-define），检查 `Runner.app/PlugIns/HonghongWidgets.appex` 和 `NSSupportsLiveActivities`，打包上传 artifact `honghong-ios-unsigned-<run_number>`（保留 14 天）。**未签名，不能装到手机，也不发布**。
- 版本：`--build-name 0.1.<iOS 工作流 run_number> --build-number <run_number>`（计数和 Android 不同，见第 10 节）。
- 以后（有 Apple 开发者账号后）：注册 `com.honghong.honghong` 和 `com.honghong.honghong.HonghongWidgets`、开启 App Group `group.com.honghong.honghong`；把证书/描述文件/App Store Connect API Key 放进 secrets；CI 改为签名构建并用 `xcrun altool`/fastlane 上传 TestFlight。iOS 不走应用内更新。

## 8. 回滚与热修复

APK 不能降级安装（versionCode 只能增），所以**回滚＝用旧代码发一个更高的版本号**：

1. `git revert <坏提交>`（或修复），提交信息写清楚，必要时带 `[强制更新]`；合进 master 之后，**手动触发**一次 Android 工作流出新的 dev 包（versionCode 更大，所有人都能覆盖安装）；如果是正式版，就打补丁标签。
2. 正式版出问题：在修复后的提交上打新的补丁标签（例如 `v0.2.1`）。
3. 想让 App 立刻停止推送坏版本：可以手动编辑 honghong-releases 的 `version.json`，把顶层和 `channels` 指回上一个好版本——但已经装了坏版本的人不会被"降级"，只能等修复版。
4. 不要删除已发布的 Release 资产（已下载但未安装的用户、镜像缓存会失效）。

## 9. 模型发布（分类模型 cls-*）

模型不跟 App 发版，走 Supabase：

- 训练与发布：`ml/src/train.py --version cls-N` → `ml/src/publish_model.py --env <secrets>/supabase-nc_am.env --build ../build --version cls-N --rollout <百分比>`（用 service_role，只在训练端/服务器上用）。
- 文件：Storage 私有桶 `models`，路径 `models/classifier/{version}.tflite` 和 `.json`（meta：类别、特征规格、融合权重 blend.weight、自检样本、评估指标）。
- 记录：`model_versions` 表（`kind='classifier'`、`rollout_percent`、sha256、meta），只有 service_role 能写，登录设备只读。
- 灰度：RPC `eligible_model('classifier')` 按 `hashtext(auth.uid()) % 100 < rollout_percent` 分桶，取符合条件里 `released_at` 最新的一条。提高 rollout 就扩大范围；设为 0 即停止下发（已安装的不会自动卸载）。
- App：同步时最多每 6 小时检查一次 → 下载 → 校验 sha256 → 加载并跑自检样本 → 设为当前；加载/推理失败的版本进黑名单并自动回退到上一个版本 → 内置模型（`assets/models/cry_head.*`）→ 只用规则。本地保留 2 个版本。
- 现状：cls-1 已发布，`blend.weight = 0`（影子模式，不影响结果，原因见 `ml/README.md`）。

## 10. 发现的不一致 / 待改进

1. **App 不区分渠道**：`UpdateService.check()` 调 `ReleaseInfo.parse()` 时没传 `channel`，用的是顶层（最近一次发布，不论 dev/stable）。所以「正式版用户只收正式版」目前不成立，`channels` 字段没被使用。需要在 App 里加渠道设置（或按当前包的渠道）。
2. ~~标签版本号可能和 dev 版本撞名~~：已解决，dev 版现在带 `-dev` 后缀。以下为历史说明：dev 版本名是 `0.1.<run_number>`，如果打 `v0.1.20` 而 dev 也曾发过 `0.1.20`，`publish.yml` 会**删掉同名 Release 重建**，覆盖掉 dev 的包。正式版请用不会出现在 dev 序列里的号（如升次版本 `0.2.0`），或以后改为 dev 带后缀。
3. **iOS 和 Android 版本号不一致**（已确认等上 TestFlight 时再统一）：两个工作流各自的 run_number 不同，同一提交的 iOS `0.1.x` 和 Android `0.1.y` 对不上；iOS 也不响应 `v*` 标签。上 TestFlight 前应统一（例如都用 commit 计数或共享的版本来源）。
4. **pubspec 的 `+build` 和第三段没用**，容易误导；可以在 pubspec 注释里写明。
5. **强制更新只维持一版**：下一次普通发布 `minSupportedVersionCode` 归 0，跳过强制版本、直接从更老版本升到更新版本的用户不会被强制。若需要「低于某版本必须升级」，应把 minSupportedVersionCode 做成持续继承的最大值。
6. **更新日志只取 `app/` 目录的提交**（`git log … -- .` 在 app 目录执行），只改 CI/文档的提交不会出现在日志里（这是预期，但标记 `[强制更新]` 也必须写在动了 `app/` 的提交里才生效）。
7. 迁移 0001 里的 `eligible_model` 没有 `coalesce`（uid 为空时出错），0003 已用 `create or replace` 修正，新库按顺序执行即可。

## 11. 应用分发页（/download、/download/beta）

代码在 `web/download/`，说明见该目录 README。页面运行时读 honghong-releases 的公开 `version.json`：`channels.stable` 给正式版页，`channels.dev` 给测试版页。发版后页面自动更新，不用改 config，releases 仓库也不用改。

**服务器布局（nc_am，1Panel OpenResty 容器 `1Panel-openresty-UXJT`，宿主机 `/opt/1panel/www` 挂到容器内 `/www`）**
- 静态文件：`/opt/1panel/www/sites/honghong.hczhw.com/download/`（`index.html`、`beta/`、`assets/`、`data/version.json`）
- location：`/opt/1panel/www/sites/honghong.hczhw.com/proxy/download.conf`（内容即 `web/download/deploy/download.conf`，站点的 `include proxy/*.conf` 会自动加载）
- 版本数据同步：`/opt/honghong-download/sync-version.sh`，宿主机 crontab 每 5 分钟跑一次，只读公开地址，不需要任何密钥

**首次上线（需本人确认后执行）**
```sh
# box 上
cd /workspace/honghong/web/download
tar czf /tmp/download-page.tgz index.html beta assets
scp /tmp/download-page.tgz deploy/sync-version.sh deploy/download.conf nc-am:/tmp/
# nc_am 上
S=/opt/1panel/www/sites/honghong.hczhw.com
sudo mkdir -p $S/download && sudo tar xzf /tmp/download-page.tgz -C $S/download
sudo install -D -m 755 /tmp/sync-version.sh /opt/honghong-download/sync-version.sh
sudo /opt/honghong-download/sync-version.sh            # 先手动跑一次，生成 data/version.json
sudo install -m 644 /tmp/download.conf $S/proxy/download.conf
sudo docker exec 1Panel-openresty-UXJT nginx -t && sudo docker exec 1Panel-openresty-UXJT nginx -s reload
( sudo crontab -l 2>/dev/null; echo '*/5 * * * * /opt/honghong-download/sync-version.sh >> /opt/honghong-download/sync.log 2>&1' ) | sudo crontab -
# 验证
curl -sI https://honghong.hczhw.com/download | grep -i location          # 301 → /download/
curl -s  https://honghong.hczhw.com/download/ | grep -c data-kind=\"release\"
curl -sI https://honghong.hczhw.com/download/beta/ | grep -i x-robots-tag
curl -s  https://honghong.hczhw.com/download/data/version.json | python3 -m json.tool | head
curl -s -o /dev/null -w '%{http_code}\n' https://honghong.hczhw.com/ai/healthz   # 原有网关不受影响，应为 200
```

**之后更新页面本身**（版本数据不用管，cron 会同步）
```sh
scp /tmp/download-page.tgz nc-am:/tmp/
S=/opt/1panel/www/sites/honghong.hczhw.com
sudo rm -rf $S/download.new && sudo mkdir $S/download.new && sudo tar xzf /tmp/download-page.tgz -C $S/download.new
sudo cp -a $S/download/data $S/download.new/
sudo cp -al $S/download/files $S/download.new/ 2>/dev/null || true   # 硬链接，不占额外空间
sudo rm -rf $S/download.prev && sudo mv $S/download $S/download.prev && sudo mv $S/download.new $S/download
```

**回滚**
- 只回滚页面：`sudo rm -rf $S/download && sudo mv $S/download.prev $S/download`
- 整个下线：`sudo rm $S/proxy/download.conf && sudo docker exec 1Panel-openresty-UXJT nginx -t && sudo docker exec 1Panel-openresty-UXJT nginx -s reload`；再 `sudo crontab -e` 删掉 sync-version 那一行；静态目录可留可删。下线后 `/download` 回到站点原来的 404。

**注意**
- 不要把 `web/download/deploy/` 和 README 传上服务器。
- 在 1Panel 面板里改这个站点的「反向代理」时，留意它不会覆盖 `proxy/download.conf`（文件名和面板生成的不同）。
- 二期起 APK 也同步到本站（见下），页面优先从本站下载，GitHub 只作备用。

### 11.1 二期：本站同步 APK、更新说明

- `sync-version.sh` 在同步 version.json 的同时，把每个渠道当前版本的 APK 下载到 `download/files/<渠道>/<apkName 去掉 .apk>-<versionCode>-<sha256 前 8 位>.apk`（例如 `honghong-0.1.19-19-418a7796.apk`；内容一变文件名就变，Cloudflare 缓存 APK 1 天也不会拿到旧包）：
  - 只接受 `https://github.com/JiHe021499/honghong-releases/releases/download/` 下的地址；
  - 先下到同目录的临时文件，**大小和 sha256 都和 version.json 一致**才 `rename` 成正式文件（原子替换），否则丢弃；
  - 校验通过后在 `data/version.json` 的 `channels.<渠道>` 里写 `localApkUrl`（如 `/download/files/dev/honghong-0.1.19-19-418a7796.apk`）。下载失败或校验失败就不写，页面自动用 GitHub 地址；
  - 每个渠道保留最近 3 个 APK（`HH_KEEP`），当前版本永远不删；磁盘剩余低于 2 GB（`HH_MIN_FREE_MB`）时不下载；
  - 用文件锁防止上一轮没跑完时重入；已校验过的文件记在 `.sha256` 标记里，之后每 5 分钟不重复算哈希。
- 页面：有 `localApkUrl` 时主按钮走本站，下面给一个「从 GitHub 下载」的备用链接；拿不到本站数据时退回 raw.githubusercontent.com，只有 GitHub 地址。
- nginx：`/download/files/` 下只放行 `.apk`，`Content-Type: application/vnd.android.package-archive`、`Content-Disposition: attachment`；`.sha256` 标记、临时文件、锁文件都返回 404。
- 磁盘：nc_am 根分区 1007G，已用 213G，可用 754G（2026-10-14 查看）。APK 约 22 MB，两个渠道各 3 个，约 140 MB。

**二期上线（需本人确认后执行；一期已上线，只替换页面、脚本和 conf）**
```sh
# box 上
cd /workspace/honghong && git checkout master && git pull
web/download/deploy/pack.sh /tmp/download-page.tgz      # 给 css/js 加 ?v=<提交号>，工作区有改动会拒绝打包
cd web/download
scp /tmp/download-page.tgz deploy/sync-version.sh deploy/download.conf nc-am:/tmp/
# nc_am 上
TS=$(date +%Y%m%d-%H%M%S); S=/opt/1panel/www/sites/honghong.hczhw.com
sudo cp -a $S/proxy/download.conf $S/proxy/download.conf.bak-$TS
sudo cp -a /opt/honghong-download/sync-version.sh /opt/honghong-download/sync-version.sh.bak-$TS
sudo crontab -l | sudo tee /opt/honghong-download/root-crontab.bak-$TS >/dev/null
# 1）脚本：先装新脚本并手动跑一次，确认 APK 下好、version.json 带上 localApkUrl
sudo install -m 755 /tmp/sync-version.sh /opt/honghong-download/sync-version.sh
sudo /opt/honghong-download/sync-version.sh
sudo ls -l $S/download/files/*/
sudo python3 -c "import json;d=json.load(open('$S/download/data/version.json'));print({k:v.get('localApkUrl') for k,v in d['channels'].items()})"
# 2）nginx：先测后载，失败就恢复旧 conf
sudo install -m 644 /tmp/download.conf $S/proxy/download.conf
if sudo docker exec 1Panel-openresty-UXJT nginx -t; then sudo docker exec 1Panel-openresty-UXJT nginx -s reload
else sudo cp -a $S/proxy/download.conf.bak-$TS $S/proxy/download.conf; echo "nginx -t 失败，已恢复，未 reload"; fi
# 3）页面
sudo rm -rf $S/download.new && sudo mkdir $S/download.new && sudo tar xzf /tmp/download-page.tgz -C $S/download.new --no-same-owner
sudo cp -a $S/download/data $S/download.new/ && sudo cp -al $S/download/files $S/download.new/
sudo rm -rf $S/download.prev && sudo mv $S/download $S/download.prev && sudo mv $S/download.new $S/download
# crontab 不用改（还是同一个脚本路径）
# 验证
H=https://honghong.hczhw.com
A=$(curl -s "$H/download/data/version.json?x=$RANDOM" | python3 -c "import json,sys;print(json.load(sys.stdin)['channels']['dev']['localApkUrl'])"); echo $A   # /download/files/dev/honghong-<版本>-<code>-<sha8>.apk
curl -sI $H$A | grep -iE '^HTTP|content-type|content-length|disposition'   # 200、package-archive、大小、attachment
curl -s -o /dev/null -w '%{http_code}\n' $H$A.sha256                      # 404
curl -s $H$A | sha256sum                                                  # 与 version.json 的 sha256 一致
curl -sI $H/download/ | grep -iE 'cf-cache-status|cache-control'          # DYNAMIC、no-cache（HTML 不被 CDN 缓存）
curl -sI "$H/download/data/version.json?x=$RANDOM" | grep -iE 'cf-cache-status|cache-control'   # DYNAMIC、max-age=60
curl -s $H/download/beta/ | grep -oE 'assets/app\.js\?v=[0-9a-f]+'           # 带上本次提交号
curl -s "$H$(curl -s $H/download/beta/ | grep -oE '/?assets/app\.js\?v=[0-9a-f]+' | sed 's#^/\?#/download/beta/../#')" | grep -c localApkUrl   # ≥1：拿到的是新 app.js
for u in /download /download/ /download/beta/ /ai/healthz /rest/v1/ /; do curl -s -o /dev/null -w "$u %{http_code}\n" $H$u; done   # 301 200 200 200 401 404
```

**二期回滚**
```sh
S=/opt/1panel/www/sites/honghong.hczhw.com; TS=<上面的时间戳>
sudo cp -a $S/proxy/download.conf.bak-$TS $S/proxy/download.conf
sudo docker exec 1Panel-openresty-UXJT nginx -t && sudo docker exec 1Panel-openresty-UXJT nginx -s reload
sudo cp -a /opt/honghong-download/sync-version.sh.bak-$TS /opt/honghong-download/sync-version.sh
sudo rm -rf $S/download && sudo mv $S/download.prev $S/download
sudo /opt/honghong-download/sync-version.sh          # 用旧脚本重写 version.json，去掉 localApkUrl
sudo rm -rf $S/download.prev/files                   # 可选：删掉已下载的 APK
```
回滚后旧 HTML 引用的是旧的 `?v=`（或不带 `?v=`）资源地址，Cloudflare 会按旧地址给旧文件，不会混用。页面旧版本不认识 `localApkUrl`，所以回滚后即使 version.json 里还留着它也只会继续用 GitHub 地址。

**缓存约定（2026-10-14 产品决定）**
- HTML：`no-cache`，Cloudflare 不缓存（`cf-cache-status: DYNAMIC`，已在线上核实）。
- css/js：Cloudflare 会缓存（边缘最长 4 小时），所以 HTML 里一律引用 `assets/xxx?v=<提交号>`，**必须用 `pack.sh` 打包**，不要再直接 tar。
- version.json：`max-age=60`，Cloudflare 不缓存（DYNAMIC）；页面请求还带按分钟变化的 `t=` 参数。备用的 raw.githubusercontent.com 自身缓存 5 分钟。
- APK：Cloudflare 缓存 1 天；文件名带 versionCode 和 sha256 片段，同名文件内容不会变。
- 同一个版本号不允许重新发布：android.yml 的「发布前检查：版本号未被占用」用 `git ls-remote` 查 honghong-releases 的标签，已存在就报错。dev 版要重发请重新手动触发（会得到新的 run_number），不要 Re-run。
