//
//  MacOS Icons
//  Logo animato del sito macosicons.com: cinque strati impilati che, al passaggio del
//  mouse, si spostano di pochissimo l'uno dall'altro (parallasse), con gli strati piu'
//  "in superficie" (occhi, bocca) che si muovono di piu' rispetto al fondo.
//

import SwiftUI

// MARK: - BrandLogo

/// Logo del brand, componibile a qualsiasi dimensione tramite `size`.
struct BrandLogo: View {
    private let size: CGFloat

    /// Spostamento del puntatore normalizzato fra -1 e 1 su entrambi gli assi, rispetto
    /// al centro del logo. Resta a zero finche' il mouse non entra, e ci torna quando esce.
    @State private var pointer: CGPoint = .zero

    /// Con Riduci movimento attivo il parallasse non si applica: strati fermi e centrati.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(size: CGFloat) {
        self.size = size
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            shadowLayer
            baseLayer
            squareLayer
            mouthLayer
            eyeLayer(leftFraction: Face.eyeLefts.0)
            eyeLayer(leftFraction: Face.eyeLefts.1)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .allowsHitTesting(true)
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard !reduceMotion else { return }
            switch phase {
            case .active(let point):
                let half = size / 2
                pointer = CGPoint(
                    x: clamp((point.x - half) / half),
                    y: clamp((point.y - half) / half)
                )
            case .ended:
                pointer = .zero
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pointer)
        .accessibilityElement()
        .accessibilityLabel("macOSicons")
    }

    // MARK: - Strati

    /// Ombra proiettata dal fondo: lo stesso `logo-base`, sfocato e attenuato, dietro a tutto.
    private var shadowLayer: some View {
        Image("logo-base")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .blur(radius: size * 0.20)
            .opacity(0.4)
            .offset(parallax(Factor.base))
            .allowsHitTesting(false)
    }

    /// Forma di fondo, riempie tutto il quadrato.
    private var baseLayer: some View {
        Image("logo-base")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .offset(parallax(Factor.base))
            .allowsHitTesting(false)
    }

    /// Riquadro interno piu' chiaro, quadrato anch'esso, centrato al 90% del lato.
    private var squareLayer: some View {
        let side = size * 0.90
        let inset = (size - side) / 2
        return Image("logo-square")
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .offset(x: inset, y: inset)
            .offset(parallax(Factor.square))
            .allowsHitTesting(false)
    }

    /// Bocca: il bordo sinistro sta al 39,25% del lato, non il centro. Sul sito il CSS
    /// ha un `transform: translate(-50%)` che lo script del parallasse riscrive inline,
    /// quindi non ha mai effetto: leggerlo come centro sposta la bocca di quasi il 18%
    /// del lato e fa sembrare la faccia storta.
    private var mouthLayer: some View {
        let height = size * Face.height
        let width = height * Ratio.mouth
        return Image("logo-mouth")
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .offset(x: size * Face.mouthLeft, y: size * Face.mouthTop)
            .offset(parallax(Factor.mouth))
            .allowsHitTesting(false)
    }

    /// Un occhio: `leftFraction` distingue i due occhi usando la stessa vista.
    private func eyeLayer(leftFraction: CGFloat) -> some View {
        let height = size * Face.height
        let width = height * Ratio.eye
        return Image("logo-eye")
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .offset(x: size * leftFraction, y: size * Face.eyeTop)
            .offset(parallax(Factor.eye))
            .allowsHitTesting(false)
    }

    // MARK: - Parallasse

    /// Spostamento in punti di uno strato, dato il suo fattore: cresce verso la superficie.
    private func parallax(_ factor: CGFloat) -> CGSize {
        guard !reduceMotion else { return .zero }
        return CGSize(width: pointer.x * factor * size, height: pointer.y * factor * size)
    }

    /// Posizione della faccia in frazioni del lato del logo. Sono gli stessi valori usati
    /// da `tools/genera-appicon.py` per l'app icon, ricavati con un fit sui pixel
    /// dell'icona ufficiale di macosicons.com: gli offset sono bordi, mai centri.
    private enum Face {
        static let height: CGFloat = 0.1775
        static let eyeTop: CGFloat = 0.2800
        static let eyeLefts: (CGFloat, CGFloat) = (0.2925, 0.6125)
        static let mouthTop: CGFloat = 0.5575
        static let mouthLeft: CGFloat = 0.3925
    }

    /// Fattori di spostamento per strato, crescenti dal fondo verso gli occhi.
    private enum Factor {
        static let base: CGFloat = 0.012
        static let square: CGFloat = 0.024
        static let mouth: CGFloat = 0.030
        static let eye: CGFloat = 0.036
    }

    /// Proporzioni larghezza/altezza degli asset non quadrati, per derivare la larghezza
    /// da un'altezza fissa senza dipendere dalla dimensione intrinseca dell'immagine.
    private enum Ratio {
        static let eye: CGFloat = 24.0 / 43.0
        static let mouth: CGFloat = 86.0 / 44.0
    }
}

// MARK: - Utility

/// Limita un valore normalizzato all'intervallo -1...1.
private func clamp(_ value: CGFloat) -> CGFloat {
    max(-1, min(1, value))
}

// MARK: - Preview

#Preview {
    HStack(spacing: Space.xl) {
        BrandLogo(size: 64)
        BrandLogo(size: 160)
    }
    .padding(Space.xl)
    .background(Brand.background)
}
