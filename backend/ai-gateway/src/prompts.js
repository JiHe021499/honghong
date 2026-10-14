// 提示词版本化：改提示词必须升版本号，响应和指标里都带上版本。
// parse-v2：补充尿布 type 判定规则（v1 评测中“拉了”常漏标 poo）。
import { PARSE_SCHEMA } from './schema.js';

export const PARSE_PROMPT_VERSION = 'parse-v2';
export const SUMMARY_PROMPT_VERSION = 'sum-v1';

const ATTRS = `attributes 只允许下列键（其他键不要输出，未提及的不要输出）：
- feeding：count(整数1-30)、method("breast"亲喂|"bottle_breast"瓶喂母乳|"formula"奶粉)、side("left"|"right"|"both")、ml(整数1-400)、duration_min(整数1-180)
- sleep：duration_min(整数1-960)、night_wakings(整数0-20)
- diaper：type("pee"尿|"poo"便|"both")、count(整数1-30)、texture_note(性状原话，如"黄色软便")
- mood：type(≤10字，如"哭闹""开心""烦躁")
- other：topic(≤10字，如"体温""辅食""洗澡""疫苗")`;

export function parseMessages({ text, ageInDays, now }) {
  const system = `你是育儿记录助手。把妈妈说的一句口语拆成结构化卡片，只输出一个 JSON 对象，必须严格符合下面的 JSON Schema：
${JSON.stringify(PARSE_SCHEMA)}

${ATTRS}

规则：
1. 分类只有 feeding(喂奶) / sleep(睡眠) / diaper(尿布、尿、拉、便便) / mood(情绪、哭闹、开心) / other(体温、辅食、洗澡、疫苗、吐奶等其它)。
2. 一句多事拆成多张卡；同一分类同一时段的描述合并为一张。
3. kind：说的是单次事件用 "event"；“今天一共/今天吃奶6次/一天拉了3次”这种当日总数用 "aggregate"，time_period 用 "all_day"。
4. 时间：明确钟点给 event_time("HH:mm"，24 小时制，下午3点=15:00，晚上8点=20:00)；有结束时间给 end_time；只说了上午/下午/晚上/夜里给 time_period(morning/afternoon/evening/night)，event_time 为 null；没说时间两者都为 null。
5. day_offset：说“昨晚/昨天/夜里”且指的是前一天时为 -1，否则 0。参考当前时间判断。
6. 不臆造：只提取明确说出的信息，没说的字段不要输出、不要推测数值。
7. 程度词原样保留在 intensity（如“厉害”“很香”“一点点”）。
8. note 填该卡对应的原话片段（必须摘自原文），不要改写，不要加评价。
9. 不做任何诊断、不说是否正常、不给用药建议。
10. 月龄只用于理解：6 个月以下“吃”默认是喂奶；6 个月以上提到粥/米粉/果泥等是辅食(other, topic=辅食)。
11. confidence 为 0~1，越不确定越低。无法归类的内容放 other，不要丢弃任何内容。
12. 尿布 type：说到“拉/拉了/便便/大便/拉肚子”为 "poo"，只说“尿”为 "pee"，又尿又拉为 "both"；性状（稀、绿、奶瓣、水样）放 texture_note。
13. 顶层只有 "cards" 一个键。`;
  const user = JSON.stringify({ text, age_in_days: ageInDays, now });
  return [
    { role: 'system', content: system },
    { role: 'user', content: JSON.stringify({ text: '今天吃奶6次，下午哭得厉害', age_in_days: 60, now: '2026-10-14T20:31:00+08:00' }) },
    { role: 'assistant', content: JSON.stringify({ cards: [
      { category: 'feeding', kind: 'aggregate', event_time: null, end_time: null, day_offset: 0, time_period: 'all_day', attributes: { count: 6 }, intensity: null, note: '今天吃奶6次', confidence: 0.95 },
      { category: 'mood', kind: 'event', event_time: null, end_time: null, day_offset: 0, time_period: 'afternoon', attributes: { type: '哭闹' }, intensity: '厉害', note: '下午哭得厉害', confidence: 0.9 },
    ] }) },
    { role: 'user', content: user },
  ];
}

export function summaryMessages({ date, ageInDays, stats }) {
  const system = `你是温和的育儿记录助手。根据当天的统计数据写一句今日小结，输出 JSON：{"content":"..."}。
要求：
- 不超过 50 个汉字，一句话，语气温和，可以以“妈妈辛苦啦”之类结尾。
- 只能使用给定的数字和标签，不得编造任何没给出的事实或数字。
- feed.count 是实际记录的次数；feed.aggregate_count 是妈妈口头说的全天次数。两者都有且不同时分开说（如“记录了4次喂奶，妈妈提到全天约6次”），不要相加、不要取最大值。
- 不做诊断、不说是否正常、不提用药、不使用恐吓性语言，不提生病。
- 睡眠 total_min 换算成“约X小时”或“X小时Y分钟”。`;
  return [{ role: 'system', content: system }, { role: 'user', content: JSON.stringify({ date, age_in_days: ageInDays, stats }) }];
}
