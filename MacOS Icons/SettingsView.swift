//
//  SettingsView.swift
//  MacOS Icons
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var searchService: IconSearchService
    @State private var workerURL = ""
    @State private var token = ""
    @State private var isValidating = false
    @State private var validationError: String?

    var body: some View {
        Form {
            Section("Worker personale") {
                TextField("https://tuo-worker.workers.dev", text: $workerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                SecureField("CLIENT_AUTH_TOKEN", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { validateAndSave() }

                Text("L’URL viene salvato nelle preferenze. Il token resta nel Portachiavi e non viene mai mostrato o scritto nei file dell’app.")
                    .font(Font.cellMeta)
                    .foregroundStyle(Brand.textMuted)

                if searchService.isConfigured {
                    Label("Worker verificato e configurato", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle.fill")
                        .font(Font.cellMeta)
                        .foregroundStyle(.orange)
                }

                Button {
                    validateAndSave()
                } label: {
                    if isValidating {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Verifico il Worker…")
                        }
                    } else {
                        Text("Verifica e salva")
                    }
                }
                .disabled(isValidating || workerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || token.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
        .scrollContentBackground(.hidden)
        .background(Brand.background)
        .preferredColorScheme(.dark)
        .onAppear {
            workerURL = searchService.workerURLString
        }
    }

    private func validateAndSave() {
        guard !isValidating else { return }
        isValidating = true
        validationError = nil

        Task {
            do {
                try await searchService.validateAndSaveConfiguration(workerURL: workerURL, token: token)
                workerURL = searchService.workerURLString
                token = ""
            } catch {
                validationError = (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "Configurazione non riuscita. Controlla i dati e riprova.")
            }
            isValidating = false
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(IconSearchService())
}
