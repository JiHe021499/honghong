// P0 供应商评测脚本：对 OpenAI 兼容接口（国内厂商大多提供）发送拆分请求，检查
// 1) 是否支持 response_format=json_schema（strict）；2) 输出能否通过 schema；3) 分类召回；4) 延迟 P50/P90。
// 用法：LLM_BASE_URL=... LLM_API_KEY=... LLM_MODEL=... node eval/run.js
// 种子用例只有 8 句，正式评测集（50–100 句真实口语）在 P2 补齐。
import { readFileSync } from 'node:fs';
import { PARSE_SCHEMA, validateParse } from '../src/schema.js';

const { LLM_BASE_URL: base, LLM_API_KEY: key, LLM_MODEL: model, LLM_JSON_MODE: mode = 'json_schema' } = process.env;
// LLM_JSON_MODE=json_object：供应商不支持 json_schema 时的降级模式（schema 写进提示词 + 服务端 validateParse 强校验）
if (!base || !key || !model) { console.error('需要 LLM_BASE_URL / LLM_API_KEY / LLM_MODEL（供应商待用户拍板，见 README）'); process.exit(2); }
const cases = readFileSync(new URL('./cases.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const sys = '你是育儿记录助手。把妈妈的口语拆成结构化卡片，只输出符合 schema 的 JSON；不确定的放 other，不要编造。';
const sysMsg = mode === 'json_object' ? `${sys}\n输出 JSON，必须严格符合以下 JSON Schema：\n${JSON.stringify(PARSE_SCHEMA)}` : sys;
const rf = mode === 'json_object' ? { type: 'json_object' } : { type: 'json_schema', json_schema: { name: 'diary_parse', strict: true, schema: PARSE_SCHEMA } };
const lat = []; let schemaOk = 0, hit = 0, total = 0;
for (const c of cases) {
  const t0 = Date.now();
  const r = await fetch(`${base.replace(/\/$/, '')}/chat/completions`, {
    method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${key}` },
    body: JSON.stringify({ model, temperature: 0, messages: [{ role: 'system', content: sysMsg }, { role: 'user', content: c.text }],
      response_format: rf }),
  });
  lat.push(Date.now() - t0);
  if (!r.ok) { console.log(c.id, 'HTTP', r.status, (await r.text()).slice(0, 200)); continue; }
  let out; try { out = JSON.parse((await r.json()).choices[0].message.content); } catch { console.log(c.id, '非 JSON'); continue; }
  const v = validateParse(out); if (v.ok) schemaOk++;
  const cats = new Set((out.cards ?? []).map((x) => x.category));
  for (const e of c.expect) { total++; if (cats.has(e)) hit++; }
  console.log(c.id, v.ok ? 'schema✓' : `schema✗ ${v.errors[0]}`, [...cats].join(','));
}
lat.sort((a, b) => a - b);
const pct = (p) => lat[Math.min(lat.length - 1, Math.floor(p * lat.length))];
console.log(JSON.stringify({ model, mode, cases: cases.length, schema_pass: schemaOk, category_recall: +(hit / total).toFixed(2), p50_ms: pct(0.5), p90_ms: pct(0.9) }));
