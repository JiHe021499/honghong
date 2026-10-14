// 最小 WebSocket 实现（RFC 6455），零第三方依赖：服务端接受升级、客户端发起连接。
// 只支持本项目需要的：文本/二进制帧、分片重组、ping/pong、close；不做扩展（permessage-deflate）。
import { createHash, randomBytes } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const acceptKey = (key) => createHash('sha1').update(key + GUID).digest('base64');
export const MAX_FRAME = 1 << 20; // 单帧上限 1MB，防止恶意大帧占内存

export class WsConn extends EventEmitter {
  constructor(socket, { client = false, head } = {}) {
    super();
    this.socket = socket;
    this.client = client; // 客户端发出的帧必须加掩码
    this.buf = head && head.length ? Buffer.from(head) : Buffer.alloc(0);
    this.frag = null;
    this.closed = false;
    socket.setNoDelay?.(true);
    socket.on('data', (d) => { this.buf = Buffer.concat([this.buf, d]); this._read(); });
    socket.on('close', () => this._gone(1006));
    socket.on('error', () => this._gone(1006));
    if (this.buf.length) queueMicrotask(() => this._read());
  }

  _gone(code, reason = '') {
    if (this.closed) return;
    this.closed = true;
    this.emit('close', code, reason);
  }

  _read() {
    for (;;) {
      const b = this.buf;
      if (b.length < 2) return;
      const fin = (b[0] & 0x80) !== 0;
      const op = b[0] & 0x0f;
      const masked = (b[1] & 0x80) !== 0;
      let len = b[1] & 0x7f;
      let off = 2;
      if (len === 126) { if (b.length < 4) return; len = b.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (b.length < 10) return; const big = b.readBigUInt64BE(2); if (big > BigInt(MAX_FRAME)) return this._fail(1009); len = Number(big); off = 10; }
      if (len > MAX_FRAME) return this._fail(1009);
      const mlen = masked ? 4 : 0;
      if (b.length < off + mlen + len) return;
      let payload = b.subarray(off + mlen, off + mlen + len);
      if (masked) {
        const m = b.subarray(off, off + 4);
        payload = Buffer.from(payload);
        for (let i = 0; i < payload.length; i++) payload[i] ^= m[i & 3];
      }
      this.buf = b.subarray(off + mlen + len);
      this._frame(fin, op, Buffer.from(payload));
      if (this.closed) return;
    }
  }

  _frame(fin, op, payload) {
    if (op === 0x8) {
      const code = payload.length >= 2 ? payload.readUInt16BE(0) : 1005;
      const reason = payload.length > 2 ? payload.subarray(2).toString('utf8') : '';
      if (!this.closing) this._send(0x8, payload.subarray(0, 2));
      this._gone(code, reason);
      this.socket.end();
      return;
    }
    if (op === 0x9) return this._send(0xA, payload);
    if (op === 0xA) return;
    if (op === 0x0) {
      if (!this.frag) return this._fail(1002);
      this.frag.parts.push(payload);
      if (this.frag.parts.reduce((n, p) => n + p.length, 0) > MAX_FRAME) return this._fail(1009);
      if (!fin) return;
      const { op: fop, parts } = this.frag;
      this.frag = null;
      return this._message(fop, Buffer.concat(parts));
    }
    if (op === 0x1 || op === 0x2) {
      if (!fin) { this.frag = { op, parts: [payload] }; return; }
      return this._message(op, payload);
    }
    this._fail(1002);
  }

  _message(op, data) {
    if (op === 0x1) this.emit('message', data.toString('utf8'), false);
    else this.emit('message', data, true);
  }

  _fail(code) { this.close(code); this.socket.destroy(); this._gone(code); }

