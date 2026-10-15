import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { randomBytes } from 'node:crypto';
import { createHandler } from '../src/app.js';
import { createAsrUpgrade } from '../src/asr.js';
import { loadConfig } from '../src/config.js';
import { signJwt } from '../src/jwt.js';
import { DailyLimiter } from '../src/rate_limit.js';
import { entry, errorFields, levelFor, requestId } from '../src/log.js';
import { sanitizeEvent, sanitizeBatch, MAX_EVENTS } from '../src/client_events.js';
import { fakeLlm } from './fake_llm.js';

const SECRET = 'test-secret-at-least-32-characters-long';
const JWT = signJwt({ sub: 'u1', role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 }, SECRET);
const RID = '3f2b6c1e-8d4a-4c3b-9e7f-0a1b2c3d4e5f';

async function server(fn, { llm = fakeLlm(['{"cards":[]}']), xfyun } = {}) {
  const logs = [];
  const base = loadConfig({ SUPABASE_JWT_SECRET: SECRET });
  const cfg = { ...base, xfyun: { ...base.xfyun, ...(xfyun ?? {}) } };
  const limiter = new DailyLimiter(cfg.limits);
  const log = (m) => logs.push(m);
  const srv = createServer(createHandler(cfg, { limiter, llm, log }));
  srv.on('upgrade', createAsrUpgrade(cfg, { limiter, log }));
  await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  try { await fn(`http://127.0.0.1:${srv.address().port}`, logs); } finally { srv.close(); }
}

test('entry：补 ts/level/svc，按状态码推断级别，丢掉 undefined', () => {
  const e = entry({ route: 'x', code: 503, a: undefined }, () => new Date('2026-10-15T00:00:00Z'));
  assert.deepEqual(e, { ts: '2026-10-15T00:00:00.000Z', level: 'error', svc: 'ai-gateway', route: 'x', code: 503 });
  assert.equal(levelFor(200), 'info');
  assert.equal(levelFor(401), 'warn');
  assert.equal(entry({ code: 200, level: 'warn' }).level, 'warn');
});

test('requestId：合法的沿用，不合法/缺失的重新生成', () => {
  assert.equal(requestId({ 'x-request-id': RID }), RID);
  assert.match(requestId({ 'x-request-id': 'bad id with spaces' }), /^[0-9a-f-]{36}$/);
  assert.match(requestId({}), /^[0-9a-f-]{36}$/);
});

test('errorFields：只取类型和位置，不取 message', () => {
  const f = errorFields(new TypeError('宝宝小明今天吃奶 secret'));
  assert.equal(f.err_name, 'TypeError');
  assert.ok(!JSON.stringify(f).includes('secret'));
  assert.ok(!JSON.stringify(f).includes('小明'));
});

test('HTTP：回写 x-request-id，日志里是同一个 id，且有 ts/level/svc', () => server(async (b, logs) => {
  const r = await fetch(b + '/healthz', { headers: { 'x-request-id': RID } });
  assert.equal(r.headers.get('x-request-id'), RID);
  assert.equal(logs[0].request_id, RID);
  assert.equal(logs[0].level, 'info');
  assert.equal(logs[0].svc, 'ai-gateway');
  assert.ok(!Number.isNaN(Date.parse(logs[0].ts)));
  const r2 = await fetch(b + '/healthz');
  assert.match(r2.headers.get('x-request-id'), /^[0-9a-f-]{36}$/);
}));

test('HTTP 4xx 带 err_code 且为 warn', () => server(async (b, logs) => {
  await fetch(b + '/diary-parse', { method: 'POST', body: '{}' });
  assert.equal(logs[0].code, 401);
  assert.equal(logs[0].level, 'warn');
  assert.equal(logs[0].err_code, 'unauthorized');
}));

