// POST /diary-parse 的核心逻辑（架构 §4.2 / §5.1 / §5.2）。
// DeepSeek 降级方案：json_object + 提示词内 schema；网关强制校验，不合规重试一次。
// 第二次：根结构仍不合法 → 报错（failed）；只有个别卡片不合法 → 这些卡转 other（partial，架构 §5.2-1）。
import { CATEGORIES, validateParse } from './schema.js';
import { PARSE_PROMPT_VERSION, parseMessages } from './prompts.js';
import { diagnosisHits, riskHits } from './risk.js';

export class ParseFailed extends Error {
  constructor(reason) { super(reason); this.reason = reason; }
}

const int = (lo, hi) => (v) => (Number.isInteger(v) && v >= lo && v <= hi ? v : undefined);
const oneOf = (...xs) => (v) => (xs.includes(v) ? v : undefined);
const str = (max) => (v) => (typeof v === 'string' && v.trim() && [...v].length <= max ? v.trim() : undefined);
export const ATTR_RULES = {
  feeding: { count: int(1, 30), method: oneOf('breast', 'bottle_breast', 'formula'), side: oneOf('left', 'right', 'both'), ml: int(1, 400), duration_min: int(1, 180) },
  sleep: { duration_min: int(1, 960), night_wakings: int(0, 20) },
  diaper: { type: oneOf('pee', 'poo', 'both'), count: int(1, 30), texture_note: str(30) },
  mood: { type: str(10) },
  other: { topic: str(10) },
};
const PERIODS = ['morning', 'afternoon', 'evening', 'night', 'all_day'];
const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;
const REVIEW_CONF = 0.5; // < 0.6 时客户端显示“请核对”

/** 清洗一张已通过 schema 的卡片：未知键丢弃、越界置空并降置信度、诊断词回退。 */
export function sanitizeCard(c, text) {
  let review = false;
  const attrs = {};
  const rules = ATTR_RULES[c.category];
  for (const [k, v] of Object.entries(c.attributes ?? {})) {
    if (!rules[k] || v === null) continue; // 不认识的键丢弃；null 视为未提及
    const ok = rules[k](v);
    if (ok === undefined) review = true; // 越界/类型不对：置空，不猜
    else attrs[k] = ok;
  }
  const out = {
    category: c.category,
    kind: c.kind,
    event_time: c.event_time && HHMM.test(c.event_time) ? c.event_time : null,
    end_time: c.end_time && HHMM.test(c.end_time) ? c.end_time : null,
    day_offset: c.day_offset === -1 ? -1 : 0,
    time_period: PERIODS.includes(c.time_period) ? c.time_period : null,
    attributes: attrs,
    intensity: c.intensity ?? null,
    note: c.note,
    confidence: c.confidence,
  };
  if ((c.event_time && !out.event_time) || (c.end_time && !out.end_time)) review = true;
  if (out.kind === 'aggregate' && !out.time_period) out.time_period = 'all_day';
  // 合规：AI 产出的诊断词回退为原文
  if (diagnosisHits(out.note, text).length) { out.note = [...text].slice(0, 200).join(''); review = true; }
  if (out.intensity && diagnosisHits(out.intensity, text).length) { out.intensity = null; review = true; }
  if (review) out.confidence = Math.min(out.confidence, REVIEW_CONF);
  return out;
}

export function otherCard(note, confidence = 0.3) {
  return { category: 'other', kind: 'event', event_time: null, end_time: null, day_offset: 0, time_period: null, attributes: {}, intensity: null, note: [...note].slice(0, 200).join(''), confidence };
}

const FILLER = /嗯+|啊+|呃+|那个|然后|还有|就是|对了|哦+|吧|呢/g;
const bigrams = (s) => { const t = s.replace(/[^\p{L}\p{N}]/gu, ''); const a = []; for (let i = 0; i < t.length - 1; i++) a.push(t.slice(i, i + 2)); return t.length === 1 ? [t] : a; };

/** 原文覆盖检查（§5.2-4）：返回卡片 note 没覆盖到的分句。 */
export function uncoveredClauses(text, cards) {
  const notes = cards.map((c) => c.note ?? '').join('|');
  const have = new Set(bigrams(notes));
  return text.split(/[，,。.；;！!？?\n、]+|然后|还有/).map((s) => s.trim()).filter((s) => {
    const bare = s.replace(/[^\p{L}\p{N}]/gu, '').replace(FILLER, '');
    if (bare.length < 2) return false;
    if (notes.includes(s)) return false;
    const bg = bigrams(s);
    return bg.filter((b) => have.has(b)).length / bg.length < 0.5;
  });
}

function tryParse(content) {
  let obj;
  try { obj = JSON.parse(content); } catch { return { root: false }; }
  if (!obj || typeof obj !== 'object' || !Array.isArray(obj.cards)) return { root: false };
  const v = validateParse(obj);
  return { root: true, ok: v.ok, obj, errors: v.errors };
}

/** 单张卡是否通过 schema（复用整体校验器） */
const cardValid = (c) => validateParse({ cards: [c] }).ok && CATEGORIES.includes(c.category);

export async function parseDiary(llm, { text, ageInDays, now }, { onAttempt } = {}) {
  const messages = parseMessages({ text, ageInDays, now });
  let last;
  for (let attempt = 1; attempt <= 2; attempt++) {
    const content = await llm.chat(messages, { maxTokens: 1200 });
    last = tryParse(content);
    onAttempt?.(attempt, last);
    if (last.root && last.ok) break;
  }
  if (!last.root) throw new ParseFailed('schema_invalid');

  let status = last.ok ? 'ok' : 'partial';
  const raw = last.obj.cards.slice(0, 10);
  const cards = raw.map((c) => (c && typeof c === 'object' && cardValid(c) ? sanitizeCard(c, text) : otherCard(typeof c?.note === 'string' && text.includes(c.note) ? c.note : text)));
  const rest = uncoveredClauses(text, cards);
  if (rest.length && cards.length < 10) cards.push(otherCard(rest.join('，'), 0.5));
  if (!cards.length) { cards.push(otherCard(text)); status = 'partial'; }
  const words = riskHits(text);
  return { status, prompt_version: PARSE_PROMPT_VERSION, model: llm.model, cards, risk: { hit: words.length > 0, words } };
}
