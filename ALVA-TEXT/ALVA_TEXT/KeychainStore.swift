import Foundation
import Security

/// Tiny wrapper around the macOS generic-password Keychain API.
/// Replaces the previous `UserDefaults` storage for the OpenAI API key so
/// the secret is no longer written in cleartext to the app's preferences plist.
enum KeychainStore {
    /// Service identifier used for every ALVA-TEXT Keychain item.
    private static let service = "com.alva.text"

    /// Writes (or deletes, when `value` is empty) the string for `account`.
    /// Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so the value
    /// is not synced to iCloud Keychain and stays on this Mac.
    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        if value.isEmpty {
            return delete(account: account)
        }

        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }

        return false
    }

    /// Reads the string for `account`, or `nil` if it was never stored.
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Deletes the value for `account`. Returns `true` if the item is gone
    /// afterwards (whether or not it existed before).
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
