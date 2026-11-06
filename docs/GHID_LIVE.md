# Ghid complet: de la zero la LIVE pe TikTok

Acest ghid te duce pas cu pas de la proiectul din acest repository până la un LIVE pe TikTok care rulează ore întregi fără intervenție.

---

## 1. De ce ai nevoie

| Ce | Pentru ce |
|---|---|
| Cont Roblox + **Roblox Studio** | jocul |
| **Rojo** (recomandat) sau copiere manuală | sincronizarea codului în Studio |
| **Node.js 22+** pe PC | relay-ul TikTok → Roblox (`relay/`) |
| **TikFinity** (sau `tiktok-live-connector`) | citirea gift-urilor și a chatului din LIVE |
| **cloudflared** (Cloudflare Tunnel, gratuit) | adresa HTTPS publică a relay-ului |
| **TikTok LIVE Studio** sau **OBS** | transmisia verticală |
| Opțional: un al doilea dispozitiv | panoul de admin, ca să nu apară pe stream |

---

## 2. Pregătire (o singură dată)

### 2.1 Codul în Studio
- **Cu Rojo:** în folderul proiectului rulezi:
  ```bash
  rojo serve
  ```
  Apoi, în Studio, pluginul Rojo → *Connect*. Structura din `default.project.json` se creează singură. Tot Rojo setează *HttpEnabled* și *StreamingEnabled = false*.
- **Fără Rojo:** creezi obiectele din `ARHITECTURA.md` §5 (Folder / Script / LocalScript / ModuleScript) și copiezi codul. Regula după extensie:
  - `.server.lua` → Script
  - `.client.lua` → LocalScript
  - `.lua` → ModuleScript

### 2.2 Setări în Studio
1. **File → Publish to Roblox** (API-urile de avatar și Secrets cer un joc publicat).
2. **Game Settings → Security:**
   - ✅ *Allow HTTP Requests*
   - ✅ *Enable Studio Access to API Services* (pentru salvarea setărilor din panoul de admin)
3. **Workspace → StreamingEnabled = false.** Cu Rojo e automat.

### 2.3 Configurare (`ReplicatedStorage > Shared > Config`)
- `Config.Admin.UserIds = { TU_USERID }`
- `Config.Debug.FakeJoinsInStudio`, `RunSelfTests`: rămân active, rulează **doar** în Studio.
- `Config.Sounds`: pune ID-uri `rbxassetid://...` din Creator Store pentru sunetele lipsă (Winner, Finish, Rocket...).
- `Config.Gifts.ByName`: ce gift dă ce recompensă. Se poate schimba și din panou, în timpul LIVE-ului.

### 2.4 Relay-ul
Pașii detaliați sunt în [`relay/README.md`](../relay/README.md). Pe scurt:
```bash
cd relay
```
```bash
cp .env.example .env
```
```bash
npm run genkey
```
Pune cheia generată în `.env` la `RELAY_KEY`, apoi verifică instalarea:
```bash
npm test
```

### 2.5 Cheia în Roblox Secrets Store
Creator Hub → jocul tău → **Secrets** → *Create*:
- Name: `TIKTOK_RELAY_KEY`
- Value: aceeași valoare ca `RELAY_KEY`
- Domain: `*.trycloudflare.com` (sau domeniul tău, dacă folosești un tunel cu nume)

### 2.6 Tunel cu adresă fixă (recomandat)
Tunelul rapid (`cloudflared tunnel --url ...`) primește o adresă nouă la fiecare pornire. Ai două variante:
- îl schimbi de fiecare dată din **panoul de admin → Control → Relay TikTok** (nu trebuie republicat jocul), sau
- creezi un **named tunnel** Cloudflare pe un domeniu propriu, cu adresă fixă. O pui o singură dată în `Config.Bridge.BaseUrl`.

### 2.7 Server privat
Pe pagina jocului: **Servers → Create Private Server**. Acolo rulează LIVE-ul. Ești singurul jucător (camera), plus eventual al doilea dispozitiv pentru panou.

---

## 3. Testare înainte de primul LIVE

