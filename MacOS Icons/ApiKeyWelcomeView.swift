//
//  ApiKeyWelcomeView.swift
//  MacOS Icons
//
//  Prima configurazione del Worker personale. URL e token vengono verificati con /health
//  prima di essere salvati e prima che l'app mostri il catalogo.
//

import SwiftUI

struct WorkerSetupView: View {
    let onSaved: () -> Void

    @EnvironmentObject private var searchService: IconSearchService
    @State private var draftURL = ""
    @State private var draftToken = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case url
        case token
    }

    private let contentWidth: CGFloat = 520

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer(minLength: 0)
            brandHeader
            stepsCard
            configurationForm
            Text("Potrai cambiare Worker e token in qualsiasi momento dalle Impostazioni (⌘,).")
                .font(Font.cellMeta)
                .foregroundStyle(Brand.textMuted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: contentWidth)
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var brandHeader: some View {
        VStack(spacing: Space.md) {
            BrandLogo(size: 56)

            VStack(spacing: Space.xs) {
                Text("Collega il tuo Worker")
                    .font(Font.heroTitle)
                    .foregroundStyle(Brand.text)
                    .multilineTextAlignment(.center)

                Text("L’app open source interroga solo il Worker Cloudflare che controlli tu. Il token resta nel Portachiavi di questo Mac.")
                    .font(Font.heroSubtitle)
                    .foregroundStyle(Brand.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            step(number: 1, text: String(localized: "Pubblica il Worker incluso nel progetto"))
            step(number: 2, text: String(localized: "Copia il suo URL HTTPS"))
            step(number: 3, text: String(localized: "Incolla lo stesso CLIENT_AUTH_TOKEN configurato nel Worker"))
        }
        .padding(Space.md)
        .surface(radius: Radius.lg)
    }

    private func step(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Text(verbatim: "\(number)")
                .font(Font.cellLabel)
                .foregroundStyle(Brand.accent)
                .frame(width: Space.lg, height: Space.lg)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            Text(text)
                .font(Font.heroSubtitle)
                .foregroundStyle(Brand.text)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Passo \(number): \(text)")
    }

    private var configurationForm: some View {
        VStack(spacing: Space.md) {
            TextField("https://tuo-worker.workers.dev", text: $draftURL)
                .configurationFieldStyle(isFocused: focusedField == .url)
                .focused($focusedField, equals: .url)
                .accessibilityLabel("URL HTTPS del Worker")

            SecureField("CLIENT_AUTH_TOKEN", text: $draftToken)
                .configurationFieldStyle(isFocused: focusedField == .token)
                .focused($focusedField, equals: .token)
                .onSubmit { validateAndSave() }
                .accessibilityLabel("CLIENT_AUTH_TOKEN")

            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle.fill")
                    .font(Font.cellMeta)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                validateAndSave()
            } label: {
                if isValidating {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Verifico il Worker…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Verifica e salva")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.accent)
            .controlSize(.large)
            .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            .disabled(isValidating || draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftToken.isEmpty)
        }
    }

    private func validateAndSave() {
        guard !isValidating else { return }
        isValidating = true
        validationError = nil

        Task {
            do {
                try await searchService.validateAndSaveConfiguration(workerURL: draftURL, token: draftToken)
                onSaved()
            } catch {
                validationError = (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "Configurazione non riuscita. Controlla i dati e riprova.")
            }
            isValidating = false
        }
    }
}

private extension View {
    func configurationFieldStyle(isFocused: Bool) -> some View {
        self
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Brand.text)
            .padding(Space.sm)
            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isFocused ? Brand.accent : Brand.stroke, lineWidth: 1)
            )
            .accentGlow(isFocused)
            .animation(Animation.ui, value: isFocused)
    }
}

#Preview {
    WorkerSetupView(onSaved: {})
        .environmentObject(IconSearchService())
        .frame(width: 900, height: 700)
        .background(Color.black)
}
