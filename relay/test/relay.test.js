import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { loadConfig } from '../src/config.js';
import { EventStore } from '../src/eventStore.js';
import { Verifier } from '../src/verify.js';
import { Pipeline } from '../src/pipeline.js';
import { GiftStreakTracker, parseCommand, extractUser, ROBLOX_NAME_RE } from '../src/normalize.js';
import { createRelayServer } from '../src/httpServer.js';

const KEY = 'k'.repeat(64);

function setup({ requireVerification = false, fetchImpl, clock = { t: 1_000_000 } } = {}) {
  const dataDir = mkdtempSync(path.join(tmpdir(), 'relay-test-'));
  const config = { ...loadConfig({}), dataDir, relayKey: KEY, requireVerification };
  const now = () => clock.t;
  const store = new EventStore({ ...config, now, persist: false });
  const verifier = new Verifier({ config, fetchImpl, now, persist: false });
  const pipeline = new Pipeline({ config, store, verifier, now, log: { debug() {} } });
  return { config, store, verifier, pipeline, clock };
}

const chat = (userId, comment, msgId) => ({ userId: String(userId), uniqueId: `u${userId}`, nickname: `N${userId}`, comment, msgId });
const gift = (userId, extra) => ({ userId: String(userId), uniqueId: `u${userId}`, giftId: 5655, giftName: 'Rose', diamondCount: 1, giftType: 0, repeatCount: 1, repeatEnd: true, ...extra });

test('parseCommand și validarea username-ului', () => {
  assert.deepEqual(parseCommand('!JOIN  @Builderman extra'), { command: '!join', arg: 'Builderman' });
  assert.equal(parseCommand('salut'), null);
  assert.ok(ROBLOX_NAME_RE.test('Abc_12'));
  assert.ok(!ROBLOX_NAME_RE.test('_abc'));
  assert.ok(!ROBLOX_NAME_RE.test('a_b_c'));
  assert.ok(!ROBLOX_NAME_RE.test('ab'));
  assert.ok(!ROBLOX_NAME_RE.test('nume invalid'));
});

test('extractUser acceptă formatul v1 și v2, respinge ID-uri invalide', () => {
  assert.equal(extractUser({ userId: '123', uniqueId: 'a' }).userId, '123');
  assert.equal(extractUser({ user: { userId: '456', uniqueId: 'b' } }).userId, '456');
  assert.equal(extractUser({ userId: 'abc' }), null);
  assert.equal(extractUser({}), null);
});

test('combo: se emite doar diferența, fără dubluri', () => {
  const t = new GiftStreakTracker();
  const g = (rc, end = false) => ({ id: 1, giftType: 1, repeatCount: rc, repeatEnd: end, groupId: 'g' });
  assert.equal(t.process('1', g(1)), 1);
  assert.equal(t.process('1', g(2)), 1);
  assert.equal(t.process('1', g(2)), 0); // duplicat
  assert.equal(t.process('1', g(5)), 3); // a sărit câteva actualizări
  assert.equal(t.process('1', g(5, true)), 0); // final
  assert.equal(t.process('1', g(1)), 1); // combo nou
  assert.equal(t.process('1', { id: 2, giftType: 0, repeatCount: 3, repeatEnd: true, groupId: '' }), 3);
});

test('!join valid ajunge în store cu identitatea TikTok din eveniment', async () => {
  const { pipeline, store } = setup();
  const ev = await pipeline.handleChat(chat(111, '!join Builderman', 'm1'));
  assert.equal(ev.type, 'join');
  assert.equal(ev.tiktokUserId, '111');
  assert.equal(ev.robloxName, 'Builderman');
  assert.equal(store.lastSeq, 1);
});

test('!join: duplicat msgId și spam sunt ignorate, username invalid respins', async () => {
  const { pipeline, store, clock } = setup();
  await pipeline.handleChat(chat(1, '!join Abc', 'same'));
  assert.equal(await pipeline.handleChat(chat(1, '!join Abc', 'same')), null);
  await pipeline.handleChat(chat(1, '!join Abc', 'x2'));
  assert.equal(await pipeline.handleChat(chat(1, '!join Abc', 'x3')), null, 'al 3-lea rapid = spam');
  clock.t += 6000;
  const bad = await pipeline.handleChat(chat(2, '!join a_b_c', 'x4'));
  assert.equal(bad.type, 'joinRejected');
  assert.equal(bad.code, 'INVALID_USERNAME');
  assert.equal(store.lastSeq, 3);
});

test('gift: duplicat msgId ignorat, combo agregat', () => {
  const { pipeline, store } = setup();
  pipeline.handleGift(gift(1, { msgId: 'g1' }));
  assert.equal(pipeline.handleGift(gift(1, { msgId: 'g1' })), null);
  for (let i = 1; i <= 4; i++) pipeline.handleGift(gift(1, { giftType: 1, repeatCount: i, repeatEnd: false, groupId: 'x', msgId: `s${i}` }));
  pipeline.handleGift(gift(1, { giftType: 1, repeatCount: 4, repeatEnd: true, groupId: 'x', msgId: 's-end' }));
  const total = store.events.filter((e) => e.type === 'gift').reduce((s, e) => s + e.gift.count, 0);
  assert.equal(total, 5); // 1 + 4
});

