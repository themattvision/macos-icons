//
//  IconSortOrder.swift
//  MacOS Icons
//
//  Criterio di ordinamento dei risultati. Tipo condiviso fra sidebar (che lo sceglie)
//  e servizio di ricerca (che lo traduce nel parametro `sort` dell'API).
//

import Foundation

enum IconSortOrder: String, CaseIterable, Identifiable, Hashable {
    /// Ordine restituito dal motore di ricerca, cioe' per pertinenza sulla query
    case relevance
    /// Piu' scaricate per prime
    case popular
    /// Caricate di recente per prime
    case recent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relevance: return String(localized: "Pertinenza")
        case .popular:   return String(localized: "Più popolari")
        case .recent:    return String(localized: "Più recenti")
        }
    }

    var systemImage: String {
        switch self {
        case .relevance: return "sparkle.magnifyingglass"
        case .popular:   return "arrow.down.circle"
        case .recent:    return "clock"
        }
    }

    /// Valore per il campo `sort` dell'API macosicons. Vuoto = ordine di pertinenza.
    var apiSortRules: [String] {
        switch self {
        case .relevance: return []
        case .popular:   return ["downloads:desc"]
        case .recent:    return ["timeStamp:desc"]
        }
    }
}
