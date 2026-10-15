/// 云端配置通过 --dart-define 注入，仓库里不放任何密钥。
/// 两个都为空时 App 完全离线运行，家庭和"参与改进"显示为未开放。
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
bool get cloudConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

/// 妈咪日记 AI 网关地址（--dart-define=AI_GATEWAY_URL=...），例如线上预计为
/// https://honghong.hczhw.com/ai/ （尚未部署）。为空时语音/文字整理不可用，只能手动保存为“其他”。
const _aiGatewayUrlDefine = String.fromEnvironment('AI_GATEWAY_URL');

/// 实际使用的网关地址：显式注入优先；否则按部署约定取 SUPABASE_URL 同域的 /ai/。
/// （0.1.39-dev 之前的发布构建没注入 AI_GATEWAY_URL，导致语音联网识别和整理整体不可用）
final aiGatewayUrl = resolveAiGatewayUrl(_aiGatewayUrlDefine, supabaseUrl);

String resolveAiGatewayUrl(String explicit, String supabase) {
  if (explicit.trim().isNotEmpty) return explicit.trim();
  final s = supabase.trim();
  if (s.isEmpty) return '';
  return '${s.endsWith('/') ? s : '$s/'}ai/';
}
bool get aiGatewayConfigured => cloudConfigured && aiGatewayUrl.isNotEmpty;
