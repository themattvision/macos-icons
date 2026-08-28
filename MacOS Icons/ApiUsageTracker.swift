//
//  ApiUsageTracker.swift
//  MacOS Icons
//
//  Il piano gratuito di macOSicons concede 100 query al mese per chiave API, ma l'app
//  non ha mai mostrato quante ne restassero: si bruciavano in silenzio finche' l'API
//  non rispondeva 429. Questo file tiene un conteggio locale, mese per mese, cosi'
//  l'utente vede il consumo prima di restare a secco.
//

import Foundation

@MainActor
final class ApiUsageTracker: ObservableObject {
    static let shared = ApiUsageTracker()

    /// Quota mensile del piano gratuito di macOSicons.
    static let freeMonthlyQuota = 100

    // Chiavi UserDefaults, prefissate per non collidere con "macosicons.apiKey" (la chiave API vera).
    private enum Keys {
        static let calls = "macosicons.usage.calls"
        static let period = "macosicons.usage.period"
        static let exhausted = "macosicons.usage.exhausted"
    }

    private let defaults: UserDefaults

    /// Chiamate di rete davvero partite nel mese corrente (le risposte servite dalla cache non contano).
    @Published private(set) var callsThisMonth: Int

    /// True quando l'API ha risposto 429 in questo mese: da lì in poi sappiamo che la quota è finita
    /// anche se il nostro conteggio locale dice di meno (per esempio l'utente ha usato la stessa chiave altrove).
    @Published private(set) var isQuotaExhausted: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Se il mese salvato non e' quello corrente, si riparte da zero: il conteggio e' per
        // mese di calendario, l'approssimazione piu' onesta che possiamo fare senza un endpoint
        // che dica davvero quante query restano.
        let currentPeriod = Self.currentPeriodKey()
        let savedPeriod = defaults.string(forKey: Keys.period)

        if savedPeriod == currentPeriod {
            callsThisMonth = defaults.integer(forKey: Keys.calls)
            isQuotaExhausted = defaults.bool(forKey: Keys.exhausted)
        } else {
            callsThisMonth = 0
            isQuotaExhausted = false
            defaults.set(currentPeriod, forKey: Keys.period)
            defaults.set(0, forKey: Keys.calls)
            defaults.set(false, forKey: Keys.exhausted)
        }
    }

    /// Registra una chiamata di rete effettivamente partita verso l'API.
    func recordCall() {
        rolloverIfNeeded()
        callsThisMonth += 1
        defaults.set(callsThisMonth, forKey: Keys.calls)
    }

    /// Segna la quota come esaurita, chiamata quando l'API risponde 429.
    func markQuotaExhausted() {
        rolloverIfNeeded()
        isQuotaExhausted = true
        defaults.set(true, forKey: Keys.exhausted)
    }

    /// Azzera lo stato quando la chiave API cambia: chiave nuova, quota nuova.
    func resetForNewKey() {
        callsThisMonth = 0
        isQuotaExhausted = false
        defaults.set(Self.currentPeriodKey(), forKey: Keys.period)
        defaults.set(0, forKey: Keys.calls)
        defaults.set(false, forKey: Keys.exhausted)
    }

    /// Ricerche stimate ancora disponibili nel mese, mai negativo. Zero se isQuotaExhausted.
    var remaining: Int {
        if isQuotaExhausted { return 0 }
        return max(0, Self.freeMonthlyQuota - callsThisMonth)
    }

    /// Data in cui la quota si azzera, cioè il primo giorno del mese successivo a mezzanotte.
    var quotaResetDate: Date {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        let startOfMonth = calendar.date(from: components) ?? now
        return calendar.date(byAdding: DateComponents(month: 1), to: startOfMonth) ?? now
    }

    /// Testo pronto per la UI, tipo "12 su 100 questo mese".
    var usageDescription: String {
        if isQuotaExhausted {
            return String(localized: "Quota mensile esaurita")
        }
        return String(localized: "\(callsThisMonth) su \(Self.freeMonthlyQuota) questo mese")
    }

    /// Se il mese salvato non e' piu' quello corrente, azzera contatore e flag prima di procedere.
    /// Chiamato da recordCall/markQuotaExhausted cosi' un nuovo mese riparte sempre pulito, anche
    /// se l'app e' rimasta aperta a cavallo del cambio mese senza mai essere riavviata.
    private func rolloverIfNeeded() {
        let currentPeriod = Self.currentPeriodKey()
        guard defaults.string(forKey: Keys.period) != currentPeriod else { return }

        callsThisMonth = 0
        isQuotaExhausted = false
        defaults.set(currentPeriod, forKey: Keys.period)
        defaults.set(0, forKey: Keys.calls)
        defaults.set(false, forKey: Keys.exhausted)
    }

    /// Chiave "YYYY-MM" del mese di calendario corrente, usata per capire quando azzerare.
    private static func currentPeriodKey() -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }
}
