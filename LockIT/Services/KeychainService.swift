import Foundation
import LocalAuthentication
import Security

enum KeychainError: Error {
    case keyGenerationFailed(OSStatus)
    case itemNotFound
    case unexpectedData
    case unhandled(OSStatus)
}

final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    private func accessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let ac = SecAccessControlCreateWithFlags(nil,
                                                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                       [.biometryCurrentSet],
                                                       &error) else {
            throw error!.takeRetainedValue() as Error
        }
        return ac
    }

    func storeKey(_ key: Data, account: String) throws {
        print("🔑 Storing key for account: \(account)")
        
        // Simplified keychain storage without access control for now
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "LockIT",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: key
        ]
        
        print("🗑️ Deleting existing key if present...")
        SecItemDelete(query as CFDictionary)
        
        print("💾 Adding new key to keychain...")
        let status = SecItemAdd(query as CFDictionary, nil)
        print("📊 Keychain add status: \(status)")
        
        guard status == errSecSuccess else { 
            print("❌ Keychain store failed with status: \(status)")
            throw KeychainError.unhandled(status) 
        }
        print("✅ Key stored successfully")
    }

    func retrieveKey(account: String, context: LAContext) throws -> Data {
        print("🔍 Retrieving key for account: \(account)")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "LockIT",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        print("📊 Keychain retrieve status: \(status)")
        
        if status == errSecItemNotFound { 
            print("❌ Key not found in keychain")
            throw KeychainError.itemNotFound 
        }
        guard status == errSecSuccess, let data = item as? Data else {
            print("❌ Keychain retrieve failed with status: \(status)")
            throw KeychainError.unhandled(status)
        }
        print("✅ Key retrieved successfully")
        return data
    }
}

