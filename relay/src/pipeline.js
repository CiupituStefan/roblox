// Pipeline: eveniment brut TikTok -> validare -> anti-spam -> deduplicare
// -> reguli de înscriere/verificare -> EventStore (de unde îl citește Roblox).
import { extractUser, extractMsgId, extractComment, extractGift, parseCommand, GiftStreakTracker } from './normalize.js';
import { TtlSet, RateLimiter } from './util.js';

export class Pipeline {
  constructor({ config, store, verifier, now = Date.now, log = console }) {
    this.config = config;
    this.store = store;
    this.verifier = verifier;
    this.now = now;
    this.log = log;
    this.seenMsgIds = new TtlSet(10 * 60 * 1000, 50000, now);
    this.streaks = new GiftStreakTracker({ now });
    this.joinLimiter = new RateLimiter({ capacity: 2, refillPerSec: 1 / 5, now }); // 2 rapid, apoi 1 la 5s
    this.giftLimiter = new RateLimiter({ capacity: 40, refillPerSec: 10, now });
    this.stats = { chat: 0, gift: 0, join: 0, joinRejected: 0, verify: 0, dropped: 0 };
  }

  _identity(user) {
    return { tiktokUserId: user.userId, tiktokUniqueId: user.uniqueId, tiktokNickname: user.nickname };
  }

  async handleChat(data) {
    this.stats.chat++;
    const user = extractUser(data);
    if (!user) return this._drop('chat fără userId valid');
    const msgId = extractMsgId(data);
    if (msgId && !this.seenMsgIds.addIfNew(`c:${msgId}`)) return this._drop('chat duplicat');

    const cmd = parseCommand(extractComment(data));
    if (!cmd) return null;

    if (this.config.joinCommands.includes(cmd.command)) {
      if (!this.joinLimiter.allow(user.userId)) return this._drop(`spam !join de la ${user.userId}`);
      const decision = await this.verifier.checkJoin(user, cmd.arg);
      if (decision.ok) {
        this.stats.join++;
        return this.store.push({
          type: 'join',
          id: `join:${msgId ?? `${user.userId}:${this.now()}`}`,
          ...this._identity(user),
          robloxName: decision.robloxName,
          robloxUserId: decision.robloxUserId ?? null,
          verified: decision.verified,
        });
      }
      this.stats.joinRejected++;
      return this.store.push({
        type: 'joinRejected',
        id: `joinRejected:${msgId ?? `${user.userId}:${this.now()}`}`,
        ...this._identity(user),
        robloxName: decision.robloxName ?? cmd.arg,
        code: decision.code,
      });
    }

    if (this.config.verifyCommands.includes(cmd.command)) {
      const ev = await this.verifier.handleVerify(user, cmd.arg);
      if (!ev) return this._drop(`spam !verify de la ${user.userId}`);
      this.stats.verify++;
      return this.store.push({ ...ev, id: `verify:${msgId ?? `${user.userId}:${this.now()}`}`, ...this._identity(user) });
    }
    return null;
  }

  handleGift(data) {
    this.stats.gift++;
    const user = extractUser(data);
    if (!user) return this._drop('gift fără userId valid');
    const gift = extractGift(data);
    const msgId = extractMsgId(data);

    // gift-urile non-combo cu același msgId sunt duplicate (ex. reconectare)
    if (gift.giftType !== 1 && msgId && !this.seenMsgIds.addIfNew(`g:${msgId}`)) return this._drop('gift duplicat');

    const count = this.streaks.process(user.userId, gift);
    if (count <= 0) return null;
    if (!this.giftLimiter.allow(user.userId)) return this._drop(`spam gift de la ${user.userId}`);

    return this.store.push({
      type: 'gift',
      id: `gift:${user.userId}:${gift.id}:${gift.groupId}:${msgId ?? ''}:${gift.repeatCount}`,
      ...this._identity(user),
      gift: { id: gift.id, name: gift.name, diamonds: gift.diamonds, count },
    });
  }

  _drop(reason) {
    this.stats.dropped++;
    if (process.env.DEBUG) this.log.debug?.(`[pipeline] ignorat: ${reason}`);
    return null;
  }

  cleanup() {
    this.streaks.cleanup();
    this.joinLimiter.cleanup();
    this.giftLimiter.cleanup();
    this.verifier.cleanup();
  }
}
