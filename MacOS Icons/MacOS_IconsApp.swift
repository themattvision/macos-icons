//
//  MacOS_IconsApp.swift
//  MacOS Icons
//
//  Created by Matteo Zampieri on 14/09/25.
//

import SwiftUI

@main
struct MacOS_IconsApp: App {
    // Un'unica istanza mantiene allineate finestra principale e Impostazioni. La chiave
    // personale resta nel Portachiavi e non viene duplicata in UserDefaults.
    @StateObject private var searchService = IconSearchService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(searchService)
        }
        .defaultSize(width: 1000, height: 680)
        .windowToolbarStyle(.unified)

        // Pannello Impostazioni di sistema, raggiungibile con Cmd+, dal menu applicazione.
        Settings {
            SettingsView()
                .environmentObject(searchService)
        }
    }
}
