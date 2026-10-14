// OpenAI 兼容 chat/completions 客户端（DeepSeek）。json_object 模式；schema 写在提示词里，由网关强制校验。
// 只返回模型文本，不记录请求/响应内容；错误信息不含密钥。
export class LlmError extends Error {
  constructor(code, message) { super(message ?? code); this.code = code; }
}

export function createLlm(cfg, { fetchImpl = globalThis.fetch } = {}) {
  return {
    model: cfg.model,
    configured: Boolean(cfg.apiKey),
    /** @returns {Promise<string>} 模型返回的 content */
    async chat(messages, { maxTokens = 800, temperature = 0 } = {}) {
      if (!cfg.apiKey) throw new LlmError('llm_not_configured');
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), cfg.timeoutMs);
      let r;
      try {
        r = await fetchImpl(`${cfg.baseUrl.replace(/\/$/, '')}/chat/completions`, {
          method: 'POST',
          signal: ctrl.signal,
          headers: { 'content-type': 'application/json', authorization: `Bearer ${cfg.apiKey}` },
          body: JSON.stringify({ model: cfg.model, messages, temperature, max_tokens: maxTokens, response_format: { type: 'json_object' } }),
        });
      } catch (e) {
        throw new LlmError(e.name === 'AbortError' ? 'llm_timeout' : 'llm_network');
      } finally { clearTimeout(timer); }
      if (!r.ok) throw new LlmError('llm_http', `llm_http_${r.status}`);
      const j = await r.json().catch(() => null);
      const content = j?.choices?.[0]?.message?.content;
      if (typeof content !== 'string') throw new LlmError('llm_bad_response');
      return content;
    },
  };
}
