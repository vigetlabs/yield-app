import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.yield.auth"
    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item first
        delete(key: key)

        // Try Data Protection Keychain first (no per-app ACLs, uses team ID)
        let dpQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecUseDataProtectionKeychain as String: true,
        ]

        var status = SecItemAdd(dpQuery as CFDictionary, nil)

        if status != errSecSuccess {
            // Fall back to legacy keychain
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ]
            status = SecItemAdd(legacyQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        lock.lock()
        cache[key] = value
        lock.unlock()
    }

    static func load(key: String) -> String? {
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached {
            return cached
        }

        // Try Data Protection Keychain first
        if let value = loadFromKeychain(key: key, dataProtection: true) {
            lock.lock()
            cache[key] = value
            lock.unlock()
            return value
        }

        // Fall back to legacy keychain
        if let value = loadFromKeychain(key: key, dataProtection: false) {
            lock.lock()
            cache[key] = value
            lock.unlock()
            return value
        }

        return nil
    }

    static func delete(key: String) {
        lock.lock()
        cache.removeValue(forKey: key)
        lock.unlock()
        deleteFromKeychain(key: key, dataProtection: true)
        deleteFromKeychain(key: key, dataProtection: false)
    }

    // MARK: - Private

    private static func loadFromKeychain(key: String, dataProtection: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private static func deleteFromKeychain(key: String, dataProtection: Bool) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        SecItemDelete(query as CFDictionary)
    }
}
