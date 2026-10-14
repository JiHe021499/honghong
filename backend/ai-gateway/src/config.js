// 全部配置来自环境变量；密钥不进仓库、不进 App。
export function loadConfig(env = process.env) {
  const cfg = {
    port: Number(env.PORT ?? 8787),
    host: env.HOST ?? '127.0.0.1', // 只监听本机，由 OpenResty 反代
    jwtSecret: env.SUPABASE_JWT_SECRET ?? '',
    maxBodyBytes: Number(env.MAX_BODY_BYTES ?? 8 * 1024),
    maxTextChars: 500, // 架构 §8：文本长度上限 500 字
    limits: {
      'diary-parse': Number(env.LIMIT_PARSE_PER_DAY ?? 60),
      'diary-summary': Number(env.LIMIT_SUMMARY_PER_DAY ?? 3),
      'diary-asr': Number(env.LIMIT_ASR_PER_DAY ?? 60), // 联网识别：每人每天 60 次（北京时间分日）
    },
    // 讯飞语音听写（流式版）：本机识别不可用时的联网兜底（D9 修订）。三项都有才算配置好，否则 /diary-asr 返回 503。
    xfyun: {
      appId: env.XFYUN_APPID ?? '',
      apiKey: env.XFYUN_API_KEY ?? '',
      apiSecret: env.XFYUN_API_SECRET ?? '',
      url: env.XFYUN_URL ?? 'wss://iat-api.xfyun.cn/v2/iat',
      maxSeconds: 60, // 单次最长 60 秒音频（讯飞上限）
      idleMs: Number(env.ASR_IDLE_MS ?? 8000), // 客户端 8s 不发数据就结束（讯飞 10s 断开）
    },
    // LLM：用户已选 DeepSeek（json_object 降级方案，D11）。OpenAI 兼容接口。
    llm: {
      provider: env.LLM_PROVIDER ?? 'deepseek',
      apiKey: env.DEEPSEEK_API_KEY ?? env.LLM_API_KEY ?? '',
      baseUrl: env.LLM_BASE_URL ?? 'https://api.deepseek.com',
      model: env.LLM_MODEL ?? 'deepseek-chat',
      timeoutMs: Number(env.LLM_TIMEOUT_MS ?? 7000), // 客户端 8s 超时，留 1s 余量
    },
    idempotencyTtlMs: 24 * 3600 * 1000,
  };
  cfg.xfyun.configured = Boolean(cfg.xfyun.appId && cfg.xfyun.apiKey && cfg.xfyun.apiSecret);
  return cfg;
}

export function assertConfig(cfg) {
  if (!cfg.jwtSecret) throw new Error('缺少 SUPABASE_JWT_SECRET');
}
