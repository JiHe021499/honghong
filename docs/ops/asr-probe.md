# ASR 合成探测与告警（日志方案 P0）

目标：按住说话的联网识别（网关 `/diary-asr` → 讯飞）整体坏掉时，**10 分钟内**有人收到告警。

探测脚本：`backend/ai-gateway/eval/probe.js`（基于 `eval/asr_smoke.js`）
1. `GET <base>/healthz`：必须 `ok=true` 且 `asr_configured=true`（`PROBE_REQUIRE_LLM=1` 时还要 `llm_configured=true`）。
2. `WSS <base>/diary-asr`：带 `x-request-id`，发 2 秒合成的正弦波 PCM（不是人声），发 `end`，必须收到 `final`。
3. 每次输出一行 JSON（`svc=probe`、`request_id`、`stage`、`err_code`、`consecutive_fails`），失败时退出码为 1。
4. **连续 2 次失败**发一次告警；恢复后发一次恢复通知。告警发送失败时下次会重试。

告警通道**还没选定**，做成可插拔，配哪个用哪个，都不配时只打印到 stderr：
- `ALERT_WEBHOOK_URL` + `ALERT_WEBHOOK_FORMAT`：
  - `generic`（默认）：`{text,status,source,result}`
  - `text`：企业微信或钉钉的文本机器人格式
  - `feishu`：飞书机器人格式
- `ALERT_COMMAND`：任意命令，告警文本从 stdin 传入，比如用来发邮件。

## 网关侧配置（部署时）
- `.env` 加 `PROBE_SUBS=<探测账号 sub>`：探测走单独限流桶 `diary-asr-probe`（默认 600 次/天），日志带 `probe=true`，统计时可以排除。
- 探测账号 JWT（推荐用这个，不要把网关的 `SUPABASE_JWT_SECRET` 交给外部 CI）：在**新服务器**上用网关的 secret 签一个长期 token，例如：
  ```sh
  cd backend/ai-gateway && node -e "import('./src/jwt.js').then(({signJwt})=>console.log(signJwt({sub:'hh-probe',role:'authenticated',exp:Math.floor(Date.now()/1000)+90*86400}, process.env.SUPABASE_JWT_SECRET)))"
  ```
  这个 token 90 天过期，需要按时轮换；轮换忘了会因为 401 告警。

## (a) 服务器内 cron（**本 PR 没有安装**；nc-am 已确认被入侵，请装在重建后的新服务器上）
```sh
# 1. 配置（只有 root 可读）
sudo mkdir -p /etc/honghong /var/lib/honghong
sudo install -m 600 /dev/null /etc/honghong/probe.env
sudo editor /etc/honghong/probe.env   # 填 PROBE_BASE_URL / PROBE_JWT / ALERT_* / PROBE_SOURCE=server-cron / PROBE_STATE_FILE=/var/lib/honghong/asr-probe.json
# 2. 手动跑一次确认
sudo /opt/honghong/backend/ai-gateway/ops/probe-cron.sh; echo "exit=$?"
# 3. 安装 cron（每 5 分钟）
echo '*/5 * * * * root /opt/honghong/backend/ai-gateway/ops/probe-cron.sh >> /var/log/honghong-asr-probe.log 2>&1' | sudo tee /etc/cron.d/honghong-asr-probe
```
（路径按实际 checkout 位置调整；需要 Node ≥ 20 和 `flock`。日志文件建议配 logrotate。）

## (b) GitHub Actions（外部兜底）
- 把 `docs/ops/probe.yml` 复制到 `.github/workflows/probe.yml` 并提交（需要有 workflow 权限的账号）。
- 仓库变量：`PROBE_BASE_URL`；可选 `PROBE_REQUIRE_LLM`、`ALERT_WEBHOOK_FORMAT`。
- 仓库 secret：`PROBE_JWT`、`ALERT_WEBHOOK_URL`。
- GitHub 的定时任务可能延迟或跳过，所以它只是兜底；服务器整体挂掉时靠它报警。

## 验收（在测试环境或新服务器上做）
1. 正常状态下手动触发一次，确认 `ok=true`，网关日志里能按探测输出的 `request_id` 查到同一次会话（`probe=true`）。
2. 把网关 `.env` 里的 `XFYUN_API_KEY` 改错并重启网关，或者直接 `docker compose stop ai-gateway`。
3. 等两次探测（≤10 分钟），告警通道应该收到「连续失败」，内容含阶段、`err_code` 和 `request_id`。
4. 恢复配置或启动网关，下一次探测后收到「已恢复」。
本地可以用 `npm test`（`test/probe.test.js`）复现完整流程：key 错误、网关停止、ASR 未配置、恢复。
