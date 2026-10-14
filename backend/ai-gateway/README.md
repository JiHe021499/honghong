# ai-gateway（妈咪日记 AI 网关）

独立轻量 Node 服务（零第三方依赖，Node ≥ 20），挂在 Caddy 后，校验自建 Supabase 签发的匿名登录 JWT（架构 D10）。LLM 密钥只放在这里，不进 App。

| 接口 | 状态 |
|---|---|
| `GET /healthz` | ✅ 返回 `{ ok, llm_configured }` |
| `POST /diary-parse` | ✅ P2：DeepSeek json_object + 提示词内 schema，强制校验、不合规重试一次；清洗（未知键丢弃、越界置空降置信度、诊断词回退原文）、原文覆盖补卡、风险词；限流 60 次/天/用户 |
| `POST /diary-summary` | ✅ P2：只收聚合统计；≤50 字、无诊断词、不出现统计外数字，不合规重试一次后模板兜底；`idempotency_key` 24h 幂等（重放不占限流）；限流 3 次/天/用户 |
| `GET /diary-asr`（WebSocket） | ✅ 讯飞「语音听写（流式版）」中转，本机识别不可用时的兜底（D9 修订）。客户端发 16k PCM 二进制帧 + `{"type":"end"}`，收 partial/final/error；音频只在内存转发；60 次/天/人，单次 ≤60s；未配置 `XFYUN_*` 返回 503 |

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

## 讯飞联网识别
环境变量：`XFYUN_APPID`、`XFYUN_API_KEY`、`XFYUN_API_SECRET`（只放服务器 `.env`，不进仓库）。可选 `LIMIT_ASR_PER_DAY`（默认 60）。
反向代理需转发 WebSocket Upgrade 头，见架构文档 §4.4。本机联调：
```bash
SUPABASE_JWT_SECRET=$S XFYUN_APPID=... XFYUN_API_KEY=... XFYUN_API_SECRET=... npm start
ASR_SMOKE_JWT_SECRET=$S node eval/asr_smoke.js /tmp/a.pcm   # 16k/16bit/单声道 PCM
```

## 评测
供应商：DeepSeek `deepseek-chat`（用户已选，json_object 降级方案）。Key 只放环境变量 `DEEPSEEK_API_KEY` / 服务器 `.env`。
```bash
DEEPSEEK_API_KEY=... npm run eval -- --out /tmp/results.json
```
结果见 `eval/REPORT.md`。

状态码：400 参数错误；401 鉴权失败；429 限流；502 上游超时/错误或两次 schema 不合规（`{status:"failed", error}`，客户端按屏 14 兜底）；503 未配置 Key。
