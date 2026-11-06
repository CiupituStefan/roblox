// Sursă: biblioteca open-source "tiktok-live-connector" (NEOFICIALĂ).
// Instalare: npm i tiktok-live-connector
// ATENȚIE: nu este un API oficial TikTok; poate încălca Termenii TikTok și se poate
// strica la actualizările TikTok. Nu cere parole: citește fluxul public al LIVE-ului.
export async function startConnector({ username, onChat, onGift, log = console }) {
  let mod;
  try {
    mod = await import('tiktok-live-connector');
  } catch {
    throw new Error('Pachetul tiktok-live-connector nu este instalat. Rulează: npm i tiktok-live-connector');
  }
  const Ctor = mod.TikTokLiveConnection ?? mod.WebcastPushConnection; // v2 ?? v1
  const CHAT = mod.WebcastEvent?.CHAT ?? 'chat';
  const GIFT = mod.WebcastEvent?.GIFT ?? 'gift';
  const DISCONNECTED = mod.ControlEvent?.DISCONNECTED ?? 'disconnected';

  let stopped = false;
  let status = 'connecting';
  let attempt = 0;
  const conn = new Ctor(username);
  conn.on(CHAT, (d) => onChat(d));
  conn.on(GIFT, (d) => onGift(d));
  conn.on(DISCONNECTED, () => {
    status = 'disconnected';
    log.warn('[connector] deconectat');
    retry();
  });

  const connect = async () => {
    if (stopped) return;
    status = 'connecting';
    try {
      await conn.connect();
      status = 'connected';
      attempt = 0;
      log.info(`[connector] conectat la LIVE-ul @${username}`);
    } catch (err) {
      status = 'disconnected';
      log.warn(`[connector] conectare eșuată (${err?.message ?? err}). Ești LIVE?`);
      retry();
    }
  };
  const retry = () => {
    if (stopped) return;
    const delay = Math.min(30000, 2000 * 2 ** attempt++);
    setTimeout(connect, delay).unref?.();
  };

  connect();
  return {
    name: 'connector',
    status: () => status,
    stop() {
      stopped = true;
      try {
        conn.disconnect();
      } catch {
        /* ignorat */
      }
    },
  };
}
