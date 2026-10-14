// 假的讯飞听写服务：按官方协议校验握手签名和帧格式，返回动态修正（wpgs）风格的结果。
import { createServer } from 'node:http';
import { acceptUpgrade, rejectUpgrade } from '../src/ws.js';
import { authorization, signature } from '../src/xfyun.js';

export async function startFakeXfyun({ apiKey, apiSecret, appId, words = ['今天', '吃奶', '六次'], failCode = 0 }) {
  const seen = { frames: [], bytes: 0, handshakes: 0, badAuth: 0 };
  const srv = createServer();
  srv.on('upgrade', (req, socket, head) => {
    seen.handshakes++;
    const u = new URL(req.url, 'http://x');
    const date = u.searchParams.get('date');
    const host = u.searchParams.get('host');
    const want = authorization({ apiKey, signature: signature({ host, date, path: u.pathname, apiSecret }) });
    if (u.searchParams.get('authorization') !== want || host !== req.headers.host || Math.abs(Date.parse(date) - Date.now()) > 300e3) {
      seen.badAuth++;
      return rejectUpgrade(socket, 401, { message: 'HMAC signature does not match' });
    }
    const ws = acceptUpgrade(req, socket, head);
    let sn = 0;
    ws.on('message', (raw) => {
      const m = JSON.parse(raw);
      seen.frames.push(m.data.status);
      if (m.data.status === 0 && (m.common?.app_id !== appId || m.business?.language !== 'zh_cn')) {
        return ws.send(JSON.stringify({ code: 10005, message: 'appid auth failed' }));
      }
      if (m.data.format !== 'audio/L16;rate=16000' || m.data.encoding !== 'raw') return ws.send(JSON.stringify({ code: 10163, message: 'bad param' }));
      const audio = Buffer.from(m.data.audio, 'base64');
      seen.bytes += audio.length;
      if (audio.length > 1280) return ws.send(JSON.stringify({ code: 10163, message: 'frame too large' }));
      if (failCode && m.data.status === 0) return ws.send(JSON.stringify({ code: failCode, message: 'fail' }));
      if (m.data.status === 0) {
        sn++;
        ws.send(JSON.stringify({ code: 0, sid: 'iat-fake', data: { status: 0, result: { sn, ls: false, pgs: 'apd', ws: [{ cw: [{ w: words[0] }] }] } } }));
      }
      if (m.data.status === 2) {
        // 先给一次替换（修正），再给最后一片
        sn++;
        ws.send(JSON.stringify({ code: 0, data: { status: 1, result: { sn, ls: false, pgs: 'rpl', rg: [1, 1], ws: words.slice(0, 2).map((w) => ({ cw: [{ w }] })) } } }));
        sn++;
        ws.send(JSON.stringify({ code: 0, data: { status: 2, result: { sn, ls: true, pgs: 'apd', ws: words.slice(2).map((w) => ({ cw: [{ w }] })) } } }));
      }
    });
  });
  await new Promise((r) => srv.listen(0, '127.0.0.1', r));
  return { url: `ws://127.0.0.1:${srv.address().port}/v2/iat`, seen, close: () => srv.close() };
}
