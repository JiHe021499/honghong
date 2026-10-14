import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHandler } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createLlm, LlmError } from '../src/llm.js';
import { signJwt } from '../src/jwt.js';
import { fakeLlm } from './fake_llm.js';

const SECRET = 'test-secret-at-least-32-characters-long';
const tok = (sub = 'u1') => signJwt({ sub, role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 }, SECRET);
async function serve(deps, fn, over = {}) {
  const cfg = { ...loadConfig({ SUPABASE_JWT_SECRET: SECRET }), ...over };
  const srv = createServer(createHandler(cfg, deps));
  await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  try { await fn(`http://127.0.0.1:${srv.address().port}`); } finally { srv.close(); }
}
const post = (b, p, body, t = tok()) => fetch(b + p, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${t}` }, body: JSON.stringify(body) });
const SUM = { date: '2026-10-14', age_in_days: 102, stats: { feed: { count: 4 } }, idempotency_key: 's-1' };
const PARSE = { text: '今天吃奶6次，下午哭得厉害', age_in_days: 102, now: '2026-10-14T20:31:00+08:00' };

test('diary-summary：同一 key 24h 内返回同一结果，只调一次模型，重放不占限流', async () => {
  const calls = [];
  await serve({ log: () => {}, llm: fakeLlm([JSON.stringify({ content: '今天吃了4次奶，辛苦啦' }), JSON.stringify({ content: '今天记录了4次喂奶' })], calls) }, async (b) => {
    const r1 = await (await post(b, '/diary-summary', SUM)).json();
    const r2 = await (await post(b, '/diary-summary', SUM)).json();
    const r3 = await (await post(b, '/diary-summary', SUM)).json();
    assert.deepEqual(r1, r2);
    assert.deepEqual(r1, r3);
    assert.equal(calls.length, 1);
    // 另一个用户同 key 不共享
    const other = await (await post(b, '/diary-summary', SUM, tok('u2'))).json();
    assert.equal(other.content, '今天记录了4次喂奶');
  }, { limits: { 'diary-summary': 1, 'diary-parse': 60 } });
});

test('diary-summary 参数校验', async () => {
  await serve({ log: () => {}, llm: fakeLlm(['{}']) }, async (b) => {
    assert.equal((await post(b, '/diary-summary', { ...SUM, date: '10/14' })).status, 400);
    assert.equal((await post(b, '/diary-summary', { ...SUM, idempotency_key: undefined })).status, 400);
    assert.equal((await post(b, '/diary-summary', { ...SUM, stats: { feed: { count: 'x' } } })).status, 400);
  });
});

test('parse 失败与上游故障的状态码', async () => {
  await serve({ log: () => {}, llm: fakeLlm(['nope']) }, async (b) => {
    const r = await post(b, '/diary-parse', PARSE);
    assert.equal(r.status, 502);
    assert.deepEqual(await r.json(), { status: 'failed', error: 'schema_invalid' });
  });
  await serve({ log: () => {}, llm: fakeLlm([new LlmError('llm_timeout')]) }, async (b) => {
    assert.deepEqual(await (await post(b, '/diary-parse', PARSE)).json(), { status: 'failed', error: 'llm_timeout' });
  });
});

test('日志不含用户原文，只有 hash/耗时/状态/prompt 版本', async () => {
  const logs = [];
  const reply = JSON.stringify({ cards: [{ category: 'feeding', kind: 'aggregate', time_period: 'all_day', attributes: { count: 6 }, note: '今天吃奶6次', confidence: 0.9 },
    { category: 'mood', kind: 'event', time_period: 'afternoon', attributes: { type: '哭闹' }, intensity: '厉害', note: '下午哭得厉害', confidence: 0.9 }] });
  await serve({ log: (m) => logs.push(JSON.stringify(m)), llm: fakeLlm([reply]) }, async (b) => {
    assert.equal((await post(b, '/diary-parse', PARSE)).status, 200);
  });
  assert.equal(logs.length, 1);
  assert.doesNotMatch(logs[0], /吃奶|哭/);
  const m = JSON.parse(logs[0]);
  assert.equal(m.prompt_version, 'parse-v2');
  assert.equal(m.status, 'ok');
  assert.match(m.text_hash, /^[0-9a-f]{12}$/);
});

test('LLM 客户端：json_object 请求、超时、HTTP 错误不泄露 Key', async () => {
  let req;
  const llm = createLlm({ apiKey: 'sk-secret', baseUrl: 'https://api.deepseek.com/', model: 'deepseek-chat', timeoutMs: 50 }, {
    fetchImpl: async (url, init) => { req = { url, init }; return new Response(JSON.stringify({ choices: [{ message: { content: '{"cards":[]}' } }] })); },
  });
  assert.equal(await llm.chat([{ role: 'user', content: 'x' }]), '{"cards":[]}');
  assert.equal(req.url, 'https://api.deepseek.com/chat/completions');
  const body = JSON.parse(req.init.body);
  assert.deepEqual(body.response_format, { type: 'json_object' });
  assert.equal(body.model, 'deepseek-chat');

  const slow = createLlm({ apiKey: 'sk-secret', baseUrl: 'http://x', model: 'm', timeoutMs: 20 }, {
    fetchImpl: (_u, init) => new Promise((_r, rej) => init.signal.addEventListener('abort', () => rej(Object.assign(new Error('a'), { name: 'AbortError' })))),
  });
  await assert.rejects(slow.chat([]), (e) => e.code === 'llm_timeout' && !String(e.message).includes('sk-secret'));
  const bad = createLlm({ apiKey: 'sk-secret', baseUrl: 'http://x', model: 'm', timeoutMs: 50 }, { fetchImpl: async () => new Response('denied sk-secret', { status: 401 }) });
  await assert.rejects(bad.chat([]), (e) => e.code === 'llm_http' && !e.message.includes('sk-secret'));
});
