//
//  DesignSystem.swift
//  MacOS Icons
//
//  Vocabolario visivo condiviso da tutte le viste, allineato al brand di macosicons.com:
//  fondo nero profondo, aloni blu e viola molto diffusi negli angoli, accento blu elettrico,
//  forme a pillola e superfici scure appena staccate dal fondo.
//  Nessun valore di spaziatura, colore o tipografia va scritto a mano altrove: si pesca da qui.
//

import SwiftUI

// MARK: - Spaziatura

/// Scala di spaziatura a base 4. Qualunque valore fuori da questa scala e' un errore, non una scelta.
enum Space {
    /// 4 — distanza fra elementi che si toccano (icona e sua etichetta)
    static let xxs: CGFloat = 4
    /// 8 — gap interni di un controllo compatto
    static let xs: CGFloat = 8
    /// 12 — separazione fra righe correlate
    static let sm: CGFloat = 12
    /// 16 — padding standard di un componente
    static let md: CGFloat = 16
    /// 24 — respiro fra gruppi distinti
    static let lg: CGFloat = 24
    /// 32 — margine di una vista principale
    static let xl: CGFloat = 32
    /// 48 — stacco fra sezioni di primo livello
    static let xxl: CGFloat = 48
}

// MARK: - Raggi

enum Radius {
    /// 6 — chip e badge
    static let sm: CGFloat = 6
    /// 10 — celle e controlli
    static let md: CGFloat = 10
    /// 16 — superfici grandi e schede
    static let lg: CGFloat = 16
    /// 22 — anteprima icona in evidenza (proporzione da app icon macOS)
    static let icon: CGFloat = 22
    /// 24 — pannello grande che occupa la testa di una schermata (la zona di trascinamento).
    /// Sopra i 20 pt il raggio smette di leggersi come "controllo" e inizia a leggersi come
    /// "superficie", che e' esattamente il ruolo di quel pannello.
    static let xl: CGFloat = 24
    /// 999 — pillola piena, la forma dei controlli del sito
    static let pill: CGFloat = 999
}

// MARK: - Palette del brand

/// Colori estratti dal sito ufficiale. Sono fissi e non semantici di sistema, perche' l'app
/// adotta un tema scuro proprio come il sito invece di seguire chiaro/scuro di macOS.
enum Brand {
    /// #000000 — fondo della finestra
    static let background = Color(red: 0, green: 0, blue: 0)
    /// #0E0F12 — superficie appena staccata dal fondo (sidebar, schede)
    static let surface = Color(red: 0.055, green: 0.059, blue: 0.071)
    /// #181A1C — superficie in rilievo (cella in hover, campo di ricerca)
    static let surfaceRaised = Color(red: 0.094, green: 0.102, blue: 0.110)
    /// #3B82F6 — blu d'accento, quello dei bottoni del sito
    static let accent = Color(red: 0.231, green: 0.510, blue: 0.965)
    /// #68CCFA — ciano di supporto, usato per i bagliori
    static let cyan = Color(red: 0.408, green: 0.800, blue: 0.980)
    /// #4B0082 — viola profondo dell'alone a destra della pagina
    static let violet = Color(red: 0.294, green: 0.0, blue: 0.510)
    /// Testo primario
    static let text = Color.white
    /// Testo secondario, come i metadati sotto le icone del sito
    static let textMuted = Color.white.opacity(0.55)
    /// Bordo sottile delle superfici scure
    static let stroke = Color.white.opacity(0.08)
}

// MARK: - Tipografia

/// Il sito usa Inter. Qui si usa il font di sistema, che alle dimensioni dell'interfaccia
/// e' praticamente sovrapponibile e porta gia' tracking ottico e leggibilita' corretti,
/// senza dover imbarcare un font nel bundle.
extension Font {
    /// Titolo grande, con tracking negativo come le display del sito
    static let appTitle = Font.system(size: 28, weight: .bold)
    /// Intestazione di sezione nella sidebar
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    /// Nome dell'icona sotto la cella della griglia
    static let cellLabel = Font.system(size: 12, weight: .semibold)
    /// Riga secondaria sotto il nome (l'autore): un gradino sotto il titolo, non un
    /// metadato minuscolo. Sta in mezzo fra cellLabel e cellMeta e crea i tre livelli.
    static let cellSubtitle = Font.system(size: 11, weight: .regular)
    /// Metadato terziario: data, download, contatori
    static let cellMeta = Font.system(size: 10, weight: .regular)
    /// Valore numerico in evidenza
    static let metric = Font.system(size: 15, weight: .semibold)
    /// Titolo di un pannello d'invito (zona di trascinamento, selettore app): sta fra il
    /// titolo di schermata e l'etichetta di cella, perche' deve farsi leggere da lontano
    /// senza competere con `appTitle`, che resta il gradino piu' alto.
    static let heroTitle = Font.system(size: 20, weight: .semibold)
    /// Riga di supporto sotto `heroTitle`: piu' grande di `cellMeta` perche' qui e' una
    /// vera istruzione da leggere, non un metadato di servizio.
    static let heroSubtitle = Font.system(size: 13, weight: .regular)
}

// MARK: - Superfici e colori semantici

