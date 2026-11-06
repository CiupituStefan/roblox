// Normalizează evenimentele brute venite de la TikFinity / tiktok-live-connector
// (ambele folosesc același format; versiunea 2 a bibliotecii pune datele în `user`
// și `giftDetails`, de aceea citim cu variante de rezervă).
import { sanitizeText } from './util.js';

const TIKTOK_ID_RE = /^\d{1,32}$/;

export function extractUser(data) {
  const u = data?.user ?? {};
  let userId = data?.userId ?? u.userId ?? u.id ?? data?.userDetails?.userId;
  if (typeof userId === 'number') userId = Math.trunc(userId).toString();
  userId = userId == null ? '' : String(userId);
  if (!TIKTOK_ID_RE.test(userId)) return null; // fără identitate stabilă -> ignorăm
  return {
    userId,
    uniqueId: sanitizeText(data?.uniqueId ?? u.uniqueId ?? '', 32),
    nickname: sanitizeText(data?.nickname ?? u.nickname ?? data?.uniqueId ?? u.uniqueId ?? '', 32),
  };
}

export function extractMsgId(data) {
  const id = data?.msgId ?? data?.common?.msgId ?? data?.eventId;
  return id == null ? null : String(id);
}

export function extractComment(data) {
  return String(data?.comment ?? data?.content ?? '').slice(0, 200);
}

export function extractGift(data) {
  const d = data?.giftDetails ?? data?.gift ?? {};
  const ext = data?.extendedGiftInfo ?? {};
  const toInt = (v, def) => {
    const n = Number(v);
    return Number.isFinite(n) ? Math.trunc(n) : def;
  };
  return {
    id: toInt(data?.giftId ?? d.id ?? d.giftId, 0),
    name: sanitizeText(data?.giftName ?? d.giftName ?? d.name ?? ext.name ?? '', 40),
    diamonds: Math.max(0, toInt(data?.diamondCount ?? d.diamondCount ?? ext.diamond_count, 0)),
    giftType: toInt(data?.giftType ?? d.giftType, 0),
    repeatCount: Math.max(1, toInt(data?.repeatCount, 1)),
    repeatEnd: Boolean(data?.repeatEnd),
    groupId: data?.groupId == null ? '' : String(data.groupId),
  };
}

// Comanda din chat: "!join NumeRoblox" -> { command: "!join", arg: "NumeRoblox" }
export function parseCommand(comment) {
  const parts = comment.trim().split(/\s+/);
  if (!parts[0] || !parts[0].startsWith('!')) return null;
  return { command: parts[0].toLowerCase(), arg: parts[1] ? parts[1].replace(/^@/, '') : '' };
}

export const ROBLOX_NAME_RE = /^(?=.{3,20}$)[A-Za-z0-9]+(_[A-Za-z0-9]+)?$/;

/*
  Combo-uri (gift-uri "streakable", giftType === 1): TikTok trimite actualizări
  repetate cu repeatCount crescător (1, 2, 3...) și la final repeatEnd = true.
  Emitem DOAR diferența față de ultima actualizare, ca boost-ul să apară imediat
  și nicio bucată să nu fie numărată de două ori.
*/
export class GiftStreakTracker {
  constructor({ ttlMs = 60000, now = Date.now } = {}) {
    this.ttlMs = ttlMs;
    this.now = now;
    this.streaks = new Map();
  }

  // returnează câte bucăți NOI trebuie procesate (0 = nimic nou)
  process(userId, gift) {
    if (gift.giftType !== 1) return gift.repeatCount;
    const key = `${userId}:${gift.id}:${gift.groupId}`;
    const prev = this.streaks.get(key);
    let last = prev && this.now() - prev.at < this.ttlMs ? prev.count : 0;
    if (gift.repeatCount < last) last = 0; // combo nou
    const delta = gift.repeatCount - last;
    if (gift.repeatEnd) this.streaks.delete(key);
    else this.streaks.set(key, { count: gift.repeatCount, at: this.now() });
    return Math.max(0, delta);
  }

  cleanup() {
    const t = this.now();
    for (const [k, v] of this.streaks) if (t - v.at > this.ttlMs) this.streaks.delete(k);
  }
}
