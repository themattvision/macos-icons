//
//  AppDropZone.swift
//  MacOS Icons
//
//  Barra sopra la griglia: il punto in cui l'utente sceglie A QUALE app applicare
//  l'icona scelta piu' sotto. Due strade per arrivarci, trascinamento oppure
//  l'elenco delle app installate: il drag da solo non basta come unica via, perche'
//  richiede che l'utente sappia dove sta il .app e abbia una finestra del Finder
//  aperta, mentre l'elenco parte da dentro l'app.
//
//  L'elenco non lo apre questa barra: il bottone chiama `onBrowseApps()` e la sheet
//  la presenta ContentView, perche' una sheet appartiene alla schermata e non a una
//  riga al suo interno.
//
//  Il componente non aggancia mai il bersaglio da solo: chiama `onPick(url)` sia dal
//  drop sia dalla scelta manuale e lascia a ContentView il compito di risolvere il
//  nome dell'app e invocare `applier.attach`, cosi' c'e' un solo punto di verita' per
//  quell'operazione. Da qui si chiamano solo `detach()` e `restoreOriginalIcon()`,
//  le due azioni che appartengono davvero ai bottoni di questa barra.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Barra "trascina qui l'app"

struct AppDropZone: View {
    /// Chiamata sia dal drop sia dal pannello di scelta: qui si segnala solo l'intento,
    /// mai l'aggancio diretto (vedi nota in testa al file).
    let onPick: (URL) -> Void

    /// Richiesta di aprire l'elenco delle app installate. La sheet appartiene alla
    /// schermata, non a questa barra: qui si segnala solo che l'utente l'ha chiesta.
    let onBrowseApps: () -> Void

    @EnvironmentObject private var applier: IconApplier

    /// Accende il bordo tratteggiato mentre un'app sta sorvolando la barra.
    @State private var isTargeted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lato della miniatura, identico nei due stati: che dentro ci sia un simbolo SF
    /// o l'icona vera dell'app, la riga non deve cambiare altezza a seconda di cosa
    /// occupa quello slot.
    private let thumbnailSide: CGFloat = 40

    var body: some View {
        Group {
            if let target = applier.target {
                attachedRow(target)
            } else {
                emptyRow
            }
        }
        .frame(maxWidth: .infinity)
        // Il drop resta attivo in entrambi gli stati: si puo' sempre sostituire il
        // bersaglio trascinandone un altro sopra, non solo la prima volta.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.pathExtension.lowercased() == "app" else {
                // Falso: il Finder fa rimbalzare l'oggetto invece di farlo sparire,
                // segnalando all'utente che qui non e' un bersaglio valido.
                return false
            }
            onPick(url)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .animation(.ui, value: isTargeted)
        .animation(.ui, value: applier.phase)
        // Il passaggio fra i due stati e' un cambio di identita' della vista (if/else),
        // non un valore continuo: qui si anima la dissolvenza fra le due, non un colore.
        .animation(.ui, value: applier.target)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Stato vuoto: nessuna app agganciata

