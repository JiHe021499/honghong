import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkSummary, normalizeStats, summarize, templateSummary } from '../src/summary.js';
import { LlmError } from '../src/llm.js';
import { fakeLlm } from './fake_llm.js';

const STATS = { feed: { count: 4, total_ml: 360, aggregate_count: 6 }, sleep: { count: 3, total_min: 410 }, diaper: { count: 5, poo: 1 },
  mood: [{ period: 'afternoon', type: '哭闹', intensity: '厉害' }], other: ['洗澡'] };
const C = (content) => JSON.stringify({ content });

test('stats 校验', () => {
  assert.ok(normalizeStats(STATS));
  assert.ok(normalizeStats({}));
  assert.equal(normalizeStats({ feed: { count: -1 } }), null);
  assert.equal(normalizeStats({ feed: { count: 1.5 } }), null);
  assert.equal(normalizeStats({ other: ['这是一个超过十个字的很长的标签'] }), null);
  assert.equal(normalizeStats([]), null);
  assert.deepEqual(normalizeStats({ feed: { count: 2, extra: 1 } }), { feed: { count: 2 } });
});

test('合规检查：长度、诊断词、编造数字、睡眠小时换算允许', () => {
  assert.equal(checkSummary('今天宝宝吃了4次奶、睡了约7小时，妈妈辛苦啦。', STATS), null);
  assert.equal(checkSummary('记录了4次喂奶，妈妈提到全天约6次，辛苦啦', STATS), null);
  assert.equal(checkSummary('宝宝吃了8次奶', STATS), 'fabricated_number');
  assert.equal(checkSummary('宝宝下午哭闹可能是生病了', STATS), 'diagnosis');
  assert.equal(checkSummary('长'.repeat(51), STATS), 'too_long');
  assert.equal(checkSummary('', STATS), 'empty');
});

test('合规一次通过', async () => {
  const calls = [];
  const r = await summarize(fakeLlm([C('今天吃了4次奶，睡了约7小时，妈妈辛苦啦')], calls), { date: '2026-10-14', stats: STATS });
  assert.equal(calls.length, 1);
  assert.equal(r.fallback, false);
  assert.equal(r.prompt_version, 'sum-v1');
  assert.doesNotMatch(calls[0][1].content, /原话/);
});

test('不合规重试一次后成功；两次都不合规用模板（只用统计数字）', async () => {
  const calls = [];
  const r = await summarize(fakeLlm([C('吃了10次奶'), C('今天吃了4次奶，妈妈辛苦啦')], calls), { date: '2026-10-14', stats: STATS });
  assert.equal(calls.length, 2);
  assert.equal(r.fallback, false);
  const t = await summarize(fakeLlm(['oops']), { date: '2026-10-14', stats: STATS });
  assert.equal(t.fallback, true);
  assert.equal(t.content, templateSummary(STATS));
  assert.equal(checkSummary(t.content, STATS), null, '模板本身也合规');
});

test('模板：汇总与实际次数分开说，不相加（D2）', () => {
  assert.equal(templateSummary(STATS), '今天记录了4次喂奶、妈妈提到全天约6次、睡了约7小时、换了5次尿布，辛苦啦');
  assert.equal(templateSummary({}), '今天也辛苦啦，早点休息');
});

test('LLM 故障抛出（路由转 502，客户端记 failed 下次再试）', async () => {
  await assert.rejects(summarize(fakeLlm([new LlmError('llm_http')]), { date: '2026-10-14', stats: STATS }), /llm_http/);
});
