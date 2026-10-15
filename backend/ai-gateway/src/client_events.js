// POST /client-events：App 在用户同意后上报的失败/统计事件（日志方案 P0）。
// 只接受白名单字段，每个值再校验格式；其他一律丢弃。原样写入 stdout 日志（由日志采集收走）。
// 绝不接受：音频、识别文字、日记正文、昵称、邀请码、JWT —— 白名单里没有任何自由文本字段。

const ENUMS = {
  outcome: ['ok', 'fail', 'cancel', 'timeout'],
  engine: ['system', 'cloud'],
  net: ['wifi', 'cell', 'none', 'other'],
  level: ['info', 'warn', 'error'],
};
const PATTERNS = {
  event: /^[a-z][a-z0-9_]*(\.[a-z0-9_]+){0,4}$/,
  err_code: /^[a-z0-9_]{1,48}$/,
  request_id: /^[0-9A-Za-z-]{8,64}$/,
  app_ver: /^[0-9A-Za-z.+-]{1,32}$/,
  os: /^(android|ios|other)( [0-9.]{1,10})?$/,
  ts: /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/,
};
const INTS = ['ms', 'audio_ms', 'chars', 'count'];
const BOOLS = ['consent_cloud'];
export const MAX_EVENTS = 20;

/** 过滤一个事件；没有合法 event 名时返回 null */
export function sanitizeEvent(e) {
  if (!e || typeof e !== 'object' || Array.isArray(e)) return null;
  const out = {};
  for (const [k, re] of Object.entries(PATTERNS)) if (typeof e[k] === 'string' && e[k].length <= 64 && re.test(e[k])) out[k] = e[k];
  for (const [k, vs] of Object.entries(ENUMS)) if (vs.includes(e[k])) out[k] = e[k];
  for (const k of INTS) if (Number.isInteger(e[k]) && e[k] >= 0 && e[k] <= 86_400_000) out[k] = e[k];
  for (const k of BOOLS) if (typeof e[k] === 'boolean') out[k] = e[k];
  return out.event ? out : null;
}

export function sanitizeBatch(body) {
  const list = Array.isArray(body?.events) ? body.events.slice(0, MAX_EVENTS) : [];
  return list.map(sanitizeEvent).filter(Boolean);
}
