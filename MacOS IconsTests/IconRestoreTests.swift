//
//  IconRestoreTests.swift
//  MacOS IconsTests
//
//  Copre il ciclo applica/ripristina di IconApplier su un bundle .app usa e getta.
//  Il caso che conta e' il terzo test: la vetrina di conferma dura 1,6s e prima
//  la UI ci appoggiava sopra la comparsa del bottone "Ripristina icona originale",
//  che quindi spariva da solo un secondo e mezzo dopo aver applicato l'icona.
//

import Testing
import Foundation
import AppKit
@testable import MacOS_Icons

@MainActor
struct IconRestoreTests {

    // MARK: - Attrezzatura

    /// Bundle .app minimale in una cartella temporanea: a NSWorkspace.setIcon basta
    /// una cartella con estensione .app e permesso di scrittura, non serve un'app vera.
    private static func makeTestApp() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("icon-restore-\(UUID().uuidString)")
        let app = dir.appendingPathComponent("Bersaglio.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>test.icon.restore</string>
        <key>CFBundleExecutable</key><string>Bersaglio</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        </dict></plist>
        """
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"),
                        atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: app.appendingPathComponent("Contents/MacOS/Bersaglio"),
                                        atomically: true, encoding: .utf8)
        return app
    }

    /// IconItem non ha init pubblico (si costruisce solo da Decoder), quindi lo si
    /// crea dal JSON come farebbe la risposta dell'API. Gli url puntano a un PNG
    /// locale: cosi' il test non dipende dalla rete.
    private static func makeIcon(pointingAt fileURL: URL) throws -> IconItem {
        let json = """
        {
            "objectID": "test-1",
            "appName": "Icona di prova",
            "timeStamp": "2026-08-24T00:00:00Z",
            "icnsUrl": "\(fileURL.absoluteString)",
            "iOSUrl": null,
            "lowResPngUrl": "\(fileURL.absoluteString)",
            "category": null,
            "downloads": 1,
            "credit": null,
            "uploadedBy": null,
            "usersName": null
        }
        """
        return try JSONDecoder().decode(IconItem.self, from: Data(json.utf8))
    }

    /// PNG rosa su disco, usato come icona da applicare.
    private static func makePNG() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("icona-\(UUID().uuidString).png")
        let image = NSImage(size: NSSize(width: 256, height: 256))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSRect(x: 0, y: 0, width: 256, height: 256).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
        return url
    }

    /// Il file "Icon\r" dentro il bundle e' la prova su disco che l'icona e'
    /// personalizzata: setIcon lo crea, setIcon(nil) lo rimuove.
    private static func hasCustomIconFile(_ app: URL) -> Bool {
        FileManager.default.fileExists(atPath: app.appendingPathComponent("Icon\r").path)
    }

    // MARK: - Test

    @Test("Applicare un'icona scrive la personalizzazione sul bundle")
    func applyWritesCustomIcon() async throws {
        let app = try Self.makeTestApp()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let applier = IconApplier()
        #expect(applier.attach(url: app) == true)
        #expect(applier.canRestoreCurrentTarget == false, "un bersaglio appena agganciato non ha nulla da ripristinare")

        await applier.apply(icon: try Self.makeIcon(pointingAt: try Self.makePNG()))

        #expect(applier.phase == .applied)
        #expect(Self.hasCustomIconFile(app), "il file Icon\\r deve esistere dopo l'applicazione")
    }

    @Test("Il ripristino rimuove la personalizzazione dal bundle")
    func restoreRemovesCustomIcon() async throws {
        let app = try Self.makeTestApp()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let applier = IconApplier()
        applier.attach(url: app)
        await applier.apply(icon: try Self.makeIcon(pointingAt: try Self.makePNG()))
        #expect(Self.hasCustomIconFile(app))

        await applier.restoreOriginalIcon()

        #expect(applier.phase == .restored)
        #expect(Self.hasCustomIconFile(app) == false, "dopo il ripristino il file Icon\\r non deve piu' esistere")
        #expect(applier.canRestoreCurrentTarget == false, "ripristinato una volta, non c'e' piu' niente da ripristinare")
    }

    @Test("Il ripristino resta disponibile dopo che la conferma e' scaduta")
    func restoreStaysAvailableAfterConfirmationExpires() async throws {
        let app = try Self.makeTestApp()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let applier = IconApplier()
        applier.attach(url: app)
        await applier.apply(icon: try Self.makeIcon(pointingAt: try Self.makePNG()))
        #expect(applier.canRestoreCurrentTarget, "subito dopo l'applicazione il ripristino e' offerto")

        // Oltre i 1,6s della vetrina di conferma: la fase torna a riposo da sola.
        try await Task.sleep(for: .seconds(2.5))

        #expect(applier.phase == .idle, "la conferma transitoria e' scaduta come previsto")
        #expect(applier.canRestoreCurrentTarget,
                "il ripristino deve restare offerto anche dopo la scadenza della conferma")

        // E deve funzionare davvero, non solo essere visibile.
        await applier.restoreOriginalIcon()
        #expect(Self.hasCustomIconFile(app) == false)
    }
}
