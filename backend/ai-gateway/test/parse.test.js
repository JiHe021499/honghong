import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseDiary, ParseFailed, sanitizeCard, uncoveredClauses } from '../src/parse.js';
import { riskHits } from '../src/risk.js';
import { LlmError } from '../src/llm.js';
import { fakeLlm } from './fake_llm.js';

const IN = (text) => ({ text, ageInDays: 102, now: '2026-10-14T20:31:00+08:00' });
const card = (o = {}) => ({ category: 'feeding', kind: 'aggregate', time_period: 'all_day', attributes: { count: 6 }, note: '今天吃奶6次', confidence: 0.9, ...o });
const J = (cards, extra = {}) => JSON.stringify({ cards, ...extra });

test('合规输出一次通过，不重试；提示词含 schema、原文与时间', async () => {
  const calls = [];
  const out = await parseDiary(fakeLlm([J([card()])], calls), IN('今天吃奶6次'));
  assert.equal(calls.length, 1);
  assert.equal(out.status, 'ok');
  assert.equal(out.cards.length, 1);
  const sys = calls[0][0].content;
  assert.match(sys, /"additionalProperties":false/);
  assert.match(calls[0].at(-1).content, /2026-10-14T20:31:00\+08:00/);
});

test('非 JSON → 重试一次后成功', async () => {
  const calls = [];
  const out = await parseDiary(fakeLlm(['不是json', J([card()])], calls), IN('今天吃奶6次'));
  assert.equal(calls.length, 2);
  assert.equal(out.status, 'ok');
});

test('两次都不合规（根结构）→ 报错', async () => {
  const calls = [];
  await assert.rejects(parseDiary(fakeLlm(['{"foo":1}', '[]'], calls), IN('今天吃奶6次')), (e) => e instanceof ParseFailed && e.reason === 'schema_invalid');
  assert.equal(calls.length, 2);
});

test('个别卡片两次都不合规 → 该卡转 other(0.3)，status=partial', async () => {
  const bad = J([card(), card({ category: 'bath', note: '洗了澡' })]);
  const calls = [];
  const out = await parseDiary(fakeLlm([bad], calls), IN('今天吃奶6次，洗了澡'));
  assert.equal(calls.length, 2);
  assert.equal(out.status, 'partial');
  assert.deepEqual(out.cards.map((c) => c.category), ['feeding', 'other']);
  assert.equal(out.cards[1].note, '洗了澡');
  assert.equal(out.cards[1].confidence, 0.3);
});

test('LLM 超时/网络错误直接抛出（由路由转 502）', async () => {
  await assert.rejects(parseDiary(fakeLlm([new LlmError('llm_timeout')]), IN('喂奶')), /llm_timeout/);
});

test('清洗：未知键丢弃、越界置空并降置信度、坏时间置空', () => {
  const c = sanitizeCard(card({ kind: 'event', time_period: null, event_time: '25:00', attributes: { count: 99, ml: 120, color: 'x', method: 'formula' } }), '喂了120毫升奶粉');
  assert.deepEqual(c.attributes, { ml: 120, method: 'formula' });
  assert.equal(c.event_time, null);
  assert.equal(c.confidence, 0.5);
  const ok = sanitizeCard(card(), '今天吃奶6次');
  assert.equal(ok.confidence, 0.9);
  assert.equal(ok.day_offset, 0);
});

test('诊断词不在原话里 → note 回退为原文、intensity 置空', () => {
  const c = sanitizeCard(card({ category: 'mood', kind: 'event', attributes: { type: '哭闹' }, note: '可能是生病了', intensity: '不正常' }), '下午一直哭');
  assert.equal(c.note, '下午一直哭');
  assert.equal(c.intensity, null);
  assert.ok(c.confidence <= 0.5);
  // 妈妈自己说的不回退
  const own = sanitizeCard(card({ category: 'other', kind: 'event', attributes: { topic: '体温' }, note: '好像生病了' }), '好像生病了');
  assert.equal(own.note, '好像生病了');
});

test('原文覆盖检查：漏掉的分句追加 other 卡', async () => {
  const out = await parseDiary(fakeLlm([J([card()])]), IN('今天吃奶6次，下午去打了疫苗'));
  assert.equal(out.cards.length, 2);
  assert.equal(out.cards[1].category, 'other');
  assert.match(out.cards[1].note, /疫苗/);
  assert.deepEqual(uncoveredClauses('嗯，今天吃奶6次', [card()]), []);
});

test('风险词：命中高烧/抽搐/体温≥39', async () => {
  assert.deepEqual(riskHits('今天有点发烧38.6'), []);
  assert.ok(riskHits('烧到39.2度了').length);
  assert.ok(riskHits('刚才抽搐了一下').includes('抽搐'));
  const out = await parseDiary(fakeLlm([J([card({ category: 'other', kind: 'event', time_period: null, attributes: { topic: '体温' }, note: '高烧不退' })])]), IN('高烧不退'));
  assert.equal(out.risk.hit, true);
});

test('模型返回空卡片 → 原文 other 兜底', async () => {
  const out = await parseDiary(fakeLlm([J([])]), IN('嗯嗯'));
  assert.equal(out.cards.length, 1);
  assert.equal(out.cards[0].category, 'other');
  assert.equal(out.status, 'partial');
});

test('aggregate 缺时段自动补 all_day；超过 10 张截断', async () => {
  const out = await parseDiary(fakeLlm([J(Array.from({ length: 12 }, () => card({ time_period: null })))]), IN('今天吃奶6次'));
  assert.ok(out.cards.length <= 10);
});

test('口头语（嗯…那个）不触发覆盖补卡', () => {
  const cards = [{ note: '刚刚喂了奶' }, { note: '然后拉了' }];
  assert.deepEqual(uncoveredClauses('嗯…那个，刚刚喂了奶，然后拉了', cards), []);
});
