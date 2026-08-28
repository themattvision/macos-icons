//
//  AppPickerSheet.swift
//  MacOS Icons
//
//  Sheet aperta dal pulsante "Scegli app...": mostra l'elenco delle app installate
//  sul Mac (fornito da InstalledAppsService) con un campo di ricerca in cima, cosi'
//  l'utente sceglie il bersaglio a cui cambiare icona senza dover navigare a mano
//  dentro il pannello di sistema NSOpenPanel.
//

import SwiftUI
import AppKit

// MARK: - Sheet di selezione fra le app installate

struct AppPickerSheet: View {
    /// Chiamata col bundle .app scelto. La sheet si chiude DA SOLA prima di
    /// invocarla (vedi `select(_:)`): il chiamante non deve mai richiudere la
    /// sheet a mano dopo aver ricevuto la selezione.
    let onSelect: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Ciclo di vita legato alla sheet: ogni apertura riparte da una scansione
    /// fresca (il .task sotto chiama load()), niente stato condiviso globale.
    @StateObject private var service = InstalledAppsService()

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            // Separatore sottile fra l'intestazione e tutto il resto: campo di
            // ricerca e griglia sono un unico blocco di contenuto sotto il titolo.
            Rectangle()
                .fill(Brand.stroke)
                .frame(height: 1)

            searchField
                .padding(.horizontal, Space.lg)
                .padding(.top, Space.md)
                .padding(.bottom, Space.md)

            content
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 620)
        .background(sheetBackground)
        .task {
            await service.load()
        }
        .onAppear {
            // Focus dato appena la sheet compare: e' un selettore che si apre
            // per digitare subito il nome dell'app, non per scorrere a occhio.
            isSearchFocused = true
        }
    }

    // MARK: - Sfondo

    /// Stessi aloni del resto dell'app, ma smorzati: su una sheet piccola l'effetto
    /// pieno diventerebbe rumore, quindi restano un velo tenue sotto tutto il resto.
    private var sheetBackground: some View {
        ZStack {
            Brand.background
            BrandBackground()
                .opacity(0.5)
        }
        .ignoresSafeArea()
    }

    // MARK: - Intestazione

    private var header: some View {
        HStack(alignment: .top, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Scegli l'app da personalizzare")
                    .font(.heroTitle)
                    .foregroundStyle(Brand.text)

                Text("L'app che scegli diventa il bersaglio a cui applicherai la prossima icona.")
                    .font(.heroSubtitle)
                    .foregroundStyle(Brand.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.md)

            Button {
                dismiss()
            } label: {
                Text("Fine")
            }
            .buttonStyle(.bordered)
            .tint(Brand.textMuted)
            .controlSize(.regular)
            .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            .keyboardShortcut(.cancelAction)
        }
        .padding(Space.lg)
    }

    // MARK: - Campo di ricerca

    /// Capsula in RoundedRectangle + Radius.pill, non Capsule di sistema: stessa
    /// forma usata per i bottoni a pillola nel resto dell'app (vedi AppDropZone,
    /// SidebarView), cosi' il raggio resta un token unico e non due implementazioni.
    private var searchField: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Brand.textMuted)

            TextField("Cerca fra le tue app", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Brand.text)
                .focused($isSearchFocused)
                // Invio seleziona la prima app filtrata: comodo per chi digita
                // il nome e conferma senza toccare il mouse.
                .onSubmit(selectFirstMatch)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Brand.textMuted)
                }
                .buttonStyle(.plain)
                .help("Svuota la ricerca")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                .fill(Brand.surfaceRaised)
        )
    }

    // MARK: - Contenuto: caricamento, vuoto o griglia

    @ViewBuilder
    private var content: some View {
        let filtered = service.filtered(by: query)

        if service.isLoading && service.apps.isEmpty {
            loadingState
        } else if filtered.isEmpty {
            emptyState
        } else {
            grid(filtered)
        }
    }

    private var loadingState: some View {
        VStack(spacing: Space.sm) {
            ProgressView()
                .controlSize(.large)
                .tint(Brand.accent)
            Text("Cerco le app installate…")
                .font(.cellMeta)
                .foregroundStyle(Brand.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Brand.textMuted)
            Text("Nessuna app trovata per \"\(query)\"")
                .font(.cellLabel)
                .foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.lg)
    }

    // Colonne adattive: stessa logica di IconGridView, ma con un minimo piu'
    // piccolo perche' qui la cella e' piu' compatta (icona 56pt contro 84pt).
    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 132), spacing: Space.md)]

    private func grid(_ apps: [InstalledApp]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Space.md) {
                ForEach(apps) { app in
                    Button {
                        select(app)
                    } label: {
                        AppPickerCell(app: app)
                    }
                    .buttonStyle(PressableCellStyle())
                    // Le app non scrivibili restano visibili (l'utente le cerca e
                    // deve capire perche' non ci sono) ma non sono cliccabili.
                    .disabled(!app.isWritable)
                }
            }
            .padding(Space.lg)
        }
    }

    // MARK: - Selezione

    /// Chiude la sheet PRIMA di chiamare onSelect: e' il contratto fissato dal
    /// chiamante, che si aspetta la sheet gia' sparita quando riceve l'URL.
    private func select(_ app: InstalledApp) {
        guard app.isWritable else { return }
        dismiss()
        onSelect(app.url)
    }

    private func selectFirstMatch() {
        guard let first = service.filtered(by: query).first, first.isWritable else { return }
        select(first)
    }
}

