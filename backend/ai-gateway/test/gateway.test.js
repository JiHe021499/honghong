import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHandler } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { signJwt, verifySupabaseJwt } from '../src/jwt.js';
import { DailyLimiter } from '../src/rate_limit.js';

const SECRET = 'test-secret-at-least-32-characters-long';
const user = (sub = 'u1', extra = {}) => signJwt({ sub, role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600, ...extra }, SECRET);

async function withServer(cfgOverride, fn) {
  const cfg = { ...loadConfig({ SUPABASE_JWT_SECRET: SECRET }), ...cfgOverride };
  const srv = createServer(createHandler(cfg, { log: () => {} }));
  await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${srv.address().port}`;
  try { await fn(base); } finally { srv.close(); }
}
const post = (base, path, body, token) => fetch(base + path, { method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: typeof body === 'string' ? body : JSON.stringify(body) });

test('healthz 可访问且报告 LLM 未配置', () => withServer({}, async (b) => {
  const r = await fetch(b + '/healthz');
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { ok: true, llm_configured: false });
}));

test('无 token / 错签名 / 过期 / anon 角色 均 401', () => withServer({}, async (b) => {
  assert.equal((await post(b, '/diary-parse', { text: 'x' })).status, 401);
  assert.equal((await post(b, '/diary-parse', { text: 'x' }, signJwt({ sub: 'u', role: 'authenticated' }, 'wrong'))).status, 401);
  assert.equal((await post(b, '/diary-parse', { text: 'x' }, user('u', { exp: 1 }))).status, 401);
  assert.equal((await post(b, '/diary-parse', { text: 'x' }, signJwt({ role: 'anon' }, SECRET))).status, 401);
}));

test('diary-parse 参数校验与 P2 占位', () => withServer({}, async (b) => {
  const t = user();
  assert.equal((await post(b, '/diary-parse', {}, t)).status, 400);
  assert.equal((await post(b, '/diary-parse', { text: '奶'.repeat(501) }, t)).status, 400);
  assert.equal((await post(b, '/diary-parse', '{bad', t)).status, 400);
  const r = await post(b, '/diary-parse', { text: '今天吃奶6次' }, t);
  assert.equal(r.status, 501);
  assert.equal((await r.json()).phase, 'P2');
}));

test('请求体超限 413、未知路由 404、GET 业务路由 405', () => withServer({ maxBodyBytes: 100 }, async (b) => {
  assert.equal((await post(b, '/diary-parse', { text: 'a'.repeat(200) }, user())).status, 413);
  assert.equal((await fetch(b + '/nope')).status, 404);
  assert.equal((await fetch(b + '/diary-parse')).status, 405);
}));

test('按用户按日限流 429', () => withServer({ limits: { 'diary-summary': 2 } }, async (b) => {
  const body = { date: '2026-10-14', stats: {} };
  assert.equal((await post(b, '/diary-summary', body, user('a'))).status, 501);
  assert.equal((await post(b, '/diary-summary', body, user('a'))).status, 501);
  assert.equal((await post(b, '/diary-summary', body, user('a'))).status, 429);
  assert.equal((await post(b, '/diary-summary', body, user('b'))).status, 501);
}));

test('限流在上海时区跨日重置', () => {
  let now = new Date('2026-10-14T15:59:00Z'); // 23:59 +08
  const l = new DailyLimiter({ r: 1 }, () => now);
  assert.equal(l.take('u', 'r'), true);
  assert.equal(l.take('u', 'r'), false);
  now = new Date('2026-10-14T16:01:00Z'); // 次日 00:01 +08
  assert.equal(l.take('u', 'r'), true);
});

test('JWT 拒绝非 HS256', () => {
  const h = Buffer.from(JSON.stringify({ alg: 'none' })).toString('base64url');
  const p = Buffer.from(JSON.stringify({ sub: 'u', role: 'authenticated' })).toString('base64url');
  assert.throws(() => verifySupabaseJwt(`${h}.${p}.`, SECRET), /bad_alg/);
});
