# 妈咪日记上线清单（需要人工执行，Agent 不执行）

## 1. 合并顺序（PR 逐个叠加，从 #1 开始按顺序合）
1. #1 P0 准备阶段（网关骨架、评测脚本、新图标）→ master
2. #2 P1 数据层（drift v5、`0004_diary.sql`、DiaryRepository）
3. #3 P2 ai-gateway 拆分与小结、评测集
4. #4 P3 客户端主流程
5. #5 P4 日记时间线与编辑
6. #6 讯飞联网识别兜底
7. #7 P5 今日小结、设置「联网语音识别」开关
8. #8 P6 埋点、隐私与免责、小结失败重试、golden 修复

每合一个，就把下一个 PR 的 base 改成 master（或者先 rebase），再看 CI 是否通过。

## 2. 线上数据库
- 客户端用 drift 本地库，schema v5。升级时 App 内自动迁移，不需要线上操作。
- Supabase 迁移 `0004_diary.sql`：**目前没有在线上执行**。在线上执行之前要做三件事：先在预发库或备份上演练，确认可以回滚，再在低峰时执行。由负责人手动操作。

## 3. AI 网关（backend/ai-gateway）
现状（nc_am）：
- 已部署 asr 版本（PR #6），配了讯飞，`/diary-asr` 可用。
- **没有配 DeepSeek**，所以 `/diary-parse` 和 `/diary-summary` 目前不可用。

反向代理是 1Panel 的 OpenResty（nginx），不是 Caddy：
- 站点 `/ai/` 下的 location 已经配好 WebSocket upgrade，超时 90s。
- http 层的 `map $http_upgrade $connection_upgrade` 写在 `conf.d/00-honghong-ws-map.conf`。
- 改完配置后先 `nginx -t`，再 reload OpenResty。

环境变量以 `backend/ai-gateway/src/config.js` 为准，值只放在服务器 `.env`，不要进 git：

| 变量 | 用途 | nc_am 现状 |
|---|---|---|
| `SUPABASE_JWT_SECRET` | 校验 App 的 Supabase JWT | 已配 |
| `XFYUN_APPID`、`XFYUN_API_KEY`、`XFYUN_API_SECRET` | 讯飞语音听写，三项缺一 `/diary-asr` 就返回 503 | 已配 |
| `DEEPSEEK_API_KEY`（也可以用 `LLM_API_KEY`） | 整理和小结 | **未配，上线 P2 之后的版本前必须补上** |
| `LLM_BASE_URL`、`LLM_MODEL`、`LLM_TIMEOUT_MS` | 默认值分别是 `https://api.deepseek.com`、`deepseek-chat`、`7000` | 用默认值 |
| `LIMIT_PARSE_PER_DAY`、`LIMIT_SUMMARY_PER_DAY`、`LIMIT_ASR_PER_DAY` | 每日限额（北京时间），默认 60、3、60 | 用默认值 |
| `HOST`、`PORT`、`ASR_IDLE_MS`、`XFYUN_URL`、`MAX_BODY_BYTES` | 可选 | 用默认值 |

待办：
- [ ] 在 nc_am 的网关 `.env` 里补上 `DEEPSEEK_API_KEY`，部署 P6 版本的网关并重启。
- [ ] 确认 `/ai/diary-parse` 和 `/ai/diary-summary` 已在 OpenResty 的 `/ai/` 下放行。
- [ ] 构建 App 时注入网关地址。没配置时，日记退化为“原话存成其他”，小结一直显示“还在整理”。
- [ ] 上线后观察：网关的 429 和 5xx 比例、P90 耗时（目标 ≤5 秒），以及讯飞和 DeepSeek 的用量与余额。

## 4. 合规（联网识别、AI 上线前必须完成）
- [ ] 把 `docs/privacy/mommy-diary-privacy.md` 交法务审核，并入正式隐私政策，再发布新版本。
- [ ] 与讯飞确认数据条款（不留存、不用于训练），留存书面确认；如有必要，在控制台关闭“用于改进服务”。
- [ ] 与 DeepSeek 确认 API 数据不用于训练、不出境，留存书面确认。
- [ ] 应用商店隐私表单（App Store 隐私标签、国内各安卓商店的第三方 SDK/接口清单）新增两项：讯飞语音听写 WebAPI（服务端调用）、DeepSeek 大模型 API（服务端调用）。
- [ ] 检查 App 内的告知弹窗、设置里的“妈咪日记与隐私”和正式隐私政策三处文案是否一致。
- [ ] 如需算法备案、生成式 AI 服务登记，由负责人评估并办理。

## 5. 真机测试（内测前）
- [ ] iOS（真机，iOS 17 和 18 各一台）：首次申请麦克风和语音识别权限；系统识别；拒绝权限后的提示和文字输入。
- [ ] Android：一台有 Google 语音服务的机器，另一台国产 ROM 没有识别服务的机器。后者用来测：联网识别告知 → 同意 → 讯飞识别；拒绝后退回文字输入；在设置里关闭后，打字页出现提示并能跳转。
- [ ] 弱网和断网：解析失败时原话保存为“其他”；断网时保留草稿。
- [ ] 21:00 之后打开 App 自动生成小结；第二天早上打开时补生成昨天的；空日显示屏 23；网关故障时小结显示“还在整理”，失败满 3 次后出现“点此重试”。
- [ ] 夜间模式下检查小结页、时间线、确认页。
- [ ] 家庭同步：日记写入的喂奶、睡眠、尿布能在家人手机上看到；情绪卡、其他卡、小结不同步。
- [ ] 升级安装：从线上版本覆盖安装后，本地数据库迁移正常，原有记录没有丢失。

## 6. 发版与内测
- [ ] 版本号和更新日志；构建时注入网关地址。
- [ ] iOS：TestFlight 内测组。Android：内测渠道（应用内更新或内测分发）。
- [ ] 内测用户说明：在「设置 → 妈咪日记内测数据」中复制统计结果发回给我们（只有次数，没有内容）。
- [ ] 内测目标（PRD 第 7 节的建议值）：一键保存率 ≥70%，卡片修改率 ≤20%，识别失败率 ≤5%。
- [ ] 正式上架应用商店：内测数据达标、合规项全部完成后，再由负责人提交。
