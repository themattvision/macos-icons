//
//  MacOS Icons
//  Created by Matteo Zampieri on 14/09/25.
//
//  NOTA STORICA: la prima versione di "applica icona" puntava a farlo via
//  AppleScript verso il Finder, ed era davvero impossibile in sandbox: quella
//  strada richiede l'entitlement com.apple.security.automation.apple-events
//  (Apple Events verso un'altra app), e anche con quello il Finder non accetta
//  di riscrivere il bundle di un'app che il processo sandboxato non "possiede"
//  a occhi del sistema, semplicemente perche' il target era un path qualunque
//  scelto a mano (es. /Applications), non qualcosa che l'utente aveva appena
//  indicato in un gesto esplicito.
//
//  ORA FUNZIONA, con una strada diversa: quando l'utente TRASCINA o SCEGLIE
//  lui stesso l'app bersaglio, quel drop/quella scelta apre un accesso
//  security-scoped coperto dall'entitlement gia' presente in questo progetto,
//  com.apple.security.files.user-selected.read-write. Non serve automazione
//  ne' il Finder: NSWorkspace.shared.setIcon(_:forFile:) scrive direttamente
//  il file icona dentro il bundle, ed e' stato verificato che funziona su
//  un'app di proprieta' dell'utente proprio perche' il permesso arriva dal
//  gesto di selezione, non da uno scope di automazione. La logica vera e'
//  in IconApplier.swift (iniettato come @EnvironmentObject): questa vista
//  si limita a mostrare l'azione "Applica" quando c'e' un bersaglio agganciato.
//

import SwiftUI
import AppKit

// MARK: - Dettaglio di una singola icona (vista pensata per l'inspector laterale)

struct IconDetailView: View {
    let icon: IconItem

    @State private var selectedImageType: ImageType = .png
    @State private var errorMessage: String?

    /// Stato di hover dei bottoni, per il feedback di pressione leggero.
    @State private var isDownloadHovering = false
    @State private var isShareHovering = false
    @State private var isApplyHovering = false
    @State private var isRestoreHovering = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Iniettato da ContentView. Tiene lo stato del bersaglio trascinato (se c'e')
    /// e la fase dell'operazione: questa vista si limita a leggerlo per decidere
    /// se mostrare il blocco "Applica" e con quale faccia.
    @EnvironmentObject private var applier: IconApplier

    // MARK: - Stato del bottone Scarica

    /// Le tre facce del bottone: a riposo, mentre la rete lavora, appena confermato.
    /// E' un enum e non un semplice bool perche' il download ha davvero tre esiti
    /// distinti (annullato dall'utente, fallito, riuscito) e il bottone deve saperli
    /// distinguere senza stati impliciti.
    private enum DownloadPhase: Equatable {
        case idle
        case working
        case saved
    }

    @State private var downloadPhase: DownloadPhase = .idle

    // MARK: - Formato selezionabile

    enum ImageType: String, CaseIterable {
        case png = "PNG"
        case iOS = "iOS"
        case icns = "ICNS"

        /// URL del formato scelto, con fallback su PNG bassa risoluzione se manca l'iOS.
        func url(for icon: IconItem) -> String {
            switch self {
            case .png:
                return icon.lowResPngUrl
            case .iOS:
                return icon.iOSUrl ?? icon.lowResPngUrl
            case .icns:
                return icon.icnsUrl
            }
        }

        var fileExtension: String {
            self == .icns ? "icns" : "png"
        }
    }

