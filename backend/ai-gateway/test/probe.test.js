import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createAsrUpgrade } from '../src/asr.js';
import { createHandler } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { DailyLimiter } from '../src/rate_limit.js';
import { evaluate, run, synthPcm, webhookBody } from '../eval/probe.js';
import { startFakeXfyun } from './fake_xfyun.js';
import { fakeLlm } from './fake_llm.js';

const SECRET = 'test-secret-at-least-32-characters-long';
const FAKE = { appId: 'app-fake', apiKey: 'k'.repeat(32), apiSecret: 's'.repeat(32) };

test('evaluate：连续 2 次失败才告警一次，恢复时发恢复通知', () => {
  let s = null;
  let r = evaluate(s, false); assert.equal(r.alert, null); s = r.state;
  r = evaluate(s, false); assert.equal(r.alert, 'down'); s = r.state;
  r = evaluate(s, false); assert.equal(r.alert, null, '已告警不重复'); s = r.state;
  r = evaluate(s, true); assert.equal(r.alert, 'up'); s = r.state;
  r = evaluate(s, true); assert.equal(r.alert, null);
  assert.equal(evaluate(null, true).alert, null, '没告警过的成功不发恢复');
});

test('webhookBody：通用 / 文本 / 飞书格式', () => {
  assert.deepEqual(webhookBody('generic', 'hi', { status: 'down' }), { text: 'hi', status: 'down' });
  assert.deepEqual(webhookBody('text', 'hi'), { msgtype: 'text', text: { content: 'hi' } });
  assert.deepEqual(webhookBody('feishu', 'hi'), { msg_type: 'text', content: { text: 'hi' } });
});

test('synthPcm：16k/16bit 2 秒 = 64000 字节', () => assert.equal(synthPcm(2000).length, 64000));

async function listen(srv) { await new Promise((r) => srv.listen(0, '127.0.0.1', r)); return srv.address().port; }

async function gateway(xfyun, logs = []) {
  const base = loadConfig({ SUPABASE_JWT_SECRET: SECRET, PROBE_SUBS: 'hh-probe' });
  const cfg = { ...base, xfyun: { ...base.xfyun, ...xfyun } };
  cfg.xfyun.configured = Boolean(cfg.xfyun.appId && cfg.xfyun.apiKey && cfg.xfyun.apiSecret);
  const limiter = new DailyLimiter({ ...cfg.limits, 'diary-asr': 0 }); // 普通桶为 0：探测必须走单独的桶
  const srv = createServer(createHandler(cfg, { limiter, llm: fakeLlm(['{}']), log: (m) => logs.push(m) }));
  srv.on('upgrade', createAsrUpgrade(cfg, { limiter, log: (m) => logs.push(m) }));
  const port = await listen(srv);
  return { srv, base: `http://127.0.0.1:${port}/` };
}

test('端到端：正常 → ok；讯飞 key 错 → 连续 2 次失败告警；网关停了 → 失败；恢复 → 恢复通知', async () => {
  const xf = await startFakeXfyun(FAKE);
  const hooks = [];
  const hook = createServer((req, res) => { let b = ''; req.on('data', (c) => { b += c; }); req.on('end', () => { hooks.push(JSON.parse(b)); res.end('ok'); }); });
  const hookPort = await listen(hook);
  const dir = mkdtempSync(join(tmpdir(), 'probe-'));
  const env = (base) => ({ PROBE_BASE_URL: base, PROBE_JWT_SECRET: SECRET, PROBE_STATE_FILE: join(dir, 's.json'), ALERT_WEBHOOK_URL: `http://127.0.0.1:${hookPort}/`, PROBE_SOURCE: 'test' });
  const log = console.log; console.log = () => {};
  try {
    const logs = [];
    let g = await gateway({ ...FAKE, url: xf.url }, logs);
    let r = await run(env(g.base));
    assert.equal(r.ok, true, JSON.stringify(r));
    assert.equal(r.stage, 'done');
    assert.ok(logs.some((l) => l.route === 'diary-asr' && l.probe === true && l.request_id === r.request_id), '网关日志里有同一个 request_id，且标了 probe');
    g.srv.close();

    // 讯飞 key 改错
    g = await gateway({ ...FAKE, apiKey: 'x'.repeat(32), url: xf.url });
    r = await run(env(g.base));
    assert.equal(r.ok, false);
    assert.equal(r.stage, 'asr');
    assert.match(r.err_code, /^asr_error_upstream/);
    assert.equal(hooks.length, 0, '第一次失败不告警');
    g.srv.close();

    // 网关停了
    r = await run(env(g.base));
    assert.equal(r.ok, false);
    assert.equal(r.stage, 'exception');
    assert.equal(r.alert, 'down');
    assert.equal(hooks.length, 1);
    assert.equal(hooks[0].status, 'down');
    assert.match(hooks[0].text, /连续失败/);

    // ASR 未配置：healthz 断言失败
    g = await gateway({ appId: '', apiKey: '', apiSecret: '' });
    r = await run(env(g.base));
    assert.equal(r.err_code, 'asr_not_configured');
    assert.equal(hooks.length, 1, '已告警不重复');
    g.srv.close();

    // 恢复
    g = await gateway({ ...FAKE, url: xf.url });
    r = await run(env(g.base));
    assert.equal(r.ok, true);
    assert.equal(r.alert, 'up');
    assert.equal(hooks.length, 2);
    assert.equal(hooks[1].status, 'up');
    g.srv.close();
  } finally { console.log = log; xf.close(); hook.close(); }
});
