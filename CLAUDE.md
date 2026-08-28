# MacOS Icons: guida di progetto

## Architettura

Il client SwiftUI cerca e applica icone a bundle `.app` locali. Non è sandboxed intenzionalmente: `IconApplier` deve poter scrivere bundle scelti dall'utente. Il target principale è una file-system synchronized group Xcode, quindi i nuovi file Swift sotto `MacOS Icons/` sono rilevati senza aggiungere riferimenti PBX manuali.

Ogni installazione deve usare il proprio Worker Cloudflare incluso in `worker/`:

```text
Client macOS -> Worker personale -> API macOSicons
                 |
                 +-- CLIENT_AUTH_TOKEN
                 +-- MACOSICONS_API_KEY
```

L'app non contiene una chiave macOSicons, un endpoint condiviso o un proxy secret. `WorkerConfigurationStore` salva l'URL HTTPS in `UserDefaults` e `CLIENT_AUTH_TOKEN` nel Portachiavi. `GET /health` richiede il bearer token e deve rispondere esattamente `{ "ok": true, "version": 1 }`; `POST /search` riceve soltanto `{ query, searchOptions }`.

## Comandi verificati

```sh
xcodebuild -project "MacOS Icons.xcodeproj" -scheme "MacOS Icons" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "MacOS Icons.xcodeproj" -scheme "MacOS Icons" CODE_SIGNING_ALLOWED=NO test
cd worker && npm ci && npm test
cd worker && npx wrangler deploy --dry-run
```

## Trappole

- Non mettere segreti in `wrangler.toml`, `.xcconfig`, plist o client. Usa `wrangler secret put` nel Worker personale.
- Non aggiungere CORS al Worker senza un caso browser reale: CORS non autentica alcunché.
- La cache KV del Worker è opzionale: il primo `wrangler deploy` deve funzionare senza binding.
- Se il contratto del Worker cambia, aggiorna client, test e `worker/README.md` insieme.
- Gli asset `logo-*` e le AppIcon derivate non sono coperti dalla MIT, vedi `NOTICE.md`; non sostituirli né ridistribuirli senza autorizzazione esplicita.
