//
//  SearchFailure+Messages.swift
//  MacOS Icons
//
//  Un posto solo dove qualunque errore diventa una frase che l'utente puo' capire.
//  Prima l'app stampava in griglia il testo di sistema ("Errore HTTP: 429"): un codice
//  che non dice cosa e' successo, non dice perche' e soprattutto non dice cosa fare.
//  Qui ogni errore viene tradotto nelle tre cose che servono, con l'azione giusta accanto.
//

import Foundation

extension SearchFailure {

    // MARK: - Traduzione di un errore qualsiasi

    /// Trasforma un errore in un messaggio mostrabile.
    /// - Parameters:
    ///   - error: l'errore arrivato dalla rete o dalla decodifica
    ///   - quotaResetDate: quando riparte il conteggio mensile, usato solo dal caso quota esaurita
    static func describing(_ error: Error, quotaResetDate: Date? = nil) -> SearchFailure {
        if let networkError = error as? NetworkError {
            switch networkError {
            case .unauthorized:
                return .invalidWorkerToken
            case .rateLimited:
                return .quotaExhausted(resetDate: quotaResetDate)
            case .forbidden:
                return .invalidWorkerToken
            case .serverUnavailable:
                return .serverUnavailable
            case .decodingError:
                return .unreadableResponse
            case .missingConfiguration:
                return .missingWorkerConfiguration
            case .invalidResponse:
                return .unreadableResponse
            case .httpError(let code):
                return .unexpected(code: code)
            }
        }

        // URLError copre tutto il resto: niente rete, DNS, timeout, connessione caduta.
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .offline
            case .timedOut:
                return .timedOut
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .siteUnreachable
            case .cancelled:
                // Una richiesta annullata non e' un errore da mostrare, ma se arriva qui
                // meglio una frase neutra che il testo di sistema in inglese.
                return .offline
            default:
                return .offline
            }
        }

        return .unreadableResponse
    }

    // MARK: - Casi specifici

    /// Nessun Worker verificato: non e' un guasto, e' un passo di configurazione mancante.
    static var missingWorkerConfiguration: SearchFailure {
        SearchFailure(
            symbol: "server.rack",
            tint: .neutral,
            title: String(localized: "Configura il tuo Worker"),
            message: String(localized: "Inserisci nelle Impostazioni l’URL HTTPS del tuo Worker e il relativo CLIENT_AUTH_TOKEN. L’app li verifica prima di iniziare a cercare."),
            actionTitle: String(localized: "Apri le Impostazioni"),
            action: .openSettings
        )
    }

    /// 429: la quota mensile del piano gratuito e' finita. Ritentare non serve a niente,
    /// quindi niente bottone "Riprova": l'unica strada e' aspettare o cambiare piano.
    static func quotaExhausted(resetDate: Date?) -> SearchFailure {
        let quota = 100
        let when: String
        if let resetDate {
            when = String(localized: "Il conteggio riparte il \(Self.dayMonth(resetDate)).")
        } else {
            when = String(localized: "Il conteggio riparte all'inizio del mese prossimo.")
        }

        return SearchFailure(
            symbol: "hourglass.tophalf.filled",
            tint: .warning,
            title: String(localized: "Ricerche finite per questo mese"),
            message: String(localized: "Il servizio a monte del tuo Worker ha esaurito le \(quota) ricerche mensili. \(when) Controlla la configurazione o il piano del servizio usato dal Worker."),
            actionTitle: String(localized: "Apri le Impostazioni"),
            action: .openSettings
        )
    }

    /// 401/403: il Worker non riconosce piu' il bearer token salvato.
    static var invalidWorkerToken: SearchFailure {
        SearchFailure(
            symbol: "key.slash.fill",
            tint: .danger,
            title: String(localized: "Token del Worker rifiutato"),
            message: String(localized: "Il Worker non riconosce più il token salvato nell’app. Inserisci nelle Impostazioni il valore corrente di CLIENT_AUTH_TOKEN e verifica di nuovo la connessione."),
            actionTitle: String(localized: "Apri le Impostazioni"),
            action: .openSettings
        )
    }

    /// 5xx: il guasto è dalla loro parte, quindi vale la pena riprovare.
    static var serverUnavailable: SearchFailure {
        SearchFailure(
            symbol: "exclamationmark.icloud.fill",
            tint: .warning,
            title: String(localized: "Il Worker non risponde"),
            message: String(localized: "Il tuo Worker è temporaneamente irraggiungibile. Controlla rete e deploy, poi riprova."),
            isRetryable: true
        )
    }

    /// Nessuna rete: l'errore più comune e il più facile da risolvere.
    static var offline: SearchFailure {
        SearchFailure(
            symbol: "wifi.slash",
            tint: .warning,
            title: String(localized: "Nessuna connessione"),
            message: String(localized: "Il Mac non riesce a raggiungere il tuo Worker. Controlla la connessione a internet e riprova."),
            isRetryable: true
        )
    }

    static var timedOut: SearchFailure {
        SearchFailure(
            symbol: "clock.badge.exclamationmark.fill",
            tint: .warning,
            title: String(localized: "Risposta troppo lenta"),
            message: String(localized: "Il Worker ci ha messo troppo a rispondere e la richiesta è stata interrotta. Di solito basta riprovare."),
            isRetryable: true
        )
    }

    static var siteUnreachable: SearchFailure {
        SearchFailure(
            symbol: "network.slash",
            tint: .warning,
            title: String(localized: "Server irraggiungibile"),
            message: String(localized: "Non si riesce a contattare il Worker configurato. Può essere la rete, un DNS o un deploy non attivo."),
            isRetryable: true
        )
    }

    /// Risposta arrivata ma illeggibile: quasi sempre un cambio di formato lato loro.
    static var unreadableResponse: SearchFailure {
        SearchFailure(
            symbol: "doc.questionmark.fill",
            tint: .warning,
            title: String(localized: "Risposta non leggibile"),
            message: String(localized: "Il Worker ha risposto in un formato incompatibile con questa app. Verifica di aver pubblicato la versione corretta del Worker."),
            isRetryable: true
        )
    }

    /// Rete degli errori che non sappiamo classificare: si dice cosa fare, non il codice.
    static func unexpected(code: Int) -> SearchFailure {
        SearchFailure(
            symbol: "exclamationmark.triangle.fill",
            tint: .warning,
            title: String(localized: "Ricerca non riuscita"),
            message: String(localized: "Il Worker ha rifiutato la richiesta per un motivo inatteso. Riprova: se continua, verifica URL e token nelle Impostazioni."),
            actionTitle: String(localized: "Apri le Impostazioni"),
            action: .openSettings,
            isRetryable: true
        )
    }

    /// Ricerca andata a buon fine ma senza risultati: non e' un errore, e infatti il
    /// simbolo non e' d'allarme, ma passa dalla stessa vista per non avere due schermate gemelle.
    static func noResults(query: String) -> SearchFailure {
        SearchFailure(
            symbol: "questionmark.folder",
            tint: .neutral,
            title: String(localized: "Nessun risultato"),
            message: String(localized: "Nessuna icona trovata per \"\(query)\". Prova con un altro nome, per esempio quello del produttore invece che dell'app.")
        )
    }

    // MARK: - Formattazione

    /// Data in forma breve e italiana ("1 settembre"), senza anno: la quota si azzera
    /// sempre entro il mese, l'anno sarebbe rumore.
    private static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide))
    }
}
