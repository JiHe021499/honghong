#!/usr/bin/env bash
# 哄哄后端一键重建（在一台干净的服务器上全新部署自建 Supabase）
#
# 做的事：
#   1. 在目标服务器拉官方 supabase/docker 到 $REMOTE_DIR
#   2. 用官方脚本生成全新的 JWT_SECRET、anon / service_role key、ES256 密钥对和其他密钥（旧密钥一律作废）
#   3. 写入哄哄需要的配置：公网地址、开启匿名登录、关闭邮箱/手机注册、随机数据库和 Studio 密码
#   4. 叠加 docker-compose.override.yml（关 realtime/functions/supavisor，端口只绑 127.0.0.1）并启动
#   5. 执行 migrations/0001_init.sql + 0002_family.sql，刷新 PostgREST 缓存
#   6. 冒烟测试：经公网地址匿名注册一个用户
#   7. 把服务器 .env 拷一份到本机 $SECRETS_OUT（权限 600，不进仓库）
#   8. 设置 GitHub 仓库 secret：SUPABASE_URL、SUPABASE_ANON_KEY（只给 anon key）
#
# 不做的事（见 RUNBOOK.md）：装 Docker、防火墙、反向代理/HTTPS、DNS、备份 cron。
#
# 用法：
#   ./redeploy.sh --host user@server --url https://honghong.example.com --secrets-out /path/to/supabase-new.env --yes
#   可选：--ssh "ssh -o ProxyCommand='tailscale nc %h %p'"  --remote-dir /opt/honghong-supabase  --repo JiHe021499/honghong
#         --skip-gh（不设 GitHub secret）  --skip-smoke（反代/DNS 还没好时跳过公网冒烟测试）
set -euo pipefail

HOST="" URL="" SECRETS_OUT="" YES=0 SKIP_GH=0 SKIP_SMOKE=0
SSH="ssh" REMOTE_DIR="/opt/honghong-supabase" REPO="JiHe021499/honghong"
SUPABASE_REF="master"
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST=$2; shift 2 ;;
    --url) URL=${2%/}; shift 2 ;;
    --secrets-out) SECRETS_OUT=$2; shift 2 ;;
    --ssh) SSH=$2; shift 2 ;;
    --remote-dir) REMOTE_DIR=$2; shift 2 ;;
    --repo) REPO=$2; shift 2 ;;
    --supabase-ref) SUPABASE_REF=$2; shift 2 ;;
    --skip-gh) SKIP_GH=1; shift ;;
    --skip-smoke) SKIP_SMOKE=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help) sed -n 2,25p "$0"; exit 0 ;;
    *) echo "未知参数 $1"; exit 2 ;;
  esac
