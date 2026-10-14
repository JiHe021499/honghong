# backend：自建 Supabase（第二阶段）

第一阶段不需要后端。第二阶段用于收集用户**主动授权**上传的哭声片段和标注，并下发模型。

## 服务器
- 推荐 4 核 8G（最低 2 核 4G），50–100G SSD，Ubuntu 22.04/24.04
- Docker + Docker Compose；反代用 1Panel 的 OpenResty（nginx），HTTPS 由 Cloudflare 代理负责
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

反代（1Panel OpenResty / nginx）示例：
```nginx
location /auth/v1/ { proxy_pass http://127.0.0.1:8000; }
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

## 历史记录：妈咪日记 AI 网关 P0 首次上线（2026-10-14，已过时）

> ⚠️ 这是 P0 时期的记录，下面的反代片段已经过时：当时超时 30s、没有 WebSocket、没接 LLM。**现状以下文「[AI 网关（妈咪日记）：nc_am 现状](#ai-网关妈咪日记nc_am-现状)」为准**。现在 `/ai/` 已配好 WebSocket，超时 90s，http 层的 map 在 `conf.d/00-honghong-ws-map.conf`；部署的是 asr 版本，配了讯飞，没配 DeepSeek。目录、容器名、更新和回滚步骤仍然适用。

- 目录：`/opt/honghong-ai-gateway`（feat/mommy-diary-p0 分支 `backend/ai-gateway` 的 Dockerfile、docker-compose.yml、package.json、src）
- `.env`（权限 600）只有 `SUPABASE_JWT_SECRET` 一项，在服务器上从 `/opt/honghong-supabase/.env` 的 `JWT_SECRET` 生成；未配置任何 LLM Key，`/healthz` 返回 `llm_configured:false`。**密钥不入库**
- 容器：`honghong-ai-gateway-ai-gateway-1`，端口 `127.0.0.1:8787`（只绑本机），`restart: unless-stopped`
- 公网：`https://honghong.hczhw.com/ai/*`（前缀剥离后转发），例如 `/ai/healthz`、`/ai/diary-parse`（无 token 返回 401）
- 反代：在 `/opt/1panel/www/sites/honghong.hczhw.com/proxy/root.conf` 的 `location / { return 404; }` 之前加了：
  ```nginx
  location /ai/ {
      proxy_pass http://127.0.0.1:8787/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
      proxy_http_version 1.1;
      proxy_read_timeout 30s;
  }
  ```
  OpenResty 跑在 1Panel 容器 `1Panel-openresty-UXJT`（host 网络）：`docker exec 1Panel-openresty-UXJT nginx -t && docker exec 1Panel-openresty-UXJT nginx -s reload`（reload，不要重启）
- 改动前备份（服务器 UTC 时间戳）：
  - `/opt/1panel/www/conf.d/honghong.hczhw.com.conf.bak-20261014-062222`
  - `/opt/1panel/www/sites/honghong.hczhw.com/proxy/root.conf.bak-20261014-062222`

### 更新
```bash
# box 上
cd backend/ai-gateway && tar czf /tmp/aigw.tgz Dockerfile docker-compose.yml package.json src && scp /tmp/aigw.tgz nc-am:/tmp/
# 服务器上（.env 保留不动）
cd /opt/honghong-ai-gateway && cp -a src src.prev && tar xzf /tmp/aigw.tgz && docker compose up -d --build
curl -s localhost:8787/healthz && curl -s -o /dev/null -w '%{http_code}\n' https://honghong.hczhw.com/ai/healthz
```
单实例，更新时有几秒中断（P0 未接生产流量，可接受）。

### 回滚
- 代码：`rm -rf src && mv src.prev src && docker compose up -d --build`
- 下线网关：`docker compose down`，并恢复反代：
  `sudo cp -p root.conf.bak-20261014-062222 root.conf`（在 proxy 目录内），再 `nginx -t` + `nginx -s reload`

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

## AI 网关（妈咪日记）：nc_am 现状

- 已部署 `backend/ai-gateway` 的 asr 版本（PR #6），配了讯飞，没配 DeepSeek。所以 `/diary-asr` 可用，`/diary-parse` 和 `/diary-summary` 目前不可用。
- 反代：1Panel OpenResty（nginx）站点的 `/ai/` location 已配好 WebSocket upgrade，超时 90s；http 层的 `map` 写在 `conf.d/00-honghong-ws-map.conf`。不使用 Caddy。
- 环境变量以 `ai-gateway/src/config.js` 为准，值只放在服务器 `.env`：
  - `SUPABASE_JWT_SECRET`
  - `XFYUN_APPID`、`XFYUN_API_KEY`、`XFYUN_API_SECRET`
  - `DEEPSEEK_API_KEY`（也可以用 `LLM_API_KEY`，目前未配）
  - 可选：`LLM_BASE_URL`、`LLM_MODEL`、`LLM_TIMEOUT_MS`、`LIMIT_PARSE_PER_DAY`、`LIMIT_SUMMARY_PER_DAY`、`LIMIT_ASR_PER_DAY`
- 上线清单见 `docs/release/mommy-diary-launch-checklist.md`。

## 模型下发（第三阶段）

- 迁移 `0003_models.sql`（已在 nc_am 执行）：`model_versions` 增加 `meta`/`size_bytes`/`notes`，`meta` 的 sha256/version 必须与行一致。
- 发布：`ml/src/publish_model.py --env <secrets> --version cls-N --rollout 10`（service_role 只在训练机）。回滚：把 rollout_percent 设 0 或发布更高版本。
