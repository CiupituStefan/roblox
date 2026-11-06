// Punctul de pornire al relay-ului.
import { loadConfig, assertConfig } from './config.js';
import { EventStore } from './eventStore.js';
import { Verifier } from './verify.js';
import { Pipeline } from './pipeline.js';
import { createRelayServer } from './httpServer.js';
import { startTikfinity } from './sources/tikfinity.js';
import { startConnector } from './sources/connector.js';

const log = console;
const startedAt = Date.now();
let store = null; // setat mai jos; folosit și la salvarea de urgență

// O eroare neprevăzută într-un callback nu trebuie să oprească relay-ul în mijlocul LIVE-ului.
process.on('unhandledRejection', (reason) => {
  log.error(`[relay] promisiune respinsă netratată: ${reason?.stack ?? reason}`);
});
process.on('uncaughtException', (err) => {
  log.error(`[relay] eroare fatală: ${err?.stack ?? err}`);
  // starea poate fi coruptă: salvăm și ieșim; supervizorul (npm run start:live) repornește
  try {
    store?.flush();
  } catch {
    /* ignorat */
  }
  process.exit(1);
});

const config = loadConfig();
try {
  assertConfig(config);
} catch (err) {
  log.error(err.message);
  process.exit(1);
}

store = new EventStore(config);
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
  getHealth: () => ({
    uptimeSec: Math.round((Date.now() - startedAt) / 1000),
    memoryMb: Math.round(process.memoryUsage().rss / 1048576),
  }),
  log,
});

server.listen(config.port, () => {
  log.info(`[relay] ascultă pe http://localhost:${config.port}  (sursă: ${config.source}, verificare obligatorie: ${config.requireVerification})`);
  log.info('[relay] expune-l pe HTTPS, ex: cloudflared tunnel --url http://localhost:' + config.port);
});

const cleanupTimer = setInterval(() => pipeline.cleanup(), 60000);
// linie de sănătate în consolă la fiecare 10 minute
const healthTimer = setInterval(() => {
  const mem = Math.round(process.memoryUsage().rss / 1048576);
  log.info(`[relay] sănătate: sursă ${source.name}:${source.status()}, evenimente ${store.lastSeq}, confirmate ${store.lastAcked}, memorie ${mem} MB, ignorate ${pipeline.stats.dropped}`);
}, 10 * 60 * 1000);
healthTimer.unref();
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
