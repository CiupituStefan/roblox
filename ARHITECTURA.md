# TikTok LIVE Race: arhitectura completă

## 1. Ce se poate face direct în Roblox și ce are nevoie de servicii externe

| Funcționalitate | Unde rulează | Observații |
|---|---|---|
| Queue, curse, hărți, mount-uri, roata norocului, boost-uri, aură, UI, admin | **Roblox (server + client)** | 100% Luau |
| Username → UserId, avatar original | **Roblox**, API-uri oficiale | `GetUserIdFromNameAsync`, `GetHumanoidDescriptionFromUserId`, `CreateHumanoidModelFromDescription` |
| Citirea evenimentelor TikTok LIVE (chat, gift-uri) | **Extern** | Roblox nu se poate conecta la TikTok |
| Transmiterea evenimentelor către joc | **Relay extern (Node.js)** → Roblox prin `HttpService` | Roblox NU poate primi conexiuni HTTP de intrare, deci serverul Roblox *interoghează* relay-ul (polling) |
| Verificarea că un TikToker deține contul Roblox (opțional) | **Relay** + API public Roblox | Cod de verificare pus în descrierea profilului Roblox |

### Sursa evenimentelor TikTok: limitare importantă
TikTok **nu oferă un API public oficial** pentru gift-urile LIVE, deschis tuturor creatorilor. Opțiunile realiste:

1. **TikFinity** (recomandat pentru început): aplicație desktop folosită de mulți streameri. Se conectează la LIVE-ul tău și expune evenimentele local prin WebSocket/Webhooks. Relay-ul nostru se abonează la ea.
2. **Streamer.bot** cu integrare TikTok: similar, cu WebSocket local.
3. **`tiktok-live-connector`** (bibliotecă Node.js open-source): citește fluxul public al LIVE-ului tău, fără parole. Este *neoficială* (reverse-engineered), deci poate încălca Termenii TikTok și se poate strica la actualizări.

Nicio variantă nu cere parola ta și nu face scraping de conturi. Relay-ul are un **adaptor** pentru sursă, deci poți schimba sursa fără să modifici jocul.
Toate trei oferă pentru fiecare eveniment `userId` (ID numeric TikTok, stabil), `uniqueId` (@handle), numele gift-ului, ID-ul gift-ului, valoarea în diamante și `repeatCount`/`repeatEnd` pentru combo-uri.

## 2. Diagrama sistemului

```
 Spectator TikTok                 PC-ul tău / cloud                         Roblox (server de joc)
 ───────────────                  ─────────────────                         ──────────────────────
 comentariu "!join Nume"  ─┐
 gift (Rose, Galaxy...)   ─┼─► TikFinity / connector ─► RELAY (Node.js) ◄── HttpService poll (1/s) ── BridgeService
                           │                           • normalizează eventul   (cursor + ack, header cu cheie)   │
                           │                           • dedupe (eventId)                                         ▼
                           │                           • combo -> 1 event                     RegistrationService  GiftRouter
                           │                           • coadă persistentă                          │                  │
                           │                           • HTTPS public                               ▼                  ▼
                           │                           (Cloudflare Tunnel                      QueueService ◄──── BoostService
                           │                            sau Render/Railway)                         │      (validare      │
                           │                                                                        ▼    owner+raceId)    ▼
                           │                                                                   RaceService ──► AuraService / VFX
                           │                                                                        │
                           └────────────────────────── vezi pe stream ◄── clientul tău Roblox (UI 9:16) ◄──┘
```

## 3. Modelul de identitate și securitate (regula „doar propriul personaj”)

1. **Proprietarul unui concurent = `tiktokUserId` din evenimentul TikTok** care a trimis `!join`. Acest ID vine de la platformă (cine a scris), **nu** din textul comentariului. Textul conține doar *ce* cont Roblox să fie afișat.
2. Un `tiktokUserId` are o singură înscriere (coadă SAU cursă). Un cont Roblox apare o singură dată.
3. Când vine un gift: `QueueService:GetActiveRacerByTikTok(senderTikTokId, raceIdCurent)`.
   * Expeditorul nu are concurent în cursa activă → gift-ul **nu activează nimic**.
   * Nu există niciun câmp „țintă”: e imposibil să trimiți boost altui concurent.
   * Fiecare event poartă `receivedAt`; serverul acceptă doar evenimente primite după startul cursei și înainte de finish (`raceId` + fereastră de timp). Evenimentele întârziate sunt respinse.
