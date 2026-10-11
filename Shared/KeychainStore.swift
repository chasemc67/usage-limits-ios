import Foundation
import Security

/// Minimal generic-password Keychain wrapper using a shared access group so the
/// widget extension can read tokens written by the app.
enum KeychainStore {
    static let service = "com.AnomalousResearch.UsageLimits"
    static let accessGroup = "XPU32D9V4J.com.AnomalousResearch.UsageLimits.shared"

    @discardableResult
    static func save(_ key: String, _ value: String) -> Bool {
        var status = save(key, value, useAccessGroup: true)
        if status == errSecMissingEntitlement {
            // Unsigned / misconfigured builds: fall back to the app's default group.
            status = save(key, value, useAccessGroup: false)
        }
        return status == errSecSuccess
    }

    static func read(_ key: String) -> String? {
        let (value, status) = read(key, useAccessGroup: true)
        if status == errSecMissingEntitlement {
            return read(key, useAccessGroup: false).0
        }
        return value
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key, useAccessGroup: true) as CFDictionary)
        SecItemDelete(baseQuery(key, useAccessGroup: false) as CFDictionary)
    }

    // MARK: - Private

    private static func baseQuery(_ key: String, useAccessGroup: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if useAccessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func save(_ key: String, _ value: String, useAccessGroup: Bool) -> OSStatus {
        let query = baseQuery(key, useAccessGroup: useAccessGroup)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        return status
    }

    private static func read(_ key: String, useAccessGroup: Bool) -> (String?, OSStatus) {
        var query = baseQuery(key, useAccessGroup: useAccessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return (nil, status)
        }
        return (String(data: data, encoding: .utf8), status)
    }
}