test('未预期异常 → 500，日志有 err_code/err_name，不含 message 和用户文本', () => server(async (b, logs) => {
  const r = await fetch(b + '/diary-parse', {
    method: 'POST',
    headers: { authorization: `Bearer ${JWT}`, 'content-type': 'application/json' },
    body: JSON.stringify({ text: '小明今天吃奶6次', age_in_days: 10, now: '2026-10-15T08:00:00+08:00' }),
  });
  assert.equal(r.status, 500);
  const l = logs.at(-1);
  assert.equal(l.level, 'error');
  assert.equal(l.err_code, 'internal');
  assert.equal(l.err_name, 'RangeError');
  const line = JSON.stringify(logs);
  assert.ok(!line.includes('boom-secret'));
  assert.ok(!line.includes('小明'));
}, { llm: { model: 'x', configured: true, chat: async () => { throw new RangeError('boom-secret 小明'); } } }));

test('client-events：只保留白名单字段，丢掉文本/JWT/昵称等', () => {
  const e = sanitizeEvent({
    event: 'voice.asr.fail', outcome: 'fail', engine: 'cloud', err_code: 'ws_handshake_401', ms: 1200, audio_ms: 3000, chars: 0,
    request_id: RID, app_ver: '0.1.39-dev', os: 'android 14', net: 'wifi', consent_cloud: true, ts: '2026-10-15T08:00:00.000Z',
    text: '今天吃奶6次', nickname: '小明', invite_code: 'ABC123', jwt: JWT, authorization: `Bearer ${JWT}`, audio: 'AAAA', extra: { a: 1 },
  });
  assert.deepEqual(Object.keys(e).sort(), ['app_ver', 'audio_ms', 'chars', 'consent_cloud', 'engine', 'err_code', 'event', 'ms', 'net', 'os', 'outcome', 'request_id', 'ts']);
  // 格式不合法的值也丢掉（不能借合法字段夹带文本）
  const bad = sanitizeEvent({ event: 'voice.fail', err_code: '今天吃奶', app_ver: 'x'.repeat(40), os: 'android 小明', outcome: 'whatever', ms: -1 });
  assert.deepEqual(bad, { event: 'voice.fail' });
  assert.equal(sanitizeEvent({ text: 'x' }), null);
  assert.equal(sanitizeBatch({ events: Array(50).fill({ event: 'a.b' }) }).length, MAX_EVENTS);
});

test('client-events 路由：要 JWT；202 + 每个事件一行日志；日志里没有文本和 JWT', () => server(async (b, logs) => {
  const body = JSON.stringify({ events: [{ event: 'voice.asr.fail', outcome: 'fail', err_code: 'perm_denied', text: '小明哭了', jwt: JWT }, { nope: 1 }] });
  assert.equal((await fetch(b + '/client-events', { method: 'POST', body })).status, 401);
  const r = await fetch(b + '/client-events', { method: 'POST', headers: { authorization: `Bearer ${JWT}`, 'x-request-id': RID }, body });
  assert.equal(r.status, 202);
  assert.deepEqual(await r.json(), { accepted: 1 });
  const ev = logs.find((l) => l.event === 'voice.asr.fail');
  assert.equal(ev.err_code, 'perm_denied');
  assert.equal(ev.level, 'warn');
  assert.equal(ev.request_id, RID);
  assert.match(ev.uid_hash, /^[0-9a-f]{12}$/);
  const line = JSON.stringify(logs);
  assert.ok(!line.includes('小明'));
  assert.ok(!line.includes(JWT));
  assert.ok(!line.includes('"u1"'));
}));

test('WS /diary-asr 拒绝时也回写 x-request-id，日志带 request_id/err_code', () => server(async (b, logs) => {
  const u = new URL(b + '/diary-asr');
  const res = await new Promise((resolve, reject) => {
    const req = request({ hostname: u.hostname, port: u.port, path: u.pathname,
      headers: { Connection: 'Upgrade', Upgrade: 'websocket', 'Sec-WebSocket-Key': randomBytes(16).toString('base64'), 'Sec-WebSocket-Version': '13', 'x-request-id': RID } });
    req.on('response', resolve);
    req.on('error', reject);
    req.end();
  });
  assert.equal(res.statusCode, 401);
  assert.equal(res.headers['x-request-id'], RID);
  assert.equal(logs[0].request_id, RID);
  assert.equal(logs[0].err_code, 'unauthorized');
  assert.equal(logs[0].level, 'warn');
}, { xfyun: { appId: 'a', apiKey: 'k', apiSecret: 's', configured: true } }));
