# Relay TikTok LIVE → Roblox

Program mic în Node.js (fără dependențe externe) care rulează pe PC-ul tău în timpul LIVE-ului:

```
TikTok LIVE ─► TikFinity (sau tiktok-live-connector) ─► RELAY ─► HTTPS (Cloudflare Tunnel) ◄─ serverul Roblox (polling 1/s)
```

Ce face:
- transformă `!join NumeRoblox` în eveniment de înscriere, legat de **ID-ul numeric TikTok** al celui care a scris;
- transformă gift-urile în evenimente cu `count`; combo-urile x10 sunt numărate exact o dată, imediat;
- elimină duplicatele, limitează spamul (`!join`: 2 rapid, apoi 1 la 5s; gift-uri: max ~10/s per persoană);
- verificare opțională a contului Roblox (`!verify`), cu legături salvate permanent în `data/bindings.json`;
- protejează API-ul cu o cheie secretă; păstrează evenimentele dacă Roblox repornește.

## 1. Instalare (o singură dată)

1. Instalează **Node.js 22 LTS** sau mai nou de pe nodejs.org.
2. Deschide un terminal în folderul `relay`, apoi:
   ```bash
   cp .env.example .env
   ```
   ```bash
   npm run genkey
   ```
3. Pune cheia generată în `.env` la `RELAY_KEY=`. **Nu o arăta pe stream.**
4. Rulează testele:
   ```bash
   npm test
   ```

## 2. Sursa evenimentelor TikTok

### Varianta A (recomandată): TikFinity
1. Instalează TikFinity (tikfinity.zerody.one) și conectează-l la contul tău TikTok.
2. Verifică în setările TikFinity că API-ul WebSocket local e activ. Adresa implicită folosită aici este `ws://localhost:21213/`; dacă TikFinity afișează alt port, schimbă `TIKFINITY_WS_URL`.
3. În `.env`: `SOURCE=tikfinity`.

### Varianta B: tiktok-live-connector (neoficial)
```bash
npm i tiktok-live-connector
```
În `.env`: `SOURCE=connector` și `TIKTOK_USERNAME=numele_tau`.
⚠️ Biblioteca nu este un API oficial TikTok: poate încălca Termenii TikTok și se poate strica la actualizări.

> TikTok nu oferă momentan un API public oficial pentru gift-urile LIVE, deschis tuturor creatorilor. Ambele variante citesc doar LIVE-ul tău și nu cer parola.

## 3. Pornire

```bash
npm start
```
Pentru LIVE folosește varianta cu repornire automată (dacă relay-ul se oprește, pornește din nou singur):
```bash
npm run start:live
```
Test de încărcare (fără TikTok/Roblox; verifică pierderi, duplicate, întârziere, memorie):
```bash
npm run loadtest
```
Trebuie să vezi `[relay] ascultă pe http://localhost:8787` și apoi `[tikfinity] conectat ...`.

## 4. Adresă HTTPS publică (Roblox trebuie să poată ajunge la relay)

Serverele Roblox rulează în cloud, deci nu pot accesa `localhost` de pe PC-ul tău. Folosește **Cloudflare Tunnel** (gratuit):

```bash
cloudflared tunnel --url http://localhost:8787
```
Comanda afișează o adresă de forma `https://ceva-aleator.trycloudflare.com`. Copiaz-o în `Config.Bridge.BaseUrl`, fără `/` la final.
Adresa rapidă se schimbă la fiecare pornire. Pentru o adresă fixă, creează un *named tunnel* pe un domeniu propriu (documentația Cloudflare Tunnel).

Verificare: deschide `https://adresa-ta/health` în browser → `{"ok":true}`.

## 5. Configurare Roblox

1. **Game Settings → Security → Allow HTTP Requests = ON.**
2. **Cheia în Secrets Store:** Creator Hub → jocul tău → *Secrets* → *Create Secret*
   - Name: `TIKTOK_RELAY_KEY`
   - Secret: aceeași valoare ca `RELAY_KEY`
   - Domain: `*.trycloudflare.com` (sau domeniul tău)
3. **Doar pentru Studio**, dacă secretul nu e disponibil acolo: pune cheia în `ServerScriptService > Server > LocalSecrets`. Golește câmpul înainte de LIVE.
4. `Config.Bridge.BaseUrl` = adresa HTTPS de la pasul 4. Adresa se poate schimba și din panoul de admin
   (Control → Relay TikTok), fără să republici jocul.

În Output trebuie să apară `[BridgeService] status: connected`.

## 6. Test complet fără TikTok

Cu relay-ul pornit și jocul în Play (Studio):

```bash
npm run sim -- join 555 builderman Ana
```
```bash
npm run sim -- gift 900000001 Rose
```
```bash
npm run sim -- combo 900000001 Rose 5
```
```bash
npm run sim -- gift 123456 Galaxy
```
```bash
npm run sim -- gift 555 Perfume
```
```bash
npm run sim -- status
```
- `join 555 builderman Ana`: înscrie un utilizator TikTok cu ID-ul 555.
- `gift 900000001 Rose`: boost pentru concurentul din cursa de test.
- `combo 900000001 Rose 5`: combo x5.
- `gift 123456 Galaxy`: spectator care nu e în cursă, primește doar o mulțumire.
- `gift 555 Perfume`: Skip Queue pentru propria înscriere.
- `status`: statistici.

## 7. Verificarea contului (opțional, recomandat)

1. Spectatorul scrie `!verify NumeRoblox`. Pe ecran apare un cod, de exemplu `RACE-KQPLMX`.
2. Pune codul în descrierea (About) profilului Roblox.
3. Scrie din nou `!verify`. Contul e legat permanent de ID-ul lui TikTok.
4. De acum, **nimeni altcineva** nu se mai poate înscrie cu acel cont Roblox, iar el se poate înscrie scriind doar `!join`.

`REQUIRE_VERIFICATION=true` acceptă doar conturi verificate.

## API (pentru referință)

| Rută | Auth | Descriere |
|---|---|---|
| `GET /health` | nu | `{ok:true}` |
| `GET /events?cursor=N\|resume&limit=100` | da | evenimentele cu `seq > N`; trimițând `N` confirmi procesarea |
| `GET /status` | da | statistici |
| `POST /simulate` | da | injectează un eveniment de test (`ALLOW_SIMULATE=true`) |

Autentificare: `Authorization: Bearer <RELAY_KEY>`.

Tipuri de evenimente: `join`, `joinRejected`, `gift`, `verifyCode`, `verifyResult`. Fiecare are `tiktokUserId`, `tiktokUniqueId`, `tiktokNickname` și `ageMs` (vechimea).
