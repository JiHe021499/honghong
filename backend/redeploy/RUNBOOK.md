# 后端重建手册（干净服务器）

> 背景：nc_am 已确认被入侵，旧的 JWT secret / anon / service_role key、数据库密码一律视为泄露，**不得复用**。
> 新服务器上 App 使用的 anon key 会变，旧版 App（0.1.7 及以前，本来就没注入云端配置）不受影响。

## 0. 准备服务器（手动）
- 全新系统（不要从 nc_am 镜像/备份恢复系统盘），Ubuntu 24.04，2 核 4G 起
- 只用 SSH 密钥登录，禁用密码；防火墙只开 22（或 Tailscale）、80、443
- 安装 docker、docker compose v2（≥ 2.24，override 用到 `!override`）、git、openssl、jq
- **不要**从 nc_am 拷 `/opt/honghong-backups`：数据库 dump 可能被篡改；第二阶段尚无真实用户数据，直接全新开始

## 1. 一条命令部署（在 box 上执行）
```bash
cd backend/redeploy
./redeploy.sh --host user@new-server --url https://honghong.hczhw.com \
  --secrets-out /cursor/stores/<bot-store>/secrets/supabase-<new-server>.env \
  --skip-smoke --yes          # 反代/DNS 配好之前先跳过公网冒烟测试
```
脚本内容见文件头注释。它会拒绝覆盖已存在的 `.env`。

## 2. 反向代理 + HTTPS（手动）
只放行三条路径到 `127.0.0.1:8000`，其余 404：
```
honghong.hczhw.com {
  @api path /auth/v1/* /rest/v1/* /storage/v1/*
  reverse_proxy @api 127.0.0.1:8000
  respond 404
}
```
（Caddy 示例；用 Cloudflare 代理时把 SSL 设为 Full (strict)，不要用 Flexible。）

## 3. DNS
Cloudflare 上 `honghong` 的 CNAME 现在指向旧的 tunnel，改为指向新服务器（A 记录或新 tunnel）。旧 tunnel 的凭据也视为泄露，应在 Cloudflare 删除并重建。

## 4. 冒烟测试 + 设 GitHub secret
```bash
# redeploy.sh 不能重跑（已有 .env），单独执行：
ANON=$(grep ^ANON_KEY= <secrets-out> | cut -d= -f2-)
curl -s -X POST https://honghong.hczhw.com/auth/v1/signup -H "apikey: $ANON" -H 'Content-Type: application/json' -d '{}' | jq .access_token
printf %s https://honghong.hczhw.com | gh secret set SUPABASE_URL -R JiHe021499/honghong
printf %s "$ANON"                     | gh secret set SUPABASE_ANON_KEY -R JiHe021499/honghong
```
（如果第 1 步没加 `--skip-smoke`，脚本已经做完这一步。）

## 5. 验证 RLS
本地：`backend/supabase/tests/run_local_rls_test.sh`（不连服务器）。
线上：用两个匿名用户 + 一个外人按 `family_rls_test.sql` 的步骤走一遍 REST 调用。

## 6. 出包
push 到 master 或在 Actions 手动运行 “Android APK”，新包会带上 SUPABASE_URL / SUPABASE_ANON_KEY。

## 7. 备份
每日 `pg_dump` + `volumes/storage` 打包，同步到异地对象存储，保留 7–30 天。

## 安全约束
- service_role key、JWT_SECRET、数据库密码只在服务器 `.env`（600）和 bot 私有存储，绝不进仓库、CI 或 App
- Studio 只绑 127.0.0.1，通过 SSH 隧道访问
