import { createServer } from 'node:http';
import { loadConfig, assertConfig } from './config.js';
import { createHandler } from './app.js';
import { createAsrUpgrade } from './asr.js';
import { DailyLimiter } from './rate_limit.js';

const cfg = loadConfig();
assertConfig(cfg);
const limiter = new DailyLimiter(cfg.limits);
const srv = createServer(createHandler(cfg, { limiter }));
srv.on('upgrade', createAsrUpgrade(cfg, { limiter }));
srv.listen(cfg.port, cfg.host, () => {
  console.log(JSON.stringify({ msg: 'ai-gateway listening', host: cfg.host, port: cfg.port, asr_configured: cfg.xfyun.configured }));
});
