//
//  IconGridView.swift
//  MacOS Icons
//
//  Created by Matteo Zampieri on 14/09/25.
//

import SwiftUI
import AppKit

// MARK: - Griglia dei risultati

/// Vista griglia stile home di macosicons.com: icona su fondo trasparente e sotto i
/// metadati raggruppati per importanza. Lo sfondo animato del brand vive sotto questa
/// vista, quindi qui non si dipinge nessun fondo opaco.
struct IconGridView: View {
    let icons: [IconItem]
    @Binding var selection: IconItem?

    // Tenuto per objectID e non per l'intero IconItem: confrontare stringhe evita
    // di legare lo stato hover all'identità (Hashable) dell'intero modello.
    @State private var hoveredID: String?

    // Celle già comparse almeno una volta: evita di rianimare la cascata quando
    // la lista viene ridisegnata (es. arrivo di altri risultati in coda).
    @State private var appeared: Set<String> = []

    // Un'unica definizione adattiva: è lei sola a decidere quante colonne stanno
    // nella riga, ripeterla con Array(repeating:count:) sarebbe un doppio calcolo.
    // La misura minima tiene conto del nome su due righe: sotto i 144 pt le parole
    // lunghe dei nomi ("Darktable (macOS Big Sur)") si troncherebbero comunque.
    private let columns = [GridItem(.adaptive(minimum: 144, maximum: 172), spacing: Space.lg)]

    var body: some View {
        ScrollView {
            // Gutter identico in orizzontale e verticale: la griglia è isotropica,
            // così l'occhio legge righe e colonne con lo stesso ritmo.
            LazyVGrid(columns: columns, spacing: Space.lg) {
                ForEach(Array(icons.enumerated()), id: \.element.id) { index, icon in
                    Button {
                        selection = icon
                    } label: {
                        IconGridItem(
                            icon: icon,
                            index: index,
                            isHovered: hoveredID == icon.objectID,
                            isSelected: selection?.objectID == icon.objectID,
                            hasAppeared: appeared.contains(icon.objectID),
                            markAppeared: { appeared.insert(icon.objectID) }
                        )
                    }
                    .buttonStyle(PressableCellStyle())
                    .onHover { isHovering in
                        hoveredID = isHovering ? icon.objectID : nil
                    }
                    // Animano solo la cella toccata dal cambio, non l'intera griglia:
                    // il valore osservato è lo stato condiviso, non una copia locale.
                    .animation(.ui, value: hoveredID)
                    .animation(.ui, value: selection?.objectID)
                }
            }
            .padding(Space.lg)
        }
    }
}

// MARK: - Singola cella

/// Icona più tre livelli di informazione, in ordine di importanza decrescente:
/// il nome (primario), l'autore (secondario, attaccato al nome perché risponde alla
/// stessa domanda "cosa e di chi"), data e download (terziario, staccato e smorzato).
///
/// La regola di layout che tiene insieme la griglia: ogni cella ha SEMPRE la stessa
/// altezza, perché nome e autore si riservano lo spazio anche quando sono corti o
/// assenti. Senza questo, una riga con un'icona senza autore si accorcia e la griglia
/// va a scalini.
private struct IconGridItem: View {
    let icon: IconItem
    let index: Int
    let isHovered: Bool
    let isSelected: Bool
    let hasAppeared: Bool
    let markAppeared: () -> Void

    // Stato locale di comparsa: parte invisibile e si anima una sola volta,
    // pilotato da hasAppeared per non ripartire ai ridisegni successivi.
    @State private var isVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Bersaglio di "trascina un'app per cambiarne l'icona": quando è agganciato,
    // la griglia offre l'applicazione diretta senza passare dall'inspector.
    @EnvironmentObject private var applier: IconApplier

    private let iconSize: CGFloat = 84

    var body: some View {
        // spacing 0: il ritmo verticale lo danno i padding fra i gruppi, non uno
        // spacing uniforme. Distanze diverse sono ciò che rende leggibili i gruppi.
        VStack(spacing: 0) {
            thumbnail
                .padding(.bottom, Space.sm)

            // Blocco primario: nome e autore stretti (4 pt) perché vanno letti insieme.
            VStack(spacing: Space.xxs) {
                Text(icon.appName)
                    .font(.cellLabel)
                    .foregroundStyle(Brand.text)
                    .multilineTextAlignment(.center)
                    // Due righe con spazio riservato: il nome intero si legge quasi
                    // sempre e l'altezza della cella non dipende da quanto è lungo.
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.tail)

                Text(authorName)
                    .font(.cellSubtitle)
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.tail)
            }

