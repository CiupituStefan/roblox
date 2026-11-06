// API HTTP pentru serverul Roblox. Expus public prin HTTPS (Cloudflare Tunnel /
// hosting). Toate rutele (cu excepția /health) cer cheia: header
// "Authorization: Bearer <RELAY_KEY>" (sau "X-Relay-Key: <RELAY_KEY>").
import { createServer } from 'node:http';
import { createHash, timingSafeEqual, randomUUID } from 'node:crypto';
import { RateLimiter } from './util.js';

const MAX_BODY = 16 * 1024;

const digest = (s) => createHash('sha256').update(String(s)).digest();

export function createRelayServer({ config, store, pipeline, getSourceStatus = () => 'none', getHealth = () => ({}), log = console }) {
  const keyDigest = digest(config.relayKey);
  const authFailures = new RateLimiter({ capacity: 20, refillPerSec: 20 / 60 }); // 20 greșeli/minut per IP

  const isAuthorized = (req) => {
    let provided = req.headers['x-relay-key'];
    const auth = req.headers.authorization;
    if (!provided && typeof auth === 'string' && auth.startsWith('Bearer ')) provided = auth.slice(7);
    if (typeof provided !== 'string' || provided.length === 0) return false;
    return timingSafeEqual(digest(provided), keyDigest);
  };

  const send = (res, status, body) => {
    const json = JSON.stringify(body);
    res.writeHead(status, {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'content-length': Buffer.byteLength(json),
    });
    res.end(json);
  };

  const readBody = (req) =>
    new Promise((resolve, reject) => {
      let size = 0;
      const chunks = [];
      req.on('data', (c) => {
        size += c.length;
        if (size > MAX_BODY) {
          reject(new Error('BODY_TOO_LARGE'));
          req.destroy();
        } else chunks.push(c);
      });
      req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      req.on('error', reject);
    });

  const server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://relay.local');
    const ip = req.headers['cf-connecting-ip'] || req.socket.remoteAddress || 'unknown';

    if (req.method === 'GET' && url.pathname === '/health') {
      return send(res, 200, { ok: true });
    }

    if (!isAuthorized(req)) {
      if (!authFailures.allow(ip)) return send(res, 429, { error: 'TOO_MANY_ATTEMPTS' });
      return send(res, 401, { error: 'UNAUTHORIZED' });
    }

    try {
      if (req.method === 'GET' && url.pathname === '/events') {
        const result = store.read(url.searchParams.get('cursor') ?? 'resume', Number(url.searchParams.get('limit') ?? 100));
        if (result.error) return send(res, 400, { error: result.error });
        return send(res, 200, { ...result, source: getSourceStatus(), serverTime: Date.now() });
      }

      if (req.method === 'GET' && url.pathname === '/status') {
        return send(res, 200, {
          source: getSourceStatus(),
          lastSeq: store.lastSeq,
          lastAcked: store.lastAcked,
          buffered: store.events.length,
          stats: pipeline.stats,
          requireVerification: config.requireVerification,
          verifiedAccounts: Object.keys(pipeline.verifier.byRoblox).length,
          ...getHealth(),
        });
      }

      if (req.method === 'POST' && url.pathname === '/simulate') {
        if (!config.allowSimulate) return send(res, 403, { error: 'SIMULATE_DISABLED' });
        let body;
        try {
          body = JSON.parse(await readBody(req));
        } catch {
          return send(res, 400, { error: 'INVALID_JSON' });
        }
        const data = { msgId: randomUUID(), ...(body.data ?? {}) };
        let stored = null;
        if (body.kind === 'chat') stored = await pipeline.handleChat(data);
        else if (body.kind === 'gift') stored = pipeline.handleGift(data);
        else return send(res, 400, { error: 'UNKNOWN_KIND' });
        return send(res, 200, { ok: true, stored });
      }

      return send(res, 404, { error: 'NOT_FOUND' });
    } catch (err) {
      log.error(`[http] eroare: ${err.stack ?? err}`);
      return send(res, 500, { error: 'INTERNAL' });
    }
  });

  server.headersTimeout = 10000;
  server.requestTimeout = 15000;
  return server;
}
