// Încarcă și validează configurarea din .env / variabile de mediu.
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const envFile = path.join(ROOT, '.env');
if (existsSync(envFile) && typeof process.loadEnvFile === 'function') {
  process.loadEnvFile(envFile);
}

const bool = (v, def) => (v === undefined || v === '' ? def : /^(1|true|yes|da)$/i.test(v));
const int = (v, def) => {
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) ? n : def;
};
const list = (v, def) =>
  (v && v.trim() ? v : def)
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);

export function loadConfig(env = process.env) {
  const config = {
    root: ROOT,
    dataDir: env.DATA_DIR || path.join(ROOT, 'data'),
    relayKey: env.RELAY_KEY || '',
    port: int(env.PORT, 8787),
    source: (env.SOURCE || 'tikfinity').toLowerCase(),
    tikfinityUrl: env.TIKFINITY_WS_URL || 'ws://localhost:21213/',
    tiktokUsername: (env.TIKTOK_USERNAME || '').replace(/^@/, ''),
    joinCommands: list(env.JOIN_COMMANDS, '!join,!intra,!race'),
    verifyCommands: list(env.VERIFY_COMMANDS, '!verify,!verifica'),
    requireVerification: bool(env.REQUIRE_VERIFICATION, false),
    allowSimulate: bool(env.ALLOW_SIMULATE, true),
    giftReplayMaxAgeMs: int(env.GIFT_REPLAY_MAX_AGE_MS, 20000),
    joinReplayMaxAgeMs: int(env.JOIN_REPLAY_MAX_AGE_MS, 600000),
    maxEvents: int(env.MAX_EVENTS, 5000),
    verifyCodeTtlMs: 15 * 60 * 1000,
  };
  return config;
}

export function assertConfig(config) {
  const problems = [];
  if (!config.relayKey || config.relayKey.length < 32) {
    problems.push('RELAY_KEY lipsește sau e prea scurtă (minim 32 caractere). Rulează: npm run genkey');
  }
  if (!['tikfinity', 'connector', 'none'].includes(config.source)) {
    problems.push(`SOURCE necunoscut: ${config.source}`);
  }
  if (config.source === 'connector' && !config.tiktokUsername) {
    problems.push('SOURCE=connector necesită TIKTOK_USERNAME');
  }
  if (problems.length) {
    throw new Error('Configurare invalidă:\n - ' + problems.join('\n - '));
  }
}