**În Studio**, apasă **Play**. În Output trebuie să apară:
```
[Tests] QueueService: 9 trecute, 0 eșuate
[Tests] GiftRouter: 6 trecute, 0 eșuate
[Tests] Mounts: 3 trecute, 0 eșuate
[Tests] Maps: 3 trecute, 0 eșuate
[Tests] RacerController: 7 trecute, 0 eșuate
[Tests] BoostService: 4 trecute, 0 eșuate
[Tests] Settings: 6 trecute, 0 eșuate
```
După ~20 s pornește o cursă cu înscrierile simulate.

**Test de încărcare** (panou admin, F2 → Control → *Test de încărcare*):
- `12 concurenți · 10 gift/s`: o cursă obișnuită;
- `40 concurenți · 30 gift/s`: un LIVE foarte aglomerat.

Rezultatul apare în panou și în Output: FPS-ul serverului, cel mai lent cadru, memoria, boost-urile aplicate. Ținte orientative: **FPS ≥ 50**, cel mai lent cadru **< 100 ms**.

**Relay-ul:**
```bash
npm run loadtest
```
Rezultat de referință măsurat: ~2000 evenimente brute/s, 46.520 evenimente livrate, **0 pierderi, 0 duplicate**, +62 MB memorie.

**Cap-coadă fără TikTok:** relay pornit + jocul în Play, apoi:
```bash
npm run sim -- join 555 NumeleTauRoblox
```
```bash
npm run sim -- gift 555 Galaxy
```

---

## 4. Ritualul de dinainte de fiecare LIVE (5 minute)

1. Pornește **TikFinity** și conectează-l la contul TikTok (poți intra LIVE puțin mai târziu).
2. Pornește relay-ul cu repornire automată:
   ```bash
   cd relay && npm run start:live
   ```
3. Pornește tunelul. Dacă e tunel rapid, copiază adresa nouă:
   ```bash
   cloudflared tunnel --url http://localhost:8787
   ```
4. Intră în **serverul privat** de pe PC-ul de stream.
5. De pe telefon / al doilea dispozitiv, intră în același server privat și deschide **panoul de admin** (⚙️ sau F2). În **Control**:
   - dacă adresa s-a schimbat, lipește-o la *Relay TikTok* → *Salvează*;
   - verifică: *Bridge TikTok: connected*, *Curse: PORNITE*, *Înscrieri: deschise*.
6. Pornește transmisia (capitolul 5) și intră LIVE.
7. Scrie în chat `!join NumeleTauRoblox` și trimite un gift mic, ca să verifici tot lanțul.

---

## 5. Transmisia verticală (9:16)

- **Fereastra Roblox în portret:** micșorează fereastra Roblox (nu fullscreen) și trage de margini până ajunge aproximativ la 9:16, de exemplu 608×1080 sau 540×960. HUD-ul și roata se reașază automat pentru portret.
- **TikTok LIVE Studio:** scenă verticală → *Add source* → *Window capture* / *Game capture* → fereastra Roblox. Activează captura audio pentru Roblox.
- **OBS:** canvas 1080×1920 → *Window Capture* (Roblox) → scalează pe toată înălțimea; pentru TikTok folosește pluginul vertical / cheia de stream TikTok, dacă ai acces.
- **Panoul de admin să nu apară pe stream:**
  - folosește-l de pe al doilea dispozitiv; sau
  - pune `Config.Admin.ShowToggleButton = false` și deschide-l doar cu F2, scurt.

---

## 6. În timpul LIVE-ului