4. **Limitare:** oricine poate scrie `!join` cu username-ul Roblox *al altcuiva* (ar concura cu avatarul acelei persoane, dar boost-urile rămân ale celui care a scris). Pentru a bloca și asta, relay-ul are **verificare opțională, persistentă**:
   * `!verify NumeRoblox` → relay-ul generează un cod (ex. `RACE-7F3K`) afișat pe ecran;
   * spectatorul pune codul în descrierea profilului Roblox;
   * relay-ul citește `users.roblox.com/v1/users/{id}` (API public) și confirmă;
   * legătura TikTok ↔ Roblox se salvează permanent; după aceea acel cont Roblox poate fi înscris **doar** de acel TikToker.
   * Comutator în config: `RequireVerification = false | true`.
5. Securitate Roblox:
   * Clienții nu au niciun RemoteEvent care modifică viteza, coada sau boost-urile. Concurenții sunt NPC-uri controlate exclusiv de server.
   * `AdminCommand` verifică `player.UserId` la **fiecare** apel.
   * Cheia relay-ului stă în **Roblox Secrets Store** (`HttpService:GetSecret`), nu în cod.
   * Relay: dedupe după `eventId`, rate-limit per utilizator TikTok, combo-urile x99 devin un singur event cu `count` plafonat.
   * Evenimentele confirmate (ack) nu sunt livrate de două ori; serverul Roblox păstrează și el un set LRU de `eventId` procesate.

## 4. Mișcarea concurenților (de ce nu fizică)

* Fiecare hartă are un **traseu definit prin puncte de control** (`Waypoints`), transformat într-o curbă netedă (Catmull-Rom).
* Fiecare concurent are `distanceAlongTrack` și o bandă laterală (`laneOffset`). Serverul avansează distanța cu `speed * dt` și poziționează modelul cu `BulkMoveTo`.
* Avantaje: nimeni nu se blochează, nu există coliziuni, toți pornesc *exact* cu aceeași viteză, iar poziția în clasament = distanța parcursă (precis și ieftin).
* Mount-ul nu modifică viteza. O variație aleatorie simetrică (±4%, media 0, configurabilă) evită egalitățile perfecte fără donații.

## 5. Structura completă a proiectului

```
ReplicatedStorage
├─ Shared/                         (Folder)
│  ├─ Config            ModuleScript  configurare centrală            [Etapa 1 ✔]
│  ├─ Signal            ModuleScript  evenimente interne              [Etapa 1 ✔]
│  ├─ Validation        ModuleScript  validare username/ID/text       [Etapa 1 ✔]
│  ├─ Remotes           ModuleScript  creează/găsește remotes         [Etapa 1 ✔]
│  ├─ TrackMath         ModuleScript  spline, distanță → CFrame       [Etapa 4 ✔]
│  └─ AuraMath          ModuleScript  nivel aură după viteză          [Etapa 6]
├─ Remotes/             (Folder, creat automat de server)
└─ Assets/
   ├─ Sounds/           (Sound-uri: Boost, Turbo, Rocket, Thunder, Teleport, Start, Finish, Win...)
   └─ VFX/              (șabloane ParticleEmitter/Beam pentru aură și boost-uri)

ServerStorage
├─ Mounts/              (modele generate procedural de MountFactory, sau modelele tale)
└─ Maps/                (hărți generate de MapBuilder, sau construite de tine)

ServerScriptService
└─ Server/
   ├─ Main              Script        pornire + conectarea serviciilor [Etapa 1 ✔]
   ├─ Services/
   │  ├─ QueueService         coadă + prioritate + cursa activă     [Etapa 1 ✔]
   │  ├─ RobloxUserService    UserId + avatar original               [Etapa 1 ✔]
   │  ├─ RegistrationService  pipeline înscriere                     [Etapa 1 ✔]
   │  ├─ RaceState            faze cursă + fereastra de boost-uri    [Etapa 2 ✔]
   │  ├─ BridgeService        polling relay, ack, dedupe             [Etapa 2 ✔]
   │  ├─ GiftRouter           gift → boost / SkipQueue               [Etapa 2 ✔]
   │  ├─ AvatarService        avatar R15 + montare pe mount          [Etapa 3 ✔]
   │  ├─ MountFactory         16 mount-uri originale procedurale     [Etapa 3 ✔]
   │  ├─ Mounts/Builder       API de construcție din Part-uri         [Etapa 3 ✔]
   │  ├─ Mounts/Designs       cele 16 modele                         [Etapa 3 ✔]
   │  ├─ MountPicker          alegere aleatorie ponderată            [Etapa 3 ✔]
   │  ├─ StagingArea          lobby-ul cu sloturi                    [Etapa 3 ✔]
   │  ├─ PreRaceService       avatare + roata norocului (server decide) [Etapa 3 ✔]
   │  ├─ MapService           rotație hărți, încărcare, grilă start  [Etapa 4 ✔]
   │  ├─ Maps/MapBuilder      pistă, borduri, start/finish, decor    [Etapa 4 ✔]
   │  ├─ Maps/MapLayouts      punctele de control ale celor 6 trasee [Etapa 4 ✔]
   │  ├─ Maps/Themes          culori, lumină, decoruri per temă      [Etapa 4 ✔]
   │  ├─ RaceService          ciclu automat complet (23 pași)        [Etapa 5]
   │  ├─ RacerController      mișcare pe spline, clasament           [Etapa 5]
   │  ├─ BoostService         validare + aplicare boost-uri          [Etapa 6]
   │  └─ AdminService         comenzi admin validate                 [Etapa 8]
   └─ Tests/
      ├─ QueueService.spec    ModuleScript  teste automate           [Etapa 1 ✔]
      ├─ GiftRouter.spec      ModuleScript  teste donații            [Etapa 2 ✔]
      ├─ Mounts.spec          ModuleScript  teste mount-uri          [Etapa 3 ✔]
      └─ Maps.spec            ModuleScript  teste trasee             [Etapa 4 ✔]
   └─ LocalSecrets          ModuleScript  cheia relay doar în Studio [Etapa 2 ✔]

StarterPlayer/StarterPlayerScripts/Client  (Folder)
├─ ClientMain           LocalScript   pornire client + cameră lobby  [Etapa 3 ✔, extins în 7]
├─ MountAnimator        ModuleScript  animații mount + poza de călare [Etapa 3 ✔]
├─ WheelController      ModuleScript  roata norocului (UI din cod)   [Etapa 3 ✔]
├─ CameraDirector       ModuleScript  camera urmărește liderul       [Etapa 7]
├─ AuraRenderer         ModuleScript  aura (interpolare culoare/mărime) [Etapa 6]
└─ BoostFxRenderer      ModuleScript  efecte boost                   [Etapa 6]

StarterGui
├─ HUD                  ScreenGui     clasament, coadă, anunțuri (9:16) [Etapa 7]
├─ Wheel                ScreenGui     roata mount-urilor             [Etapa 7]
├─ Podium               ScreenGui     podium + câștigător            [Etapa 7]
└─ AdminPanel           ScreenGui     vizibil doar pentru admin      [Etapa 8]

relay/                  (în afara Roblox, Node.js 22, fără dependențe) [Etapa 2 ✔]
├─ src/server.js        pornire
├─ src/httpServer.js    API: /events?cursor=, /status, /simulate, /health
├─ src/pipeline.js      validare, anti-spam, dedupe, reguli înscriere
├─ src/normalize.js     format TikFinity/connector, combo-uri
├─ src/eventStore.js    cursor + ack + reluare după restart
├─ src/verify.js        verificare opțională TikTok ↔ Roblox
├─ src/sources/         tikfinity.js | connector.js
├─ src/sim.js           simulator evenimente
├─ test/relay.test.js   10 teste (npm test)
└─ .env.example         RELAY_KEY, SOURCE, ...
```

