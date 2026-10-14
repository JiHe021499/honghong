# ai-gateway（妈咪日记 AI 网关）

独立轻量 Node 服务（零第三方依赖，Node ≥ 20），挂在 Caddy 后，校验自建 Supabase 签发的匿名登录 JWT（架构 D10）。LLM 密钥只放在这里，不进 App。

| 接口 | 状态 |
|---|---|
| `GET /healthz` | ✅ P0，返回 `{ ok, llm_configured }` |
| `POST /diary-parse` | P0 骨架：鉴权、限流（60 次/天/用户）、500 字上限、请求体上限；业务返回 501，P2 实现 |
| `POST /diary-summary` | P0 骨架：鉴权、限流（3 次/天/用户）；业务返回 501，P2 实现 |
| `POST /diary-asr` | 本期不做（D9） |

服务端不落库用户文本，只打匿名指标日志（路由、状态码、耗时）。

## 本地运行与测试
```bash
npm test
SUPABASE_JWT_SECRET=xxx npm start   # 监听 127.0.0.1:8787
```

## 部署
```bash
cp .env.example .env   # 填 SUPABASE_JWT_SECRET（与 Supabase 的 JWT_SECRET 一致）
docker compose up -d --build
```
Caddyfile 在现有 api 站点里加一段（路径前缀剥离后转发）：
```
api.example.com {
  handle_path /ai/* {
    reverse_proxy localhost:8787
  }
  reverse_proxy localhost:8000
}
```
App 侧地址即 `https://api.example.com/ai/diary-parse`。

## 供应商评测（P0，待拍板）
```bash
LLM_BASE_URL=https://<厂商 OpenAI 兼容地址>/v1 LLM_API_KEY=... LLM_MODEL=... npm run eval
```
输出 schema 通过数、分类召回、P50/P90 延迟。评测记录见 `docs/architecture/mommy-diary-p0-vendor-eval.md`。
