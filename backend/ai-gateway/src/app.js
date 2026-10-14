import { createHash } from 'node:crypto';
import { verifySupabaseJwt } from './jwt.js';
import { DailyLimiter } from './rate_limit.js';
import { createLlm, LlmError } from './llm.js';
import { parseDiary, ParseFailed } from './parse.js';
import { normalizeStats, summarize } from './summary.js';

const json = (res, code, body) => {
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
};

function readBody(req, max) {
  return new Promise((resolve, reject) => {
    const tooLarge = () => Object.assign(new Error('too_large'), { code: 413 });
    if (Number(req.headers['content-length'] ?? 0) > max) { req.resume(); return reject(tooLarge()); }
    let size = 0; let over = false; const chunks = [];
    req.on('data', (c) => { size += c.length; if (size > max) over = true; else if (!over) chunks.push(c); });
    req.on('end', () => (over ? reject(tooLarge()) : resolve(Buffer.concat(chunks).toString('utf8'))));
    req.on('error', reject);
  });
}

const hash = (s) => createHash('sha256').update(s).digest('hex').slice(0, 12);
const ISO_WITH_TZ = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?([+-]\d{2}:\d{2}|Z)$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const validAge = (v) => Number.isInteger(v) && v >= 0 && v <= 3 * 366;

/** 24h 幂等缓存（按用户 + idempotency_key）。单实例内存实现。 */
class IdemCache {
  constructor(ttl, now = () => Date.now()) { this.ttl = ttl; this.now = now; this.m = new Map(); }
  get(k) { const e = this.m.get(k); if (!e) return undefined; if (this.now() - e.at > this.ttl) { this.m.delete(k); return undefined; } return e.v; }
  set(k, v) { this.m.set(k, { v, at: this.now() }); if (this.m.size > 50000) this.m.delete(this.m.keys().next().value); }
}

/**
 * 路由：diary-parse / diary-summary。
 * 服务端不落库、不打印用户文本，日志只记文本 hash、耗时、状态、prompt 版本。
 */
export function createHandler(cfg, {
  limiter = new DailyLimiter(cfg.limits),
  llm = createLlm(cfg.llm),
  idem = new IdemCache(cfg.idempotencyTtlMs ?? 24 * 3600 * 1000),
  log = (m) => console.log(JSON.stringify(m)),
} = {}) {
  const llmError = (e) => {
    if (e instanceof LlmError) return e.code === 'llm_not_configured' ? [503, { status: 'failed', error: 'llm_not_configured' }] : [502, { status: 'failed', error: e.code }];
    throw e;
  };

  const routes = {
    'diary-parse': async (body, _claims, meta) => {
      if (typeof body.text !== 'string' || !body.text.trim()) return [400, { error: 'text_required' }];
      if ([...body.text].length > cfg.maxTextChars) return [400, { error: 'text_too_long' }];
      if (!validAge(body.age_in_days)) return [400, { error: 'bad_age_in_days' }];
      if (typeof body.now !== 'string' || !ISO_WITH_TZ.test(body.now)) return [400, { error: 'bad_now' }];
      meta.text_hash = hash(body.text);
      try {
        const out = await parseDiary(llm, { text: body.text.trim(), ageInDays: body.age_in_days, now: body.now }, { onAttempt: (n) => { meta.attempts = n; } });
        meta.status = out.status; meta.prompt_version = out.prompt_version; meta.cards = out.cards.length;
        return [200, out];
      } catch (e) {
        if (e instanceof ParseFailed) { meta.status = 'failed'; return [502, { status: 'failed', error: e.reason }]; }
        return llmError(e);
      }
    },
    'diary-summary': async (body, claims, meta) => {
      if (typeof body.date !== 'string' || !DATE.test(body.date)) return [400, { error: 'bad_date' }];
      if (body.age_in_days !== undefined && !validAge(body.age_in_days)) return [400, { error: 'bad_age_in_days' }];
      if (typeof body.idempotency_key !== 'string' || !body.idempotency_key || body.idempotency_key.length > 64) return [400, { error: 'bad_idempotency_key' }];
      const stats = normalizeStats(body.stats);
      if (!stats) return [400, { error: 'bad_stats' }];
      try {
        const out = await summarize(llm, { date: body.date, ageInDays: body.age_in_days, stats });
        meta.prompt_version = out.prompt_version; meta.fallback = out.fallback;
        const resp = { content: out.content, prompt_version: out.prompt_version };
        idem.set(`${claims.sub}:${body.idempotency_key}`, resp);
        return [200, resp];
      } catch (e) { return llmError(e); }
    },
  };

  return async (req, res) => {
    const t0 = Date.now();
    const path = new URL(req.url, 'http://x').pathname.replace(/^\/+/, '');
    const meta = {};
    const done = (code, body) => { json(res, code, body); log({ route: path, code, ms: Date.now() - t0, ...meta }); };
    try {
      if (req.method === 'GET' && path === 'healthz') return done(200, { ok: true, llm_configured: llm.configured, asr_configured: Boolean(cfg.xfyun?.configured) });
      const handler = routes[path];
      if (!handler) return done(404, { error: 'not_found' });
      if (req.method !== 'POST') return done(405, { error: 'method_not_allowed' });
      let claims;
      try { claims = verifySupabaseJwt((req.headers.authorization ?? '').replace(/^Bearer\s+/i, ''), cfg.jwtSecret); }
      catch { return done(401, { error: 'unauthorized' }); }
      let body;
      try { body = JSON.parse(await readBody(req, cfg.maxBodyBytes)); }
      catch (e) { return done(e.code === 413 ? 413 : 400, { error: e.code === 413 ? 'too_large' : 'bad_json' }); }
      if (!body || typeof body !== 'object' || Array.isArray(body)) return done(400, { error: 'bad_json' });
      // 幂等重放不计入限流
      if (path === 'diary-summary' && typeof body.idempotency_key === 'string') {
        const hit = idem.get(`${claims.sub}:${body.idempotency_key}`);
        if (hit) { meta.idempotent_hit = true; return done(200, hit); }
      }
      if (!limiter.take(claims.sub, path)) return done(429, { error: 'rate_limited' });
      const [code, out] = await handler(body, claims, meta);
      return done(code, out);
    } catch {
      return done(500, { error: 'internal' });
    }
  };
}
