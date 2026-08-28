//
//  IconSearchService.swift
//  MacOS Icons
//
//  Created by Matteo Zampieri on 14/09/25.
//

import Foundation
import OSLog

/// Ultima volta che l'API ha risposto "quota esaurita": serve a non ripetere chiamate
/// che sappiamo gia' destinate a fallire, senza pero' restare bloccati per sempre.
private let lastRateLimitDefaultsKey = "macosicons.lastRateLimit"

/// Servizio per gestire le chiamate all'API di ricerca icone
@MainActor
class IconSearchService: ObservableObject {
    @Published var searchState: SearchState = .idle
    /// URL pubblico del Worker personale. Non e' un segreto e viene mostrato nelle Impostazioni.
    @Published private(set) var workerURLString: String
    @Published var currentPage: Int = 1
    @Published var totalPages: Int = 0
    @Published var isLoadingMore: Bool = false
    /// Numero totale di risultati per la query corrente, usato ad esempio per il sottotitolo della finestra
    @Published private(set) var totalHits: Int = 0
    /// True quando la lista in vista sono le ultime icone caricate (home), false quando e' il risultato di una ricerca
    @Published private(set) var isShowingLatest: Bool = false
    /// True quando c'e' gia' un elenco a schermo e lo si sta aggiornando (nuova ricerca o cambio ordinamento).
    /// Diverso da searchState = .loading: .loading vuol dire "non ho niente da mostrare ancora", isRefreshing
    /// vuol dire "ho gia' qualcosa e lo sto sostituendo", quindi la vista puo' tenere la griglia vecchia a schermo
    /// invece di smontarla e farla ripartire da capo.
    @Published private(set) var isRefreshing: Bool = false
    /// Avviso da mostrare sopra i risultati quando quello che si vede non arriva dalla rete
    /// ma dalla copia salvata sul Mac. Nil quando i dati sono freschi: un banner sempre acceso
    /// diventerebbe invisibile proprio quando conta.
    @Published private(set) var staleNotice: String?

    private let log = Logger(subsystem: "com.matteozampieri.macosicons", category: "search")
    private let configurationStore: WorkerConfigurationStore
    private var configuration: WorkerConfiguration?
    private var currentQuery: String = ""
    /// Ordinamento della ricerca corrente, mantenuto per far paginare loadMoreResults con lo stesso criterio
    private var currentSortOrder: IconSortOrder = .relevance
    private var allIcons: [IconItem] = []
    /// Diventa true al primo caricamento riuscito (ricerca o home): serve a loadMoreResults per sapere
    /// se c'e' gia' un elenco da continuare, dato che con la home la query resta vuota
    private var hasLoadedResults: Bool = false

    /// Momento dell'ultimo 429, persistito: se l'app si riavvia dieci volte di fila non deve
    /// sprecare una chiamata ad ogni lancio per riscoprire che la quota e' finita.
    private var lastRateLimitAt: Date? {
        get { UserDefaults.standard.object(forKey: lastRateLimitDefaultsKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastRateLimitDefaultsKey) }
    }

    /// Quanto si aspetta prima di riprovare dopo un "quota esaurita". Non e' un backoff per il
    /// server ma per l'utente: la quota e' mensile, quindi riprovare subito è inutile, ma restare
    /// bloccati fino a fine mese sarebbe peggio se il conteggio si sbloccasse prima.
    private let rateLimitCooldown: TimeInterval = 15 * 60

    /// Quanto resta valida una risposta salvata. La home cambia quando il catalogo pubblica
    /// icone nuove, quindi vive un'ora; una ricerca per nome invece dà gli stessi risultati
    /// per giorni, e con 100 chiamate al mese ripeterla sarebbe uno spreco.
    private let latestCacheTTL: TimeInterval = 60 * 60
    private let searchCacheTTL: TimeInterval = 24 * 60 * 60

    var isConfigured: Bool {
        configuration != nil
    }

    init(configurationStore: WorkerConfigurationStore = WorkerConfigurationStore()) {
        self.configurationStore = configurationStore
        let storedConfiguration = configurationStore.load()
        self.configuration = storedConfiguration
        self.workerURLString = storedConfiguration?.endpoint.absoluteString ?? ""
    }

    /// Verifica il Worker con i valori ancora in bozza e li persiste solo dopo un health check
    /// autenticato riuscito. Il token non passa mai da UserDefaults.
    func validateAndSaveConfiguration(workerURL: String, token: String) async throws {
        let endpoint = try Self.normalizedWorkerURL(workerURL)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw WorkerConfigurationError.missingToken }

