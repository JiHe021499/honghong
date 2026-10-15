#!/bin/sh
# 服务器内 ASR 合成探测（每 5 分钟由 cron 调用）。安装方法见 docs/ops/asr-probe.md。
# 配置放在 /etc/honghong/probe.env（chmod 600，不进仓库），例如：
#   PROBE_BASE_URL=https://<host>/ai/
#   PROBE_JWT=<探测账号 JWT>            # 或 PROBE_JWT_SECRET=<网关 SUPABASE_JWT_SECRET>（仅本机）
#   PROBE_SOURCE=server-cron
#   PROBE_STATE_FILE=/var/lib/honghong/asr-probe.json
#   ALERT_WEBHOOK_URL=...  ALERT_WEBHOOK_FORMAT=generic|text|feishu   # 或 ALERT_COMMAND=...
set -eu
ENV_FILE="${PROBE_ENV_FILE:-/etc/honghong/probe.env}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE" >&2; exit 2; }
set -a; . "$ENV_FILE"; set +a
mkdir -p "$(dirname "${PROBE_STATE_FILE:-/tmp/hh-asr-probe.json}")"
# flock 防止上一次还没跑完时重叠
exec flock -n /tmp/hh-asr-probe.lock node "$DIR/eval/probe.js"
