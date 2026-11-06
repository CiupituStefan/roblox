// Simulator: trimite evenimente false prin relay, ca și cum ar veni din TikTok LIVE.
//
//   npm run sim -- join   <tiktokUserId> <NumeRoblox> [nickname]
//   npm run sim -- gift   <tiktokUserId> <NumeGift> [bucăți] [diamante/bucată] [giftId]
//   npm run sim -- combo  <tiktokUserId> <NumeGift> <bucăți>     (simulează un combo x N)
//   npm run sim -- verify <tiktokUserId> [NumeRoblox]
//   npm run sim -- status
import { loadConfig } from './config.js';

const config = loadConfig();
const base = process.env.RELAY_URL || `http://localhost:${config.port}`;
const headers = { authorization: `Bearer ${config.relayKey}`, 'content-type': 'application/json' };
const [, , kind, ...args] = process.argv;

const post = async (body) => {
  const res = await fetch(`${base}/simulate`, { method: 'POST', headers, body: JSON.stringify(body) });
  console.log(res.status, JSON.stringify(await res.json(), null, 2));
};
const user = (id, nick) => ({ userId: String(id), uniqueId: nick ?? `tt_${id}`, nickname: nick ?? `Spectator ${id}` });

switch (kind) {
  case 'join': {
    const [id, name, nick] = args;
    await post({ kind: 'chat', data: { ...user(id, nick), comment: `!join ${name ?? ''}` } });
    break;
  }
  case 'verify': {
    const [id, name] = args;
    await post({ kind: 'chat', data: { ...user(id), comment: `!verify ${name ?? ''}`.trim() } });
    break;
  }
  case 'gift': {
    const [id, giftName, count = '1', diamonds = '1', giftId = '0'] = args;
    await post({
      kind: 'gift',
      data: { ...user(id), giftName, giftId: Number(giftId), diamondCount: Number(diamonds), giftType: 0, repeatCount: Number(count), repeatEnd: true },
    });
    break;
  }
  case 'combo': {
    const [id, giftName, count = '5'] = args;
    const groupId = String(Date.now());
    for (let i = 1; i <= Number(count); i++) {
      await post({ kind: 'gift', data: { ...user(id), giftName, giftId: 1, diamondCount: 1, giftType: 1, repeatCount: i, repeatEnd: false, groupId } });
    }
    await post({ kind: 'gift', data: { ...user(id), giftName, giftId: 1, diamondCount: 1, giftType: 1, repeatCount: Number(count), repeatEnd: true, groupId } });
    break;
  }
  case 'status': {
    const res = await fetch(`${base}/status`, { headers });
    console.log(res.status, JSON.stringify(await res.json(), null, 2));
    break;
  }
  default:
    console.log('Utilizare: npm run sim -- join|gift|combo|verify|status ...  (vezi src/sim.js)');
}
