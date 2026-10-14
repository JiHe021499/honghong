// POST 以外的唯一接口：/diary-asr WebSocket 中转（架构 §4.1，D9 修订：本机识别不可用时的联网兜底）。
// 客户端 ↔ 网关：
//   握手：GET /diary-asr，Authorization: Bearer <Supabase JWT>
//   客户端 → 网关：二进制帧 = 16k/16bit/单声道 PCM；文本帧 {"type":"end"} 表示说完了
//   网关 → 客户端：{"type":"partial","text"}、{"type":"final","text"}、{"type":"error","error"}，随后网关关闭连接
// 音频只在内存中转发，不落盘；日志只记时长、状态、耗时，不记音频和识别文本。
import { acceptUpgrade, connectWs, rejectUpgrade } from './ws.js';
import { verifySupabaseJwt } from './jwt.js';
import { BYTES_PER_SEC, FRAME_BYTES, ResultAssembler, firstFrame, lastFrame, midFrame, signedUrl } from './xfyun.js';

export const ROUTE = 'diary-asr';

export function createAsrUpgrade(cfg, { limiter, log = (m) => console.log(JSON.stringify(m)), connect = connectWs } = {}) {
  const x = cfg.xfyun;
  const maxBytes = BYTES_PER_SEC * x.maxSeconds;

  return (req, socket, head) => {
    const t0 = Date.now();
    const path = new URL(req.url, 'http://x').pathname.replace(/^\/+/, '');
    const reject = (code, error) => { rejectUpgrade(socket, code, { error }); log({ route: ROUTE, code, ms: Date.now() - t0, status: error }); };
    if (path !== ROUTE) return reject(404, 'not_found');
    if (!x.configured) return reject(503, 'asr_not_configured');
    let claims;
    try { claims = verifySupabaseJwt((req.headers.authorization ?? '').replace(/^Bearer\s+/i, ''), cfg.jwtSecret); }
    catch { return reject(401, 'unauthorized'); }
    if (!limiter.take(claims.sub, ROUTE)) return reject(429, 'rate_limited');
    const client = acceptUpgrade(req, socket, head);
    if (!client) return;
    session(client, t0);
  };

  function session(client, t0) {
    let up = null; // 讯飞连接
    let sent = 0; // 已转发的音频字节
    let pending = Buffer.alloc(0); // 不满一帧的余量
    let first = true;
    let ended = false;
    let finished = false;
    let status = 'ok';
    const queue = []; // 讯飞握手完成前缓存的帧（内存）
    const asm = new ResultAssembler();

    const finish = (st, err) => {
      if (finished) return;
      finished = true;
      clearTimeout(hardStop);
      clearTimeout(idle);
      status = st;
      if (err) client.send(JSON.stringify({ type: 'error', error: err }));
      client.close(err ? 1011 : 1000);
      up?.close(1000);
      pending = Buffer.alloc(0);
      queue.length = 0;
      log({ route: ROUTE, code: 101, ms: Date.now() - t0, audio_ms: Math.round((sent / BYTES_PER_SEC) * 1000), status });
    };
    // 单次最长 60s 音频；墙钟再给 15s 余量等结果
    const hardStop = setTimeout(() => finish('timeout', 'timeout'), (x.maxSeconds + 15) * 1000);
    let idle;
    const touch = () => { clearTimeout(idle); idle = setTimeout(() => finish('idle', 'idle'), x.idleMs); };
    touch();

    const toUp = (s) => (up ? up.send(s) : queue.push(s));
    const pushAudio = (chunk) => {
      pending = Buffer.concat([pending, chunk]);
      while (pending.length >= FRAME_BYTES) {
        const f = pending.subarray(0, FRAME_BYTES);
        pending = pending.subarray(FRAME_BYTES);
        toUp(first ? firstFrame({ appId: x.appId, audio: f }) : midFrame(f));
        first = false;
      }
    };
    const endAudio = () => {
      if (ended) return;
      ended = true;
      if (pending.length) { toUp(first ? firstFrame({ appId: x.appId, audio: pending }) : midFrame(pending)); first = false; pending = Buffer.alloc(0); }
      if (first) return finish('empty', 'no_audio');
      toUp(lastFrame());
    };

    client.on('message', (data, binary) => {
      if (finished) return;
      touch();
      if (binary) {
        if (ended) return;
        const room = maxBytes - sent;
        const chunk = data.length > room ? data.subarray(0, room) : data;
        sent += chunk.length;
        pushAudio(chunk);
        if (sent >= maxBytes) endAudio(); // 到 60s 自动收尾
        return;
      }
      let m;
      try { m = JSON.parse(data); } catch { return; }
      if (m?.type === 'end') endAudio();
    });
    client.on('close', () => { if (!finished) finish(ended ? 'client_closed' : 'cancelled'); });

    connect(signedUrl({ url: x.url, apiKey: x.apiKey, apiSecret: x.apiSecret }), { timeoutMs: 5000 })
      .then((ws) => {
        if (finished) return ws.close(1000);
        up = ws;
        for (const s of queue.splice(0)) up.send(s);
        up.on('message', (raw, binary) => {
          if (binary || finished) return;
          let m;
          try { m = JSON.parse(raw); } catch { return finish('upstream_bad_json', 'upstream'); }
          if (m.code !== 0) return finish(`xf_${m.code}`, m.code === 11201 || m.code === 11202 ? 'upstream_quota' : 'upstream');
          const text = asm.push(m.data?.result);
          if (m.data?.status === 2) {
            client.send(JSON.stringify({ type: 'final', text }));
            return finish(text ? 'ok' : 'empty_result');
          }
          client.send(JSON.stringify({ type: 'partial', text }));
        });
        up.on('close', () => { if (!finished) finish('upstream_closed', 'upstream'); });
      })
      .catch((e) => finish(`upstream_${e.status || 'conn'}`, 'upstream'));
  }
}
