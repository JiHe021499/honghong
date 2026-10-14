// 讯飞「语音听写（流式版）WebAPI」：鉴权签名、请求帧、结果拼接。
// 协议对照官方文档 https://www.xfyun.cn/doc/asr/voicedictation/API.html （2026-10-14 核对）：
// - 握手 URL 带 host / date(RFC1123, GMT) / authorization 三个 query 参数；
// - signature = base64(hmac-sha256(apiSecret, "host: $host\ndate: $date\nGET $path HTTP/1.1"))；
// - authorization = base64('api_key="..", algorithm="hmac-sha256", headers="host date request-line", signature=".."')；
// - 首帧带 common.app_id + business，data.status 0/1/2，audio 为 base64 的 16k/16bit/单声道 PCM；
// - 建议每 40ms 发 1280 字节；会话最长 60s；10s 不发数据服务端断开。
import { createHmac } from 'node:crypto';

export const DEFAULT_URL = 'wss://iat-api.xfyun.cn/v2/iat';
export const FRAME_BYTES = 1280; // 16k * 16bit * 40ms
export const BYTES_PER_SEC = 16000 * 2;

export function signature({ host, date, path, apiSecret }) {
  const origin = `host: ${host}\ndate: ${date}\nGET ${path} HTTP/1.1`;
  return createHmac('sha256', apiSecret).update(origin).digest('base64');
}

export function authorization({ apiKey, signature: sig }) {
  return Buffer.from(`api_key="${apiKey}", algorithm="hmac-sha256", headers="host date request-line", signature="${sig}"`).toString('base64');
}

/** 生成带鉴权参数的握手 URL。date 默认当前时间（服务端允许 ±300s 偏差）。 */
export function signedUrl({ url = DEFAULT_URL, apiKey, apiSecret, date = new Date().toUTCString() }) {
  const u = new URL(url);
  const sig = signature({ host: u.host, date, path: u.pathname, apiSecret });
  const q = new URLSearchParams({ authorization: authorization({ apiKey, signature: sig }), date, host: u.host });
  return `${u.origin.replace(/^http/, 'ws')}${u.pathname}?${q}`;
}

/** 首帧：common + business + data(status 0)。dwa=wpgs 打开动态修正，边说边出字。 */
export function firstFrame({ appId, audio, eosMs = 3000 }) {
  return JSON.stringify({
    common: { app_id: appId },
    business: { language: 'zh_cn', domain: 'iat', accent: 'mandarin', dwa: 'wpgs', eos: eosMs, ptt: 1 },
    data: { status: 0, format: 'audio/L16;rate=16000', encoding: 'raw', audio: audio.toString('base64') },
  });
}
export const midFrame = (audio) => JSON.stringify({ data: { status: 1, format: 'audio/L16;rate=16000', encoding: 'raw', audio: audio.toString('base64') } });
export const lastFrame = () => JSON.stringify({ data: { status: 2, format: 'audio/L16;rate=16000', encoding: 'raw', audio: '' } });

/** 按 sn 拼接识别结果；pgs=rpl 时用新结果替换 rg 范围内的旧片段（动态修正）。 */
export class ResultAssembler {
  constructor() { this.parts = new Map(); }
  push(result) {
    if (!result || typeof result !== 'object') return this.text;
    const text = (result.ws ?? []).map((w) => w?.cw?.[0]?.w ?? '').join('');
    if (result.pgs === 'rpl' && Array.isArray(result.rg)) {
      for (let i = result.rg[0]; i <= result.rg[1]; i++) this.parts.delete(i);
    }
    if (Number.isInteger(result.sn)) this.parts.set(result.sn, text);
    return this.text;
  }
  get text() { return [...this.parts.entries()].sort((a, b) => a[0] - b[0]).map((e) => e[1]).join(''); }
}
