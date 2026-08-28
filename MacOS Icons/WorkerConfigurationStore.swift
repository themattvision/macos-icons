//
//  WorkerConfigurationStore.swift
//  MacOS Icons
//
//  Archivio della configurazione del Worker personale. L'URL non e' un segreto e vive
//  in UserDefaults; CLIENT_AUTH_TOKEN resta esclusivamente nel Portachiavi di macOS.
//

import Foundation
import OSLog
import Security

struct WorkerConfiguration {
    let endpoint: URL
    let token: String
}

final class WorkerConfigurationStore {
    private static let endpointDefaultsKey = "macosicons.workerURL"
    private static let legacyAPIKeyDefaultsKey = "macosicons.apiKey"

    private let service = "com.matteozampieri.macosicons"
    private let tokenAccount = "client-auth-token"
    private let legacyAPIKeyAccount = "macosicons-api-key"
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "com.matteozampieri.macosicons", category: "credentials")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        removeLegacyAPIKey()
    }

    func load() -> WorkerConfiguration? {
        guard
            let endpointString = defaults.string(forKey: Self.endpointDefaultsKey),
            let endpoint = URL(string: endpointString),
            let token = try? read(account: tokenAccount),
            !token.isEmpty
        else {
            return nil
        }

        return WorkerConfiguration(endpoint: endpoint, token: token)
    }

    func save(_ configuration: WorkerConfiguration) throws {
        try write(configuration.token, account: tokenAccount)
        defaults.set(configuration.endpoint.absoluteString, forKey: Self.endpointDefaultsKey)
    }

    private func removeLegacyAPIKey() {
        defaults.removeObject(forKey: Self.legacyAPIKeyDefaultsKey)
        do {
            try delete(account: legacyAPIKeyAccount)
        } catch {
            log.error("Pulizia della vecchia chiave API fallita: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func write(_ value: String, account: String) throws {
        let encodedValue = Data(value.utf8)
        let lookup = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: encodedValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = lookup
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        default:
            throw KeychainError.status(updateStatus)
        }
    }

    private func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private enum KeychainError: LocalizedError {
    case invalidData
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return String(localized: "Il token salvato nel Portachiavi non è leggibile.")
        case .status(let status):
            return SecCopyErrorMessageString(status, nil) as String?
                ?? String(localized: "Errore Portachiavi (codice \(status)).")
        }
    }
}
