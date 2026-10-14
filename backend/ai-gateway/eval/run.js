// 妈咪日记评测：走网关同一套 parse/summary 流水线（含校验、重试、清洗），统计准确率与延迟。
// 用法：DEEPSEEK_API_KEY=... node eval/run.js [--out eval/results.json] [--concurrency 4]
// Key 只从环境变量读取，不打印、不写入结果文件。
import { readFileSync, writeFileSync } from 'node:fs';
import { loadConfig } from '../src/config.js';
import { createLlm } from '../src/llm.js';
import { parseDiary } from '../src/parse.js';
import { summarize, checkSummary } from '../src/summary.js';

const args = Object.fromEntries(process.argv.slice(2).reduce((a, x, i, arr) => (x.startsWith('--') ? [...a, [x.slice(2), arr[i + 1]]] : a), []));
const cfg = loadConfig();
if (!cfg.llm.apiKey) { console.error('需要环境变量 DEEPSEEK_API_KEY'); process.exit(2); }
const llm = createLlm({ ...cfg.llm, timeoutMs: Number(process.env.LLM_TIMEOUT_MS ?? 30000) });
const conc = Number(args.concurrency ?? 4);
const cases = readFileSync(new URL('./cases.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const sumCases = JSON.parse(readFileSync(new URL('./summary_cases.json', import.meta.url), 'utf8'));

async function pool(items, fn) {
  const out = new Array(items.length); let i = 0;
  await Promise.all(Array.from({ length: conc }, async () => { while (i < items.length) { const k = i++; out[k] = await fn(items[k]); } }));
  return out;
}

const matches = (card, chk) => {
  if (card.category !== chk.category) return false;
  for (const k of ['kind', 'event_time', 'end_time', 'time_period', 'day_offset']) if (chk[k] !== undefined && card[k] !== chk[k]) return false;
  if (chk.intensity_contains && !(card.intensity ?? '').includes(chk.intensity_contains) && !(card.note ?? '').includes(chk.intensity_contains)) return false;
  for (const [k, v] of Object.entries(chk.attributes ?? {})) if (card.attributes?.[k] !== v) return false;
  return true;
};

const parseRes = await pool(cases, async (c) => {
  const t0 = Date.now(); let attempts = 0; let first = null;
  try {
    const out = await parseDiary(llm, { text: c.text, ageInDays: c.age_in_days, now: c.now }, { onAttempt: (n, r) => { attempts = n; if (n === 1) first = r.root && r.ok; } });
    const got = [...new Set(out.cards.map((x) => x.category))].sort();
    const exp = [...new Set(c.expect.categories)];
    const checks = c.expect.checks.map((chk) => out.cards.some((card) => matches(card, chk)));
    return { id: c.id, text: c.text, ms: Date.now() - t0, attempts, firstOk: first, status: out.status, got, exp, checks, risk: out.risk.hit, expRisk: c.expect.risk, cards: out.cards };
  } catch (e) {
    return { id: c.id, text: c.text, ms: Date.now() - t0, attempts, firstOk: first, status: 'failed', error: e.reason ?? e.code ?? e.message, got: [], exp: c.expect.categories, checks: c.expect.checks.map(() => false), risk: false, expRisk: c.expect.risk };
  }
});

const sumRes = await pool(sumCases, async (c) => {
  const t0 = Date.now();
  try { const r = await summarize(llm, c); return { id: c.id, ms: Date.now() - t0, content: r.content, fallback: r.fallback, reason: r.fallback_reason ?? null, compliant: checkSummary(r.content, c.stats) === null }; }
  catch (e) { return { id: c.id, ms: Date.now() - t0, error: e.code ?? e.message }; }
});

const pct = (arr, p) => { const a = [...arr].sort((x, y) => x - y); return a[Math.min(a.length - 1, Math.ceil(p * a.length) - 1)]; };
const r2 = (x) => Math.round(x * 1000) / 1000;
let tp = 0, fp = 0, fn = 0;
for (const r of parseRes) { for (const g of r.got) (r.exp.includes(g) ? tp++ : fp++); for (const e of r.exp) if (!r.got.includes(e)) fn++; }
const allChecks = parseRes.flatMap((r) => r.checks);
const riskCases = parseRes.filter((r) => r.expRisk);
const metrics = {
  model: cfg.llm.model,
  prompt_version: (await import('../src/prompts.js')).PARSE_PROMPT_VERSION,
  parse: {
    cases: parseRes.length,
    schema_first_try_pass: r2(parseRes.filter((r) => r.firstOk).length / parseRes.length),
    retried: parseRes.filter((r) => r.attempts > 1).length,
    failed: parseRes.filter((r) => r.status === 'failed').length,
    partial: parseRes.filter((r) => r.status === 'partial').length,
    category_set_exact: r2(parseRes.filter((r) => r.got.join() === r.exp.join()).length / parseRes.length),
    category_precision: r2(tp / (tp + fp)),
    category_recall: r2(tp / (tp + fn)),
    field_checks: `${allChecks.filter(Boolean).length}/${allChecks.length}`,
    field_check_accuracy: r2(allChecks.filter(Boolean).length / allChecks.length),
    risk_recall: `${riskCases.filter((r) => r.risk).length}/${riskCases.length}`,
    risk_false_positive: parseRes.filter((r) => !r.expRisk && r.risk).length,
    latency_ms: { p50: pct(parseRes.map((r) => r.ms), 0.5), p90: pct(parseRes.map((r) => r.ms), 0.9), max: Math.max(...parseRes.map((r) => r.ms)) },
  },
  summary: {
    cases: sumRes.length,
    errors: sumRes.filter((r) => r.error).length,
    fallback: sumRes.filter((r) => r.fallback).length,
    compliant: sumRes.filter((r) => r.compliant).length,
    latency_ms: { p50: pct(sumRes.map((r) => r.ms), 0.5), p90: pct(sumRes.map((r) => r.ms), 0.9) },
  },
};
console.log(JSON.stringify(metrics, null, 2));
const misses = parseRes.filter((r) => r.status === 'failed' || r.got.join() !== r.exp.join() || r.checks.includes(false) || r.risk !== r.expRisk)
  .map((r) => ({ id: r.id, text: r.text, exp: r.exp, got: r.got, checks: r.checks, status: r.status, error: r.error, risk: r.risk, expRisk: r.expRisk, cards: r.cards }));
if (args.out) writeFileSync(args.out, JSON.stringify({ metrics, misses, summaries: sumRes }, null, 2));
