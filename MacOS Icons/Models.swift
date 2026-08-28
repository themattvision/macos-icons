//
//  Models.swift
//  MacOS Icons
//
//  Created by Matteo Zampieri on 14/09/25.
//

import Foundation

// MARK: - Modelli per la risposta dell'API di ricerca icone

/// Struttura principale della risposta dell'API di ricerca
struct IconSearchResponse: Codable {
    let hits: [IconItem]
    let query: String
    let processingTimeMs: Int
    let hitsPerPage: Int
    let page: Int
    let totalPages: Int
    let totalHits: Int
}

/// Elemento icona restituito dall'API
struct IconItem: Codable, Identifiable, Hashable {
    let id = UUID() // ID locale per SwiftUI
    let objectID: String
    let appName: String
    let timeStamp: TimeStampValue
    let icnsUrl: String
    let iOSUrl: String?
    let lowResPngUrl: String
    let category: String?
    let downloads: Int?
    let credit: String?
    let uploadedBy: String?
    let usersName: String?

    /// Converte il timestamp in Date
    var date: Date {
        switch timeStamp {
        case .string(let stringValue):
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: stringValue) ?? Date()
        case .number(let numberValue):
            return Date(timeIntervalSince1970: numberValue / 1000) // Converti da millisecondi
        }
    }

    /// Chiavi per la decodifica JSON
    enum CodingKeys: String, CodingKey {
        case objectID
        case appName
        case timeStamp
        case icnsUrl
        case iOSUrl
        case lowResPngUrl
        case category
        case downloads
        case credit
        case uploadedBy
        case usersName
    }

    /// Inizializzatore personalizzato per gestire campi opzionali
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        objectID = try container.decode(String.self, forKey: .objectID)
        appName = try container.decode(String.self, forKey: .appName)
        timeStamp = try container.decode(TimeStampValue.self, forKey: .timeStamp)
        icnsUrl = try container.decode(String.self, forKey: .icnsUrl)
        iOSUrl = try container.decodeIfPresent(String.self, forKey: .iOSUrl)
        lowResPngUrl = try container.decode(String.self, forKey: .lowResPngUrl)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        downloads = try container.decodeIfPresent(Int.self, forKey: .downloads)
        credit = try container.decodeIfPresent(String.self, forKey: .credit)
        uploadedBy = try container.decodeIfPresent(String.self, forKey: .uploadedBy)
        usersName = try container.decodeIfPresent(String.self, forKey: .usersName)
    }

    /// Implementazione di Hashable usando objectID come identificatore unico
    func hash(into hasher: inout Hasher) {
        hasher.combine(objectID)
    }

    /// Implementazione di Equatable per Hashable
    static func == (lhs: IconItem, rhs: IconItem) -> Bool {
        return lhs.objectID == rhs.objectID
    }
}

/// Enum per gestire timestamp che possono essere stringhe o numeri
enum TimeStampValue: Codable {
    case string(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let numberValue = try? container.decode(Double.self) {
            self = .number(numberValue)
        } else {
            throw DecodingError.typeMismatch(TimeStampValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Number for timestamp"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let stringValue):
            try container.encode(stringValue)
        case .number(let numberValue):
            try container.encode(numberValue)
        }
    }
}

// MARK: - Modelli per la richiesta API

/// Opzioni di ricerca per personalizzare la query
struct SearchOptions: Codable {
    let hitsPerPage: Int
    let page: Int
    let offset: Int
    let filters: [String]
    let sort: [String]

    init(hitsPerPage: Int = 20, page: Int = 1, offset: Int = 0, filters: [String] = [], sort: [String] = []) {
        self.hitsPerPage = hitsPerPage
        self.page = page
        self.offset = offset
        self.filters = filters
        self.sort = sort
    }
}

/// Corpo della richiesta per l'API di ricerca
struct SearchRequest: Codable {
    let query: String
    let searchOptions: SearchOptions?

    init(query: String, searchOptions: SearchOptions? = nil) {
        self.query = query
        self.searchOptions = searchOptions
    }
}

// MARK: - Errore pronto da mostrare

/// Un errore gia' tradotto per l'utente: davanti a lui non deve mai finire un codice HTTP
/// o il testo grezzo di URLSession. Ogni caso porta le tre cose che servono davvero:
/// cosa e' successo (titolo), perche' (messaggio) e cosa fare adesso (azione).
struct SearchFailure: Equatable {
    /// Cosa succede premendo il bottone dell'errore.
    enum Action: Equatable {
        /// Apre un indirizzo esterno, per esempio la dashboard di macOSicons.
        case openURL(URL)
        /// Apre il pannello Impostazioni dell'app, dove si incolla la chiave.
        case openSettings
    }

    /// Colore semantico del simbolo. Sta qui come enum e non come `Color` perche' questo
    /// file descrive i dati e non deve dipendere da SwiftUI: la vista lo traduce in colore.
    enum Tint: Equatable {
        case warning
        case danger
        case neutral
    }

    let symbol: String
    let tint: Tint
    let title: String
    let message: String
    let actionTitle: String?
    let action: Action?
    /// True solo quando ritentare ha davvero senso: su una quota mensile esaurita
    /// un bottone "Riprova" sarebbe una presa in giro, il risultato non cambia.
    let isRetryable: Bool

    init(
        symbol: String,
        tint: Tint = .warning,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: Action? = nil,
        isRetryable: Bool = false
    ) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.isRetryable = isRetryable
    }
}

// MARK: - Enum per gestire gli stati dell'app

/// Stati possibili durante la ricerca
enum SearchState {
    case idle
    case loading
    case success([IconItem])
    case error(SearchFailure)
}