## 6. Etapele de implementare

| # | Etapă | Rezultat verificabil |
|---|---|---|
| **1** | **Fundație: Config, Remotes, Queue, identificare Roblox, înscriere ✔** | Teste automate trec; înscrieri simulate cu conturi reale apar în coadă |
| **2** | **Relay Node.js + BridgeService + GiftRouter ✔** | Un `!join` real din LIVE apare în coadă; gift-urile ajung în joc |
| **3** | **Avatar R15 + 16 mount-uri procedurale + roata norocului ✔** | Avatarul original stă pe mount, cu animație |
| **4** | **6 hărți procedurale fără obstacole + TrackMath ✔** | Traseu continuu de la start la finish, lat, cu decor doar în afara pistei |
| 5 | RaceService: ciclul automat complet | Curse care se repetă singure, cu clasament și podium |
| 6 | Boost-uri + aura în 4 niveluri + VFX + sunete | Gift → boost doar pentru propriul personaj |
| 7 | UI vertical 9:16 + camera de transmisie | Lizibil pe telefon |
| 8 | Panou de administrare | Toate controalele din cerință |
| 9 | Rezistență: test de încărcare (50 de concurenți, 20 de gift-uri/s), LIVE de mai multe ore | Fără scurgeri de memorie, reconectare relay |

## 7. Rularea în timpul LIVE-ului
* Testezi în **Studio** (Play). Pentru LIVE folosești jocul **publicat**, pe un **server privat**, ca să fii singurul jucător. Clientul tău Roblox este „camera” pe care o transmiți (OBS / TikTok LIVE Studio, captură 9:16).
* Serverul Roblox este cel care face cererile HTTP către relay, deci relay-ul trebuie să aibă un **URL HTTPS public** (Cloudflare Tunnel de pe PC sau un serviciu găzduit).
* Sunetele și animațiile trebuie să fie asset-uri pe care le deții sau care sunt publice în Creator Store. Mount-urile și VFX-urile sunt construite procedural din Part-uri, ca modele originale.
