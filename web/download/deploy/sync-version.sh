#!/bin/sh
# 把 honghong-releases 的公开 version.json 同步到分发页目录。只读公开地址，不需要任何密钥。
# 用法（nc_am 宿主机 crontab）：*/5 * * * * /opt/honghong-download/sync-version.sh >> /opt/honghong-download/sync.log 2>&1
set -eu
SRC=https://raw.githubusercontent.com/JiHe021499/honghong-releases/main/version.json
DST=/opt/1panel/www/sites/honghong.hczhw.com/download/data/version.json
mkdir -p "$(dirname "$DST")"
tmp=$(mktemp "$DST.XXXXXX")
trap 'rm -f "$tmp"' EXIT
curl -fsS --max-time 20 "$SRC" -o "$tmp"
# 内容不是合法 JSON 或缺 channels 时保留旧文件
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert isinstance(d.get("channels"), dict)' "$tmp"
if ! cmp -s "$tmp" "$DST" 2>/dev/null; then
  chmod 644 "$tmp"; mv "$tmp" "$DST"; echo "$(date '+%F %T') 已更新"
fi
