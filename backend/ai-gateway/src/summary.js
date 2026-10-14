// POST /diary-summary（架构 §4.3 / §5.4）：只收聚合统计，不收原话。
// 输出合规：≤50 字、无诊断/恐吓词、不出现统计里没有的数字；不合规重试一次，仍不合规用模板句（只用统计数字）。
import { SUMMARY_PROMPT_VERSION, summaryMessages } from './prompts.js';
import { diagnosisHits } from './risk.js';

const MAX_CHARS = 50;
const nonNegInt = (v, max = 10000) => v === undefined || (Number.isInteger(v) && v >= 0 && v <= max);
const shortStr = (v) => typeof v === 'string' && [...v].length <= 10;

/** 校验并规整请求里的 stats；不合法返回 null */
export function normalizeStats(s) {
  if (!s || typeof s !== 'object' || Array.isArray(s)) return null;
  const out = {};
  const pick = (key, fields) => {
    if (s[key] === undefined) return true;
    const o = s[key];
    if (!o || typeof o !== 'object') return false;
    out[key] = {};
    for (const f of fields) { if (!nonNegInt(o[f])) return false; if (o[f] !== undefined) out[key][f] = o[f]; }
    return true;
  };
  if (!pick('feed', ['count', 'total_ml', 'aggregate_count']) || !pick('sleep', ['count', 'total_min']) || !pick('diaper', ['count', 'poo', 'pee'])) return null;
  if (s.mood !== undefined) {
    if (!Array.isArray(s.mood) || s.mood.length > 10) return null;
    for (const m of s.mood) if (!m || ![m.period, m.type, m.intensity].every((x) => x == null || shortStr(x))) return null;
    out.mood = s.mood.map((m) => ({ period: m.period ?? null, type: m.type ?? null, intensity: m.intensity ?? null }));
  }
  if (s.other !== undefined) {
    if (!Array.isArray(s.other) || s.other.length > 10 || !s.other.every(shortStr)) return null;
    out.other = s.other;
  }
  return out;
}

/** 统计里允许出现的数字（含睡眠小时/分钟换算） */
function allowedNumbers(stats) {
  const n = new Set();
  const add = (v) => { if (Number.isFinite(v)) n.add(String(v)); };
  for (const k of ['feed', 'sleep', 'diaper']) for (const v of Object.values(stats[k] ?? {})) add(v);
  const m = stats.sleep?.total_min;
  if (m) { const h = m / 60; [Math.floor(h), Math.round(h), Math.ceil(h), m % 60, +(h.toFixed(1))].forEach(add); }
  return n;
}

export function checkSummary(content, stats) {
  if (typeof content !== 'string') return 'not_string';
  const c = content.trim();
  if (!c) return 'empty';
  if ([...c].length > MAX_CHARS) return 'too_long';
  if (/[\n\r]/.test(c)) return 'multiline';
  if (diagnosisHits(c).length) return 'diagnosis';
  const ok = allowedNumbers(stats);
  for (const num of c.match(/\d+(?:\.\d+)?/g) ?? []) if (!ok.has(num)) return 'fabricated_number';
  return null;
}

/** 模板兜底：只用统计数字，绝不虚构 */
export function templateSummary(stats) {
  const parts = [];
  const f = stats.feed ?? {};
  if (f.count) parts.push(`记录了${f.count}次喂奶`);
  if (f.aggregate_count && f.aggregate_count !== f.count) parts.push(`妈妈提到全天约${f.aggregate_count}次`);
  if (stats.sleep?.total_min) parts.push(`睡了约${Math.round(stats.sleep.total_min / 60)}小时`);
  if (stats.diaper?.count) parts.push(`换了${stats.diaper.count}次尿布`);
  let s = parts.length ? `今天${parts.join('、')}，辛苦啦` : '今天也辛苦啦，早点休息';
  while ([...s].length > MAX_CHARS && parts.length > 1) { parts.pop(); s = `今天${parts.join('、')}，辛苦啦`; }
  return s;
}

export async function summarize(llm, { date, ageInDays, stats }) {
  const messages = summaryMessages({ date, ageInDays, stats });
  let reason;
  for (let attempt = 1; attempt <= 2; attempt++) {
    const raw = await llm.chat(messages, { maxTokens: 200, temperature: 0.3 });
    let content;
    try { content = JSON.parse(raw)?.content; } catch { content = undefined; }
    reason = checkSummary(content, stats);
    if (!reason) return { content: content.trim(), prompt_version: SUMMARY_PROMPT_VERSION, fallback: false };
  }
  return { content: templateSummary(stats), prompt_version: SUMMARY_PROMPT_VERSION, fallback: true, fallback_reason: reason };
}
