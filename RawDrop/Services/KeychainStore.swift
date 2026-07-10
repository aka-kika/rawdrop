import Foundation
import Security

/// Small Keychain helper for the Ollama API key (never stored in UserDefaults/plist).
enum KeychainStore {
    private static let service = "com.akakika.RawDrop"

    static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: LocalizedError {
        case unhandled(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unhandled(let s): return "Keychain error (\(s))"
            }
        }
    }
}

enum OllamaSecrets {
    static let apiKeyAccount = "ollama.apiKey"

    static var apiKey: String? {
        KeychainStore.get(account: apiKeyAccount)
    }

    static func setAPIKey(_ key: String) throws {
        try KeychainStore.set(key, account: apiKeyAccount)
    }

    static func clearAPIKey() {
        KeychainStore.delete(account: apiKeyAccount)
    }
}
