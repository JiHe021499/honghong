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
