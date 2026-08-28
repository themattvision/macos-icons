# Security policy

## Segnalazioni

Non pubblicare segreti, token, chiavi API o una proof of concept sfruttabile in una issue pubblica. Invia invece una descrizione riproducibile a [info@matteozampieri.com](mailto:info@matteozampieri.com), includendo la versione del client o del Worker e l'impatto osservato.

## Confini di sicurezza

- `MACOSICONS_API_KEY` e `CLIENT_AUTH_TOKEN` sono secret del Worker dell'installazione, mai file del repository.
- L'app salva solo il bearer token nel Portachiavi e l'URL del Worker nelle preferenze locali.
- Ogni deploy è indipendente: un token o una chiave esposti vanno ruotati nel proprio account Cloudflare e aggiornati nell'app.

Le versioni attivamente mantenute coincidono con il branch `main`.
