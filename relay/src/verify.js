// Verificarea proprietății contului Roblox + legăturile TikTok <-> Roblox.
//
//   !verify NumeRoblox  -> generează un cod (ex. RACE-KQPLMX) afișat pe ecran
//   (spectatorul pune codul în descrierea "About" a profilului Roblox)
//   !verify             -> relay-ul citește descrierea prin API-ul public Roblox;
//                          dacă găsește codul, legătura se salvează permanent.
//
// Doar proprietarul contului Roblox poate modifica descrierea, deci verificarea
// dovedește proprietatea. Ultima verificare reușită câștigă (proprietarul real își
// poate recupera oricând contul de la un impostor).
import path from 'node:path';
import { randomInt } from 'node:crypto';
import { readJson, writeJsonAtomic, RateLimiter } from './util.js';
import { ROBLOX_NAME_RE } from './normalize.js';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // doar litere: cifrele pot fi cenzurate de filtrul Roblox
const USER_AGENT = 'TikTokRaceRelay/1.0';

export function generateCode() {
  let s = '';
  for (let i = 0; i < 6; i++) s += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return `RACE-${s}`;
}

export class Verifier {
  constructor({ config, fetchImpl = globalThis.fetch, now = Date.now, persist = true }) {
    this.config = config;
    this.fetch = fetchImpl;
    this.now = now;
    this.persist = persist;
    this.file = path.join(config.dataDir, 'bindings.json');
    const saved = persist ? readJson(this.file, null) : null;
    this.byRoblox = saved?.byRoblox ?? {}; // robloxUserId -> { tiktokUserId, robloxName, at }
    this.byTikTok = saved?.byTikTok ?? {}; // tiktokUserId -> robloxUserId
    this.pending = new Map(); // tiktokUserId -> { robloxUserId, robloxName, code, expires }
    this.lookupCache = new Map(); // lowerName -> { value, expires }
    this.verifyLimiter = new RateLimiter({ capacity: 1, refillPerSec: 1 / 8, now });
  }

  hasBindings() {
    return Object.keys(this.byRoblox).length > 0;
  }

  async lookupUser(name) {
    const key = name.toLowerCase();
    const cached = this.lookupCache.get(key);
    if (cached && cached.expires > this.now()) return cached.value;
    const res = await this.fetch('https://users.roblox.com/v1/usernames/users', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'user-agent': USER_AGENT },
      body: JSON.stringify({ usernames: [name], excludeBannedUsers: true }),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error(`Roblox usernames API: HTTP ${res.status}`);
    const json = await res.json();
    const row = json?.data?.[0];
    const value = row ? { id: Number(row.id), name: String(row.name) } : null;
    this.lookupCache.set(key, { value, expires: this.now() + (value ? 600000 : 60000) });
    return value;
  }

