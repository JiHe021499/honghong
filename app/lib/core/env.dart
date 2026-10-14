/// 云端配置通过 --dart-define 注入，仓库里不放任何密钥。
/// 两个都为空时 App 完全离线运行，家庭和"参与改进"显示为未开放。
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
bool get cloudConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

/// 妈咪日记 AI 网关地址（--dart-define=AI_GATEWAY_URL=...），例如线上预计为
/// https://honghong.hczhw.com/ai/ （尚未部署）。为空时语音/文字整理不可用，只能手动保存为“其他”。
const aiGatewayUrl = String.fromEnvironment('AI_GATEWAY_URL');
bool get aiGatewayConfigured => cloudConfigured && aiGatewayUrl.isNotEmpty;
