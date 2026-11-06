// Utilitare mici: persistare atomică, set cu expirare, limitare de rată.
import { writeFileSync, renameSync, readFileSync, existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';

export function readJson(file, fallback) {
  try {
    if (!existsSync(file)) return fallback;
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch (err) {
    console.warn(`[util] Nu pot citi ${file}: ${err.message}`);
    return fallback;
  }
}

export function writeJsonAtomic(file, data) {
  mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp`;
  writeFileSync(tmp, JSON.stringify(data, null, 2));
  renameSync(tmp, file);
}

// Set cu expirare (pentru deduplicare). Curăță automat elementele vechi.
export class TtlSet {
  constructor(ttlMs, maxSize = 20000, now = Date.now) {
    this.ttlMs = ttlMs;
    this.maxSize = maxSize;
    this.now = now;
    this.map = new Map();
  }
  has(key) {
    const exp = this.map.get(key);
    if (exp === undefined) return false;
    if (exp <= this.now()) {
      this.map.delete(key);
      return false;
    }
    return true;
  }
  add(key) {
    this.map.delete(key);
    this.map.set(key, this.now() + this.ttlMs);
    if (this.map.size > this.maxSize) {
      // Map păstrează ordinea inserării -> ștergem cele mai vechi
      const excess = this.map.size - this.maxSize;
      let i = 0;
      for (const k of this.map.keys()) {
        if (i++ >= excess) break;
        this.map.delete(k);
      }
    }
  }
  // true dacă e nou (și îl adaugă), false dacă era deja văzut
  addIfNew(key) {
    if (this.has(key)) return false;
    this.add(key);
    return true;
  }
}

// Token bucket per cheie: `capacity` evenimente, reumplere `refillPerSec`.
export class RateLimiter {
  constructor({ capacity, refillPerSec, now = Date.now }) {
    this.capacity = capacity;
    this.refillPerSec = refillPerSec;
    this.now = now;
    this.buckets = new Map();
  }
  allow(key, cost = 1) {
    const t = this.now();
    let b = this.buckets.get(key);
    if (!b) {
      b = { tokens: this.capacity, last: t };
      this.buckets.set(key, b);
    }
    b.tokens = Math.min(this.capacity, b.tokens + ((t - b.last) / 1000) * this.refillPerSec);
    b.last = t;
    if (b.tokens >= cost) {
      b.tokens -= cost;
      return true;
    }
    return false;
  }
  cleanup(maxIdleMs = 10 * 60 * 1000) {
    const t = this.now();
    for (const [k, b] of this.buckets) if (t - b.last > maxIdleMs) this.buckets.delete(k);
  }
}

export const sanitizeText = (s, max = 40) =>
  String(s ?? '')
    .replace(/[\u0000-\u001f\u007f]/g, '')
    .trim()
    .slice(0, max);
