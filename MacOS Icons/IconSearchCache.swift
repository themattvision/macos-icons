//
//  IconSearchCache.swift
//  MacOS Icons
//
//  L'API gratuita di macosicons.com concede solo 100 query al mese per API key,
//  e la key dell'utente le esaurisce facilmente (risposta 429). Questa cache su
//  disco riusa le risposte di ricerca gia' ottenute per non consumare altre query
//  quando la stessa combinazione (query, ordinamento, pagina) viene richiesta di nuovo.
//

import Foundation
import CryptoKit
import OSLog

/// Cache persistente delle risposte di ricerca icone, indicizzata per (query, sort, page).
/// E' un actor (non @MainActor) perche' fa I/O su disco: l'isolamento suo, separato dal
/// main actor dei servizi SwiftUI, evita di bloccare la UI durante lettura/scrittura file.
actor IconSearchCache {
    static let shared = IconSearchCache()

    /// Risposta cachata con la sua eta', indipendentemente dalla freschezza.
    struct CachedResponse {
        let response: IconSearchResponse
        let storedAt: Date
        var age: TimeInterval { Date().timeIntervalSince(storedAt) }
    }

    /// Formato su disco di una entry: risposta + timestamp di quando e' stata salvata.
    private struct DiskEntry: Codable {
        let storedAt: Double
        let response: IconSearchResponse
    }

    private let log = Logger(subsystem: "com.matteozampieri.macosicons", category: "cache")

    /// Prefisso di versione nella stringa hashata: cambiarlo invalida tutta la cache esistente
    /// senza dover toccare i file gia' su disco (semplicemente non matchano piu' nessuna chiave nuova).
    private let cacheVersion = "v1"

    /// Tetto alla cache: oltre questa soglia si eliminano le entry piu' vecchie (per data di modifica).
    private let maxEntries = 300
    private let maxBytes = 20 * 1024 * 1024 // 20 MB

    /// Primo livello di cache, in RAM: ricerche ripetute nella stessa sessione non toccano il disco.
    /// Tenuto coerente con store/clear.
    private var memoryCache: [String: CachedResponse] = [:]

    /// Cartella su disco dedicata alla cache, risolta pigramente al primo utilizzo.
    /// Se la creazione fallisce (permessi, sandbox particolare, disco pieno) resta nil e la
    /// cache degrada a no-op silenziosa: niente crash, semplicemente non persiste su disco.
    private lazy var cacheDirectory: URL? = {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            log.error("Impossibile risolvere la cartella Application Support")
            return nil
        }

        let directory = base
            .appendingPathComponent("MacOS Icons", isDirectory: true)
            .appendingPathComponent("SearchCache", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            log.error("Impossibile creare la cartella della cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    private init() {}

    // MARK: - Lettura

    /// Restituisce la entry cachata se esiste, di qualunque eta'. Serve al chiamante per
    /// sopravvivere a un errore di rete (es. 429 per limite mensile esaurito) servendo dati vecchi
    /// piuttosto che niente.
    func entry(query: String, sort: [String], page: Int) -> CachedResponse? {
        let key = cacheKey(query: query, sort: sort, page: page)

        if let cached = memoryCache[key] {
            return cached
        }

        guard let cached = readFromDisk(key: key) else {
            return nil
        }

        // Popola il livello in RAM cosi' le letture successive nella stessa sessione sono immediate.
        memoryCache[key] = cached
        return cached
    }

    /// Restituisce la risposta solo se piu' giovane di maxAge, altrimenti nil.
    func fresh(query: String, sort: [String], page: Int, maxAge: TimeInterval) -> IconSearchResponse? {
        guard let cached = entry(query: query, sort: sort, page: page), cached.age <= maxAge else {
            return nil
        }
        return cached.response
    }

    // MARK: - Scrittura

    /// Salva (o sovrascrive) la risposta per quella combinazione, sia in RAM sia su disco.
    func store(_ response: IconSearchResponse, query: String, sort: [String], page: Int) {
        let key = cacheKey(query: query, sort: sort, page: page)
        let storedAt = Date()
        memoryCache[key] = CachedResponse(response: response, storedAt: storedAt)

        guard let directory = cacheDirectory else {
            // Nessuna cartella disponibile: la cache resta solo in memoria per questa sessione.
            return
        }

        let fileURL = directory.appendingPathComponent(key).appendingPathExtension("json")
        let diskEntry = DiskEntry(storedAt: storedAt.timeIntervalSince1970, response: response)

        do {
            let data = try JSONEncoder().encode(diskEntry)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Scrittura cache fallita: \(error.localizedDescription, privacy: .public)")
            return
        }

        // La potatura ha un costo (enumerare la cartella): la si fa solo quando la cache in RAM
        // supera la soglia, non ad ogni singola scrittura, cosi' il costo resta ammortizzato.
        if memoryCache.count > maxEntries {
            pruneIfNeeded(directory: directory)
        }
    }

    /// Svuota tutta la cache, in RAM e su disco. Usata da un comando nelle impostazioni.
    func clear() {
        memoryCache.removeAll()

        guard let directory = cacheDirectory else { return }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            log.error("Svuotamento cache fallito: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Numero di entry attualmente su disco e spazio occupato in byte, per mostrarlo nelle impostazioni.
    func statistics() -> (entries: Int, bytes: Int) {
        guard let directory = cacheDirectory else { return (0, 0) }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return (0, 0)
        }

        var totalBytes = 0
        for file in files {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalBytes += size
            }
        }
        return (files.count, totalBytes)
    }

    // MARK: - Helpers privati

    /// Chiave di cache stabile: hash SHA-256 esadecimale di versione + query normalizzata + sort + page.
    /// La query e' normalizzata (trim + lowercase) perche' varianti di maiuscole/spazi sono la stessa
    /// ricerca lato utente. Il sort resta un array ordinato unito con virgola: l'ordine delle regole
    /// e' semanticamente rilevante per l'API, quindi non va riordinato.
    private func cacheKey(query: String, sort: [String], page: Int) -> String {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sortKey = sort.joined(separator: ",")
        let raw = "\(cacheVersion)|\(normalizedQuery)|\(sortKey)|\(page)"

        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Legge una entry dal disco. Qualunque errore di IO o di decodifica la tratta come assente:
    /// una entry corrotta viene anche rimossa dal disco, cosi' non continua a fallire ad ogni lettura.
    private func readFromDisk(key: String) -> CachedResponse? {
        guard let directory = cacheDirectory else { return nil }

        let fileURL = directory.appendingPathComponent(key).appendingPathExtension("json")

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        do {
            let diskEntry = try JSONDecoder().decode(DiskEntry.self, from: data)
            return CachedResponse(
                response: diskEntry.response,
                storedAt: Date(timeIntervalSince1970: diskEntry.storedAt)
            )
        } catch {
            log.error("Entry di cache corrotta, la rimuovo: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    /// Elimina le entry piu' vecchie (per data di modifica del file) quando si supera il tetto
    /// di numero file o di spazio occupato. Chiamata solo occasionalmente da store, non ad ogni scrittura.
    private func pruneIfNeeded(directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return
        }

        struct FileInfo {
            let url: URL
            let modifiedAt: Date
            let size: Int
        }

        let infos: [FileInfo] = files.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return nil
            }
            return FileInfo(
                url: url,
                modifiedAt: values.contentModificationDate ?? .distantPast,
                size: values.fileSize ?? 0
            )
        }

        var totalBytes = infos.reduce(0) { $0 + $1.size }
        guard infos.count > maxEntries || totalBytes > maxBytes else { return }

        // Piu' vecchie per prime, cosi' si eliminano finche' si rientra sotto entrambi i tetti.
        let sortedByAge = infos.sorted { $0.modifiedAt < $1.modifiedAt }
        var remainingCount = infos.count

        for info in sortedByAge {
            guard remainingCount > maxEntries || totalBytes > maxBytes else { break }
            try? FileManager.default.removeItem(at: info.url)
            memoryCache.removeValue(forKey: info.url.deletingPathExtension().lastPathComponent)
            remainingCount -= 1
            totalBytes -= info.size
        }
    }
}
