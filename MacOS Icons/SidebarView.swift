//
//  SidebarView.swift
//  MacOS Icons
//
//  Created by Matteo Zampieri on 14/09/25.
//

import SwiftUI

// MARK: - Sidebar

/// Barra laterale vestita col brand di macosicons.com: fondo nero, righe di ordinamento
/// a pillola con accento blu elettrico, intestazioni maiuscole discrete.
struct SidebarView: View {
    @Binding var sortOrder: IconSortOrder
    let searchState: SearchState

    var body: some View {
        List {
            // Testata col marchio: non selezionabile, solo il logo reagisce al mouse.
            Section {
                brandHeader
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .allowsHitTesting(true)

                Rectangle()
                    .fill(Brand.stroke)
                    .frame(height: 1)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(IconSortOrder.allCases) { order in
                    sortRow(order)
                }
            } header: {
                sectionHeader(String(localized: "Ordina per"))
            }

            // La sezione esiste solo quando ci sono davvero risultati: uno spazio vuoto
            // e' meglio di una scheda vuota con un messaggio placeholder.
            if case .success(let icons) = searchState, !icons.isEmpty {
                Section {
                    resultsCard(icons)
                        .listRowBackground(Color.clear)
                } header: {
                    sectionHeader(String(localized: "Risultati"))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background)
        .listStyle(.sidebar)
    }

    // MARK: - Testata col marchio

    /// Logo animato piu' nome del brand, come in alto a sinistra su macosicons.com.
    /// Riga puramente decorativa: nessun tap gesture, non fa parte della selezione.
    private var brandHeader: some View {
        HStack(spacing: Space.sm) {
            BrandLogo(size: 32)

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "macOSicons")
                    .font(.cellLabel)
                    .foregroundStyle(Brand.text)
                Text("Catalogo icone")
                    .font(.cellMeta)
                    .foregroundStyle(Brand.textMuted)
            }
        }
        .padding(.vertical, Space.md)
    }

    // MARK: - Riga di ordinamento a pillola

    /// Ogni voce e' una pillola disegnata a mano: niente piu' evidenziazione blu piena di sistema,
    /// lo stato selezionato/hover lo gestiamo noi con i colori del brand.
    private func sortRow(_ order: IconSortOrder) -> some View {
        Button {
            withAnimation(.ui) {
                sortOrder = order
            }
        } label: {
            SortPillRow(order: order, isSelected: sortOrder == order)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCellStyle(pressedScale: 0.98))
        .listRowBackground(Color.clear)
    }

    // MARK: - Scheda risultati

    /// Statistiche della ricerca corrente dentro una superficie del brand.
    private func resultsCard(_ icons: [IconItem]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            statRow(
                label: String(localized: "Icone trovate"),
                systemImage: "magnifyingglass",
                value: icons.count.formatted(.number.locale(Locale.autoupdatingCurrent))
            )
            statRow(
                label: String(localized: "Download totali"),
                systemImage: "arrow.down.circle",
                value: totalDownloads(icons).formatted(.number.notation(.compactName).locale(Locale.autoupdatingCurrent))
            )
            if let mostRecent = mostRecentIcon(icons) {
                statRow(
                    label: String(localized: "Più recente"),
                    systemImage: "calendar",
                    value: mostRecent.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale.autoupdatingCurrent))
                )
            }
        }
        .padding(Space.sm)
        .surface(radius: Radius.lg)
    }

    /// Riga compatta etichetta/valore, solo informativa: mai selezionabile come le voci di ordinamento.
    private func statRow(label: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
                .foregroundStyle(Brand.textMuted)
            Spacer()
            Text(value)
                .font(.metric)
                .foregroundStyle(Brand.text)
                .monospacedDigit()
        }
    }

    // MARK: - Intestazione di sezione

    /// Etichetta maiuscola e discreta, come le sezioni del sito.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sectionHeader)
            .foregroundStyle(Brand.textMuted)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    // MARK: - Calcoli statistiche

    private func totalDownloads(_ icons: [IconItem]) -> Int {
        icons.compactMap(\.downloads).reduce(0, +)
    }

    private func mostRecentIcon(_ icons: [IconItem]) -> IconItem? {
        icons.max { $0.date < $1.date }
    }
}

// MARK: - Riga di ordinamento

/// Pillola di una singola voce di ordinamento, con stato selezionato/hover propri.
private struct SortPillRow: View {
    let order: IconSortOrder
    let isSelected: Bool

    /// Hover rilevato a mano: la List non offre piu' l'evidenziazione di sistema.
    @State private var isHovering = false

    var body: some View {
        Label(order.label, systemImage: order.systemImage)
            .foregroundStyle(isSelected ? Brand.text : Brand.textMuted)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .fill(pillFill)
            )
            .accentGlow(isSelected)
            .onHover { hovering in
                withAnimation(.ui) {
                    isHovering = hovering
                }
            }
    }

    private var pillFill: Color {
        if isSelected { return Brand.accent }
        if isHovering { return Brand.surfaceRaised }
        return .clear
    }
}

// MARK: - Preview

#Preview("Con risultati") {
    let json = """
    [
        {
            "objectID": "1",
            "appName": "Preview App",
            "timeStamp": "2026-08-01T00:00:00Z",
            "icnsUrl": "https://example.com/icon.icns",
            "iOSUrl": null,
            "lowResPngUrl": "https://example.com/icon.png",
            "category": null,
            "downloads": 1345,
            "credit": null,
            "uploadedBy": null,
            "usersName": null
        }
    ]
    """
    let icons = (try? JSONDecoder().decode([IconItem].self, from: Data(json.utf8))) ?? []
    return SidebarView(sortOrder: .constant(.popular), searchState: .success(icons))
}

#Preview("Nessun risultato") {
    SidebarView(sortOrder: .constant(.relevance), searchState: .idle)
}
