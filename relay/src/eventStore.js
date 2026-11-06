// Coada de evenimente pentru Roblox, cu număr de secvență (cursor).
//
// Protocol:
//   GET /events?cursor=N   -> evenimentele cu seq > N. Trimițând cursor=N, serverul
//                             Roblox confirmă (ack) că a procesat tot până la N.
//   GET /events?cursor=resume -> serverul Roblox tocmai a pornit: continuăm de la
//                             ultimul ack, dar sărim evenimentele prea vechi
//                             (gift-uri vechi nu au sens într-o cursă nouă).
import path from 'node:path';
import { readJson, writeJsonAtomic } from './util.js';

export class EventStore {
  constructor({ dataDir, maxEvents = 5000, giftReplayMaxAgeMs = 20000, joinReplayMaxAgeMs = 600000, now = Date.now, persist = true }) {
    this.file = path.join(dataDir, 'state.json');
    this.maxEvents = maxEvents;
    this.giftReplayMaxAgeMs = giftReplayMaxAgeMs;
    this.joinReplayMaxAgeMs = joinReplayMaxAgeMs;
    this.now = now;
    this.persist = persist;
    this.events = [];
    const state = persist ? readJson(this.file, {}) : {};
    this.lastSeq = Number.isInteger(state.lastSeq) ? state.lastSeq : 0;
    this.lastAcked = Number.isInteger(state.lastAcked) ? state.lastAcked : this.lastSeq;
    this._saveTimer = null;
  }

  push(event) {
    this.lastSeq += 1;
    const stored = { ...event, seq: this.lastSeq, ts: event.ts ?? this.now() };
    this.events.push(stored);
    if (this.events.length > this.maxEvents) this.events.splice(0, this.events.length - this.maxEvents);
    this._scheduleSave();
    return stored;
  }

  _maxAgeFor(type) {
    return type === 'gift' ? this.giftReplayMaxAgeMs : this.joinReplayMaxAgeMs;
  }

  // cursorParam: string din query ("resume" sau număr)
  read(cursorParam, limit = 100) {
    limit = Math.max(1, Math.min(200, limit | 0 || 100));
    const t = this.now();
    let cursor;
    let resumed = false;

    if (cursorParam === 'resume' || cursorParam === undefined || cursorParam === '') {
      cursor = this.lastAcked;
      resumed = true;
    } else {
      cursor = Number.parseInt(cursorParam, 10);
      if (!Number.isFinite(cursor) || cursor < 0) return { error: 'INVALID_CURSOR' };
      if (cursor > this.lastSeq) {
        // Roblox are un cursor din viitor (relay resetat): îl aliniem
        return { cursor: this.lastSeq, events: [], reset: true };
      }
      if (cursor > this.lastAcked) {
        this.lastAcked = cursor;
        this._scheduleSave();
      }
    }

    const out = [];
    let next = cursor;
    for (const e of this.events) {
      if (e.seq <= cursor) continue;
      if (out.length >= limit) break;
      next = e.seq;
      const ageMs = t - e.ts;
      if (resumed && ageMs > this._maxAgeFor(e.type)) continue; // prea vechi pentru reluare
      out.push({ ...e, ageMs });
    }
    // dacă nu mai sunt evenimente în buffer peste cursor, cursorul devine lastSeq
    if (out.length < limit && next < this.lastSeq) {
      const pendingAfter = this.events.some((e) => e.seq > next);
      if (!pendingAfter) next = this.lastSeq;
    }
    return { cursor: next, events: out, resumed };
  }

  _scheduleSave() {
    if (!this.persist || this._saveTimer) return;
    this._saveTimer = setTimeout(() => {
      this._saveTimer = null;
      this.flush();
    }, 1000);
    this._saveTimer.unref?.();
  }

  flush() {
    if (!this.persist) return;
    writeJsonAtomic(this.file, { lastSeq: this.lastSeq, lastAcked: this.lastAcked });
  }
}
