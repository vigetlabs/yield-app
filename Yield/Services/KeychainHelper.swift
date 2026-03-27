import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.yield.auth"
    private static var cache: [String: String] = [:]

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        // Delete from both legacy and Data Protection keychains
        deleteLegacy(key: key)
        deleteDataProtection(key: key)

        // Save to Data Protection Keychain (no per-app ACLs, uses team ID)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecUseDataProtectionKeychain as String: true,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        cache[key] = value
    }

    static func load(key: String) -> String? {
        if let cached = cache[key] {
            return cached
        }

        // Try Data Protection Keychain first
        if let value = loadDataProtection(key: key) {
            cache[key] = value
            return value
        }

        // Fall back to legacy keychain (migrates on next save)
        if let value = loadLegacy(key: key) {
            cache[key] = value
            // Migrate to Data Protection Keychain
            try? save(key: key, value: value)
            return value
        }

        return nil
    }

    static func delete(key: String) {
        cache.removeValue(forKey: key)
        deleteLegacy(key: key)
        deleteDataProtection(key: key)
    }

    // MARK: - Data Protection Keychain

    private static func loadDataProtection(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func deleteDataProtection(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Legacy Keychain (for migration)

    private static func loadLegacy(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func deleteLegacy(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
