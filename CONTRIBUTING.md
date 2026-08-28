# Contribuire

## Prima di aprire una pull request

1. Non aggiungere endpoint personali, account ID, chiavi API, token, file `.dev.vars`, `.env` o configurazioni Cloudflare locali.
2. Non introdurre un fallback verso un Worker condiviso: ogni utente deve poter usare il proprio.
3. Esegui `npm test` in `worker/` e build o test Xcode appropriati al cambiamento.
4. Aggiorna `README.md`, `worker/README.md` o `CLAUDE.md` quando cambia il contratto Worker, l'onboarding o una trappola operativa.

## Convenzioni

- Mantieni il contratto `GET /health` e `POST /search` compatibile con il client prima di modificare entrambi i lati.
- Non registrare body, bearer token o chiavi upstream nel Worker.
- Nuovi test Swift usano Swift Testing; i test UI restano XCTest quando servono automazione.
- Non modificare asset di branding senza una decisione esplicita del titolare e una verifica dei diritti.