            // Terziario: staccato dal blocco primario (8 pt, il doppio del gap interno)
            // così si legge come un'altra cosa e non come una terza riga del titolo.
            metaRow
                .padding(.top, Space.xs)
        }
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity)
        .background(cellBackground)
        .contentShape(Rectangle())
        .opacity(isVisible ? 1 : 0)
        // Con Riduci movimento la comparsa resta solo una dissolvenza: niente scala,
        // che su cinquanta celle a scacchiera e' proprio il movimento da evitare.
        .scaleEffect(isVisible || reduceMotion ? 1 : 0.94)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .help(helpText)
        .contextMenu {
            // Voce primaria in cima e solo quando c'è un bersaglio agganciato:
            // è l'azione che l'utente sta cercando in quel momento, non le
            // utilità generiche più sotto che restano valide comunque.
            if let target = applier.target {
                Button("Applica a \(target.name)") {
                    Task { await applier.apply(icon: icon) }
                }
                .disabled(!applier.canApply)

                Divider()
            }

            Button("Copia nome") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(icon.appName, forType: .string)
            }
            Button("Apri su macOSicons") {
                NSWorkspace.shared.open(ExternalLinks.website)
            }
        }
        .onAppear(perform: reveal)
        // Doppio click come scorciatoia: applica subito l'icona al bersaglio
        // agganciato. Il click singolo resta quello del Button esterno
        // (seleziona e apre l'inspector), qui intercettiamo solo il secondo
        // tap ravvicinato senza sottrarglielo.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard applier.canApply else { return }
                Task { await applier.apply(icon: icon) }
            }
        )
    }

    // MARK: Pezzi della cella

    private var thumbnail: some View {
        RetryableAsyncImage(
            url: icon.lowResPngUrl,
            width: iconSize,
            height: iconSize,
            cornerRadius: Radius.md
        )
        .frame(width: iconSize, height: iconSize)
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
        .offset(y: isHovered ? -2 : 0)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .accentGlow(isHovered, color: Brand.cyan)
    }

    /// Riga terziaria: data e download CENTRATI e uniti da un separatore, non spinti
    /// ai due bordi opposti da uno Spacer. In una cella da 150 pt la giustificazione
    /// piena apre un buco in mezzo e rompe l'asse centrale di icona, nome e autore.
    /// È smorzata a riposo e si accende quando la cella è sotto al puntatore: il
    /// dettaglio c'è ma non compete con il nome nella lettura a colpo d'occhio.
    private var metaRow: some View {
        HStack(spacing: Space.xxs) {
            Text(dateLabel)
                .monospacedDigit()

            if let downloads = icon.downloads {
                Text(verbatim: "·")
                    .foregroundStyle(Brand.textMuted.opacity(0.45))

                HStack(spacing: Space.xxs) {
                    Image(systemName: "arrow.down")
                        .imageScale(.small)
                    Text(
                        downloads.formatted(
                            .number.notation(.compactName).locale(Locale.autoupdatingCurrent)
                        )
                    )
                    .monospacedDigit()
                }
            }
        }
        .font(.cellMeta)
        .foregroundStyle(Brand.textMuted)
        .lineLimit(1)
        // 0.75 su un grigio già al 55% resta chiaramente terziario ma sempre leggibile:
        // sotto questa soglia, su fondo nero, la riga diventa un fantasma.
        .opacity(isHovered || isSelected ? 1 : 0.75)
    }

    /// Selezione e hover restano leggibili come colori sempre presenti (mai un if/else
    /// nella gerarchia): così l'animazione interpola i colori invece di scambiare viste.
    private var cellBackground: some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
    }

    private var fillColor: Color {
        if isSelected { return Brand.accent.opacity(0.16) }
        if isHovered { return Brand.surfaceRaised.opacity(0.9) }
        return Color.clear
    }

    private var strokeColor: Color {
        if isSelected { return Brand.accent.opacity(0.55) }
        if isHovered { return Brand.stroke }
        return Color.clear
    }

    // MARK: Dati derivati

    /// Autore normalizzato: stringa vuota se manca, perché la riga occupa comunque
    /// il suo spazio (lineLimit reservesSpace) e le celle restano allineate.
    private var authorName: String {
        (icon.usersName ?? icon.credit ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Data breve, non il numerico completo: giorno e mese abbreviati invece della
    /// data numerica per esteso. L'anno compare solo quando serve davvero, cioè
    /// quando non è quello corrente.
    private var dateLabel: String {
        let base = Date.FormatStyle().locale(Locale.autoupdatingCurrent)
        let isCurrentYear = Calendar.current.isDate(icon.date, equalTo: Date(), toGranularity: .year)
        let style = isCurrentYear
            ? base.day().month(.abbreviated)
            : base.day().month(.abbreviated).year()
        return icon.date.formatted(style)
    }

    /// Tooltip che racconta l'azione disponibile: col bersaglio agganciato il
    /// solo nome non basta più a dire cosa succederà passando sopra la cella.
    private var helpText: String {
        guard let target = applier.target else { return icon.appName }
        return String(localized: "Applica \(icon.appName) a \(target.name)")
    }

    /// VoiceOver legge una frase sola invece di quattro frammenti scollegati.
    private var accessibilityLabel: String {
        var parts = [icon.appName]
        if !authorName.isEmpty { parts.append(String(localized: "di \(authorName)")) }
        if let downloads = icon.downloads { parts.append(String(localized: "\(downloads) download")) }
        return parts.joined(separator: ", ")
    }

    /// Fa comparire la cella: se è la prima volta la anima in cascata con un ritardo
    /// crescente per indice, altrimenti (es. ricomparsa per scroll) la mostra di scatto.
    private func reveal() {
        guard !hasAppeared else {
            isVisible = true
            return
        }
        markAppeared()
        withAnimation(.stagger(index, reduceMotion: reduceMotion)) {
            isVisible = true
        }
    }
}

// MARK: - Preview

#Preview {
    // IconItem non ha un init pubblico (solo da Decoder): la preview resta con array vuoto.
    IconGridView(icons: [], selection: .constant(nil))
        .environmentObject(IconApplier())
}
