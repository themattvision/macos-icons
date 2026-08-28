//
//  IconApplier.swift
//  MacOS Icons
//
//  Created by Matteo Zampieri on 24/08/26.
//
//  Servizio che applica davvero una IconItem scaricata da macosicons.com
//  all'app che l'utente aggancia (trascinandola, sceglendola dal pannello di
//  sistema o dall'elenco delle app installate). NSWorkspace.setIcon scrive il
//  file "Icon\r" dentro il bundle: serve solo il permesso di scrittura POSIX
//  su quel bundle, e per questo l'App Sandbox e' stata disattivata (verificato
//  il 24/08/2026: dentro la sandbox setIcon torna false su qualunque app non
//  passata da pannello o trascinamento, quindi l'elenco interno non avrebbe
//  potuto applicare niente).
//  Sulle app di sistema (volume sigillato) o di root resta comunque impossibile,
//  e per quello isWritable esiste: serve a dare un messaggio onesto PRIMA di
//  tentare, non solo a gestire il fallimento dopo.
//  Le chiamate a start/stopAccessingSecurityScopedResource restano perche' sono
//  innocue fuori dalla sandbox e tornerebbero necessarie se un domani si
//  reintroducesse (per una distribuzione su App Store).
//

import SwiftUI
import AppKit
import OSLog

// MARK: - Bersaglio: l'app .app agganciata per ricevere una nuova icona

/// Rappresenta l'app che l'utente ha trascinato nella finestra. E' un valore
/// (struct), non un riferimento: ogni volta che l'icona cambia se ne ricrea
/// una copia con lo stesso url/name ma currentIcon aggiornato, cosi' la UI
/// osserva un cambiamento vero tramite Equatable/Published invece di dover
/// invalidare a mano una NSImage mutabile.
struct AppTarget: Identifiable, Equatable {
    var id: URL { url }
    let url: URL             // url del bundle .app
    let name: String         // nome senza estensione .app
    let currentIcon: NSImage // icona attualmente mostrata dal Finder
    let isWritable: Bool     // false per app di sistema / root:wheel
}

// MARK: - Servizio che applica/ripristina l'icona sul bersaglio agganciato

@MainActor
final class IconApplier: ObservableObject {

    /// Le fasi dell'operazione. E' un enum e non un semplice bool "loading"
    /// perche' la UI deve distinguere in corso / appena riuscito / appena
    /// ripristinato / fallito con un messaggio specifico, esattamente come
    /// il pattern DownloadPhase gia' usato in IconDetailView.
    enum Phase: Equatable {
        case idle
        case applying
        case applied
        case restored
        case failed(String)   // messaggio gia' pronto per l'utente, in italiano
    }

    @Published private(set) var target: AppTarget?
    @Published private(set) var phase: Phase = .idle

    /// true quando c'e' un bersaglio scrivibile e nessuna operazione in corso:
    /// e' la guardia che la UI usa per abilitare/disabilitare il bottone "Applica".
    var canApply: Bool {
        guard let target else { return false }
        return target.isWritable && phase != .applying
    }

    /// Bersagli a cui questa sessione ha applicato un'icona e che quindi hanno
    /// davvero qualcosa da ripristinare. Serve perche' la sola `phase` non basta:
    /// e' transitoria (torna a .idle dopo la vetrina di conferma) e una UI che ci
    /// si appoggiasse farebbe sparire il ripristino dopo un secondo e mezzo.
    @Published private(set) var customizedTargets: Set<URL> = []

    /// true quando il bersaglio agganciato ha un'icona applicata da questa sessione
    /// e la si puo' togliere adesso: e' la guardia del bottone "Ripristina".
    var canRestoreCurrentTarget: Bool {
        guard let target else { return false }
        return target.isWritable && phase != .applying && customizedTargets.contains(target.url)
    }

    private let log = Logger(subsystem: "com.matteozampieri.macosicons", category: "icon-apply")


    /// Durata della vetrina di conferma ("Applicata" / "Ripristinata") prima
    /// di tornare a riposo: stessi 1.6s usati da IconDetailView per "Salvato",
    /// cosi' il feedback delle due operazioni di icona ha lo stesso ritmo.
    private static let confirmationDisplayDuration: Duration = .seconds(1.6)

    /// L'url a cui e' aperto un accesso security-scoped, se presente. Va tenuto
    /// a parte da target.url perche' deve sopravvivere esattamente all'accesso
    /// che ha aperto: un solo start per un solo stop, mai due start in parallelo.
    private var securityScopedURL: URL?

