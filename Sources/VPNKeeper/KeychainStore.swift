import Foundation
import LocalAuthentication
import Security
import VPNCore

enum KeychainStore {
    static let service = "kz.local.VPNKeeper.credentials"
    static let account = "default-profile"
    static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    static func load(interactive: Bool) throws -> VaultEntry? {
        // This app's Keychain calls are serialized on the main actor. The legacy
        // login-keychain ACL also needs its process-level interaction switch:
        // query-level LAContext/UI flags alone can still wait for SecurityAgent.
        let interactionStatus = SecKeychainSetUserInteractionAllowed(interactive)
        guard interactionStatus == errSecSuccess else { throw failure(interactionStatus) }
        defer { SecKeychainSetUserInteractionAllowed(true) }
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        if !interactive {
            let context = LAContext()
            context.interactionNotAllowed = true
            q[kSecUseAuthenticationContext as String] = context
            // Legacy login-keychain ACL prompts can ignore LAContext alone.
            // Retain the legacy no-UI flag too so background reads fail rather than hang.
            q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        do { return try JSONDecoder().decode(VaultEntry.self, from: data) } catch {
            throw KeeperError("Сохранённые данные повреждены. Импортируйте QR и пароль заново.")
        }
    }

    static func save(_ entry: VaultEntry) throws {
        let data = try JSONEncoder().encode(entry)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            for (key, value) in attributes { q[key] = value }
            q[kSecAttrLabel as String] = "VPN Keeper — пароль и TOTP"
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess {
            throw failure(status)
        }
    }

    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    private static func failure(_ status: OSStatus) -> KeeperError {
        KeeperError("Связка ключей недоступна (код \(status)). Разблокируйте macOS и сохраните настройки вручную.")
    }
}
