# MacOS Icons

Applicazione macOS nativa per cercare icone su macOSicons e applicarle a bundle `.app` locali. Il codice è open source, ma ogni installazione usa il proprio Worker Cloudflare e la propria chiave API macOSicons: non esiste alcun endpoint condiviso o fallback gestito da Matteo.

## Cosa fa

- Cerca il catalogo macOSicons e conserva una cache locale.
- Consente di trascinare o scegliere un'applicazione installata.
- Applica e ripristina l'icona di bundle `.app` scrivibili.
- Conserva il token del Worker nel Portachiavi di macOS, mai nel bundle o in `UserDefaults`.

## Requisiti

- macOS 14 o successivo.
- Xcode 26.6 o successivo.
- Node.js 20 o successivo e un account Cloudflare per il Worker.
- Una chiave API personale di macOSicons, configurata solo come secret del Worker.

## Avvio rapido

1. Distribuisci il tuo Worker dalla cartella [`worker`](worker/README.md). Ti serviranno due secret: `MACOSICONS_API_KEY` e `CLIENT_AUTH_TOKEN`.
2. Apri `MacOS Icons.xcodeproj` in Xcode, scegli il tuo Team in Signing & Capabilities ed esegui il target `MacOS Icons`.
3. Al primo avvio inserisci l'URL HTTPS del tuo Worker e lo stesso `CLIENT_AUTH_TOKEN` configurato su Cloudflare. L'app esegue `GET /health` prima di salvare i valori.

La chiave API macOSicons non viene mai chiesta dall'app e non attraversa la rete dal Mac. Il Worker la conserva nel suo secret store e la usa soltanto per chiamare l'upstream.

## Build e test

Per una build locale senza firma:

```sh
xcodebuild \
  -project "MacOS Icons.xcodeproj" \
  -scheme "MacOS Icons" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Per i test del client:

```sh
xcodebuild \
  -project "MacOS Icons.xcodeproj" \
  -scheme "MacOS Icons" \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Per i test del Worker:

```sh
cd worker
npm ci
npm test
```

## Sicurezza e privacy

- L'URL del Worker è una preferenza locale, il token è nel Portachiavi.
- Il Worker richiede `Authorization: Bearer <CLIENT_AUTH_TOKEN>` sia per `/health` sia per `/search`.
- Le richieste di ricerca non contengono `apiKey` e il Worker non inoltra il bearer token all'upstream.
- Ogni fork deve distribuire il proprio Worker, impostare i propri secret e ruotarli autonomamente.

Consulta [SECURITY.md](SECURITY.md) per le segnalazioni di vulnerabilità.

## Limiti

L'app può modificare solo bundle per cui l'utente ha permessi di scrittura. App protette dal sistema, firmate o in cartelle non scrivibili possono rifiutare il cambio icona. Le icone ottenute dal catalogo macOSicons restano soggette ai diritti e alle condizioni dei rispettivi autori e del servizio.

MacOS Icons non è affiliata a macOSicons o ad Apple. `macOS` è un marchio di Apple Inc.

## Licenza

Il codice sorgente è distribuito con licenza [MIT](LICENSE). Gli asset di branding sono esclusi dalla licenza, come dettagliato in [NOTICE.md](NOTICE.md).

Per contribuire, consulta [CONTRIBUTING.md](CONTRIBUTING.md).
