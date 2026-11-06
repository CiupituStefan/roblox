# TikTok LIVE Race (Roblox)

Joc de curse haotic pentru TikTok LIVE: spectatorii se înscriu cu username-ul Roblox
prin chat (`!join Nume`), apar în joc cu **avatarul lor original**, primesc un mount
aleatoriu de la roata norocului și își pot accelera **doar propriul personaj** prin gift-uri.

- Arhitectura completă și etapele: [`ARHITECTURA.md`](ARHITECTURA.md)
- Relay-ul TikTok → Roblox (Node.js): [`relay/README.md`](relay/README.md)

## Structură

```
src/ReplicatedStorage/Shared          -> ReplicatedStorage > Shared (module partajate)
src/ServerScriptService/Server        -> ServerScriptService > Server (logica serverului)
src/StarterPlayerScripts/Client       -> StarterPlayer > StarterPlayerScripts > Client
relay/                                -> serviciul extern Node.js (rulează pe PC-ul tău)
default.project.json                  -> proiect Rojo (sincronizare automată în Studio)
```

## Pornire rapidă

1. Cu [Rojo](https://rojo.space): `rojo serve` și conectează pluginul din Studio.
   Fără Rojo: creează manual obiectele din tabelul din `ARHITECTURA.md` și copiază codul.
2. Publică locul, activează **Allow HTTP Requests** și dezactivează **Workspace.StreamingEnabled**.
3. Apasă **Play**: testele automate rulează în Output, iar un ciclu de test pornește cu conturi reale.
4. Pentru TikTok: urmează pașii din `relay/README.md`.

## Panoul de administrare

- Apasă **F2** (sau butonul ⚙️ din colțul stânga-jos) ca să-l deschizi. Apare doar pentru admini:
  proprietarul jocului, `Config.Admin.UserIds` sau oricine în Studio (`AllowAllInStudio`).
- Toate comenzile sunt verificate pe server; setările modificabile sunt într-o listă albă cu limite.
- Modificările se salvează (DataStore) și se reîncarcă la repornire (`Config.Admin.PersistSettings`).
  În Studio activează *Game Settings → Security → Enable Studio Access to API Services*.
- În LIVE: deschide panoul de pe un al doilea dispozitiv conectat la același server privat,
  ca să nu apară pe stream (sau ascunde butonul cu `Config.Admin.ShowToggleButton = false`).