| Situație | Ce faci |
|---|---|
| Vrei o pauză | Panou → Control → ⏸ *Pauză* (mișcarea și cronometrele se opresc) |
| Cineva face spam / are nume nepotrivit | Panou → Coadă → ✖ lângă nume |
| Vrei să adaugi pe cineva fără TikTok | Panou → Coadă → username → *Adaugă* (nu poate primi boost-uri din gift-uri) |
| Ai nevoie de mai mulți concurenți pe cursă | Panou → Cursă → *Concurenți / cursă* (de la cursa următoare) |
| Un gift nu face nimic | Panou → Gift-uri: verifică numele exact (apare în consola relay-ului) și adaugă-l |
| Prea multe boost-uri / prea haotic | Panou → Boost-uri: scade multiplicatorii sau duratele; Cursă → *Pauză între boost-uri* |
| Vrei o anumită hartă | Panou → Hărți → *Următoarea* |
| Cursa pare blocată | Watchdog-ul o anulează automat; altfel Panou → Control → ↻ *Repornește ciclul* |
| Închizi înscrierile spre final | Panou → Control → *Înscrieri deschise: NU* |

---

## 7. Rezistența la LIVE-uri de mai multe ore

**Pe server:**
- Fiecare cursă e izolată: o eroare anulează doar cursa respectivă, iar ciclul continuă.
- **Watchdog:** dacă o fază durează mult peste normal, cursa e anulată; dacă nici asta nu merge, ciclul se repornește singur.
- Memoria e curățată periodic: cache-urile de conturi, anti-spam, deduplicare. Modelele concurenților, hărțile vechi și efectele sunt șterse după fiecare cursă.
- La fiecare 5 minute, Output primește o linie `[Sănătate]` cu FPS, memorie, curse terminate și intervenții ale watchdog-ului.
- Setările din panou sunt salvate și supraviețuiesc repornirii serverului.

**Relay-ul:**
- `npm run start:live` îl repornește automat dacă se oprește.
- Se reconectează singur la TikFinity / LIVE.
- Păstrează cursorul pe disc: dacă serverul Roblox repornește, nu se pierd înscrieri, iar gift-urile vechi nu sunt aplicate în cursa nouă.

**Limita Roblox de 500 de cereri HTTP pe minut** este respectată: interogare la 1 s, iar în rafale cel mult ~400 de cereri pe minut, cu câte 200 de evenimente pe cerere.

---

## 8. Probleme frecvente

| Simptom | Cauză probabilă | Soluție |
|---|---|---|
| `[BridgeService] status: notConfigured` | `Bridge.BaseUrl` nu e setat | pune adresa în panou sau în Config |
| `status: httpDisabled` | HTTP oprit | Game Settings → Security → Allow HTTP Requests |
| `status: noSecret` | secretul lipsește | Secrets Store (2.5); în Studio poți folosi `LocalSecrets` |
| `status: unauthorized` | cheie diferită | `RELAY_KEY` din `.env` = valoarea secretului |
| `status: error` în buclă | tunel oprit / adresă veche | repornește `cloudflared`, actualizează adresa |
| `!join` nu apare | TikFinity neconectat | consola relay: `[tikfinity] conectat`; în TikFinity verifică API-ul WebSocket |
| Contul „nu există” | username greșit / cont banat | spectatorul verifică username-ul (nu display name) |
| Avatarul nu se încarcă | Roblox lent | concurentul e scos după 25 s; se poate reînscrie |
| Camera nu vede harta | StreamingEnabled activ | Workspace → StreamingEnabled = false |
| Setările nu se salvează | API Services oprit în Studio | Enable Studio Access to API Services |
| Sunete lipsă | ID-uri goale | `Config.Sounds` cu ID-uri din Creator Store |

---

## 9. Limitări cunoscute

- **TikTok** nu are un API oficial public pentru gift-urile LIVE. Instrumentele folosite (TikFinity, tiktok-live-connector) pot fi afectate de schimbările TikTok. `tiktok-live-connector` este neoficial și poate încălca Termenii TikTok.
- **Anunțul audio al câștigătorului:** Roblox nu oferă o voce generată pe care s-o putem folosi sigur. Încarcă un clip propriu în `Config.Sounds.Winner`.
- **Serverele Roblox** se pot reporni la actualizări ale jocului sau ale platformei. Reintri în serverul privat; setările și cursorul relay-ului se păstrează.
- **Verificarea `!verify`** depinde de API-ul public Roblox pentru descrierea profilului. Dacă e indisponibil, verificarea eșuează temporar, dar înscrierile normale merg.
