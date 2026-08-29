//
//  AgentWorkerSetupPrompt.swift
//  MacOS Icons
//
//  Il testo operativo che l'utente invia al proprio agente per configurare
//  il Worker personale senza dover seguire istruzioni tecniche nell'app.
//

import Foundation

enum AgentWorkerSetupPrompt {
    static let text = """
    Configura MacOS Icons sul mio Mac. Procedi in autonomia:

    1. Usa il Worker incluso nel repository https://github.com/themattvision/macos-icons, nella cartella worker/.
    2. Pubblicalo nel mio account Cloudflare già autenticato.
    3. Chiedimi la mia MACOSICONS_API_KEY soltanto quando ti serve, poi salvala come secret del Worker. Non salvarla in file, nel repository o nel client macOS.
    4. Genera un CLIENT_AUTH_TOKEN lungo e casuale, salvalo come secret del Worker e non committarlo.
    5. Pubblica il Worker e verifica GET /health con Authorization: Bearer <CLIENT_AUTH_TOKEN>.
    6. Quando è tutto pronto, rispondimi soltanto con questi due valori, uno per riga:
    WORKER_URL: https://...
    CLIENT_AUTH_TOKEN: ...

    Non modificare il codice dell’app macOS.
    """
}