    // MARK: - Aggancio del bersaglio

    /// Aggancia l'app trascinata come bersaglio. Ritorna false (e mette phase
    /// = .failed) se l'url non e' un .app, senza toccare l'accesso security-scoped
    /// precedente: un trascinamento non valido non deve sganciare un bersaglio
    /// valido gia' agganciato.
    @discardableResult
    func attach(url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app" else {
            phase = .failed(String(localized: "Quello non e' un'app. Trascina un'applicazione, per esempio una da Applicazioni."))
            return false
        }

        // Mai due accessi security-scoped aperti insieme: se c'era gia' un
        // bersaglio agganciato, chiudiamo il suo accesso prima di aprirne uno nuovo.
        stopAccessingCurrentScopeIfNeeded()

        // L'accesso va tenuto aperto per tutta la durata dell'aggancio (serve
        // sia per leggere l'icona ora sia per scriverla con apply() piu' tardi),
        // quindi si registra l'url a cui si e' chiesto l'accesso solo se e' riuscito.
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        } else {
            // Non blocchiamo l'aggancio: puo' capitare che l'url non richieda
            // davvero uno scope (es. gia' dentro un ambito accessibile), in quel
            // caso il false non e' un errore fatale, e le operazioni successive
            // (che passano comunque dal Finder/FileManager) diranno la verita'.
            log.notice("startAccessingSecurityScopedResource ha restituito false per \(url.path, privacy: .public)")
        }

        let name = url.deletingPathExtension().lastPathComponent
        let currentIcon = NSWorkspace.shared.icon(forFile: url.path)
        let isWritable = FileManager.default.isWritableFile(atPath: url.path)

        log.info("Bersaglio agganciato: \(name, privacy: .public) scrivibile=\(isWritable)")
        target = AppTarget(url: url, name: name, currentIcon: currentIcon, isWritable: isWritable)
        // Un nuovo aggancio riparte sempre da capo: eventuali fallimenti/conferme
        // del bersaglio precedente non hanno senso su quello nuovo.
        phase = .idle
        return true
    }

    /// Sgancia il bersaglio corrente e chiude l'accesso security-scoped aperto
    /// da attach(url:). Va chiamato sia quando l'utente rimuove esplicitamente
    /// il bersaglio, sia (internamente) prima di agganciarne uno diverso.
    func detach() {
        stopAccessingCurrentScopeIfNeeded()
        target = nil
        phase = .idle
    }

    /// Chiude l'accesso security-scoped aperto, se ce n'e' uno: centralizza la
    /// regola "mai uno stop senza uno start corrispondente" in un solo punto.
    private func stopAccessingCurrentScopeIfNeeded() {
        guard let securityScopedURL else { return }
        securityScopedURL.stopAccessingSecurityScopedResource()
        self.securityScopedURL = nil
    }

    // MARK: - Applicazione dell'icona scelta

    /// Scarica l'icona scelta dall'utente e la applica al bersaglio agganciato.
    func apply(icon: IconItem) async {
        guard let target else {
            // Non dovrebbe succedere se la UI rispetta canApply, ma un messaggio
            // onesto costa poco ed evita un fallimento silenzioso.
            phase = .failed(String(localized: "Trascina prima un'app su cui applicare l'icona."))
            return
        }

        phase = .applying

        // L'icns e' il formato giusto per un'icona d'app (multi-risoluzione,
        // e' quello che il Finder si aspetta dentro il bundle): si prova quello
        // per primo, e solo se scaricarlo o decodificarlo fallisce si scende
        // sul PNG bassa risoluzione come paracadute, meglio di niente.
        var image = await downloadImage(from: target.name, urlString: icon.icnsUrl)
        if image == nil {
            image = await downloadImage(from: target.name, urlString: icon.lowResPngUrl)
        }

        guard let image else {
            phase = .failed(String(localized: "Non sono riuscito a scaricare questa icona. Controlla la connessione e riprova."))
            return
        }

        // Il download ha sospeso: nel frattempo l'utente puo' aver trascinato
        // un'altra app o sganciato il bersaglio. Si riparte dal bersaglio ATTUALE
        // e si abbandona in silenzio se non e' piu' quello per cui era partita
        // l'operazione: scrivere l'icona su un'app che l'utente non sta piu'
        // guardando sarebbe una modifica a sorpresa su un file suo.
        guard let currentTarget = self.target, currentTarget.url == target.url else {
            phase = .idle
            return
        }

        applyImageToTarget(image, target: currentTarget, successPhase: .applied)
    }

    // MARK: - Ripristino dell'icona originale

    /// Rimette l'icona originale dell'app, cioe' rimuove la personalizzazione
    /// (setIcon con immagine nil e' il modo documentato di NSWorkspace per farlo).
    func restoreOriginalIcon() async {
        guard let target else {
            phase = .failed(String(localized: "Trascina prima un'app di cui ripristinare l'icona."))
            return
        }

        phase = .applying
        applyImageToTarget(nil, target: target, successPhase: .restored)
    }

    // MARK: - Nucleo comune ad apply e restoreOriginalIcon

    /// setIcon(nil, ...) ripristina l'originale, setIcon(image, ...) applica
    /// una nuova icona: stessa chiamata NSWorkspace, stessa gestione di esito
    /// e stesso ritorno a .idle, cambia solo l'immagine e la fase di successo.
    private func applyImageToTarget(_ image: NSImage?, target: AppTarget, successPhase: Phase) {
        let succeeded = NSWorkspace.shared.setIcon(image, forFile: target.url.path, options: [])

        guard succeeded else {
            phase = .failed(failureMessage(for: target))
            return
        }

        // Il Finder tiene una cache delle icone: rileggerla subito dopo setIcon
        // e' cio' che IconDetailView non deve fare (li' e' un semplice download),
        // ma qui serve per rispecchiare nella UI l'icona appena applicata senza
        // dover ricreare il bersaglio da capo (i campi di AppTarget sono let).
        let refreshedIcon = NSWorkspace.shared.icon(forFile: target.url.path)
        self.target = AppTarget(
            url: target.url,
            name: target.name,
            currentIcon: refreshedIcon,
            isWritable: target.isWritable
        )

        // Memoria di cosa e' stato personalizzato, indipendente dalla vetrina di
        // conferma: applicare aggiunge il bersaglio, ripristinare lo toglie perche'
        // da quel momento non c'e' piu' niente da riportare indietro.
        switch successPhase {
        case .applied:  customizedTargets.insert(target.url)
        case .restored: customizedTargets.remove(target.url)
        default:        break
        }

        phase = successPhase
        scheduleReturnToIdle(from: successPhase)
    }

    /// Messaggio in italiano semplice, con le tre cose (cosa/perche'/cosa fare),
    /// diverso a seconda che il problema sia "app non scrivibile" (caso comune:
    /// app di sistema o installata da root) oppure un fallimento generico di setIcon.
    private func failureMessage(for target: AppTarget) -> String {
        if !target.isWritable {
            return String(localized: "macOS non lascia modificare questa app perche' e' un'app di sistema o non ti appartiene. Copiala nella tua cartella Applicazioni personale e riprova da li'.")
        }
        return String(localized: "Non sono riuscito a cambiare l'icona di \"\(target.name)\". Riprova; se il problema continua, prova a chiudere l'app prima di riapplicare l'icona.")
    }

    /// Dopo la conferma (.applied o .restored) si torna a riposo da soli, con lo
    /// stesso controllo "solo se la fase non e' gia' cambiata" usato da
    /// IconDetailView.scheduleReturnToIdle: se nel frattempo l'utente ha lanciato
    /// un'altra operazione, questo timer non deve calpestarne l'esito.
    private func scheduleReturnToIdle(from confirmedPhase: Phase) {
        Task {
            try? await Task.sleep(for: Self.confirmationDisplayDuration)
            if phase == confirmedPhase {
                phase = .idle
            }
        }
    }

    // MARK: - Download

    /// Scarica un'immagine da un URL testuale, senza bloccare la UI (siamo
    /// @MainActor ma URLSession.shared.data(from:) sospende invece di bloccare).
    /// Ritorna nil per qualunque motivo di fallimento (url non valido, rete,
    /// dati non decodificabili come immagine): il chiamante decide il da farsi,
    /// qui si logga solo il dettaglio tecnico per la diagnosi.
    private func downloadImage(from targetName: String, urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString) else {
            log.error("URL icona non valido per \(targetName, privacy: .public): \(urlString, privacy: .public)")
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else {
                log.error("Dati scaricati non decodificabili come immagine per \(targetName, privacy: .public) da \(urlString, privacy: .public)")
                return nil
            }
            return image
        } catch {
            log.error("Download icona fallito per \(targetName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