  _send(op, payload) {
    if (this.socket.destroyed) return;
    const len = payload.length;
    const mask = this.client;
    let head;
    if (len < 126) { head = Buffer.alloc(2); head[1] = len; }
    else if (len < 65536) { head = Buffer.alloc(4); head[1] = 126; head.writeUInt16BE(len, 2); }
    else { head = Buffer.alloc(10); head[1] = 127; head.writeBigUInt64BE(BigInt(len), 2); }
    head[0] = 0x80 | op;
    if (mask) {
      head[1] |= 0x80;
      const m = randomBytes(4);
      const p = Buffer.from(payload);
      for (let i = 0; i < p.length; i++) p[i] ^= m[i & 3];
      this.socket.write(Buffer.concat([head, m, p]));
    } else {
      this.socket.write(Buffer.concat([head, payload]));
    }
  }

  send(data) {
    if (this.closed || this.closing) return;
    if (typeof data === 'string') this._send(0x1, Buffer.from(data, 'utf8'));
    else this._send(0x2, data);
  }

  close(code = 1000, reason = '') {
    if (this.closed || this.closing) return;
    this.closing = true;
    const r = Buffer.from(reason, 'utf8').subarray(0, 120);
    const p = Buffer.alloc(2 + r.length);
    p.writeUInt16BE(code, 0);
    r.copy(p, 2);
    this._send(0x8, p);
    // 对方不回 close 时兜底断开
    setTimeout(() => { if (!this.socket.destroyed) this.socket.destroy(); }, 2000).unref();
  }
}

/** 服务端：接受 HTTP upgrade。调用前应已完成鉴权等检查。 */
export function acceptUpgrade(req, socket, head) {
  const key = req.headers['sec-websocket-key'];
  if (!key || (req.headers.upgrade ?? '').toLowerCase() !== 'websocket' || req.headers['sec-websocket-version'] !== '13') {
    rejectUpgrade(socket, 400, { error: 'bad_upgrade' });
    return null;
  }
  socket.write(['HTTP/1.1 101 Switching Protocols', 'Upgrade: websocket', 'Connection: Upgrade', `Sec-WebSocket-Accept: ${acceptKey(key)}`, '', ''].join('\r\n'));
  return new WsConn(socket, { head });
}

const REASONS = { 400: 'Bad Request', 401: 'Unauthorized', 404: 'Not Found', 429: 'Too Many Requests', 500: 'Internal Server Error', 503: 'Service Unavailable' };
export function rejectUpgrade(socket, code, body) {
  const s = JSON.stringify(body);
  socket.end([`HTTP/1.1 ${code} ${REASONS[code] ?? 'Error'}`, 'Content-Type: application/json; charset=utf-8', `Content-Length: ${Buffer.byteLength(s)}`, 'Connection: close', '', s].join('\r\n'));
}

/** 客户端：连接 ws:// 或 wss://。握手失败时 reject 的 Error 带 status 与 body。 */
export function connectWs(url, { timeoutMs = 5000 } = {}) {
  const u = new URL(url);
  const key = randomBytes(16).toString('base64');
  const req = (u.protocol === 'wss:' ? httpsRequest : httpRequest)({
    hostname: u.hostname,
    port: u.port || (u.protocol === 'wss:' ? 443 : 80),
    path: u.pathname + u.search,
    headers: { Connection: 'Upgrade', Upgrade: 'websocket', 'Sec-WebSocket-Key': key, 'Sec-WebSocket-Version': '13', Host: u.host },
    timeout: timeoutMs,
  });
  return new Promise((resolve, reject) => {
    req.on('upgrade', (res, socket, head) => {
      if (res.headers['sec-websocket-accept'] !== acceptKey(key)) { socket.destroy(); return reject(Object.assign(new Error('bad_accept'), { status: 0 })); }
      resolve(new WsConn(socket, { client: true, head }));
    });
    req.on('response', (res) => {
      let body = '';
      res.on('data', (c) => { if (body.length < 2000) body += c; });
      res.on('end', () => reject(Object.assign(new Error('handshake_failed'), { status: res.statusCode, body })));
    });
    req.on('timeout', () => { req.destroy(); reject(Object.assign(new Error('timeout'), { status: 0 })); });
    req.on('error', (e) => reject(Object.assign(e, { status: 0 })));
    req.end();
  });
}
