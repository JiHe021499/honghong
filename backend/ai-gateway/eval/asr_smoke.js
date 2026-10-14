// 本机联调：把一段 16k/16bit/单声道 PCM 按 40ms/1280 字节实时推给本机网关的 /diary-asr，打印识别结果和耗时。
// 用法：ASR_SMOKE_JWT_SECRET=<与网关 SUPABASE_JWT_SECRET 相同的本地测试值> node eval/asr_smoke.js /tmp/a.pcm [ws://127.0.0.1:8787/diary-asr]
// 不读取、不打印任何讯飞凭证（凭证只在网关进程的环境变量里）。
import { readFileSync } from 'node:fs';
import { request } from 'node:http';
import { randomBytes } from 'node:crypto';
import { WsConn } from '../src/ws.js';
import { signJwt } from '../src/jwt.js';

const [file, url = 'ws://127.0.0.1:8787/diary-asr'] = process.argv.slice(2);
const pcm = readFileSync(file);
const jwt = signJwt({ sub: 'smoke-user', role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 600 }, process.env.ASR_SMOKE_JWT_SECRET);
const u = new URL(url);
const t0 = Date.now();
const req = request({ hostname: u.hostname, port: u.port, path: u.pathname, headers: { Connection: 'Upgrade', Upgrade: 'websocket', 'Sec-WebSocket-Key': randomBytes(16).toString('base64'), 'Sec-WebSocket-Version': '13', Authorization: `Bearer ${jwt}` } });
req.on('response', (r) => { console.log(JSON.stringify({ handshake: r.statusCode })); process.exit(1); });
req.on('upgrade', async (_r, socket, head) => {
  const ws = new WsConn(socket, { client: true, head });
  const tOpen = Date.now();
  let tEnd = 0; let firstPartial = 0; const partials = [];
  ws.on('message', (m) => {
    const j = JSON.parse(m);
    if (j.type === 'partial') { partials.push(j.text); if (!firstPartial) firstPartial = Date.now() - tOpen; }
    else console.log(JSON.stringify({ ...j, audio_ms: Math.round(pcm.length / 32), handshake_ms: tOpen - t0, first_partial_ms: firstPartial, after_end_ms: Date.now() - tEnd, total_ms: Date.now() - t0, partials: partials.length }));
  });
  ws.on('close', (code) => { console.log(JSON.stringify({ closed: code })); process.exit(0); });
  for (let i = 0; i < pcm.length; i += 1280) { ws.send(pcm.subarray(i, i + 1280)); await new Promise((r) => setTimeout(r, 40)); }
  tEnd = Date.now();
  ws.send(JSON.stringify({ type: 'end' }));
});
req.end();
