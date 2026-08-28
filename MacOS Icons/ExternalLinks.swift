//
//  ExternalLinks.swift
//  MacOS Icons
//
//  Gli indirizzi esterni a cui l'app manda l'utente, in un posto solo. Stavano
//  scritti a mano in piu' viste: bastava che il sito cambiasse il percorso della
//  dashboard per doverli inseguire uno per uno, dimenticandone qualcuno.
//

import Foundation

enum ExternalLinks {
    /// Home del catalogo, aperta dal menu contestuale di un'icona.
    static let website = URL(string: "https://macosicons.com")!
}
