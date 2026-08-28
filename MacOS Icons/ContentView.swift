//
//  ContentView.swift
//  MacOS Icons
//
//  Created by Matteo Zampieri on 14/09/25.
//

import SwiftUI
import Foundation

// MARK: - Vista principale

struct ContentView: View {
    @EnvironmentObject private var searchService: IconSearchService
    // Un solo applier per finestra: e' lui a tenere il bersaglio dell'app agganciata
    // e lo stato del cambio icona, condiviso fra la barra di drop e l'inspector.
    @StateObject private var applier = IconApplier()
    @State private var searchText = ""
    @State private var sortOrder: IconSortOrder = .relevance
    @State private var selectedIcon: IconItem? = nil
    @State private var showsInspector = false
    @State private var isDropTargeted = false
    // Presenta il selettore con l'elenco delle app installate: sta qui e non dentro
    // AppDropZone perche' la sheet appartiene alla schermata, non al pannello che la chiede.
    @State private var showsAppPicker = false

    var body: some View {
        NavigationSplitView {
            SidebarView(sortOrder: $sortOrder, searchState: searchService.searchState)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            resultsArea
        }
        .environmentObject(searchService)
        .environmentObject(applier)
        .inspector(isPresented: $showsInspector) {
            // L'inspector vive in un ramo separato della gerarchia (e' un overlay di sistema),
            // quindi non e' garantito che erediti l'environment messo sul NavigationSplitView:
            // lo passiamo di nuovo qui esplicitamente perche' IconDetailView legge l'applier.
            inspectorContent
                .environmentObject(applier)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .navigationTitle(windowTitle)
        .navigationSubtitle(subtitle)
        .toolbar {
            brandItem
            ToolbarItem {
                Button {
                    showsInspector.toggle()
                } label: {
                    Label("Mostra i dettagli", systemImage: "sidebar.right")
                }
                .help("Mostra i dettagli")
            }
        }
        // Niente fondo opaco sulla toolbar: il nero del brand deve arrivare fino in cima.
        .toolbarBackground(.hidden, for: .windowToolbar)
        // L'app segue il tema del sito, non quello di sistema.
        .preferredColorScheme(.dark)
        // Appena la finestra si apre, la home mostra subito le ultime icone caricate.
        .task {
            // Senza un Worker verificato non parte nessuna richiesta di rete.
            guard searchService.isConfigured else { return }
            await searchService.loadLatest()
        }
        .onChange(of: selectedIcon) { _, newValue in
            // L'inspector si apre da solo appena l'utente sceglie un'icona.
            if newValue != nil {
                showsInspector = true
            }
        }
        .onChange(of: searchText) { _, newValue in
            // Svuotare la ricerca riporta alla home invece di lasciare una schermata vuota.
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty, !searchService.isShowingLatest {
                Task {
                    await searchService.loadLatest()
                }
            }
        }
        .onChange(of: sortOrder) { _, newValue in
            // Sulla home l'ordinamento riordina le ultime icone, altrimenti rilancia la ricerca.
            if searchService.isShowingLatest {
                Task {
                    await searchService.loadLatest()
                }
            } else if case .success = searchService.searchState {
                runSearch()
            }
        }
    }

    // MARK: Marchio in toolbar

    /// Il logo e' un elemento decorativo, non un comando: da macOS 26 la toolbar
    /// metterebbe ogni item dentro la sua capsula di vetro, e un marchio dentro un
    /// pulsante sembra cliccabile senza esserlo. `sharedBackgroundVisibility` toglie
    /// il vetro solo a questo item, lasciandolo agli altri.
    @ToolbarContentBuilder
    private var brandItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                BrandLogo(size: 22)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                BrandLogo(size: 22)
            }
        }
    }

    // MARK: Area risultati

    /// Colonna di dettaglio: barra di drop fissa in cima, poi ricerca, stati del risultato
    /// e drag & drop su tutta l'area sottostante.
    private var resultsArea: some View {
        // VStack esterno cosi' la barra resta ancorata sopra la griglia e fuori dalla sua
        // ScrollView: scorrendo le icone la barra non scompare mai.
        VStack(spacing: 0) {
            // Finche' manca il Worker non ha senso mostrare ne' la zona di trascinamento ne'
            // la griglia: senza catalogo non c'e' niente da applicare, quindi la schermata di
            // benvenuto prende tutto lo spazio ed e' l'unica cosa da fare.
            if !searchService.isConfigured {
                WorkerSetupView(onSaved: reloadAfterConfigurationSaved)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                AppDropZone(onPick: handlePickedApp, onBrowseApps: { showsAppPicker = true })
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.sm)

                if let staleNotice = searchService.staleNotice {
                    StaleResultsBanner(text: staleNotice)
                        .padding(.horizontal, Space.lg)
                        .padding(.bottom, Space.sm)
                        .transition(.opacity)
                }

                ZStack {
                    resultsContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.ui, value: resultStateTag)
                        // Stale-while-revalidate: durante un aggiornamento (nuova ricerca, cambio ordinamento)
                        // la griglia precedente resta a schermo smorzata e non cliccabile invece di sparire,
                        // cosi' IconGridView non viene mai smontata e la cascata di comparsa non riparte da zero.
                        .opacity(searchService.isRefreshing ? 0.35 : 1)
                        .allowsHitTesting(!searchService.isRefreshing)
                        .animation(.fade, value: searchService.isRefreshing)
                        // Lo spinner sta sopra il contenuto smorzato, ma non deve essere smorzato lui stesso:
                        // per questo e' un overlay applicato DOPO l'opacity, non dentro resultsContent.
                        .overlay {
                            if searchService.isRefreshing {
                                // Piu' piccolo del loader a pieno schermo: qui sotto c'e' gia' la griglia
                                // precedente smorzata, l'attesa va segnalata senza coprirla.
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(Brand.accent)
                                    .transition(.opacity)
                            }
                        }

                    if isDropTargeted {
                        dropOverlay
                            .transition(.opacity)
                    }
                }
                .animation(.ui, value: isDropTargeted)
            }
        }
        // La comparsa della schermata di benvenuto (e la sua uscita appena il Worker e' pronto)
        // e' solo una dissolvenza: qui cambia l'intera colonna, un movimento sarebbe brusco.
        .animation(.fade, value: searchService.isConfigured)
        .animation(.ui, value: searchService.staleNotice)
        // Fondo del brand sull'intera colonna (barra compresa), non solo sullo ZStack dei
        // risultati: altrimenti la barra nuova galleggerebbe su uno sfondo diverso dal resto.
        .background { BrandBackground() }
        // Stessa closure del trascinamento: da qualunque strada arrivi l'app, il seguito
        // (aggancio + ricerca del suo nome) e' identico.
        .sheet(isPresented: $showsAppPicker) {
            AppPickerSheet(onSelect: handlePickedApp)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Cerca icone")
        .onSubmit(of: .search) { runSearch() }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            // Solo bundle .app: qualunque altro file va rimbalzato dal Finder invece di
            // essere accettato in silenzio e non fare nulla.
            guard url.pathExtension.lowercased() == "app" else { return false }
            handlePickedApp(url)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    /// Un solo switch su `searchState`: ogni caso ha la vista brandizzata piu' adatta.
    /// La griglia non riceve `.transition`: la sua comparsa la gestisce gia' `IconGridView`.
    @ViewBuilder
    private var resultsContent: some View {
        switch searchService.searchState {
        case .idle:
            // Stato "sto per caricare": all'apertura le ultime icone stanno gia' arrivando,
            // quindi qui non deve lampeggiare un invito a cercare ma lo stesso spinner.
            loadingView
                .transition(.opacity)

        case .loading:
            loadingView
                .transition(.opacity)

        case .success(let icons):
            if icons.isEmpty {
                FailureStateView(failure: .noResults(query: searchText), onRetry: retryCurrentRequest)
                    .transition(.opacity)
            } else {
                IconGridView(icons: icons, selection: $selectedIcon)
            }

        case .error(let failure):
            FailureStateView(failure: failure, onRetry: retryCurrentRequest)
                .transition(.opacity)
        }
    }

    /// Tag minimo dello stato corrente, solo per pilotare la dissolvenza: l'array di icone
    /// non serve al confronto, conta solo in quale "famiglia" di stato siamo.
    private var resultStateTag: Int {
        switch searchService.searchState {
        // Idle e loading condividono la stessa vista (lo spinner): stesso tag, niente dissolvenza fra i due.
        case .idle, .loading: return 1
        case .success(let icons): return icons.isEmpty ? 2 : 3
        case .error: return 4
        }
    }

    /// Ricerca in corso: spinner d'accento piu' una didascalia discreta sotto.
    private var loadingView: some View {
        VStack(spacing: Space.md) {
            ProgressView()
                .controlSize(.large)
                .tint(Brand.accent)
            Text("Ricerca in corso…")
                .foregroundStyle(Brand.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Overlay morbido visibile solo mentre si trascina qualcosa sopra l'area risultati.
    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(Brand.accent.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Brand.accent, style: StrokeStyle(lineWidth: 2, dash: [8]))
            )
            .overlay(
                VStack(spacing: Space.sm) {
                    // "app.dashed" e' un'icona applicativa vuota: comunica meglio di una
                    // freccia di download che qui l'app diventa un bersaglio, non un termine di ricerca.
                    Image(systemName: "app.dashed")
                        .imageScale(.large)
                        .foregroundStyle(Brand.accent)
                    Text("Rilascia l'app per cambiarne l'icona")
                        .font(.cellLabel)
                        .foregroundStyle(Brand.textMuted)
                }
            )
            .allowsHitTesting(false)
    }

    // MARK: Inspector

    /// Dettaglio dell'icona selezionata, o un segnaposto quando non c'e' selezione.
    @ViewBuilder
    private var inspectorContent: some View {
        if let selectedIcon {
            IconDetailView(icon: selectedIcon)
        } else {
            BrandedEmptyState(
                symbol: "square.dashed",
                title: String(localized: "Nessuna icona selezionata"),
                message: String(localized: "Seleziona un'icona dalla griglia per vederne i dettagli.")
            )
        }
    }

    // MARK: Titolo

    /// Titolo della finestra: "Ultime icone" sulla home, il nome dell'app altrove (marchio, non tradotto).
    private var windowTitle: String {
        searchService.isShowingLatest ? String(localized: "Ultime icone") : "MacOS Icons"
    }

    /// Conteggio dei risultati in barra del titolo, vuoto quando non c'e' niente da contare.
    private var subtitle: String {
        if case .success(let icons) = searchService.searchState, !icons.isEmpty {
            return String(localized: "\(icons.count) icone")
        }
        return ""
    }

    // MARK: Azioni

    /// L'app scelta (trascinata o presa dal pannello) diventa il bersaglio del cambio icona e,
    /// nello stesso gesto, riempie la ricerca col suo nome: chi trascina un'app sta quasi sempre
    /// cercando la SUA icona, quindi partire gia' con la ricerca compilata evita un secondo passo
    /// manuale. Se l'attach fallisce (bundle non valido) non tocchiamo la ricerca: niente stato a meta'.
    private func handlePickedApp(_ url: URL) {
        guard applier.attach(url: url) else { return }
        searchText = appName(from: url)
        runSearch()
    }

    /// Lancia la ricerca solo se il testo non e' vuoto dopo il trim.
    private func runSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await searchService.searchIcons(query: trimmed, sortOrder: sortOrder)
        }
    }

    /// Appena il Worker e' verificato si carica subito la home: l'utente ha appena fatto un
    /// passo di configurazione, la ricompensa deve essere il catalogo pieno, non un vuoto
    /// da riempire cercando qualcosa a mano.
    private func reloadAfterConfigurationSaved() {
        Task {
            await searchService.loadLatest()
        }
    }

    /// Riprova l'ultima richiesta: la home se siamo sulla home, altrimenti la ricerca scritta.
    /// Serve al bottone degli errori che hanno senso di essere ritentati (rete, server giu').
    private func retryCurrentRequest() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if trimmed.isEmpty {
                await searchService.loadLatest()
            } else {
                await searchService.searchIcons(query: trimmed, sortOrder: sortOrder)
            }
        }
    }

    /// Ricava il nome dell'app da un URL trascinato, togliendo l'estensione .app.
    private func appName(from url: URL) -> String {
        let fileName = url.lastPathComponent
        if fileName.hasSuffix(".app") {
            return String(fileName.dropLast(4))
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Stato vuoto brandizzato

/// Sostituisce `ContentUnavailableView` di sistema, spento su fondo nero: un simbolo grande
/// d'accento, un titolo e una descrizione centrata. Riusata per idle e per la selezione vuota.
private struct BrandedEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var symbolColor: Color = Brand.accent

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolColor)

            Text(title)
                .font(.appTitle)
                .foregroundStyle(Brand.text)

            Text(message)
                .foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Stato di errore

/// L'errore mostrato come una cosa da risolvere, non come un vicolo cieco: sotto al testo
/// c'e' sempre il gesto che lo chiude (aprire le Impostazioni, aprire la dashboard, riprovare).
/// Prima qui compariva la stringa di sistema, tipo "Errore HTTP: 429", che non dice a nessuno
/// cosa fare.
private struct FailureStateView: View {
    let failure: SearchFailure
    var onRetry: (() -> Void)? = nil

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: failure.symbol)
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tintColor)

            Text(failure.title)
                .font(.appTitle)
                .foregroundStyle(Brand.text)

            Text(failure.message)
                .foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if failure.action != nil || (failure.isRetryable && onRetry != nil) {
                HStack(spacing: Space.sm) {
                    if let action = failure.action, let actionTitle = failure.actionTitle {
                        Button(actionTitle) { perform(action) }
                            .buttonStyle(AccentPillButtonStyle())
                    }

                    if failure.isRetryable, let onRetry {
                        Button(String(localized: "Riprova")) { onRetry() }
                            .buttonStyle(QuietPillButtonStyle())
                    }
                }
                .padding(.top, Space.xs)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tintColor: Color {
        switch failure.tint {
        case .warning: return .orange
        case .danger: return .red
        case .neutral: return Brand.accent
        }
    }

    private func perform(_ action: SearchFailure.Action) {
        switch action {
        case .openSettings:
            openSettings()
        case .openURL(let url):
            openURL(url)
        }
    }
}

// MARK: - Avviso sui dati salvati

/// Striscia discreta sopra la griglia quando quello che si vede non arriva dalla rete ma dalla
/// copia sul Mac. Non e' un errore e non deve sembrarlo: i risultati sotto sono veri e usabili,
/// qui si dice solo che potrebbero non essere gli ultimi.
private struct StaleResultsBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "internaldrive.fill")
                .foregroundStyle(Brand.accent)

            Text(text)
                .font(.cellLabel)
                .foregroundStyle(Brand.textMuted)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Bottoni degli stati

/// Bottone principale degli stati d'errore: pillola scura con bordo e testo d'accento.
/// Il giallo del brand resta un dettaglio e non diventa un fondo pieno, che a questa
/// dimensione griderebbe piu' del testo dell'errore.
private struct AccentPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cellLabel)
            .foregroundStyle(Brand.accent)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .strokeBorder(Brand.accent.opacity(configuration.isPressed ? 0.9 : 0.6), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Bottone secondario: stessa forma, nessun accento, cosi' la gerarchia fra le due azioni si vede.
private struct QuietPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cellLabel)
            .foregroundStyle(Brand.textMuted)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .strokeBorder(Brand.stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

#Preview {
    ContentView()
        .environmentObject(IconSearchService())
}