  async getDescription(robloxUserId) {
    const res = await this.fetch(`https://users.roblox.com/v1/users/${robloxUserId}`, {
      headers: { 'user-agent': USER_AGENT },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error(`Roblox users API: HTTP ${res.status}`);
    const json = await res.json();
    return String(json?.description ?? '');
  }

  _save() {
    if (this.persist) writeJsonAtomic(this.file, { byRoblox: this.byRoblox, byTikTok: this.byTikTok });
  }

  _bind(tiktokUserId, robloxUserId, robloxName) {
    // șterge legăturile vechi ale ambelor părți
    const oldRoblox = this.byTikTok[tiktokUserId];
    if (oldRoblox !== undefined) delete this.byRoblox[oldRoblox];
    const oldOwner = this.byRoblox[robloxUserId];
    if (oldOwner) delete this.byTikTok[oldOwner.tiktokUserId];
    this.byRoblox[robloxUserId] = { tiktokUserId, robloxName, at: this.now() };
    this.byTikTok[tiktokUserId] = robloxUserId;
    this._save();
  }

  /*
    Decide dacă o înscriere e permisă. Returnează:
      { ok: true, robloxName, robloxUserId?, verified }
      { ok: false, code, robloxName? }
  */
  async checkJoin(user, robloxName) {
    if (!robloxName) {
      const boundId = this.byTikTok[user.userId];
      if (boundId !== undefined) {
        const b = this.byRoblox[boundId];
        return { ok: true, robloxName: b.robloxName, robloxUserId: Number(boundId), verified: true };
      }
      return { ok: false, code: 'MISSING_USERNAME' };
    }
    if (!ROBLOX_NAME_RE.test(robloxName)) return { ok: false, code: 'INVALID_USERNAME', robloxName };

    const required = this.config.requireVerification;
    if (!required && !this.hasBindings()) return { ok: true, robloxName, verified: false };

    let account;
    try {
      account = await this.lookupUser(robloxName);
    } catch (err) {
      console.warn(`[verify] lookup eșuat pentru ${robloxName}: ${err.message}`);
      return required ? { ok: false, code: 'LOOKUP_FAILED', robloxName } : { ok: true, robloxName, verified: false };
    }
    if (!account) {
      return required ? { ok: false, code: 'USER_NOT_FOUND', robloxName } : { ok: true, robloxName, verified: false };
    }
    const binding = this.byRoblox[account.id];
    if (binding && binding.tiktokUserId !== user.userId) {
      return { ok: false, code: 'ROBLOX_BOUND_TO_OTHER', robloxName: account.name };
    }
    const verified = Boolean(binding);
    if (required && !verified) return { ok: false, code: 'NOT_VERIFIED', robloxName: account.name };
    return { ok: true, robloxName: account.name, robloxUserId: account.id, verified };
  }

  /*
    Procesează "!verify [NumeRoblox]". Returnează un eveniment pentru Roblox
    (afișat pe ecran) sau null dacă e ignorat (spam).
  */
  async handleVerify(user, arg) {
    if (!this.verifyLimiter.allow(user.userId)) return null;
    const result = (fields) => ({ type: 'verifyResult', ...fields });
    let pending = this.pending.get(user.userId);
    if (pending && pending.expires <= this.now()) {
      this.pending.delete(user.userId);
      pending = undefined;
    }

    const wantsNew = arg && (!pending || pending.robloxName.toLowerCase() !== arg.toLowerCase());
    if (wantsNew) {
      if (!ROBLOX_NAME_RE.test(arg)) return result({ ok: false, code: 'INVALID_USERNAME', robloxName: arg });
      let account;
      try {
        account = await this.lookupUser(arg);
      } catch {
        return result({ ok: false, code: 'LOOKUP_FAILED', robloxName: arg });
      }
      if (!account) return result({ ok: false, code: 'USER_NOT_FOUND', robloxName: arg });
      if (this.byRoblox[account.id]?.tiktokUserId === user.userId) {
        return result({ ok: true, code: 'ALREADY_VERIFIED', robloxName: account.name });
      }
      const code = generateCode();
      this.pending.set(user.userId, {
        robloxUserId: account.id,
        robloxName: account.name,
        code,
        expires: this.now() + this.config.verifyCodeTtlMs,
      });
      return { type: 'verifyCode', code, robloxName: account.name, expiresInSec: Math.round(this.config.verifyCodeTtlMs / 1000) };
    }

    if (!pending) return result({ ok: false, code: arg ? 'CODE_EXPIRED' : 'MISSING_USERNAME' });

    let description;
    try {
      description = await this.getDescription(pending.robloxUserId);
    } catch {
      return result({ ok: false, code: 'LOOKUP_FAILED', robloxName: pending.robloxName });
    }
    if (!description.toUpperCase().includes(pending.code)) {
      return result({ ok: false, code: 'CODE_NOT_FOUND', robloxName: pending.robloxName, verifyCode: pending.code });
    }
    this._bind(user.userId, pending.robloxUserId, pending.robloxName);
    this.pending.delete(user.userId);
    return result({ ok: true, code: 'VERIFIED', robloxName: pending.robloxName });
  }

  cleanup() {
    const t = this.now();
    for (const [k, p] of this.pending) if (p.expires <= t) this.pending.delete(k);
    for (const [k, c] of this.lookupCache) if (c.expires <= t) this.lookupCache.delete(k);
    this.verifyLimiter.cleanup();
  }
}
