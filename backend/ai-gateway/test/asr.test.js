import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createAsrUpgrade } from '../src/asr.js';
import { createHandler } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { signJwt } from '../src/jwt.js';
import { DailyLimiter } from '../src/rate_limit.js';
import { connectWs } from '../src/ws.js';
import { ResultAssembler, authorization, signature, signedUrl } from '../src/xfyun.js';
import { startFakeXfyun } from './fake_xfyun.js';

const SECRET = 'test-secret-at-least-32-characters-long';
const tok = (sub = 'u1') => signJwt({ sub, role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 }, SECRET);
const FAKE = { appId: 'app-fake', apiKey: 'k'.repeat(32), apiSecret: 's'.repeat(32) };

test('签名与官方文档示例一致', () => {
  // https://www.xfyun.cn/doc/asr/voicedictation/API.html 接口鉴权一节的示例
  const sig = signature({ host: 'iat-api.xfyun.cn', date: 'Wed, 10 Jul 2019 07:35:43 GMT', path: '/v2/iat', apiSecret: 'secretxxxxxxxx2df7900c09xxxxxxxx' });
  assert.equal(sig, 'Hp3Ty4ZkSBmL8jKyOLpQiv9Sr5nvmeYEH7WsL/ZO2Jg=');
  assert.equal(authorization({ apiKey: 'keyxxxxxxxx8ee279348519exxxxxxxx', signature: sig }),
    'YXBpX2tleT0ia2V5eHh4eHh4eHg4ZWUyNzkzNDg1MTlleHh4eHh4eHgiLCBhbGdvcml0aG09ImhtYWMtc2hhMjU2IiwgaGVhZGVycz0iaG9zdCBkYXRlIHJlcXVlc3QtbGluZSIsIHNpZ25hdHVyZT0iSHAzVHk0WmtTQm1MOGpLeU9McFFpdjlTcjVudm1lWUVIN1dzTC9aTzJKZz0i');
  const u = new URL(signedUrl({ apiKey: 'k', apiSecret: 's', date: 'Wed, 10 Jul 2019 07:35:43 GMT' }));
  assert.equal(u.origin + u.pathname, 'wss://iat-api.xfyun.cn/v2/iat');
  assert.equal(u.searchParams.get('host'), 'iat-api.xfyun.cn');
  assert.equal(u.searchParams.get('date'), 'Wed, 10 Jul 2019 07:35:43 GMT');
});

test('动态修正结果拼接：apd 追加，rpl 替换 rg 范围', () => {
  const a = new ResultAssembler();
  a.push({ sn: 1, pgs: 'apd', ws: [{ cw: [{ w: '今天' }] }] });
  a.push({ sn: 2, pgs: 'rpl', rg: [1, 1], ws: [{ cw: [{ w: '今天' }] }, { cw: [{ w: '吃奶' }] }] });
  assert.equal(a.push({ sn: 3, pgs: 'apd', ws: [{ cw: [{ w: '六次。' }] }] }), '今天吃奶六次。');
});

async function gateway(over, fn) {
  const logs = [];
  const base = loadConfig({ SUPABASE_JWT_SECRET: SECRET });
  const cfg = { ...base, ...over, xfyun: { ...base.xfyun, ...(over.xfyun ?? {}) } };
  cfg.xfyun.configured = Boolean(cfg.xfyun.appId && cfg.xfyun.apiKey && cfg.xfyun.apiSecret);
  const limiter = new DailyLimiter(cfg.limits);
  const srv = createServer(createHandler(cfg, { limiter, log: () => {} }));
  srv.on('upgrade', createAsrUpgrade(cfg, { limiter, log: (m) => logs.push(m) }));
  await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  try { await fn(`ws://127.0.0.1:${srv.address().port}`, logs); } finally { srv.close(); }
}

/** 连上网关并收集消息；带 Authorization 头需要自己发握手，这里给 connectWs 加头 */
async function dial(base, token, path = '/diary-asr') {
  const { request } = await import('node:http');
  const { randomBytes } = await import('node:crypto');
  const { WsConn } = await import('../src/ws.js');
  const u = new URL(base + path);
  return new Promise((resolve, reject) => {
    const req = request({ hostname: u.hostname, port: u.port, path: u.pathname,
      headers: { Connection: 'Upgrade', Upgrade: 'websocket', 'Sec-WebSocket-Key': randomBytes(16).toString('base64'), 'Sec-WebSocket-Version': '13', ...(token ? { Authorization: `Bearer ${token}` } : {}) } });
    req.on('upgrade', (_res, socket, head) => {
      const ws = new WsConn(socket, { client: true, head });
      const msgs = [];
      ws.on('message', (m) => msgs.push(JSON.parse(m)));
      ws.closedP = new Promise((r) => ws.on('close', (code) => r(code)));
      ws.msgs = msgs;
      resolve(ws);
    });
    req.on('response', (res) => resolve({ status: res.statusCode }));
    req.on('error', reject);
    req.end();
  });
}

const pcm = (ms) => Buffer.alloc(32 * ms, 1); // 16k*16bit = 32 字节/毫秒

