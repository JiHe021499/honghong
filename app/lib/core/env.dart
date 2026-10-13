/// 云端配置通过 --dart-define 注入，仓库里不放任何密钥。
/// 两个都为空时 App 完全离线运行，家庭和"参与改进"显示为未开放。
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
bool get cloudConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
