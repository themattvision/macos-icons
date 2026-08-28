//
//  MacOS Icons
//  Created by Matteo Zampieri on 14/09/25.
//

import SwiftUI
import AppKit

// MARK: - Immagine remota con placeholder e gestione errore

struct RetryableAsyncImage: View {
    let url: String
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var loadingFailed = false
    // Ultima immagine caricata con successo: serve a non far collassare l'inspector quando
    // l'utente cambia formato e il nuovo url e' ancora in caricamento o fallisce, e a dare
    // al crossfade qualcosa da cui partire invece di un buco vuoto.
    @State private var lastImage: Image?

    var body: some View {
        Group {
            if loadingFailed {
                if let lastImage {
                    // Il formato corrente non si carica, ma teniamo a schermo l'ultima
                    // anteprima buona invece di far sparire tutto (caso inspector).
                    lastImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    // Nessuna immagine precedente da mostrare: l'icona che fallisce sparisce,
                    // com'era in origine (caso griglia, dove il frame lo riserva gia' il
                    // chiamante). Qui pero' serve una vista vera e non EmptyView: l'onChange
                    // in fondo deve restare vivo anche in questo ramo, altrimenti loadingFailed
                    // non torna mai false e il formato successivo non viene piu' nemmeno provato.
                    // E' esattamente il bug che questa versione chiude.
                    Color.clear
                        .frame(width: width, height: height)
                }
            } else {
                AsyncImage(
                    url: URL(string: url),
                    transaction: Transaction(animation: reduceMotion ? .fadeReduced : .fade)
                ) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: width, height: height)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                            .transition(.opacity)
                            .onAppear {
                                lastImage = image
                            }
                    case .failure(_):
                        // La fase di errore non ha piu' bisogno di un onAppear che sposta lo
                        // stato: l'onChange sotto copre gia' il reset a ogni nuovo url, qui
                        // basta segnalare il fallimento.
                        Color.clear
                            .frame(width: width, height: height)
                            .onAppear {
                                loadingFailed = true
                            }
                    case .empty:
                        // Finche' non arriva nulla, mostriamo l'ultima immagine buona se
                        // esiste: cosi' lo slot dell'inspector non torna mai a essere un
                        // rettangolo vuoto con lo spinner quando si cambia formato.
                        Group {
                            if let lastImage {
                                lastImage
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                // Segnaposto: una superficie del brand, ferma. Qui dentro ci
                                // finiscono fino a cinquanta istanze insieme, quindi non ci va
                                // niente di animato ne' sfocato.
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(Brand.surfaceRaised)
                            }
                        }
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .onChange(of: url) { _, _ in
            // Al cambio di formato si resetta solo il fallimento: lastImage va tenuta,
            // e' proprio quello che permette al crossfade di avere un punto di partenza
            // invece di un vuoto mentre il nuovo url carica.
            loadingFailed = false
        }
    }
}