done
[ -n "$HOST" ] && [ -n "$URL" ] && [ -n "$SECRETS_OUT" ] || { echo "需要 --host --url --secrets-out"; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
mig="$here/../supabase/migrations"
# 远端脚本经 stdin 交给 bash（登录 shell 可能是 fish，不能直接拼命令行）
r() { printf '%s\n' "$1" | $SSH "$HOST" bash -s; }

echo "目标：$HOST:$REMOTE_DIR  公网：$URL  仓库 secret：$([ $SKIP_GH = 1 ] && echo 跳过 || echo "$REPO")"
if [ $YES != 1 ]; then echo "加 --yes 才会真正执行"; exit 1; fi

echo "== 0. 检查服务器"
r "command -v docker >/dev/null && docker compose version >/dev/null && command -v openssl >/dev/null && command -v git >/dev/null" \
  || { echo "服务器需要 docker、docker compose、openssl、git"; exit 1; }
r "test ! -e '$REMOTE_DIR/.env'" || { echo "$REMOTE_DIR/.env 已存在，拒绝覆盖（这是全新部署脚本）"; exit 1; }

echo "== 1. 拉官方 supabase/docker"
r "set -e; sudo mkdir -p '$REMOTE_DIR' && sudo chown \$(id -u):\$(id -g) '$REMOTE_DIR'
   t=\$(mktemp -d); git clone -q --depth 1 --branch '$SUPABASE_REF' https://github.com/supabase/supabase \"\$t/s\"
   cp -r \"\$t/s/docker/.\" '$REMOTE_DIR/'; rm -rf \"\$t\"; cd '$REMOTE_DIR'; cp .env.example .env; chmod 600 .env"
$SSH "$HOST" "cat > $REMOTE_DIR/docker-compose.override.yml" < "$here/docker-compose.override.yml"

echo "== 2/3. 生成全新密钥并写配置"
r "set -e; cd '$REMOTE_DIR'
   sh utils/generate-keys.sh --update-env >/dev/null
   sh utils/add-new-auth-keys.sh --update-env >/dev/null
   setv() { if grep -q \"^\$1=\" .env; then sed -i \"s|^\$1=.*|\$1=\$2|\" .env; else echo \"\$1=\$2\" >> .env; fi; }
   setv POSTGRES_PASSWORD \$(openssl rand -hex 24)
   setv DASHBOARD_USERNAME honghong
   setv DASHBOARD_PASSWORD \$(openssl rand -hex 16)
   setv SUPABASE_PUBLIC_URL '$URL'
   setv API_EXTERNAL_URL '$URL'
   setv SITE_URL '$URL'
   setv ENABLE_ANONYMOUS_USERS true
   setv ENABLE_EMAIL_SIGNUP false
   setv ENABLE_PHONE_SIGNUP false
   setv DISABLE_SIGNUP false
   setv COMPOSE_FILE docker-compose.yml:docker-compose.override.yml
   grep -q '^ANON_KEY=ey' .env && grep -q '^JWT_SECRET=..' .env"

echo "== 4. 启动"
r "cd '$REMOTE_DIR' && docker compose pull -q && docker compose up -d"
echo "等待数据库就绪…"
for i in $(seq 1 60); do
  r "docker exec supabase-db pg_isready -U postgres -h localhost" >/dev/null 2>&1 && break
  sleep 5
done
sleep 15  # 等 auth / storage 完成各自的内部迁移（storage.buckets 由 storage 服务创建）

echo "== 5. 执行迁移"
for f in "$mig/0001_init.sql" "$mig/0002_family.sql"; do
  echo "  $(basename "$f")"
  $SSH "$HOST" "docker exec -i supabase-db psql -U postgres -d postgres -v ON_ERROR_STOP=1 -1 -q" < "$f"
done
r "docker exec supabase-db psql -U postgres -c \"notify pgrst, 'reload schema'\" >/dev/null"

echo "== 7. 保存密钥到本机 $SECRETS_OUT"
umask 077
$SSH "$HOST" "cat $REMOTE_DIR/.env" > "$SECRETS_OUT"
chmod 600 "$SECRETS_OUT" 2>/dev/null || echo "  （目标文件系统不支持 chmod，请确认存放位置本身是私有的）"
ANON=$(grep -E '^ANON_KEY=' "$SECRETS_OUT" | cut -d= -f2-)

if [ $SKIP_SMOKE != 1 ]; then
  echo "== 6. 冒烟测试（公网匿名注册）"
  sleep 3
  tok=$(curl -fsS -X POST "$URL/auth/v1/signup" -H "apikey: $ANON" -H 'Content-Type: application/json' -d '{}' | jq -r .access_token)
  [ -n "$tok" ] && [ "$tok" != null ] || { echo "匿名注册失败，检查反代/DNS 或 ENABLE_ANONYMOUS_USERS"; exit 1; }
  curl -fsS "$URL/rest/v1/family_members?select=user_id" -H "apikey: $ANON" -H "Authorization: Bearer $tok" >/dev/null
  echo "  通过"
fi

if [ $SKIP_GH != 1 ]; then
  echo "== 8. 设置 GitHub secret（$REPO）"
  printf %s "$URL" | gh secret set SUPABASE_URL -R "$REPO"
  printf %s "$ANON" | gh secret set SUPABASE_ANON_KEY -R "$REPO"
fi

echo "完成。接下来：重新触发 CI（push 到 master 或 workflow_dispatch）出带云端配置的包；配置备份 cron（见 RUNBOOK.md）。"