test('cursor: ack, resume sare gift-urile vechi dar păstrează join-urile recente', () => {
  const clock = { t: 1_000_000 };
  const { store } = setup({ clock });
  store.push({ type: 'gift', id: 'a' });
  store.push({ type: 'join', id: 'b' });
  let r = store.read('0');
  assert.equal(r.events.length, 2);
  assert.equal(r.cursor, 2);
  r = store.read('2'); // ack
  assert.equal(r.events.length, 0);
  assert.equal(store.lastAcked, 2);

  store.push({ type: 'gift', id: 'c' });
  store.push({ type: 'join', id: 'd' });
  clock.t += 60_000; // Roblox a fost oprit 1 minut
  r = store.read('resume');
  assert.deepEqual(r.events.map((e) => e.id), ['d'], 'gift vechi omis, join recent păstrat');
  assert.equal(r.cursor, 4);
  assert.equal(r.events[0].ageMs, 60_000);

  r = store.read('999');
  assert.equal(r.reset, true);
  assert.equal(r.cursor, 4);
});

function fakeRoblox({ users = {}, descriptions = {} } = {}) {
  return async (url, opts) => {
    const ok = (body) => ({ ok: true, status: 200, json: async () => body });
    if (url.endsWith('/v1/usernames/users')) {
      const name = JSON.parse(opts.body).usernames[0].toLowerCase();
      const u = users[name];
      return ok({ data: u ? [{ id: u.id, name: u.name }] : [] });
    }
    const m = url.match(/\/v1\/users\/(\d+)$/);
    if (m) return ok({ description: descriptions[m[1]] ?? '' });
    return { ok: false, status: 404, json: async () => ({}) };
  };
}

test('verificare: cod -> descriere -> legătură; impostorul este blocat', async () => {
  const descriptions = {};
  const fetchImpl = fakeRoblox({ users: { realplayer: { id: 42, name: 'RealPlayer' } }, descriptions });
  const { pipeline, clock } = setup({ fetchImpl });

  const codeEv = await pipeline.handleChat(chat(10, '!verify RealPlayer', 'v1'));
  assert.equal(codeEv.type, 'verifyCode');
  assert.match(codeEv.code, /^RACE-[A-Z]{6}$/);

  clock.t += 9000;
  const fail = await pipeline.handleChat(chat(10, '!verify', 'v2'));
  assert.equal(fail.code, 'CODE_NOT_FOUND');

  descriptions['42'] = `salut ${codeEv.code.toLowerCase()} !`;
  clock.t += 9000;
  const ok = await pipeline.handleChat(chat(10, '!verify', 'v3'));
  assert.equal(ok.ok, true);
  assert.equal(ok.code, 'VERIFIED');

  // impostorul (alt cont TikTok) încearcă să se înscrie cu contul verificat
  const imp = await pipeline.handleChat(chat(99, '!join realplayer', 'j1'));
  assert.equal(imp.type, 'joinRejected');
  assert.equal(imp.code, 'ROBLOX_BOUND_TO_OTHER');

  // proprietarul se poate înscrie și cu "!join" simplu
  const own = await pipeline.handleChat(chat(10, '!join', 'j2'));
  assert.equal(own.type, 'join');
  assert.equal(own.robloxName, 'RealPlayer');
  assert.equal(own.verified, true);
  assert.equal(own.robloxUserId, 42);
});

test('REQUIRE_VERIFICATION: cont neverificat respins', async () => {
  const fetchImpl = fakeRoblox({ users: { someone: { id: 7, name: 'Someone' } } });
  const { pipeline } = setup({ requireVerification: true, fetchImpl });
  const ev = await pipeline.handleChat(chat(5, '!join Someone', 'r1'));
  assert.equal(ev.code, 'NOT_VERIFIED');
});

test('HTTP: autentificare, /events, /simulate', async () => {
  const { config, store, pipeline } = setup();
  const server = createRelayServer({ config, store, pipeline, log: { error() {} } });
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const auth = { authorization: `Bearer ${KEY}` };
  try {
    assert.equal((await fetch(`${base}/health`)).status, 200);
    assert.equal((await fetch(`${base}/events`)).status, 401);
    assert.equal((await fetch(`${base}/events`, { headers: { authorization: 'Bearer wrong' } })).status, 401);

    let res = await fetch(`${base}/simulate`, {
      method: 'POST',
      headers: { ...auth, 'content-type': 'application/json' },
      body: JSON.stringify({ kind: 'gift', data: gift(77) }),
    });
    assert.equal(res.status, 200);

    res = await fetch(`${base}/events?cursor=0`, { headers: auth });
    const body = await res.json();
    assert.equal(body.events.length, 1);
    assert.equal(body.events[0].gift.name, 'Rose');
    assert.equal(body.events[0].tiktokUserId, '77');
    assert.equal(typeof body.events[0].ageMs, 'number');

    res = await fetch(`${base}/events?cursor=abc`, { headers: { 'x-relay-key': KEY } });
    assert.equal(res.status, 400);
  } finally {
    server.close();
  }
});
