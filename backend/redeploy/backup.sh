#!/bin/bash
# 哄哄每日备份：pg_dump + storage 目录打包，保留 7 天（同机；建议再同步到异地）
# 安装：cp 到 /opt/honghong-supabase/backup.sh，crontab：30 3 * * * /opt/honghong-supabase/backup.sh >> /opt/honghong-backups/backup.log 2>&1
set -euo pipefail
umask 077
B=/opt/honghong-backups; TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$B"
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > "$B/db-$TS.dump"
sudo -n tar -C /opt/honghong-supabase/volumes -czf "$B/storage-$TS.tgz" storage
sudo -n chown "$(id -u):$(id -g)" "$B/storage-$TS.tgz"
find "$B" -type f \( -name 'db-*.dump' -o -name 'storage-*.tgz' \) -mtime +7 -delete
echo "$(date -Is) ok $TS"
