import { createServer } from 'node:http';
import { loadConfig, assertConfig } from './config.js';
import { createHandler } from './app.js';

const cfg = loadConfig();
assertConfig(cfg);
createServer(createHandler(cfg)).listen(cfg.port, cfg.host, () => {
  console.log(JSON.stringify({ msg: 'ai-gateway listening', host: cfg.host, port: cfg.port }));
});
