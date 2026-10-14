# backend：自建 Supabase（第二阶段）

第一阶段不需要后端。第二阶段用于收集用户**主动授权**上传的哭声片段和标注，并下发模型。

## 服务器
- 推荐 4 核 8G（最低 2 核 4G），50–100G SSD，Ubuntu 22.04/24.04
- Docker + Docker Compose；Caddy（或 Nginx）反代并自动 HTTPS
- 防火墙只开 80/443（SSH 建议改端口 + 密钥登录），Postgres 不暴露公网
- 国内服务器需 ICP 备案

## 部署
```bash
git clone --depth 1 https://github.com/supabase/supabase
cp -r supabase/docker ./docker && cd docker
cp .env.example .env   # 修改 POSTGRES_PASSWORD、JWT_SECRET、ANON_KEY、SERVICE_ROLE_KEY、DASHBOARD 密码
docker compose up -d
```
开启匿名登录（`GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED=true`），然后执行 `supabase/migrations/0001_init.sql`。

Caddyfile 示例：
```
api.example.com {
  reverse_proxy localhost:8000
}
```

## 备份
每日 `pg_dump` + 同步 Storage 目录到另一处对象存储，保留 30 天，并定期演练恢复。

## 重建

见 `redeploy/RUNBOOK.md` 和 `redeploy/redeploy.sh`（一条命令在干净服务器上全新部署，生成新密钥，执行 0001+0002，设置 GitHub secret）。

## 当前部署：nc_am（2026-10-14 全新重建）

- 2026-10-14 用 `redeploy/redeploy.sh` 全新部署：旧栈和数据卷、旧备份全部删除，JWT secret / anon / service_role key / 数据库密码 / Studio 账号全部重新生成（只在服务器 `.env` 和 bot 私有存储）
- 网关 `127.0.0.1:8000`、Studio `127.0.0.1:54323`；OpenResty 站点和 Cloudflare tunnel 沿用（只放行 /auth/v1、/rest/v1、/storage/v1）
- 已执行 0001 + 0002；公网验证：匿名注册、家庭创建/加入、外人隔离、Storage 按设备目录隔离均通过，测试用户已删除
- 备份：`redeploy/backup.sh` → `/opt/honghong-supabase/backup.sh`，crontab 每天 03:30（服务器时间 CEST）

## 历史部署：nc_am 第一次部署（2026-10-13，服务器被入侵，已整体删除；以下密钥全部作废）

- 地址：`https://honghong.hczhw.com`（Cloudflare 代理 → 源站 1Panel OpenResty :80 → `127.0.0.1:8000` Supabase 网关）
- 目录：`/opt/honghong-supabase`（官方 `supabase/docker`，网关为 envoy），`.env` 权限 600，**密钥只在服务器和 bot 私有存储，不入库**
- 运行的服务：db、auth、rest、storage、imgproxy、meta、studio、api-gw；realtime/functions/supavisor 通过 `docker-compose.override.yml` 的 `profiles: [disabled]` 关闭（supavisor 会占宿主 5432，与 1Panel Postgres 冲突）
- 端口：网关 `127.0.0.1:8000`，Studio `127.0.0.1:54323`；数据库不映射宿主端口；各容器有 `mem_limit`
- 公网只放行 `/auth/v1/`、`/rest/v1/`、`/storage/v1/`，其余路径 404（Studio 不对公网开放）
  - 反代配置：`/opt/1panel/www/conf.d/honghong.hczhw.com.conf` + `/opt/1panel/www/sites/honghong.hczhw.com/proxy/root.conf`（按 1Panel 目录约定手写，未登记进 1Panel 面板数据库）
- 访问 Studio：`ssh -L 54323:127.0.0.1:54323 heji@nc-am`，浏览器开 `http://localhost:54323`
- 已启用匿名登录，关闭邮箱/手机注册；`0001_init.sql` 已执行，桶 `cry-clips`、`models`（私有）已建，RLS 验证通过
- 启停：`cd /opt/honghong-supabase && docker compose up -d` / `docker compose ps`
- 备份：cron 每天 03:30（服务器时间 UTC）运行 `/opt/honghong-supabase/backup.sh`，pg_dump + storage 打包到 `/opt/honghong-backups`，保留 7 天（同机备份，建议再同步到异地）
- App 端配置：`SUPABASE_URL=https://honghong.hczhw.com` + anon key（anon key 可放客户端；service_role key 绝不能进 App）

## 模型下发（第三阶段）

- 迁移 `0003_models.sql`（已在 nc_am 执行）：`model_versions` 增加 `meta`/`size_bytes`/`notes`，`meta` 的 sha256/version 必须与行一致。
- 发布：`ml/src/publish_model.py --env <secrets> --version cls-N --rollout 10`（service_role 只在训练机）。回滚：把 rollout_percent 设 0 或发布更高版本。
