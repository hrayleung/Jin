import Foundation
import Security

/// Keychain manager for secure API key storage
actor KeychainManager {
    private let service = "com.jin.credentials"

    /// Save API key for provider
    func saveAPIKey(_ key: String, for providerID: String) throws {
        let account = keychainAccount(for: providerID)
        let data = key.data(using: .utf8)!

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// Get API key for provider
    func getAPIKey(for providerID: String) throws -> String? {
        let account = keychainAccount(for: providerID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.retrievalFailed(status: status)
        }

        return key
    }

    /// Delete API key for provider
    func deleteAPIKey(for providerID: String) throws {
        let account = keychainAccount(for: providerID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    /// Check if API key exists
    func hasAPIKey(for providerID: String) -> Bool {
        (try? getAPIKey(for: providerID)) != nil
    }

    // MARK: - Private

    func saveServiceAccountJSON(_ json: String, for providerID: String) throws {
        let account = keychainAccount(for: providerID, suffix: "_service_account")
        let data = json.data(using: .utf8)!

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    func getServiceAccountJSON(for providerID: String) throws -> String? {
        let account = keychainAccount(for: providerID, suffix: "_service_account")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.retrievalFailed(status: status)
        }

        return json
    }

    func deleteServiceAccountJSON(for providerID: String) throws {
        let account = keychainAccount(for: providerID, suffix: "_service_account")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    private func keychainAccount(for providerID: String, suffix: String = "") -> String {
        "jin_\(providerID)\(suffix)"
    }
}

/// Keychain errors
enum KeychainError: Error, LocalizedError {
    case saveFailed(status: OSStatus)
    case retrievalFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save API key to Keychain (status: \(status))"
        case .retrievalFailed(let status):
            return "Failed to retrieve API key from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete API key from Keychain (status: \(status))"
        }
    }
}