// MARK: - Singola cella

/// Icona 56pt (misura richiesta esplicitamente per questo selettore, piu' piccola
/// della cella della griglia principale a 84pt: qui la lista puo' essere lunga
/// quanto le app installate sul Mac e serve piu' densita') piu' nome su due righe.
private struct AppPickerCell: View {
    let app: InstalledApp

    @State private var isHovering = false

    private let iconSize: CGFloat = 56 // misura richiesta esplicitamente per questo selettore

    var body: some View {
        VStack(spacing: Space.xs) {
            thumbnail

            Text(app.name)
                .font(.cellLabel)
                .foregroundStyle(Brand.text)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
        }
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity)
        .background(cellBackground)
        .contentShape(Rectangle())
        // App non scrivibile: smorzata, non nascosta. Nascondere costringerebbe
        // l'utente a chiedersi perche' un'app che sa di avere non compare in cerca.
        .opacity(app.isWritable ? 1 : 0.45)
        .onHover { hovering in
            guard app.isWritable else { return }
            withAnimation(.ui) { isHovering = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .help(helpText)
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .continuousCorners(Radius.md)

            if !app.isWritable {
                // Lucchetto sovrapposto in basso a destra: spiega a colpo d'occhio
                // perche' quella cella, pur visibile, non risponde al click.
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.text)
                    .padding(4)
                    .background(Brand.surfaceRaised, in: Circle())
                    .overlay(Circle().strokeBorder(Brand.stroke, lineWidth: 1))
                    .offset(x: 4, y: 4)
            }
        }
    }

    /// Colori sempre presenti (mai un if/else di viste diverse): cosi' l'hover
    /// interpola invece di scambiare gerarchia, stessa logica di IconGridView.
    private var cellBackground: some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
    }

    private var fillColor: Color {
        isHovering ? Brand.surfaceRaised.opacity(0.9) : Color.clear
    }

    private var strokeColor: Color {
        isHovering ? Brand.stroke : Color.clear
    }

    private var accessibilityLabel: String {
        app.isWritable ? app.name : String(localized: "\(app.name), non modificabile")
    }

    private var helpText: String {
        app.isWritable
            ? app.name
            : String(localized: "Quest'app è protetta da macOS e non si può personalizzare")
    }
}

// MARK: - Preview

#Preview {
    AppPickerSheet(onSelect: { _ in })
}
