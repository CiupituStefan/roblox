// Punctul de pornire al relay-ului.
import { loadConfig, assertConfig } from './config.js';
import { EventStore } from './eventStore.js';
import { Verifier } from './verify.js';
import { Pipeline } from './pipeline.js';
import { createRelayServer } from './httpServer.js';
import { startTikfinity } from './sources/tikfinity.js';
import { startConnector } from './sources/connector.js';

const log = console;
const config = loadConfig();
try {
  assertConfig(config);
} catch (err) {
  log.error(err.message);
  process.exit(1);
}

const store = new EventStore(config);
const verifier = new Verifier({ config });
const pipeline = new Pipeline({ config, store, verifier, log });

const onChat = (data) =>
  pipeline.handleChat(data).catch((err) => log.error(`[chat] ${err.stack ?? err}`));
const onGift = (data) => {
  try {
    pipeline.handleGift(data);
  } catch (err) {
    log.error(`[gift] ${err.stack ?? err}`);
  }
};

let source = { name: 'none', status: () => 'none', stop() {} };
if (config.source === 'tikfinity') {
  source = startTikfinity({ url: config.tikfinityUrl, onChat, onGift, log });
} else if (config.source === 'connector') {
  try {
    source = await startConnector({ username: config.tiktokUsername, onChat, onGift, log });
  } catch (err) {
    log.error(err.message);
    process.exit(1);
  }
}

const server = createRelayServer({
  config,
  store,
  pipeline,
  getSourceStatus: () => `${source.name}:${source.status()}`,
  log,
});

server.listen(config.port, () => {
  log.info(`[relay] ascultă pe http://localhost:${config.port}  (sursă: ${config.source}, verificare obligatorie: ${config.requireVerification})`);
  log.info('[relay] expune-l pe HTTPS, ex: cloudflared tunnel --url http://localhost:' + config.port);
});

const cleanupTimer = setInterval(() => pipeline.cleanup(), 60000);
cleanupTimer.unref();

const shutdown = () => {
  log.info('[relay] oprire...');
  clearInterval(cleanupTimer);
  source.stop();
  store.flush();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 2000).unref();
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