    private var emptyRow: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isTargeted ? Brand.accent : Brand.textMuted)
                .frame(width: thumbnailSide, height: thumbnailSide)

            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Trascina qui l'app per cambiarne l'icona")
                    .font(.cellLabel)
                    .foregroundStyle(Brand.text)
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.tail)

                Text("Poi scegli un'icona qui sotto")
                    .font(.cellMeta)
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.tail)

                // Terza riga vuota ma riservata: pareggia l'altezza allo stato agganciato,
                // che puo' arrivare a mostrare fino a tre righe (nome, stato, avviso di
                // sola lettura). Senza questa riga la griglia sotto salterebbe al primo drop.
                Text(verbatim: " ")
                    .font(.cellMeta)
                    .lineLimit(1, reservesSpace: true)
                    .hidden()
            }

            Spacer(minLength: Space.sm)

            chooseAppButton
        }
        .padding(Space.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isTargeted ? Brand.accent : Brand.stroke,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
        )
    }

    // MARK: - Stato agganciato: un'app e' il bersaglio

    private func attachedRow(_ target: AppTarget) -> some View {
        HStack(spacing: Space.md) {
            Image(nsImage: target.currentIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: thumbnailSide, height: thumbnailSide)
                .continuousCorners(Radius.md)

            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(target.name)
                    .font(.cellLabel)
                    .foregroundStyle(Brand.text)
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.tail)

                statusRow

                warningRow(target)
            }

            Spacer(minLength: Space.sm)

            HStack(spacing: Space.sm) {
                // Visibile solo se il bersaglio e' scrivibile: su un'app di sistema
                // non c'e' niente da ripristinare, l'app non e' mai stata toccata.
                if target.isWritable {
                    Button("Ripristina") {
                        Task { await applier.restoreOriginalIcon() }
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.textMuted)
                    .controlSize(.small)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                    .help("Riporta \(target.name) alla sua icona originale")
                }

                Button {
                    applier.detach()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Brand.textMuted)
                }
                .buttonStyle(.plain)
                .help("Stacca \(target.name) dalla zona di trascinamento")
            }
        }
        .padding(Space.md)
        .surface(radius: Radius.lg)
    }

    /// Riga di stato: cambia testo, colore e a volte simbolo in base alla fase di
    /// `IconApplier`. Sempre una riga sola (cellMeta, reservesSpace) cosi' il cambio
    /// di fase non fa mai muovere il bottone Ripristina o la X accanto.
    @ViewBuilder
    private var statusRow: some View {
        switch applier.phase {
        case .idle:
            Text("Scegli un'icona qui sotto per applicarla")
                .font(.cellMeta)
                .foregroundStyle(Brand.textMuted)
                .lineLimit(1, reservesSpace: true)
                .truncationMode(.tail)

        case .applying:
            HStack(spacing: Space.xxs) {
                ProgressView()
                    .controlSize(.small)
                Text("Applico l'icona…")
                    .font(.cellMeta)
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.tail)
            }

        case .applied:
            HStack(spacing: Space.xxs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Icona applicata. Se l'app era aperta, chiudila e riaprila per vederla.")
                    .font(.cellMeta)
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.tail)
                    .help("Icona applicata. Se l'app era aperta, chiudila e riaprila per vederla.")
            }

        case .restored:
            Text("Icona originale ripristinata.")
                .font(.cellMeta)
                .foregroundStyle(Brand.textMuted)
                .lineLimit(1, reservesSpace: true)
                .truncationMode(.tail)

        case .failed(let message):
            HStack(spacing: Space.xxs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.cellMeta)
                    .foregroundStyle(.orange)
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.tail)
                    .help(message)
            }
        }
    }

    /// Avviso di sola lettura: sempre presente nel layout (stessa altezza), ma visibile
    /// solo quando il bersaglio non e' scrivibile. Stessa idea di `authorName` nella
    /// griglia: la riga riserva lo spazio anche quando non ha niente da dire.
    @ViewBuilder
    private func warningRow(_ target: AppTarget) -> some View {
        Text("macOS non lascia modificare quest'app.")
            .font(.cellMeta)
            .foregroundStyle(.orange)
            .lineLimit(1, reservesSpace: true)
            .truncationMode(.tail)
            .opacity(target.isWritable ? 0 : 1)
            .accessibilityHidden(target.isWritable)
    }

    // MARK: - Bottone "Scegli app…"

    private var chooseAppButton: some View {
        Button {
            onBrowseApps()
        } label: {
            Text("Scegli app…")
        }
        .buttonStyle(.bordered)
        .tint(Brand.accent)
        .controlSize(.regular)
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
        .help("Apri il pannello per scegliere un'app da /Applications")
    }

    // MARK: - Accessibilita'

    /// Un'unica frase che riassume lo stato corrente della barra, invece di far leggere
    /// a VoiceOver i frammenti separati di icona, nome e bottoni.
    private var accessibilityLabel: String {
        guard let target = applier.target else {
            return String(localized: "Trascina qui un'app per cambiarne l'icona, oppure scegli l'app dal pannello.")
        }
        var parts = [String(localized: "App agganciata: \(target.name)")]
        if !target.isWritable {
            parts.append(String(localized: "macOS non lascia modificare quest'app"))
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Preview

#Preview {
    AppDropZone(onPick: { _ in }, onBrowseApps: {})
        .environmentObject(IconApplier())
        .frame(width: 700)
        .padding()
        .background(Color.black)
}