    private var selectedURL: URL? {
        URL(string: selectedImageType.url(for: icon))
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header
                formatPicker
                infoSurface
                actions
            }
            .padding(Space.md)
        }
        // Fondo nero come il resto dell'app: senza questi due modificatori
        // insieme spunta il grigio di sistema dietro la ScrollView.
        .scrollContentBackground(.hidden)
        .background(Brand.background)
        .navigationTitle(icon.appName)
        .alert("Errore", isPresented: Binding(
            get: { errorMessage != nil },
            set: { isPresented in if !isPresented { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Intestazione: anteprima su piedistallo, nome, autore

    /// Lato dell'anteprima: l'icona resta a 128pt, dimensione richiesta per il dettaglio.
    private let previewSize: CGFloat = 128

    private var header: some View {
        VStack(spacing: Space.sm) {
            preview
            Text(icon.appName)
                .font(.appTitle)
                .foregroundStyle(Brand.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let author = icon.usersName ?? icon.credit {
                Text(author)
                    .font(.cellMeta)
                    .foregroundStyle(Brand.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Piedistallo dietro l'icona: un alone radiale tenue, come nelle schede del sito.
    private var preview: some View {
        let pedestalSide = previewSize + Space.xxl

        return ZStack {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Brand.accent.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: pedestalSide / 2
                    )
                )
                .frame(width: pedestalSide, height: pedestalSide)

            RetryableAsyncImage(
                url: selectedImageType.url(for: icon),
                width: previewSize,
                height: previewSize,
                cornerRadius: Radius.icon
            )
            .accentGlow(true, color: Brand.cyan)
        }
    }

    // MARK: - Selettore formato

    private var formatPicker: some View {
        Picker("Formato", selection: $selectedImageType) {
            ForEach(ImageType.allCases, id: \.self) { type in
                Text(verbatim: type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .tint(Brand.accent)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Informazioni

    /// Riga chiave/valore. Costruita solo con i campi che esistono davvero: niente "N/A".
    private struct InfoField {
        let label: String
        let value: String
        var monospaced: Bool = false
    }

    private var infoFields: [InfoField] {
        var fields: [InfoField] = [
            InfoField(label: String(localized: "Download"), value: (icon.downloads ?? 0).formatted(.number), monospaced: true)
        ]
        if let category = icon.category {
            fields.append(InfoField(label: String(localized: "Categoria"), value: category))
        }
        if let credit = icon.credit {
            fields.append(InfoField(label: String(localized: "Crediti"), value: credit))
        }
        if let uploadedBy = icon.uploadedBy {
            fields.append(InfoField(label: String(localized: "Caricato da"), value: uploadedBy))
        }
        fields.append(InfoField(label: String(localized: "Data"), value: icon.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale.autoupdatingCurrent))))
        return fields
    }

    private var infoSurface: some View {
        VStack(spacing: 0) {
            ForEach(Array(infoFields.enumerated()), id: \.offset) { index, field in
                InfoRow(title: field.label, value: field.value, monospaced: field.monospaced)
                if index < infoFields.count - 1 {
                    // Il Divider() di sistema e' invisibile su fondo nero: un rettangolo
                    // sottile riempito dello stroke del brand resta leggibile.
                    Rectangle()
                        .fill(Brand.stroke)
                        .frame(height: 1)
                }
            }
        }
        .padding(Space.md)
        .surface(radius: Radius.lg)
    }

    // MARK: - Azioni

    /// Due gruppi distinti: "applica al bersaglio agganciato" (se c'e' un'app trascinata)
    /// e "scarica/condividi" (sempre disponibile). Il gap fra i due e' Space.lg, piu'
    /// largo di Space.sm usato dentro ciascun gruppo, cosi' si legge lo stacco fra
    /// "azione sull'app" e "azione sul file" anche senza un divisore disegnato.
    private var actions: some View {
        VStack(spacing: Space.lg) {
            applySection

            VStack(spacing: Space.sm) {
                Button {
                    downloadSelectedFormat()
                } label: {
                    downloadLabel
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .controlSize(.large)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                .scaleEffect(isDownloadHovering ? 1.02 : 1.0)
                .onHover { hovering in
                    withAnimation(.ui) { isDownloadHovering = hovering }
                }
                // Disabilitato durante il fetch: evita il doppio click che lancerebbe
                // due download in parallelo sullo stesso formato.
                .disabled(downloadPhase == .working)

                // ShareLink e' il componente di sistema: niente NSSharingServicePicker manuale.
                if let shareURL = selectedURL {
                    ShareLink(item: shareURL) {
                        Text("Condividi")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.textMuted)
                    .controlSize(.large)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                    .scaleEffect(isShareHovering ? 1.02 : 1.0)
                    .onHover { hovering in
                        withAnimation(.ui) { isShareHovering = hovering }
                    }
                }
            }
        }
    }

    // MARK: - Applica l'icona all'app agganciata (drag & drop)

    /// Compare solo quando c'e' un bersaglio agganciato: e' la ragione stessa per cui
    /// l'utente ha trascinato un'app nella finestra, quindi qui e' l'azione primaria,
    /// sopra "Scarica". Un `if` che ritorna niente quando `applier.target` e' nil non
    /// lascia un vuoto ne' uno spacing residuo in `actions`.
    @ViewBuilder
    private var applySection: some View {
        if let target = applier.target {
            VStack(alignment: .leading, spacing: Space.sm) {
                targetContextRow(target)

                Button {
                    Task { await applier.apply(icon: icon) }
                } label: {
                    applyLabel(for: target)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .controlSize(.large)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                .scaleEffect(isApplyHovering ? 1.02 : 1.0)
                .onHover { hovering in
                    withAnimation(.ui) { isApplyHovering = hovering }
                }
                // canApply e' gia' false se il bersaglio non e' scrivibile o se
                // un'operazione (applica/ripristina) e' gia' in corso: un solo
                // punto di verita' condiviso con IconApplier, non lo si ridecide qui.
                .disabled(!applier.canApply)

                if !target.isWritable {
                    // Spiegazione ferma anche PRIMA di provare: l'utente capisce
                    // subito perche' il bottone e' disabilitato invece di scoprirlo
                    // solo dopo un tentativo fallito.
                    Text("macOS non lascia modificare quest'app perché è di sistema o non ti appartiene. Copiala nella cartella Applicazioni personale e riprova da lì.")
                        .font(.cellMeta)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if case .failed(let message) = applier.phase {
                    // Messaggio a parte dall'alert del download: quell'alert e' modale
                    // e interromperebbe la vista, mentre qui l'utente sta ancora
                    // guardando il bersaglio agganciato e deve poter correggere e
                    // riprovare sul posto, senza dover chiudere prima un dialogo.
                    Text(message)
                        .font(.cellMeta)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if applier.canRestoreCurrentTarget {
                    // Mostrato solo per un bersaglio a cui questa sessione ha davvero
                    // applicato un'icona, non ogni volta che c'e' un bersaglio scrivibile:
                    // l'app non sa se il bersaglio ha gia' un'icona personalizzata da altre
                    // vie (es. un "Get Info" manuale dell'utente), quindi offrire sempre
                    // "ripristina" prometterebbe un ripristino che potrebbe non corrispondere
                    // a niente. La condizione NON puo' essere `phase`: quella e' transitoria
                    // (torna a .idle dopo 1,6s di conferma) e faceva sparire questo bottone
                    // un secondo e mezzo dopo l'applicazione, prima che l'utente lo trovasse.
                    Button {
                        Task { await applier.restoreOriginalIcon() }
                    } label: {
                        Text("Ripristina icona originale")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.textMuted)
                    .controlSize(.large)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                    .scaleEffect(isRestoreHovering ? 1.02 : 1.0)
                    .onHover { hovering in
                        withAnimation(.ui) { isRestoreHovering = hovering }
                    }
                    .disabled(applier.phase == .applying)
                }
            }
        }
    }

    /// Riga sopra il bottone: l'icona ATTUALE del bersaglio (quella che sta per essere
    /// sostituita, non quella nuova gia' visibile nell'header) accanto al suo nome, cosi'
    /// l'utente vede a colpo d'occhio a chi sta per cambiare l'icona prima di confermare.
    private func targetContextRow(_ target: AppTarget) -> some View {
        HStack(spacing: Space.xs) {
            Image(nsImage: target.currentIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .continuousCorners(Radius.sm)

            (Text("Stai per cambiare l'icona di ")
                .foregroundStyle(Brand.textMuted)
             + Text(target.name)
                .foregroundStyle(Brand.text))
                .font(.cellMeta)

            Spacer(minLength: 0)
        }
    }

    /// Stesso pattern di `downloadLabel`: facce diverse a larghezza costante. `.restored`
    /// e `.failed` non hanno una faccia propria qui (il ripristino ha il suo bottone
    /// dedicato, il fallimento si legge nel messaggio sotto) e ricadono sul testo a riposo,
    /// cosi' dopo un ripristino o un errore il bottone torna pronto per un nuovo tentativo.
    private func applyLabel(for target: AppTarget) -> some View {
        Group {
            switch applier.phase {
            case .applying:
                ProgressView()
                    .controlSize(.small)
            case .applied:
                Label("Applicata", systemImage: "checkmark")
            default:
                Text("Applica a \(target.name)")
            }
        }
        .frame(maxWidth: .infinity)
        // Con Riduci movimento attivo il morph del simbolo sparisce ma la conferma
        // resta: solo una dissolvenza, niente trasformazioni.
        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
        .animation(.ui, value: applier.phase)
    }

    // MARK: - Faccia del bottone Scarica

    /// La faccia cambia in base alla fase, ma resta larga quanto il bottone: il
    /// .frame(maxWidth: .infinity) andava sul Text originale, ora va sul contenitore
    /// cosi' il bottone non cambia dimensione passando da "Scarica" alla spunta.
    private var downloadLabel: some View {
        Group {
            switch downloadPhase {
            case .idle:
                Text("Scarica")
            case .working:
                ProgressView()
                    .controlSize(.small)
            case .saved:
                Label("Salvato", systemImage: "checkmark")
            }
        }
        .frame(maxWidth: .infinity)
        // Con Riduci movimento attivo il morph del simbolo sparisce ma la conferma
        // resta: solo una dissolvenza, niente trasformazioni.
        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
        .animation(.ui, value: downloadPhase)
    }

    // MARK: - Download su disco

    /// Scarica il formato attualmente selezionato nel Picker e apre il pannello di salvataggio.
    @MainActor
    private func downloadSelectedFormat() {
        guard let imageURL = selectedURL else {
            errorMessage = String(localized: "L'URL di questo formato non e' valido.")
            return
        }
        let filename = "\(icon.appName).\(selectedImageType.fileExtension)"

        downloadPhase = .working

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                await MainActor.run {
                    presentSavePanel(data: data, filename: filename)
                }
            } catch {
                await MainActor.run {
                    errorMessage = String(localized: "Impossibile scaricare il file: \(error.localizedDescription)")
                    downloadPhase = .idle
                }
            }
        }
    }

    @MainActor
    private func presentSavePanel(data: Data, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = selectedImageType == .icns ? [.init("com.apple.icns")!] : [.png]

        guard panel.runModal() == .OK, let url = panel.url else {
            // Annullato dall'utente: non e' un errore ne' un successo, si torna
            // semplicemente a riposo senza mostrare "Salvato".
            downloadPhase = .idle
            return
        }

        do {
            try data.write(to: url)
            downloadPhase = .saved
            scheduleReturnToIdle()
        } catch {
            errorMessage = String(localized: "Impossibile salvare il file: \(error.localizedDescription)")
            downloadPhase = .idle
        }
    }

    /// Dopo la conferma torna alla faccia di riposo da solo. Il controllo su .saved
    /// prima di resettare serve a non calpestare un secondo download gia' partito
    /// nel frattempo: se la fase e' cambiata, questo timer non deve piu' toccarla.
    @MainActor
    private func scheduleReturnToIdle() {
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if downloadPhase == .saved {
                downloadPhase = .idle
            }
        }
    }
}

// MARK: - Vista per una riga chiave/valore nella superficie informazioni

struct InfoRow: View {
    let title: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(.cellMeta)
                .foregroundStyle(Brand.textMuted)
            Spacer()
            if monospaced {
                Text(value)
                    .font(.cellMeta)
                    .foregroundStyle(Brand.text)
                    .monospacedDigit()
            } else {
                Text(value)
                    .font(.cellMeta)
                    .foregroundStyle(Brand.text)
            }
        }
        .padding(.vertical, Space.xxs)
    }
}
