# macOS Icons Worker

Proxy Cloudflare Worker minimale per la ricerca sull'API ufficiale di macOSicons. Il client si autentica verso il Worker con un token dedicato; la chiave API upstream resta sempre nei secret Cloudflare e non viene accettata nel body.

## Endpoint

### `GET /health`

Richiede `Authorization: Bearer <CLIENT_AUTH_TOKEN>` e restituisce esattamente:

```json
{ "ok": true, "version": 1 }
```

### `POST /search`

Richiede lo stesso header e `Content-Type: application/json`.

```json
{
  "query": "Safari",
  "searchOptions": {
    "hitsPerPage": 50,
    "page": 1,
    "offset": 0,
    "filters": [],
    "sort": []
  }
}
```

Il Worker invia la richiesta a `https://api.macosicons.com/api/search` con `MACOSICONS_API_KEY` nell'header upstream `x-api-key`. Un campo client `apiKey`, campi sconosciuti e valori fuori limite vengono rifiutati. Non sono emessi header CORS, quindi il servizio non abilita chiamate cross-origin dal browser.

## Configurazione locale

Richiede Node.js 20 o successivo.

```sh
npm install
cp .dev.vars.example .dev.vars
```

Compilare `.dev.vars` soltanto in locale:

```dotenv
CLIENT_AUTH_TOKEN=un-token-client-lungo-e-casuale
MACOSICONS_API_KEY=la-chiave-personale-upstream
```

Poi avviare il Worker con `npm run dev` ed eseguire i test con `npm test`.

## Deploy

Il file `wrangler.toml` non contiene account ID, route, endpoint personali, binding o segreti. Prima del deploy, salvare entrambi i valori come secret del proprio Worker:

```sh
npx wrangler secret put CLIENT_AUTH_TOKEN
npx wrangler secret put MACOSICONS_API_KEY
npx wrangler deploy
```

Un deploy fresco non richiede KV. Per abilitare la cache server-side, creare una namespace KV e aggiungere manualmente a `wrangler.toml` un binding chiamato `SEARCH_CACHE`. Facoltativamente, `SEARCH_CACHE_TTL_SECONDS` può impostare un TTL fra 60 e 86400 secondi; il default è 3600.

## Sicurezza e limiti

- Il body massimo è 16 KiB e la risposta upstream massima è 4 MiB.
- `query` accetta al massimo 200 caratteri ed è consentita vuota per il catalogo più recente.
- `hitsPerPage` è 1-100, `page` 1-1000 e `offset` 0-100000.
- `filters` accetta al massimo 20 stringhe da 200 caratteri; `sort` al massimo 5 stringhe da 100 caratteri.
- Il Worker non registra body, token o chiavi e non inoltra l'header `Authorization` all'upstream.
- Errori upstream non includono il body diagnostico nella risposta al client.