extension ShapeStyle where Self == Color {
    /// Fondo di una cella della griglia
    static var cellFill: Color { Brand.surface }
    /// Fondo dell'area contenuti principale
    static var canvas: Color { Brand.background }
    /// Separatore sottile
    static var hairline: Color { Brand.stroke }
}

// MARK: - Animazioni

/// Molle di sistema. Il default e' critically damped (nessun rimbalzo): il rimbalzo si usa
/// solo dove il gesto dell'utente ha portato con se' della velocita'.
extension Animation {
    /// Transizione standard di stato (hover, selezione, comparsa)
    static let ui = Animation.spring(response: 0.32, dampingFraction: 1.0)
    /// Reazione a un gesto diretto (drag, rilascio)
    static let gesture = Animation.spring(response: 0.36, dampingFraction: 0.8)

    /// Feedback di pressione. Qui NON si usa una molla: una pressione deve atterrare entro
    /// 160 ms e anche una molla critically damped a quella velocita' lascia una coda visibile,
    /// che su un click ripetuto si legge come lentezza.
    static let press = Animation.easeOut(duration: 0.14)

    /// Dissolvenza fra due contenuti che si sostituiscono (immagine che arriva, formato che
    /// cambia, griglia che si aggiorna). Solo opacita': niente da smorzare, quindi curva.
    static let fade = Animation.easeOut(duration: 0.22)

    /// Versione accorciata di `fade` per quando Riduci movimento e' attivo: la dissolvenza
    /// resta (un taglio secco sarebbe piu' brusco, non piu' accessibile) ma dura meno.
    static let fadeReduced = Animation.easeOut(duration: 0.12)

    /// Comparsa in cascata degli elementi di una griglia.
    /// Con `reduceMotion` la cascata sparisce del tutto: niente ritardo per indice e niente
    /// molla, resta solo una dissolvenza breve. Cinquanta celle che entrano scalate a scacchiera
    /// sono esattamente quello che l'impostazione di sistema chiede di non fare.
    static func stagger(_ index: Int, reduceMotion: Bool = false) -> Animation {
        guard !reduceMotion else { return .fadeReduced }
        return .spring(response: 0.42, dampingFraction: 0.9)
            .delay(Double(min(index, 24)) * 0.012)
    }
}

// MARK: - Stile di pressione

/// Feedback di pressione per i target costruiti a mano (celle della griglia, righe della sidebar).
/// Prima erano `.onTapGesture`, che su macOS scatta al rilascio e durante la pressione non
/// mostra niente: qui la label rientra appena e si smorza, e torna al rilascio.
///
/// La scala e' volutamente piccola: sono elementi cliccati decine di volte in una sessione di
/// browsing, quindi il movimento deve essere ai limiti del percepibile. Con Riduci movimento
/// resta solo il calo di opacita', che il feedback lo da' comunque.
struct PressableCellStyle: ButtonStyle {
    /// 0.97 su una cella da 150 pt sono circa 4,5 pt di corsa. Le righe larghe e basse della
    /// sidebar passano 0.98, perche' alla loro larghezza 0.97 diventa uno scivolamento laterale.
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, pressedScale: pressedScale)
    }

    /// Vista interna: un `ButtonStyle` non e' una `View`, quindi `@Environment` dichiarato
    /// direttamente sulla struct dello stile non viene popolato in modo affidabile.
    /// Non si puo' chiamare `Body`: quello e' il tipo associato di `ButtonStyle` e Swift la
    /// prenderebbe per l'implementazione del requisito, pretendendola non privata.
    private struct PressBody: View {
        let configuration: ButtonStyleConfiguration
        let pressedScale: CGFloat

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
                .animation(.press, value: configuration.isPressed)
        }
    }
}

// MARK: - Sfondo del brand

/// Il fondo del sito: nero pieno con due aloni molto larghi e molto tenui, uno blu in alto a
/// sinistra e uno viola a destra, che respirano lentamente. Va messo sotto tutto il contenuto.
struct BrandBackground: View {
    /// Fase dell'animazione di respiro, avanza da sola una volta comparsa la vista
    @State private var drift = false
    /// Con Riduci movimento attivo gli aloni restano fermi: nessuna oscillazione lenta a schermo pieno
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Brand.background

            halo(Brand.accent.opacity(0.22), size: 720)
                .offset(x: -260, y: drift ? -240 : -190)

            halo(Brand.violet.opacity(0.30), size: 820)
                .offset(x: 300, y: drift ? 190 : 250)

            halo(Brand.cyan.opacity(0.10), size: 520)
                .offset(x: 120, y: drift ? -60 : -20)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    /// Un alone morbido: cerchio sfumato con blur pesante, come le luci di fondo della pagina
    private func halo(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 60)
    }
}

// MARK: - Modificatori riusabili

extension View {
    /// Superficie scura del brand: fondo appena staccato dal nero piu' un bordo sottile.
    func surface(radius: CGFloat = Radius.lg) -> some View {
        background(Brand.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Brand.stroke, lineWidth: 1)
            )
    }

    /// Applica una forma ad angoli continui (la curvatura corretta su macOS, non il cerchio).
    func continuousCorners(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Bagliore d'accento dietro un elemento attivo, come l'alone dei bottoni del sito.
    func accentGlow(_ active: Bool, color: Color = Brand.accent) -> some View {
        shadow(color: active ? color.opacity(0.45) : .clear, radius: active ? 14 : 0, y: 2)
    }
}
