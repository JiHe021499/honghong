import { verifySupabaseJwt } from './jwt.js';
import { DailyLimiter } from './rate_limit.js';

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

/**
 * 路由骨架（P0）。diary-parse / diary-summary 的业务逻辑在 P2 实现，当前返回 501。
 * 服务端不落库用户文本，只打匿名指标日志（路由、状态码、耗时）。
 */
export function createHandler(cfg, { limiter = new DailyLimiter(cfg.limits), log = (m) => console.log(JSON.stringify(m)) } = {}) {
  const routes = {
    'diary-parse': async (body) => {
      if (typeof body.text !== 'string' || !body.text.trim()) return [400, { error: 'text_required' }];
      if ([...body.text].length > cfg.maxTextChars) return [400, { error: 'text_too_long' }];
      return [501, { status: 'failed', error: 'not_implemented', phase: 'P2' }];
    },
    'diary-summary': async (body) => {
      if (typeof body.date !== 'string' || !body.stats) return [400, { error: 'bad_request' }];
      return [501, { error: 'not_implemented', phase: 'P2' }];
    },
  };

  return async (req, res) => {
    const t0 = Date.now();
    const path = new URL(req.url, 'http://x').pathname.replace(/^\/+/, '');
    const done = (code, body) => { json(res, code, body); log({ route: path, code, ms: Date.now() - t0 }); };
    try {
      if (req.method === 'GET' && path === 'healthz') return done(200, { ok: true, llm_configured: Boolean(cfg.llm.provider && cfg.llm.apiKey) });
      const handler = routes[path];
      if (!handler) return done(404, { error: 'not_found' });
      if (req.method !== 'POST') return done(405, { error: 'method_not_allowed' });
      let claims;
      try { claims = verifySupabaseJwt((req.headers.authorization ?? '').replace(/^Bearer\s+/i, ''), cfg.jwtSecret); }
      catch { return done(401, { error: 'unauthorized' }); }
      if (!limiter.take(claims.sub, path)) return done(429, { error: 'rate_limited' });
      let body;
      try { body = JSON.parse(await readBody(req, cfg.maxBodyBytes)); }
      catch (e) { return done(e.code === 413 ? 413 : 400, { error: e.code === 413 ? 'too_large' : 'bad_json' }); }
      const [code, out] = await handler(body ?? {}, claims);
      return done(code, out);
    } catch (e) {
      return done(500, { error: 'internal' });
    }
  };
}
