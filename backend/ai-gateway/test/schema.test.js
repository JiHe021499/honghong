import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateParse } from '../src/schema.js';

const card = (o = {}) => ({ category: 'feeding', kind: 'aggregate', note: '吃奶6次', confidence: 0.9, time_period: 'all_day', attributes: { count: 6 }, ...o });

test('合法输出通过', () => assert.deepEqual(validateParse({ cards: [card(), card({ category: 'mood', kind: 'event', event_time: '15:00', intensity: '厉害' })] }), { ok: true, errors: [] }));
test('空数组合法', () => assert.equal(validateParse({ cards: [] }).ok, true));
test('非法分类/时间/置信度/多余键被拒', () => {
  const r = validateParse({ cards: [card({ category: 'bath', event_time: '3pm', confidence: 2, foo: 1 })], extra: 1 });
  assert.equal(r.ok, false);
  for (const m of ['root_extra_keys', 'cards[0].category', 'cards[0].event_time', 'cards[0].confidence', 'cards[0].extra:foo']) assert.ok(r.errors.includes(m), m);
});
test('超过 10 张卡被拒', () => assert.ok(validateParse({ cards: Array(11).fill(card()) }).errors.includes('too_many_cards')));
test('非对象被拒', () => { assert.equal(validateParse(null).ok, false); assert.equal(validateParse({ cards: 1 }).ok, false); });
