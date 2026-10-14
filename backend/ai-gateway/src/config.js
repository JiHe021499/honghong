// 全部配置来自环境变量；密钥不进仓库、不进 App。
export function loadConfig(env = process.env) {
  const cfg = {
    port: Number(env.PORT ?? 8787),
    host: env.HOST ?? '127.0.0.1', // 只监听本机，由 Caddy 反代
    jwtSecret: env.SUPABASE_JWT_SECRET ?? '',
    maxBodyBytes: Number(env.MAX_BODY_BYTES ?? 8 * 1024),
    maxTextChars: 500, // 架构 §8：文本长度上限 500 字
    limits: { 'diary-parse': Number(env.LIMIT_PARSE_PER_DAY ?? 60), 'diary-summary': Number(env.LIMIT_SUMMARY_PER_DAY ?? 3) },
    // LLM 供应商待 P0 评测后由用户拍板（D11），此处只留占位。
    llm: { provider: env.LLM_PROVIDER ?? '', apiKey: env.LLM_API_KEY ?? '', baseUrl: env.LLM_BASE_URL ?? '', model: env.LLM_MODEL ?? '' },
  };
  return cfg;
}

export function assertConfig(cfg) {
  if (!cfg.jwtSecret) throw new Error('缺少 SUPABASE_JWT_SECRET');
}
