import { createServer } from 'node:http';
import { loadConfig, assertConfig } from './config.js';
import { createHandler } from './app.js';
import { createAsrUpgrade } from './asr.js';
import { DailyLimiter } from './rate_limit.js';
import { entry, errorFields, stdoutLog } from './log.js';

// 未捕获的异常也按统一格式记一行（只记类型和位置）
process.on('uncaughtException', (e) => { stdoutLog(entry({ level: 'fatal', event: 'uncaught_exception', err_code: 'uncaught', ...errorFields(e) })); process.exit(1); });
process.on('unhandledRejection', (e) => stdoutLog(entry({ level: 'error', event: 'unhandled_rejection', err_code: 'unhandled_rejection', ...errorFields(e) })));

const cfg = loadConfig();
assertConfig(cfg);
const limiter = new DailyLimiter(cfg.limits);
const srv = createServer(createHandler(cfg, { limiter }));
srv.on('upgrade', createAsrUpgrade(cfg, { limiter }));
srv.listen(cfg.port, cfg.host, () => {
  stdoutLog(entry({ event: 'startup', msg: 'ai-gateway listening', host: cfg.host, port: cfg.port, asr_configured: cfg.xfyun.configured, llm_configured: Boolean(cfg.llm.apiKey) }));
});
