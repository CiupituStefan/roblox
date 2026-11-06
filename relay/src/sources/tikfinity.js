// Sursă: TikFinity (aplicație desktop). TikFinity se conectează la LIVE-ul tău și
// retransmite evenimentele local prin WebSocket, în format {event, data}.
// Folosește WebSocket-ul nativ din Node 22 (fără dependențe).
export function startTikfinity({ url, onChat, onGift, log = console }) {
  let ws;
  let stopped = false;
  let attempt = 0;
  let status = 'connecting';
  const unknownSeen = new Set();

  const connect = () => {
    if (stopped) return;
    status = 'connecting';
    try {
      ws = new WebSocket(url);
    } catch (err) {
      log.warn(`[tikfinity] URL invalid: ${err.message}`);
      return scheduleReconnect();
    }
    ws.onopen = () => {
      attempt = 0;
      status = 'connected';
      log.info(`[tikfinity] conectat la ${url}`);
    };
    ws.onmessage = (msg) => {
      let parsed;
      try {
        parsed = JSON.parse(typeof msg.data === 'string' ? msg.data : msg.data.toString());
      } catch {
        return;
      }
      const name = parsed?.event ?? parsed?.type;
      const data = parsed?.data ?? parsed;
      if (name === 'chat') onChat(data);
      else if (name === 'gift') onGift(data);
      else if (name && !unknownSeen.has(name)) {
        unknownSeen.add(name);
        log.info(`[tikfinity] eveniment ignorat (normal): ${name}`);
      }
    };
    ws.onclose = () => {
      if (status === 'connected') log.warn('[tikfinity] deconectat');
      status = 'disconnected';
      scheduleReconnect();
    };
    ws.onerror = () => {
      /* onclose urmează automat */
    };
  };

  const scheduleReconnect = () => {
    if (stopped) return;
    const delay = Math.min(30000, 1000 * 2 ** attempt++);
    if (attempt <= 3 || attempt % 10 === 0) log.info(`[tikfinity] reconectare în ${delay / 1000}s (TikFinity e pornit și conectat la LIVE?)`);
    setTimeout(connect, delay).unref?.();
  };

  connect();
  return {
    name: 'tikfinity',
    status: () => status,
    stop() {
      stopped = true;
      ws?.close();
    },
  };
}
