// ASR 合成探测（日志方案 P0）：基于 eval/asr_smoke.js。每 5 分钟跑一次（服务器 cron + GitHub Actions 各一份）。
//   1) GET <base>/healthz：必须 ok 且 asr_configured=true（PROBE_REQUIRE_LLM=1 时还要 llm_configured=true）
//   2) WSS <base>/diary-asr：发 2 秒合成的非人声 PCM（低音量正弦波），发 end，必须收到 {"type":"final"}
// 输出一行 JSON 结果；失败退出码 1。连续失败达到阈值（默认 2）时告警一次，恢复后发恢复通知。
//
// 环境变量：
//   PROBE_BASE_URL       必填，例如 https://<host>/ai/
//   PROBE_JWT            探测账号的 JWT（推荐：在服务器上一次性签发，sub 写进网关 PROBE_SUBS）
//   PROBE_JWT_SECRET     或者：用网关的 SUPABASE_JWT_SECRET 现签（只建议在服务器本机 cron 用，别放到外部 CI）
//   PROBE_SUB            现签时的 sub，默认 hh-probe
//   PROBE_STATE_FILE     连续失败计数状态文件，默认 /tmp/hh-asr-probe.json
//   PROBE_FAIL_THRESHOLD 连续失败几次告警，默认 2
//   PROBE_REQUIRE_LLM    1 = healthz 也要求 llm_configured
//   PROBE_SOURCE         写进告警里的来源标识，例如 server-cron / github-actions
// 告警通道（还没选定，可插拔，都不配时只打印）：
//   ALERT_WEBHOOK_URL    POST JSON。ALERT_WEBHOOK_FORMAT=generic（默认，{text, status, source, result}）
//                        | text（{"msgtype":"text","text":{"content":…}}，企业微信/钉钉风格）
//                        | feishu（{"msg_type":"text","content":{"text":…}}）
//   ALERT_COMMAND        任意命令，告警文本从 stdin 传入（例如发邮件的脚本）
// 不打印任何凭证；探测样本不含真人声音。
import { readFileSync, writeFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { signJwt } from '../src/jwt.js';

/** 合成 PCM：16k/16bit/单声道，440Hz 低音量正弦波 */
export function synthPcm(ms = 2000) {
  const n = 16 * ms;
  const b = Buffer.alloc(n * 2);
  for (let i = 0; i < n; i++) b.writeInt16LE(Math.round(Math.sin((2 * Math.PI * 440 * i) / 16000) * 2000), i * 2);
  return b;
}

/** 连续失败计数与告警判定（纯函数，便于测试） */
export function evaluate(prev, ok, threshold = 2) {
  const s = { fails: prev?.fails ?? 0, alerted: prev?.alerted ?? false };
  if (ok) {
    const recovered = s.alerted;
    return { state: { fails: 0, alerted: false }, alert: recovered ? 'up' : null };
  }
  s.fails += 1;
  if (s.fails >= threshold && !s.alerted) return { state: { ...s, alerted: true }, alert: 'down' };
  return { state: s, alert: null };
}

/** 把告警消息转成各 webhook 格式 */
export function webhookBody(format, text, extra = {}) {
  if (format === 'text') return { msgtype: 'text', text: { content: text } };
  if (format === 'feishu') return { msg_type: 'text', content: { text } };
  return { text, ...extra };
}

export function alertText(kind, result, source) {
  const head = kind === 'down' ? '【哄哄告警】按住说话联网识别探测连续失败' : '【哄哄恢复】按住说话联网识别探测已恢复';
  return `${head}\n来源：${source}\n阶段：${result.stage ?? '-'}\n错误：${result.err_code ?? '-'}\nrequest_id：${result.request_id}\n时间：${result.ts}`;
}

async function checkHealth(base, requireLlm) {
  const r = await fetch(new URL('healthz', base), { signal: AbortSignal.timeout(10000) });
  if (r.status !== 200) return { ok: false, err_code: `healthz_${r.status}` };
  const j = await r.json();
  if (j.ok !== true) return { ok: false, err_code: 'healthz_not_ok' };
  if (j.asr_configured !== true) return { ok: false, err_code: 'asr_not_configured' };
  if (requireLlm && j.llm_configured !== true) return { ok: false, err_code: 'llm_not_configured' };
  return { ok: true };
}

/** 用 Node 22+ 自带的 WebSocket（没有就用网关自己的 ws.js 客户端） */
async function checkAsr(base, jwt, rid, pcm) {
  const url = new URL('diary-asr', base);
  url.protocol = url.protocol === 'http:' ? 'ws:' : 'wss:';
  const { WsConn } = await import('../src/ws.js');
  const { request: httpReq } = await import('node:http');
  const { request: httpsReq } = await import('node:https');
  const { randomBytes } = await import('node:crypto');
  return new Promise((resolve) => {
    const done = (r) => { clearTimeout(timer); resolve(r); };
    const timer = setTimeout(() => done({ ok: false, err_code: 'asr_timeout' }), 30000);
    const req = (url.protocol === 'wss:' ? httpsReq : httpReq)({
      hostname: url.hostname, port: url.port || (url.protocol === 'wss:' ? 443 : 80), path: url.pathname,
      headers: { Connection: 'Upgrade', Upgrade: 'websocket', 'Sec-WebSocket-Key': randomBytes(16).toString('base64'), 'Sec-WebSocket-Version': '13', Authorization: `Bearer ${jwt}`, 'x-request-id': rid },
    });
    req.on('error', (e) => done({ ok: false, err_code: `asr_conn_${e.code ?? 'error'}`.toLowerCase() }));
    req.on('response', (r) => done({ ok: false, err_code: `ws_handshake_${r.statusCode}` }));
    req.on('upgrade', async (_r, socket, head) => {
      const ws = new WsConn(socket, { client: true, head });
      ws.on('message', (m) => {
        let j; try { j = JSON.parse(m); } catch { return; }
        if (j.type === 'final') done({ ok: true, chars: [...(j.text ?? '')].length });
        if (j.type === 'error') done({ ok: false, err_code: `asr_error_${j.error}` });
      });
      ws.on('close', (code) => done({ ok: false, err_code: `asr_closed_${code}` }));
      for (let i = 0; i < pcm.length; i += 1280) { ws.send(pcm.subarray(i, i + 1280)); await new Promise((r) => setTimeout(r, 40)); }
      ws.send(JSON.stringify({ type: 'end' }));
    });
    req.end();
  });
}

async function notify(text, result, env) {
  const tasks = [];
  if (env.ALERT_WEBHOOK_URL) {
    tasks.push(fetch(env.ALERT_WEBHOOK_URL, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify(webhookBody(env.ALERT_WEBHOOK_FORMAT ?? 'generic', text, { status: result.ok ? 'up' : 'down', source: env.PROBE_SOURCE ?? 'probe', result })),
      signal: AbortSignal.timeout(10000),
    }).then((r) => { if (!r.ok) throw new Error(`webhook_${r.status}`); }));
  }
  if (env.ALERT_COMMAND) {
    tasks.push(new Promise((res, rej) => {
      const p = spawn('sh', ['-c', env.ALERT_COMMAND], { stdio: ['pipe', 'inherit', 'inherit'] });
      p.on('exit', (c) => (c === 0 ? res() : rej(new Error(`alert_command_${c}`))));
      p.stdin.end(text);
    }));
  }
  if (!tasks.length) console.error(`[probe] 未配置告警通道（ALERT_WEBHOOK_URL / ALERT_COMMAND）：\n${text}`);
  const rs = await Promise.allSettled(tasks);
  return rs.every((r) => r.status === 'fulfilled');
}

