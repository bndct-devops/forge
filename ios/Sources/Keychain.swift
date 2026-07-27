import Foundation
import Security

/// Minimal Keychain wrapper — the PAT lives here instead of UserDefaults.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "dev.bndct.forge.companion",
         kSecAttrAccount as String: key]
    }

    static func set(_ value: String, key: String) {
        let data = Data(value.utf8)
        var q = query(key)
        if SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }

    /// One-time move of the token out of UserDefaults (pre-Keychain builds).
    static func migrateTokenFromDefaults() {
        let defaults = UserDefaults.standard
        if let legacy = defaults.string(forKey: "forge_token"), !legacy.isEmpty {
            set(legacy, key: "forge_token")
            defaults.removeObject(forKey: "forge_token")
        }
    }
}
