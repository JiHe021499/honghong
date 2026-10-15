// 统一结构化日志（日志方案 §5.1 / §5.3）。每行一个 JSON：
//   ts（ISO8601 UTC）、level（debug/info/warn/error/fatal）、svc、request_id、route、code、ms、err_code …
// 绝不记录：音频、识别文字、日记正文、昵称、邀请码、JWT、原始异常 message（可能含用户内容）。
import { randomUUID } from 'node:crypto';

export const SVC = 'ai-gateway';
const RID = /^[0-9A-Za-z-]{8,64}$/;

/** 读客户端传来的 x-request-id（校验格式），没有或不合法时生成一个 */
export function requestId(headers = {}) {
  const v = headers['x-request-id'];
  return typeof v === 'string' && RID.test(v) ? v : randomUUID();
}

/** 按状态码推断级别：5xx error，4xx warn，其余 info */
export const levelFor = (code) => (code >= 500 ? 'error' : code >= 400 ? 'warn' : 'info');

/** 组装一行日志：补 ts/level/svc，丢掉 undefined */
export function entry(fields, now = () => new Date()) {
  const out = { ts: now().toISOString(), level: fields.level ?? levelFor(fields.code ?? 0), svc: SVC };
  for (const [k, v] of Object.entries(fields)) if (v !== undefined && k !== 'level') out[k] = v;
  return out;
}

/** 异常 → 可记录的字段：只取类型名和栈的第一处代码位置，不取 message */
export function errorFields(e) {
  const frame = typeof e?.stack === 'string' ? e.stack.split('\n').find((l) => l.trim().startsWith('at ')) : undefined;
  return { err_name: e?.name ?? typeof e, err_at: frame?.trim().replace(/^at\s+/, '').slice(0, 160) };
}

export const stdoutLog = (m) => console.log(JSON.stringify(m));
