// 架构 §5.1 拆分输出 schema；服务端强制 + 客户端二次校验。P0 先提供 schema 与基础校验器，供评测脚本和 P2 复用。
const HHMM = '^\\d{2}:\\d{2}$';
export const CATEGORIES = ['feeding', 'sleep', 'diaper', 'mood', 'other'];
export const PARSE_SCHEMA = {
  type: 'object', required: ['cards'], additionalProperties: false,
  properties: { cards: { type: 'array', maxItems: 10, items: {
    type: 'object', additionalProperties: false, required: ['category', 'kind', 'note', 'confidence'],
    properties: {
      category: { enum: CATEGORIES }, kind: { enum: ['event', 'aggregate'] },
      event_time: { type: ['string', 'null'], pattern: HHMM }, end_time: { type: ['string', 'null'], pattern: HHMM },
      day_offset: { enum: [0, -1] }, time_period: { enum: ['morning', 'afternoon', 'evening', 'night', 'all_day', null] },
      attributes: { type: 'object' }, intensity: { type: ['string', 'null'], maxLength: 20 },
      note: { type: 'string', maxLength: 200 }, confidence: { type: 'number', minimum: 0, maximum: 1 },
    } } } },
};

const ALLOWED = new Set(Object.keys(PARSE_SCHEMA.properties.cards.items.properties));
/** 轻量校验（不引第三方依赖）。返回 { ok, errors }。 */
export function validateParse(out) {
  const errors = [];
  if (!out || typeof out !== 'object' || Array.isArray(out)) return { ok: false, errors: ['root_not_object'] };
  if (Object.keys(out).some((k) => k !== 'cards')) errors.push('root_extra_keys');
  if (!Array.isArray(out.cards)) return { ok: false, errors: [...errors, 'cards_not_array'] };
  if (out.cards.length > 10) errors.push('too_many_cards');
  out.cards.forEach((c, i) => {
    const e = (m) => errors.push(`cards[${i}].${m}`);
    if (!c || typeof c !== 'object') return e('not_object');
    for (const k of Object.keys(c)) if (!ALLOWED.has(k)) e(`extra:${k}`);
    if (!CATEGORIES.includes(c.category)) e('category');
    if (!['event', 'aggregate'].includes(c.kind)) e('kind');
    if (typeof c.note !== 'string' || [...c.note].length > 200) e('note');
    if (typeof c.confidence !== 'number' || c.confidence < 0 || c.confidence > 1) e('confidence');
    for (const t of ['event_time', 'end_time']) if (c[t] != null && !new RegExp(HHMM).test(c[t])) e(t);
    if (c.day_offset != null && ![0, -1].includes(c.day_offset)) e('day_offset');
    if (c.intensity != null && (typeof c.intensity !== 'string' || c.intensity.length > 20)) e('intensity');
  });
  return { ok: errors.length === 0, errors };
}
