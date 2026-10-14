// 合规词表（初版，需医学顾问审核，见 PRD 待定问题 10）。
// 风险词：只在输入原文里查，命中则确认页显示固定文案“如有担心，请及时就医”，不做判断。
export const RISK_WORDS = ['高烧', '发高烧', '抽搐', '抽筋', '惊厥', '呼吸困难', '喘不上气', '憋气', '嘴唇发紫', '发紫', '昏迷', '叫不醒', '没反应',
  '吐血', '便血', '血便', '拉血', '持续高热', '高热', '脱水', '囟门凸起', '摔到头', '撞到头', '误吞', '吞了'];
// 诊断/恐吓/用药词：不允许出现在 AI 产出的 note/intensity/小结里（除非是妈妈原话）。
export const DIAGNOSIS_WORDS = ['生病', '病了', '不正常', '异常', '需要用药', '吃药', '用药', '诊断', '感染', '肺炎', '肠胀气症', '湿疹', '黄疸', '发育迟缓', '危险', '严重', '必须就医', '赶紧去医院', '可能是'];

export function riskHits(text) {
  // 体温数字 ≥ 39 也算高烧
  const hits = RISK_WORDS.filter((w) => text.includes(w));
  const m = text.match(/(\d{2}(?:\.\d)?)\s*(?:度|℃|°)/g) ?? text.match(/\b(39|4[0-2])(?:\.\d)?\b/g) ?? [];
  if (m.some((x) => parseFloat(x) >= 39 && parseFloat(x) <= 43) && !hits.includes('高烧')) hits.push('体温≥39');
  return hits;
}

/** 返回 text 中出现、但原文 source 中没有的诊断词 */
export function diagnosisHits(text, source = '') {
  return DIAGNOSIS_WORDS.filter((w) => text.includes(w) && !source.includes(w));
}
