import Foundation
import Security

enum PreferenceSecretStoreError: LocalizedError {
    case invalidUTF8
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "Stored secret could not be decoded."
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain error (\(status))."
        }
    }
}

enum PreferenceSecretStore {
    private static let service = "com.jin.app.preference-secrets"

    static func loadSecret(forKey key: String, defaults: UserDefaults = .standard) -> String {
        let normalizedKey = normalizedPreferenceKey(key)
        guard !normalizedKey.isEmpty else { return "" }

        let legacyValue = trimmed(defaults.string(forKey: normalizedKey))
        if !legacyValue.isEmpty {
            do {
                try saveSecret(legacyValue, forKey: normalizedKey, defaults: defaults)
            } catch {
                NSLog("[Jin.SecretStore] Failed to migrate %@ to Keychain: %@", normalizedKey, error.localizedDescription)
                return legacyValue
            }
            return legacyValue
        }

        do {
            return try keychainValue(forKey: normalizedKey) ?? ""
        } catch {
            NSLog("[Jin.SecretStore] Failed to load %@ from Keychain: %@", normalizedKey, error.localizedDescription)
            return ""
        }
    }

    static func hasSecret(forKey key: String, defaults: UserDefaults = .standard) -> Bool {
        !loadSecret(forKey: key, defaults: defaults).isEmpty
    }

    static func saveSecret(_ value: String, forKey key: String, defaults: UserDefaults = .standard) throws {
        let normalizedKey = normalizedPreferenceKey(key)
        guard !normalizedKey.isEmpty else { return }

        let trimmedValue = trimmed(value)
        if trimmedValue.isEmpty {
            try deleteSecret(forKey: normalizedKey, defaults: defaults)
            return
        }

        let data = Data(trimmedValue.utf8)
        let query = keychainQuery(forKey: normalizedKey)

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            defaults.removeObject(forKey: normalizedKey)
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw PreferenceSecretStoreError.unexpectedStatus(addStatus)
            }
            defaults.removeObject(forKey: normalizedKey)
        default:
            throw PreferenceSecretStoreError.unexpectedStatus(updateStatus)
        }
    }

    static func deleteSecret(forKey key: String, defaults: UserDefaults = .standard) throws {
        let normalizedKey = normalizedPreferenceKey(key)
        guard !normalizedKey.isEmpty else { return }

        defaults.removeObject(forKey: normalizedKey)

        let status = SecItemDelete(keychainQuery(forKey: normalizedKey) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PreferenceSecretStoreError.unexpectedStatus(status)
        }
    }

    private static func keychainValue(forKey key: String) throws -> String? {
        var query = keychainQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            guard let value = String(data: data, encoding: .utf8) else {
                throw PreferenceSecretStoreError.invalidUTF8
            }
            return trimmed(value).isEmpty ? nil : trimmed(value)
        case errSecItemNotFound:
            return nil
        default:
            throw PreferenceSecretStoreError.unexpectedStatus(status)
        }
    }

    private static func keychainQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private static func normalizedPreferenceKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
