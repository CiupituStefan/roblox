// Test de încărcare pentru relay (fără TikTok, fără Roblox):
//   * simulează un LIVE foarte aglomerat: înscrieri + gift-uri + combo-uri + spam
//     direct prin pipeline (ca evenimentele venite de la TikFinity)
//   * în paralel, un „server Roblox” fals interoghează /events ca BridgeService
//   * măsoară debitul, întârzierea (ageMs), duplicatele și memoria
// Rulare: npm run loadtest  (opțional: EVENTS=20000 RATE=2000 npm run loadtest)
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { loadConfig } from '../src/config.js';
import { EventStore } from '../src/eventStore.js';
import { Verifier } from '../src/verify.js';
import { Pipeline } from '../src/pipeline.js';
import { createRelayServer } from '../src/httpServer.js';

const TOTAL = Number(process.env.EVENTS ?? 20000);
const RATE = Number(process.env.RATE ?? 2000); // evenimente brute pe secundă
const KEY = 'x'.repeat(64);
const config = { ...loadConfig({}), relayKey: KEY, dataDir: mkdtempSync(path.join(tmpdir(), 'relay-load-')), maxEvents: 5000 };
const store = new EventStore({ ...config, persist: false });
const verifier = new Verifier({ config, persist: false });
const pipeline = new Pipeline({ config, store, verifier, log: { debug() {} } });
const server = createRelayServer({ config, store, pipeline, log: { error: console.error } });
await new Promise((r) => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}`;

const users = 3000;
let sent = 0;
let comboGroup = 0;
const memStart = process.memoryUsage().rss;
const t0 = Date.now();

// producător: amestec realist de evenimente
const producer = setInterval(() => {
  const batch = Math.ceil(RATE / 100);
  for (let i = 0; i < batch && sent < TOTAL; i++, sent++) {
    const uid = String(1000 + Math.floor(Math.random() * users));
    const r = Math.random();
    if (r < 0.15) {
      pipeline.handleChat({ userId: uid, uniqueId: 'u' + uid, nickname: 'N' + uid, comment: `!join Player${uid}`, msgId: `c${sent}` });
    } else if (r < 0.2) {
      pipeline.handleChat({ userId: uid, uniqueId: 'u' + uid, comment: 'salut!', msgId: `c${sent}` });
    } else if (r < 0.25) {
      pipeline.handleGift({ userId: uid, giftId: 5655, giftName: 'Rose', diamondCount: 1, giftType: 0, repeatCount: 1, repeatEnd: true, msgId: `g${sent - 1}` }); // duplicat posibil
    } else if (r < 0.6) {
      comboGroup += 1;
      for (let k = 1; k <= 5; k++) {
        pipeline.handleGift({ userId: uid, giftId: 5655, giftName: 'Rose', diamondCount: 1, giftType: 1, repeatCount: k, repeatEnd: k === 5, groupId: String(comboGroup), msgId: `s${sent}_${k}` });
      }
    } else {
      pipeline.handleGift({ userId: uid, giftId: 6064, giftName: 'Galaxy', diamondCount: 1000, giftType: 0, repeatCount: 1, repeatEnd: true, msgId: `g${sent}` });
    }
  }
  if (sent >= TOTAL) clearInterval(producer);
}, 10);

// consumator: ca BridgeService (interogare repetată, cursor = ack)
let cursor = 'resume';
let received = 0;
let maxAge = 0;
const ages = [];
const seen = new Set();
let duplicates = 0;
let requests = 0;
while (true) {
  const res = await fetch(`${base}/events?cursor=${cursor}&limit=200`, { headers: { authorization: `Bearer ${KEY}` } });
  const body = await res.json();
  requests += 1;
  for (const e of body.events) {
    if (seen.has(e.id)) duplicates += 1;
    seen.add(e.id);
    received += 1;
    ages.push(e.ageMs);
    maxAge = Math.max(maxAge, e.ageMs);
  }
  cursor = String(body.cursor);
  if (sent >= TOTAL && store.lastSeq === Number(cursor)) break;
  if (body.events.length < 200) await new Promise((r) => setTimeout(r, 50));
}
const seconds = (Date.now() - t0) / 1000;
ages.sort((a, b) => a - b);
const p95 = ages[Math.floor(ages.length * 0.95)] ?? 0;
const mem = Math.round((process.memoryUsage().rss - memStart) / 1048576);
server.close();

console.log('──────── Test de încărcare relay ────────');
console.log(`evenimente brute trimise : ${sent}  (${Math.round(sent / seconds)}/s)`);
console.log(`evenimente pentru Roblox : ${received}  (stocate ${store.lastSeq})`);
console.log(`   join: ${pipeline.stats.join}, joinRejected: ${pipeline.stats.joinRejected}, ignorate (spam/duplicate): ${pipeline.stats.dropped}`);
console.log(`cereri /events           : ${requests}`);
console.log(`întârziere relay→Roblox  : p95 ${p95} ms, max ${maxAge} ms`);
console.log(`duplicate livrate        : ${duplicates}`);
console.log(`memorie suplimentară     : ${mem} MB`);
console.log(`durată                   : ${seconds.toFixed(1)} s`);
if (duplicates > 0 || received !== store.lastSeq) {
  console.error('EȘEC: evenimente duplicate sau pierdute');
  process.exit(1);
}
console.log('OK: fără pierderi, fără duplicate');
