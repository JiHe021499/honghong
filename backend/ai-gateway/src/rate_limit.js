/** 按 auth.uid + 接口 + 自然日（Asia/Shanghai）计数的内存限流。单实例够用；多实例时再换 Redis。 */
export class DailyLimiter {
  constructor(limits, now = () => new Date()) { this.limits = limits; this.now = now; this.counts = new Map(); this.day = null; }
  _today() { return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Shanghai' }).format(this.now()); }
  /** 返回 true 表示放行并计数。 */
  take(uid, route) {
    const day = this._today();
    if (day !== this.day) { this.counts.clear(); this.day = day; }
    const limit = this.limits[route] ?? Infinity;
    const k = `${uid}:${route}`;
    const n = this.counts.get(k) ?? 0;
    if (n >= limit) return false;
    this.counts.set(k, n + 1);
    return true;
  }
}
