/// 本地风险词表（与网关 src/risk.js 保持一致；初版，需医学顾问审核）。
/// 命中只显示固定文案“如有担心，请及时就医。”，不做任何判断。
const riskWords = ['高烧', '发高烧', '抽搐', '抽筋', '惊厥', '呼吸困难', '喘不上气', '憋气', '嘴唇发紫', '发紫', '昏迷', '叫不醒', '没反应',
  '吐血', '便血', '血便', '拉血', '持续高热', '高热', '脱水', '囟门凸起', '摔到头', '撞到头', '误吞', '吞了'];

final _temp = RegExp(r'(\d{2}(?:\.\d)?)\s*(?:度|℃|°)?');

bool hasRiskWords(String text) {
  if (riskWords.any(text.contains)) return true;
  for (final m in _temp.allMatches(text)) {
    final v = double.tryParse(m[1]!);
    if (v != null && v >= 39 && v <= 43 && (m[0]!.contains(RegExp('[度℃°]')) || text.contains('烧') || text.contains('体温'))) return true;
  }
  return false;
}
