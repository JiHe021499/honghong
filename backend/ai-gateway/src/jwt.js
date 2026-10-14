import { createHmac, timingSafeEqual } from 'node:crypto';

const b64url = (buf) => Buffer.from(buf).toString('base64url');

/** 校验自建 Supabase 签发的 HS256 JWT，返回 payload；失败抛错。 */
export function verifySupabaseJwt(token, secret, nowSec = Math.floor(Date.now() / 1000)) {
  if (!token) throw new Error('missing_token');
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('malformed');
  const [h, p, s] = parts;
  let header, payload;
  try {
    header = JSON.parse(Buffer.from(h, 'base64url').toString());
    payload = JSON.parse(Buffer.from(p, 'base64url').toString());
  } catch { throw new Error('malformed'); }
  if (header.alg !== 'HS256') throw new Error('bad_alg');
  const expected = createHmac('sha256', secret).update(`${h}.${p}`).digest();
  const got = Buffer.from(s, 'base64url');
  if (got.length !== expected.length || !timingSafeEqual(got, expected)) throw new Error('bad_signature');
  if (typeof payload.exp === 'number' && payload.exp < nowSec) throw new Error('expired');
  if (payload.role !== 'authenticated' || !payload.sub) throw new Error('not_user'); // 拒绝 anon key / service_role
  return payload;
}

/** 测试用：签发 HS256 JWT。 */
export function signJwt(payload, secret) {
  const h = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const p = b64url(JSON.stringify(payload));
  const s = createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url');
  return `${h}.${p}.${s}`;
}