export async function run(env = process.env) {
  const base = env.PROBE_BASE_URL;
  if (!base) throw new Error('缺少 PROBE_BASE_URL');
  const baseUrl = base.endsWith('/') ? base : `${base}/`;
  const rid = randomUUID();
  const t0 = Date.now();
  const result = { ts: new Date().toISOString(), level: 'info', svc: 'probe', event: 'probe.asr', request_id: rid, source: env.PROBE_SOURCE ?? 'probe' };
  try {
    const h = await checkHealth(baseUrl, env.PROBE_REQUIRE_LLM === '1');
    if (!h.ok) Object.assign(result, { ok: false, stage: 'healthz', err_code: h.err_code });
    else {
      const jwt = env.PROBE_JWT || (env.PROBE_JWT_SECRET
        ? signJwt({ sub: env.PROBE_SUB ?? 'hh-probe', role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 600 }, env.PROBE_JWT_SECRET)
        : null);
      if (!jwt) Object.assign(result, { ok: false, stage: 'config', err_code: 'probe_jwt_missing' });
      else {
        const a = await checkAsr(baseUrl, jwt, rid, synthPcm(2000));
        Object.assign(result, a, { stage: a.ok ? 'done' : 'asr' });
      }
    }
  } catch (e) {
    Object.assign(result, { ok: false, stage: 'exception', err_code: `probe_${e?.name ?? 'error'}`.toLowerCase() });
  }
  result.ms = Date.now() - t0;
  result.outcome = result.ok ? 'ok' : 'fail';
  if (!result.ok) result.level = 'error';

  const stateFile = env.PROBE_STATE_FILE ?? '/tmp/hh-asr-probe.json';
  let prev = null;
  try { prev = JSON.parse(readFileSync(stateFile, 'utf8')); } catch { /* 第一次 */ }
  const { state, alert } = evaluate(prev, result.ok, Number(env.PROBE_FAIL_THRESHOLD ?? 2));
  result.consecutive_fails = state.fails;
  if (alert) result.alert = alert;
  if (alert) {
    const sent = await notify(alertText(alert, result, result.source), result, env);
    // 告警没发出去：不标记 alerted，下次继续尝试
    if (!sent && alert === 'down') state.alerted = false;
    result.alert_sent = sent;
  }
  writeFileSync(stateFile, JSON.stringify(state));
  console.log(JSON.stringify(result));
  return result;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  run().then((r) => process.exit(r.ok ? 0 : 1), (e) => { console.error(JSON.stringify({ level: 'error', svc: 'probe', err_code: 'probe_config', err_name: e.name })); process.exit(2); });
}
