// SecureStore.swift
// Private Judges Workspace - encrypted local storage primitives.
//
// Security model (requirement: "secure local storage"):
//   - a 256-bit AES-GCM key is generated on first use and kept in the
//     Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
//   - every on-device record/assessment/workspace document and image blob is
//     stored as AES-GCM sealed data; digests and identity checks still apply
//     on load
//   - the access PIN is never stored; only a PBKDF2 verifier (AuthGate.swift)
//   - exports are explicit user actions; exported JSON is the canonical
//     interchange format verified by the Python reference tools

import Foundation
import CryptoKit
import Security

// MARK: - Keychain wrapper

enum Keychain {
    static func save(_ data: Data, account: String, service: String) -> Bool {
        SecItemDelete([String(kSecClass): kSecClassGenericPassword,
                       String(kSecAttrService): service,
                       String(kSecAttrAccount): account] as CFDictionary)
        let attrs: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrService): service,
            String(kSecAttrAccount): account,
            String(kSecValueData): data,
            String(kSecAttrAccessible): kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String, service: String) -> Data? {
        let query: [String: Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrService): service,
            String(kSecAttrAccount): account,
            String(kSecReturnData): true,
            String(kSecMatchLimit): kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess ? (item as? Data) : nil
    }

    static func delete(account: String, service: String) {
        SecItemDelete([String(kSecClass): kSecClassGenericPassword,
                       String(kSecAttrService): service,
                       String(kSecAttrAccount): account] as CFDictionary)
    }
}

// MARK: - AES-GCM vault

enum VaultError: Error {
    case sealFailed
    case openFailed
    case keyUnavailable
}

struct Vault {
    let key: SymmetricKey

    func seal(_ data: Data) throws -> Data {
        guard let combined = try? AES.GCM.seal(data, using: key).combined else {
            throw VaultError.sealFailed
        }
        return combined
    }

    func open(_ data: Data) throws -> Data {
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else {
            throw VaultError.openFailed
        }
        return plain
    }

    /// Device-backed vault: key persisted in the Keychain.
    static func deviceVault(service: String = "PrivateJudgesWorkspace.vault") throws -> Vault {
        if let stored = Keychain.load(account: "store-key", service: service),
           stored.count == 32 {
            return Vault(key: SymmetricKey(data: stored))
        }
        var raw = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &raw) == errSecSuccess,
              Keychain.save(Data(raw), account: "store-key", service: service) else {
            throw VaultError.keyUnavailable
        }
        return Vault(key: SymmetricKey(data: Data(raw)))
    }

    /// Ephemeral vault for tests / transient use (never persisted).
    static func ephemeralVault() -> Vault {
        Vault(key: SymmetricKey(size: .bits256))
    }
}
