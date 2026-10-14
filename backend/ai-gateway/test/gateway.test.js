import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHandler } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { signJwt, verifySupabaseJwt } from '../src/jwt.js';
import { DailyLimiter } from '../src/rate_limit.js';
import { fakeLlm } from './fake_llm.js';

const SECRET = 'test-secret-at-least-32-characters-long';
const user = (sub = 'u1', extra = {}) => signJwt({ sub, role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600, ...extra }, SECRET);

const OK_PARSE = JSON.stringify({ cards: [{ category: 'feeding', kind: 'aggregate', time_period: 'all_day', attributes: { count: 6 }, note: '今天吃奶6次', confidence: 0.9 }] });

async function withServer(cfgOverride, fn, deps = {}) {
  const cfg = { ...loadConfig({ SUPABASE_JWT_SECRET: SECRET }), ...cfgOverride };
  const srv = createServer(createHandler(cfg, { log: () => {}, llm: fakeLlm([OK_PARSE]), ...deps }));
  await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${srv.address().port}`;
  try { await fn(base); } finally { srv.close(); }
}
const PARSE_BODY = { text: '今天吃奶6次', age_in_days: 102, now: '2026-10-14T20:31:00+08:00', input_type: 'voice' };
const post = (base, path, body, token) => fetch(base + path, { method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: typeof body === 'string' ? body : JSON.stringify(body) });

test('healthz 可访问且报告 LLM 是否配置', () => withServer({}, async (b) => {
  const r = await fetch(b + '/healthz');
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { ok: true, llm_configured: true, asr_configured: false });
}));

test('未配置 Key 时 healthz 报未配置，parse 返回 503', async () => {
  const { createLlm } = await import('../src/llm.js');
  await withServer({}, async (b) => {
    assert.equal((await (await fetch(b + '/healthz')).json()).llm_configured, false);
    const r = await post(b, '/diary-parse', PARSE_BODY, user());
    assert.equal(r.status, 503);
  }, { llm: createLlm({ apiKey: '', baseUrl: 'http://x', model: 'm', timeoutMs: 100 }) });
});

test('无 token / 错签名 / 过期 / anon 角色 均 401', () => withServer({}, async (b) => {
  assert.equal((await post(b, '/diary-parse', PARSE_BODY)).status, 401);
  assert.equal((await post(b, '/diary-parse', PARSE_BODY, signJwt({ sub: 'u', role: 'authenticated' }, 'wrong'))).status, 401);
  assert.equal((await post(b, '/diary-parse', PARSE_BODY, user('u', { exp: 1 }))).status, 401);
  assert.equal((await post(b, '/diary-parse', PARSE_BODY, signJwt({ role: 'anon' }, SECRET))).status, 401);
}));

test('diary-parse 参数校验与正常返回', () => withServer({}, async (b) => {
  const t = user();
  assert.equal((await post(b, '/diary-parse', {}, t)).status, 400);
  assert.equal((await post(b, '/diary-parse', { ...PARSE_BODY, text: '奶'.repeat(501) }, t)).status, 400);
  assert.equal((await post(b, '/diary-parse', { ...PARSE_BODY, now: '2026-10-14T20:31:00' }, t)).status, 400, 'now 必须带时区');
  assert.equal((await post(b, '/diary-parse', { ...PARSE_BODY, age_in_days: -1 }, t)).status, 400);
  assert.equal((await post(b, '/diary-parse', '{bad', t)).status, 400);
  const r = await post(b, '/diary-parse', PARSE_BODY, t);
  assert.equal(r.status, 200);
  const j = await r.json();
  assert.equal(j.status, 'ok');
  assert.equal(j.prompt_version, 'parse-v2');
  assert.equal(j.cards[0].attributes.count, 6);
  assert.deepEqual(j.risk, { hit: false, words: [] });
}));

test('请求体超限 413、未知路由 404、GET 业务路由 405', () => withServer({ maxBodyBytes: 100 }, async (b) => {
  assert.equal((await post(b, '/diary-parse', { ...PARSE_BODY, text: 'a'.repeat(200) }, user())).status, 413);
  assert.equal((await fetch(b + '/nope')).status, 404);
  assert.equal((await fetch(b + '/diary-parse')).status, 405);
}));

test('按用户按日限流 429', () => withServer({ limits: { 'diary-parse': 2 } }, async (b) => {
  assert.equal((await post(b, '/diary-parse', PARSE_BODY, user('a'))).status, 200);
  assert.equal((await post(b, '/diary-parse', PARSE_BODY, user('a'))).status, 200);
  assert.equal((await post(b, '/diary-parse', PARSE_BODY, user('a'))).status, 429);
  assert.equal((await post(b, '/diary-parse', PARSE_BODY, user('b'))).status, 200);
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
