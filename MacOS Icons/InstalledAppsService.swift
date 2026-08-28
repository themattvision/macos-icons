//
//  InstalledAppsService.swift
//  MacOS Icons
//
//  Created by Matteo Zampieri on 24/08/26.
//
//  Enumera le app installate sul Mac per mostrarle in una griglia dentro l'app,
//  come alternativa al trascinamento manuale o al pannello Apri di sistema.
//  Puo' leggere le cartelle e (piu' avanti) scrivere le icone senza alcun
//  accesso security-scoped perche' l'App Sandbox e' stata disattivata apposta
//  per questa funzione (verificato oggi con un bundle di prova): niente
//  NSOpenPanel, niente bookmark, si scandagliano le cartelle standard
//  direttamente con FileManager.
//

import SwiftUI
import AppKit
import OSLog

// MARK: - Modello

/// Una app installata sul Mac, pronta da mostrare in una griglia.
struct InstalledApp: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String          // nome senza .app
    let icon: NSImage         // icona corrente (gia' pronta per la UI)
    let isWritable: Bool      // false per le app di sistema (volume sigillato) o di root
    let isSystem: Bool        // true se sta in /System/Applications
}

// MARK: - Servizio

/// Carica l'elenco delle app installate e lo rende filtrabile per la sheet di scelta.
@MainActor
final class InstalledAppsService: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoading = false

    private let log = Logger(subsystem: "com.matteozampieri.macosicons", category: "installed-apps")

    // MARK: - Caricamento

    /// Carica (o ricarica) l'elenco. Idempotente: se e' gia' popolato e non si
    /// forza, non rifa' il lavoro, cosi' riaprire la sheet piu' volte non ripete
    /// una scansione filesystem + costruzione di decine di NSImage ogni volta.
    func load(force: Bool = false) async {
        guard force || apps.isEmpty else { return }

        isLoading = true

        // Copiato in locale PRIMA di entrare in Task.detached: il blocco gira
        // fuori dall'actor principale e non deve toccare self (che e' @MainActor),
        // solo Logger e' un value type Sendable e si puo' catturare cosi'.
        let log = self.log

        // L'enumerazione delle cartelle e la creazione delle NSImage sono lavoro
        // sincrono e potenzialmente lento (decine di bundle, un accesso disco
        // ciascuno): va fatto fuori dal main thread per non bloccare la finestra
        // per un secondo. Si pubblica il risultato in UN colpo solo alla fine,
        // mai a meta' costruzione: altrimenti la griglia "ballerebbe" man mano
        // che arrivano le icone invece di apparire gia' pronta.
        let scannedApps = await Task.detached(priority: .userInitiated) {
            Self.scanInstalledApps(log: log)
        }.value

        apps = scannedApps
        isLoading = false
    }

    /// Filtro per il campo di ricerca della sheet: query vuota mostra tutte le
    /// app, altrimenti confronto case/accent-insensitive sul nome (cosi' "eta"
    /// trova anche "Età").
    func filtered(by query: String) -> [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return apps }

        return apps.filter { app in
            app.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    // MARK: - Scansione (fuori dal main thread)

    /// Le cartelle da scandagliare, in questo ordine di priorita': prima quelle
    /// dell'utente (le piu' rilevanti, e le uniche davvero scrivibili), poi
    /// quelle di sistema. L'ordine qui non e' l'ordine mostrato in griglia (che
    /// e' alfabetico, vedi lo sorted finale) ma decide comunque quale voce
    /// "vince" nella deduplica se lo stesso path fosse raggiungibile due volte.
    private nonisolated static func scanRoots() -> [URL] {
        var roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities")
        ]

        // ~/Applications esiste solo per alcuni utenti: si aggiunge solo se c'e'
        // davvero, altrimenti sarebbe solo un errore da ignorare in piu'.
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        if FileManager.default.fileExists(atPath: userApplications.path) {
            roots.append(userApplications)
        }

        roots.append(URL(fileURLWithPath: "/System/Applications"))
        roots.append(URL(fileURLWithPath: "/System/Applications/Utilities"))
        return roots
    }

    /// Nucleo della scansione: gira su un thread in background (static + nonisolated
    /// via Task.detached), quindi non puo' toccare self ne' alcuno stato @MainActor.
    /// FileManager e NSWorkspace.icon(forFile:) sono utilizzabili qui: sono letture
    /// pure, non serve il main thread per costruire una NSImage da un path.
    private nonisolated static func scanInstalledApps(log: Logger) -> [InstalledApp] {
        let fileManager = FileManager.default

        // Deduplica per path assoluto risolto: la stessa app puo' comparire due
        // volte se raggiunta da cartelle diverse (es. tramite un symlink). Il Set
        // previene il doppione, l'ordine di scanRoots() decide quale copia arriva
        // per prima (e quindi "vince", visto che le successive vengono scartate).
        var seenPaths = Set<String>()
        var results: [InstalledApp] = []

        for root in scanRoots() {
            let (apps, subfolders) = listLevel(of: root, fileManager: fileManager)
            for appURL in apps {
                appendIfNew(appURL, fileManager: fileManager, seenPaths: &seenPaths, results: &results)
            }

            // Solo /Applications ha davvero il pattern "app dentro una sottocartella
            // del vendor" (es. "/Applications/Adobe.../X.app"): si scende di UN solo
            // livello dentro le sue sottocartelle, mai piu' a fondo, altrimenti si
            // finirebbe per scandagliare interi bundle .app (che sono cartelle) e la
            // scansione richiederebbe secondi invece di essere quasi istantanea.
            guard root.path == "/Applications" else { continue }
            for subfolder in subfolders {
                let (nestedApps, _) = listLevel(of: subfolder, fileManager: fileManager)
                for appURL in nestedApps {
                    appendIfNew(appURL, fileManager: fileManager, seenPaths: &seenPaths, results: &results)
                }
            }
        }

        // Alfabetico per nome, ma con le app non di sistema sempre prima: chi usa
        // l'app cerca quasi sempre una app sua, quelle di Apple sono "rumore" utile
        // solo in fondo alla lista.
        return results.sorted { lhs, rhs in
            if lhs.isSystem != rhs.isSystem {
                return !lhs.isSystem
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Legge il primo livello di una cartella e lo divide in bundle .app e
    /// sottocartelle non-.app (le uniche che vale la pena esplorare un livello
    /// piu' in profondita', vedi scanInstalledApps). Non lancia mai: una cartella
    /// non leggibile (permessi, non esiste) restituisce due elenchi vuoti e viene
    /// saltata in silenzio, come richiesto (nessun errore mostrato all'utente).
    private nonisolated static func listLevel(of directory: URL, fileManager: FileManager) -> (apps: [URL], subfolders: [URL]) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [])
        }

        var apps: [URL] = []
        var subfolders: [URL] = []

        for entry in entries {
            if entry.pathExtension.lowercased() == "app" {
                apps.append(entry)
                continue
            }

            // Una sottocartella "candidata" e' una directory che non e' essa stessa
            // un bundle .app (gia' escluso sopra): tipicamente le cartelle per
            // vendor tipo "Adobe" o "Microsoft" dentro /Applications.
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                subfolders.append(entry)
            }
        }

        return (apps, subfolders)
    }

    /// Costruisce una InstalledApp da un bundle .app e la aggiunge a results se il
    /// suo path risolto non e' gia' stato visto. Centralizza qui la deduplica, la
    /// lettura di scrivibilita'/sistema e la costruzione dell'icona ridimensionata,
    /// cosi' i due punti di scansione (primo livello e livello dentro le sottocartelle
    /// di /Applications) restano identici e non rischiano di divergere.
    private nonisolated static func appendIfNew(
        _ appURL: URL,
        fileManager: FileManager,
        seenPaths: inout Set<String>,
        results: inout [InstalledApp]
    ) {
        let resolvedPath = appURL.resolvingSymlinksInPath().path
        guard !seenPaths.contains(resolvedPath) else { return }
        seenPaths.insert(resolvedPath)

        let name = appURL.deletingPathExtension().lastPathComponent
        let isWritable = fileManager.isWritableFile(atPath: appURL.path)
        let isSystem = appURL.path.hasPrefix("/System/")

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        // La griglia mostra icone piccole: senza questo resize NSImage si porta
        // dietro le rappresentazioni piu' grandi disponibili nel bundle (anche
        // 512px+), che pesano inutilmente su memoria e layout di decine di celle.
        icon.size = NSSize(width: 64, height: 64)

        results.append(InstalledApp(url: appURL, name: name, icon: icon, isWritable: isWritable, isSystem: isSystem))
    }
}