test('端到端（假讯飞）：签名通过、分帧 ≤1280 字节、返回 partial/final、日志不含文本', async () => {
  const xf = await startFakeXfyun(FAKE);
  try {
    await gateway({ xfyun: { ...FAKE, url: xf.url } }, async (b, logs) => {
      const ws = await dial(b, tok());
      for (let i = 0; i < 10; i++) ws.send(pcm(100)); // 1 秒，分 10 次发，每次 3200 字节
      ws.send(JSON.stringify({ type: 'end' }));
      await ws.closedP;
      assert.equal(xf.seen.badAuth, 0);
      assert.equal(xf.seen.bytes, 32000);
      assert.equal(xf.seen.frames[0], 0);
      assert.equal(xf.seen.frames.at(-1), 2);
      assert.ok(xf.seen.frames.slice(1, -1).every((s) => s === 1));
      const fin = ws.msgs.find((m) => m.type === 'final');
      assert.equal(fin.text, '今天吃奶六次');
      assert.ok(ws.msgs.some((m) => m.type === 'partial'));
      const line = JSON.stringify(logs);
      assert.ok(!line.includes('今天'));
      assert.deepEqual(Object.keys(logs[0]).sort(), ['audio_ms', 'code', 'level', 'ms', 'request_id', 'route', 'status', 'svc', 'ts']);
      assert.equal(logs[0].level, 'info');
      assert.equal(logs[0].audio_ms, 1000);
      assert.equal(logs[0].status, 'ok');
    });
  } finally { xf.close(); }
});

test('单次最长 60 秒：超出部分不转发，自动收尾', async () => {
  const xf = await startFakeXfyun(FAKE);
  try {
    await gateway({ xfyun: { ...FAKE, url: xf.url } }, async (b, logs) => {
      const ws = await dial(b, tok());
      for (let i = 0; i < 65; i++) ws.send(pcm(1000));
      await ws.closedP;
      assert.equal(xf.seen.bytes, 32000 * 60);
      assert.equal(logs[0].audio_ms, 60000);
      assert.ok(ws.msgs.some((m) => m.type === 'final'));
    });
  } finally { xf.close(); }
});

test('未配置凭证 → 503；无 JWT → 401；超出每天 60 次 → 429', async () => {
  await gateway({}, async (b) => {
    assert.equal((await dial(b, tok())).status, 503);
  });
  const xf = await startFakeXfyun(FAKE);
  try {
    await gateway({ xfyun: { ...FAKE, url: xf.url }, limits: { 'diary-parse': 60, 'diary-summary': 3, 'diary-asr': 2 } }, async (b) => {
      assert.equal((await dial(b, null)).status, 401);
      assert.equal((await dial(b, 'bad.token.x')).status, 401);
      for (let i = 0; i < 2; i++) { const ws = await dial(b, tok()); ws.close(); await ws.closedP; }
      assert.equal((await dial(b, tok())).status, 429);
      assert.notEqual((await dial(b, tok('u2'))).status, 429); // 按人计
    });
  } finally { xf.close(); }
});

test('默认限流 60 次/天，按北京时间分日', () => {
  const cfg = loadConfig({});
  assert.equal(cfg.limits['diary-asr'], 60);
  let now = new Date('2026-10-14T15:59:00Z'); // 北京 23:59
  const l = new DailyLimiter({ 'diary-asr': 1 }, () => now);
  assert.equal(l.take('u', 'diary-asr'), true);
  assert.equal(l.take('u', 'diary-asr'), false);
  now = new Date('2026-10-14T16:00:00Z'); // 北京次日 00:00
  assert.equal(l.take('u', 'diary-asr'), true);
});

test('讯飞报错（签名不对 / 错误码）→ 客户端收到 error 并关闭', async () => {
  const xf = await startFakeXfyun({ ...FAKE, apiSecret: 'other'.repeat(7) });
  try {
    await gateway({ xfyun: { ...FAKE, url: xf.url } }, async (b, logs) => {
      const ws = await dial(b, tok());
      ws.send(pcm(200));
      ws.send(JSON.stringify({ type: 'end' }));
      await ws.closedP;
      assert.deepEqual(ws.msgs.at(-1), { type: 'error', error: 'upstream' });
      assert.equal(logs[0].status, 'upstream_401');
    });
  } finally { xf.close(); }
  const xf2 = await startFakeXfyun({ ...FAKE, failCode: 11201 });
  try {
    await gateway({ xfyun: { ...FAKE, url: xf2.url } }, async (b) => {
      const ws = await dial(b, tok());
      ws.send(pcm(200));
      ws.send(JSON.stringify({ type: 'end' }));
      await ws.closedP;
      assert.deepEqual(ws.msgs.at(-1), { type: 'error', error: 'upstream_quota' });
    });
  } finally { xf2.close(); }
});

test('用户取消（直接断开）：不再等结果，日志记 cancelled', async () => {
  const xf = await startFakeXfyun(FAKE);
  try {
    await gateway({ xfyun: { ...FAKE, url: xf.url } }, async (b, logs) => {
      const ws = await dial(b, tok());
      ws.send(pcm(300));
      await new Promise((r) => setTimeout(r, 50));
      ws.close();
      await ws.closedP;
      await new Promise((r) => setTimeout(r, 50));
      assert.equal(logs[0].status, 'cancelled');
    });
  } finally { xf.close(); }
});

test('healthz 报告 asr_configured，但不泄露凭证', async () => {
  const cfg = { ...loadConfig({ SUPABASE_JWT_SECRET: SECRET, XFYUN_APPID: 'a', XFYUN_API_KEY: 'b', XFYUN_API_SECRET: 'c' }) };
  const srv = createServer(createHandler(cfg, { log: () => {} }));
  await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  try {
    const t = await (await fetch(`http://127.0.0.1:${srv.address().port}/healthz`)).text();
    assert.equal(JSON.parse(t).asr_configured, true);
    assert.ok(!t.includes('"b"') && !t.includes('"c"'));
  } finally { srv.close(); }
  void connectWs;
});