        let candidate = WorkerConfiguration(endpoint: endpoint, token: trimmedToken)
        try await validateHealth(of: candidate)

        do {
            try configurationStore.save(candidate)
            configuration = candidate
            workerURLString = endpoint.absoluteString
            // Worker nuovo, quota e blocchi del precedente non valgono piu'.
            ApiUsageTracker.shared.resetForNewKey()
            lastRateLimitAt = nil
        } catch {
            log.error("Salvataggio della configurazione Worker fallito: \(error.localizedDescription, privacy: .public)")
            throw WorkerConfigurationError.secureStorage
        }
    }

    static func normalizedWorkerURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            var components = URLComponents(string: trimmed),
            components.scheme?.lowercased() == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            throw WorkerConfigurationError.invalidURL
        }

        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else { throw WorkerConfigurationError.invalidURL }
        return url
    }

    // MARK: - Ricerca

    /// Decide come segnalare l'inizio di un caricamento: se in griglia c'e' gia' un elenco non vuoto
    /// si resta in stale-while-revalidate (isRefreshing, searchState invariato), altrimenti si passa
    /// per .loading come al primissimo caricamento, quando non c'e' ancora niente da mostrare.
    private func beginLoading() {
        if case .success(let icons) = searchState, !icons.isEmpty {
            isRefreshing = true
        } else {
            searchState = .loading
        }
    }

    /// Esegue una ricerca di icone utilizzando l'API
    /// - Parameters:
    ///   - query: Termine di ricerca
    ///   - sortOrder: Criterio di ordinamento scelto dall'utente, mantenuto per la paginazione successiva
    func searchIcons(query: String, sortOrder: IconSortOrder) async {
        guard isConfigured else {
            searchState = .error(.missingWorkerConfiguration)
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Verifica che la query non sia vuota
        guard !trimmed.isEmpty else {
            searchState = .error(.noResults(query: query))
            return
        }

        // Reset per nuova ricerca. Una query non vuota lascia sempre la modalita' home.
        currentQuery = trimmed
        currentSortOrder = sortOrder
        currentPage = 1
        allIcons = []
        isShowingLatest = false
        beginLoading()
        defer { isRefreshing = false }

        await loadFirstPage(query: trimmed, sortOrder: sortOrder, maxAge: searchCacheTTL)
    }

    /// Carica le ultime icone caricate sul catalogo (home), con query vuota e ordinamento per data discendente.
    /// Riusa la stessa pipeline della ricerca, quindi la home e' a tutti gli effetti una ricerca con query vuota.
    func loadLatest() async {
        guard isConfigured else {
            searchState = .error(.missingWorkerConfiguration)
            return
        }

        // Query vuota + timeStamp:desc, verificato con l'API reale: torna le ultime icone caricate.
        let latestSortOrder = IconSortOrder.recent
        currentQuery = ""
        currentSortOrder = latestSortOrder
        currentPage = 1
        allIcons = []
        isShowingLatest = true
        beginLoading()
        defer { isRefreshing = false }

        await loadFirstPage(query: "", sortOrder: latestSortOrder, maxAge: latestCacheTTL)
    }

    /// Corpo comune di ricerca e home: una sola strada per cache, rete, stale e messaggi d'errore.
    private func loadFirstPage(query: String, sortOrder: IconSortOrder, maxAge: TimeInterval) async {
        do {
            let page = try await fetchPage(query: query, sortOrder: sortOrder, page: 1, maxAge: maxAge)
            allIcons = page.response.hits
            totalPages = page.response.totalPages
            totalHits = page.response.totalHits
            hasLoadedResults = true
            staleNotice = page.staleNotice

            if allIcons.isEmpty, !query.isEmpty {
                // Ricerca riuscita ma a vuoto: e' un esito, non un guasto, e merita un testo suo.
                searchState = .error(.noResults(query: query))
            } else {
                searchState = .success(allIcons)
            }
        } catch {
            log.error("Caricamento fallito: \(error.localizedDescription, privacy: .public)")
            staleNotice = nil
            searchState = .error(.describing(error, quotaResetDate: ApiUsageTracker.shared.quotaResetDate))
        }
    }

    /// Carica più risultati per l'elenco corrente (ricerca o home), mantenendo query e ordinamento in uso
    func loadMoreResults() async {
        // hasLoadedResults al posto di "query non vuota": la home ha query vuota per definizione
        // ma e' comunque un elenco valido da continuare a paginare.
        guard !isLoadingMore, hasLoadedResults, currentPage < totalPages else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = currentPage + 1
        let maxAge = currentQuery.isEmpty ? latestCacheTTL : searchCacheTTL

        do {
            let page = try await fetchPage(query: currentQuery, sortOrder: currentSortOrder, page: nextPage, maxAge: maxAge)
            allIcons.append(contentsOf: page.response.hits)
            currentPage = nextPage
            totalHits = page.response.totalHits
            searchState = .success(allIcons)
        } catch {
            log.error("Caricamento pagina successiva fallito: \(error.localizedDescription, privacy: .public)")
            // Non cambiare lo stato principale, mantieni i risultati esistenti
        }
    }

    // MARK: - Caricamento di una pagina

    /// Esito di una pagina, con l'eventuale avviso da mostrare quando i dati non sono freschi.
    private struct PageResult {
        let response: IconSearchResponse
        let staleNotice: String?
    }

    /// Ordine di preferenza: copia fresca sul Mac, poi rete, poi copia vecchia. L'ultimo passaggio
    /// e' quello che tiene in piedi l'app quando la quota mensile e' finita: meglio un catalogo
    /// di ieri che una schermata d'errore.
    private func fetchPage(query: String, sortOrder: IconSortOrder, page: Int, maxAge: TimeInterval) async throws -> PageResult {
        let sortRules = sortOrder.apiSortRules

        if let cached = await IconSearchCache.shared.fresh(query: query, sort: sortRules, page: page, maxAge: maxAge) {
            return PageResult(response: cached, staleNotice: nil)
        }

        // Quota finita da poco: chiamare l'API darebbe di sicuro un altro 429 e brucerebbe
        // tempo, quindi si va direttamente alla copia salvata.
        if isInRateLimitCooldown {
            if let stale = await IconSearchCache.shared.entry(query: query, sort: sortRules, page: page) {
                return PageResult(response: stale.response, staleNotice: Self.staleQuotaNotice(age: stale.age))
            }
            throw NetworkError.rateLimited
        }

        // hitsPerPage: 50 perche' l'API ignora il valore richiesto e restituisce comunque 50 per pagina
        let options = SearchOptions(hitsPerPage: 50, page: page, sort: sortRules)

        do {
            let response = try await performSearchWithResponse(query: query, searchOptions: options)
            await IconSearchCache.shared.store(response, query: query, sort: sortRules, page: page)
            return PageResult(response: response, staleNotice: nil)
        } catch {
            if case NetworkError.rateLimited = error {
                ApiUsageTracker.shared.markQuotaExhausted()
                lastRateLimitAt = Date()
            }

            // Qualunque sia il guasto (quota, rete, server giu'), se abbiamo una copia la mostriamo.
            if let stale = await IconSearchCache.shared.entry(query: query, sort: sortRules, page: page) {
                let notice: String
                if case NetworkError.rateLimited = error {
                    notice = Self.staleQuotaNotice(age: stale.age)
                } else {
                    notice = Self.staleOfflineNotice(age: stale.age)
                }
                return PageResult(response: stale.response, staleNotice: notice)
            }

            throw error
        }
    }

    /// True finche' siamo nella finestra di attesa dopo un "quota esaurita".
    private var isInRateLimitCooldown: Bool {
        guard let lastRateLimitAt else { return false }
        // Il conteggio si azzera a inizio mese: superata quella data l'attesa non ha piu' senso,
        // qualunque cosa dica il cronometro.
        if Date() >= ApiUsageTracker.shared.quotaResetDate { return false }
        return Date().timeIntervalSince(lastRateLimitAt) < rateLimitCooldown
    }

    // MARK: - Avvisi sui dati non freschi

    private static func staleQuotaNotice(age: TimeInterval) -> String {
        String(localized: "Ricerche del mese finite: stai vedendo la copia salvata \(relativeAge(age)).")
    }

    private static func staleOfflineNotice(age: TimeInterval) -> String {
        String(localized: "Il Worker non risponde: stai vedendo la copia salvata \(relativeAge(age)).")
    }

    /// Eta' della copia in parole, non in secondi: all'utente serve sapere se sta guardando
    /// roba di poco fa o della settimana scorsa, non un numero da interpretare.
    private static func relativeAge(_ age: TimeInterval) -> String {
        let minutes = Int(age / 60)
        if minutes < 60 {
            return String(localized: "pochi minuti fa")
        }
        let hours = minutes / 60
        if hours < 24 {
            return String(localized: "\(hours) ore fa")
        }
        let days = hours / 24
        return days == 1 ? String(localized: "ieri") : String(localized: "\(days) giorni fa")
    }

    // MARK: - Rete

    private struct HealthResponse: Decodable {
        let ok: Bool
        let version: Int
    }

    private func validateHealth(of candidate: WorkerConfiguration) async throws {
        var request = URLRequest(url: candidate.endpoint.appending(path: "health"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(candidate.token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WorkerConfigurationError.unreachable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkerConfigurationError.incompatibleContract
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw WorkerConfigurationError.invalidToken
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw WorkerConfigurationError.unreachable
        }
        guard
            let health = try? JSONDecoder().decode(HealthResponse.self, from: data),
            health.ok,
            health.version == 1
        else {
            throw WorkerConfigurationError.incompatibleContract
        }
    }

    /// Esegue la chiamata HTTP all'API e restituisce la risposta completa
    private func performSearchWithResponse(query: String, searchOptions: SearchOptions) async throws -> IconSearchResponse {
        guard let configuration else { throw NetworkError.missingConfiguration }
        let url = configuration.endpoint.appending(path: "search")

        // Prepara il corpo della richiesta
        let searchRequest = SearchRequest(query: query, searchOptions: searchOptions)
        let requestBody = try JSONEncoder().encode(searchRequest)

        // Configura la richiesta HTTP
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = requestBody

        // Configura timeout per la richiesta
        request.timeoutInterval = 30.0

        // Da qui in poi la chiamata parte davvero: e' questo il momento in cui si consuma
        // una delle 100 query mensili, non quando l'utente scrive nel campo di ricerca.
        ApiUsageTracker.shared.recordCall()

        // Esegue la richiesta con timeout
        let (data, response) = try await URLSession.shared.data(for: request)

        // Verifica la risposta HTTP
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw NetworkError.unauthorized
        case 403:
            throw NetworkError.forbidden
        case 429:
            throw NetworkError.rateLimited
        case 500...599:
            throw NetworkError.serverUnavailable
        default:
            throw NetworkError.httpError(httpResponse.statusCode)
        }

        // Decodifica la risposta JSON
        do {
            return try JSONDecoder().decode(IconSearchResponse.self, from: data)
        } catch {
            log.error("Errore di decodifica JSON: \(error.localizedDescription, privacy: .public)")
            throw NetworkError.decodingError
        }
    }

    /// Resetta lo stato della ricerca
    func resetSearch() {
        searchState = .idle
        staleNotice = nil
    }
}

// MARK: - Errori di rete

/// Enum per gestire gli errori di rete. I testi mostrati all'utente non stanno qui ma in
/// `SearchFailure`: questi casi servono a distinguere le situazioni, non a raccontarle.
enum NetworkError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case unauthorized
    case forbidden
    /// 429: la quota di chiamate del piano e' finita.
    case rateLimited
    case serverUnavailable
    case httpError(Int)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return String(localized: "Il Worker non è configurato")
        case .invalidResponse:
            return String(localized: "Risposta del server non valida")
        case .unauthorized:
            return String(localized: "Il Worker ha rifiutato il token: aggiornalo dalle Impostazioni (Cmd+,).")
        case .forbidden:
            return String(localized: "Il Worker ha rifiutato la richiesta autenticata.")
        case .rateLimited:
            return String(localized: "Ricerche del mese esaurite sul Worker.")
        case .serverUnavailable:
            return String(localized: "Il Worker non è raggiungibile in questo momento.")
        case .httpError(let code):
            return String(localized: "Errore HTTP: \(code)")
        case .decodingError:
            return String(localized: "Errore nella decodifica dei dati")
        }
    }
}

enum WorkerConfigurationError: LocalizedError, Equatable {
    case invalidURL
    case missingToken
    case unreachable
    case invalidToken
    case incompatibleContract
    case secureStorage

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Inserisci un URL HTTPS valido del tuo Worker, senza query o frammenti.")
        case .missingToken:
            return String(localized: "Inserisci il CLIENT_AUTH_TOKEN configurato nel tuo Worker.")
        case .unreachable:
            return String(localized: "Il Worker non è raggiungibile. Controlla URL, rete e deploy, poi riprova.")
        case .invalidToken:
            return String(localized: "Il Worker ha rifiutato il token. Controlla che corrisponda a CLIENT_AUTH_TOKEN.")
        case .incompatibleContract:
            return String(localized: "Il server risponde, ma non espone il contratto Worker richiesto da questa app.")
        case .secureStorage:
            return String(localized: "Il token è valido, ma non è stato possibile salvarlo nel Portachiavi.")
        }
    }
}
