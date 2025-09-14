import Foundation
import LocalAuthentication
import CryptoKit

enum FolderLockError: Error, LocalizedError {
    case bookmarkResolutionFailed
    case keyMissing
    case lockAlreadyLocked
    case unlockAlreadyUnlocked

    var errorDescription: String? {
        switch self {
        case .bookmarkResolutionFailed: return "Unable to access the selected folder."
        case .keyMissing: return "Encryption key missing. Re-register folder."
        case .lockAlreadyLocked: return "Folder is already locked."
        case .unlockAlreadyUnlocked: return "Folder is already unlocked."
        }
    }
}

final class FolderLockService {
    static let shared = FolderLockService()
    private init() {}

    func accountId(for folder: RegisteredFolder) -> String {
        "com.ethan.LockIT.key." + folder.id.uuidString
    }
    
    // Generate a deterministic account ID based on folder path for recovery
    func recoveryAccountId(for folderPath: String) -> String {
        // Use a hash of the folder path to create a consistent identifier
        let pathData = folderPath.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: pathData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return "com.ethan.LockIT.recovery." + hashString
    }

    private func resolveFolderURL(from folder: RegisteredFolder) -> URL? {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: folder.bookmarkData,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            return url
        } catch {
            print("❌ Failed to resolve bookmark: \(error)")
            return nil
        }
    }

    private func withSecurityScopedAccess<T>(url: URL, _ work: () throws -> T) rethrows -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try work()
    }

    func isLocked(folder: RegisteredFolder) -> Bool {
        guard let folderURL = resolveFolderURL(from: folder) else { 
            print("❌ Cannot resolve folder URL for \(folder.name), returning stored state: \(folder.isLocked)")
            return folder.isLocked 
        }
        let parent = folderURL.deletingLastPathComponent()
        let lockURL = parent.appendingPathComponent(folder.name + ".lockit")
        var isDir: ObjCBool = false
        let folderExists = FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir) && isDir.boolValue
        let lockExists = FileManager.default.fileExists(atPath: lockURL.path)
        let locked = lockExists && !folderExists
        print("🔍 Lock check for \(folder.name): folder exists=\(folderExists), lock exists=\(lockExists) -> locked=\(locked)")
        return locked
    }

    func lock(folder: RegisteredFolder) async throws {
        print("🔒 Starting lock operation for: \(folder.name)")
        
        guard let folderURL = resolveFolderURL(from: folder) else { 
            print("❌ Failed to resolve folder URL")
            throw FolderLockError.bookmarkResolutionFailed 
        }
        print("✅ Resolved folder URL: \(folderURL.path)")
        
        let fm = FileManager.default
        let parent = folderURL.deletingLastPathComponent()
        let name = folder.name
        let zipURL = parent.appendingPathComponent(name + ".zip")
        let lockURL = parent.appendingPathComponent(name + ".lockit")
        
        print("📁 Zip URL: \(zipURL.path)")
        print("🔐 Lock URL: \(lockURL.path)")

        // Check status first
        var isDir: ObjCBool = false
        let folderExists = fm.fileExists(atPath: folderURL.path, isDirectory: &isDir) && isDir.boolValue
        let lockExists = fm.fileExists(atPath: lockURL.path)
        print("📂 Folder exists: \(folderExists), Lock exists: \(lockExists)")
        
        if !folderExists && lockExists { 
            print("❌ Already locked")
            throw FolderLockError.lockAlreadyLocked 
        }

        // Get key via biometry (require auth on lock too)
        print("🔑 Starting authentication...")
        do {
            let context = try await BiometryAuth.shared.authenticate(reason: "Authenticate to lock \(name)")
            print("✅ Authentication successful")
            
            let account = accountId(for: folder)
            print("🔑 Account ID: \(account)")
            
            let keyData: Data
            do {
                print("🔍 Retrieving existing key...")
                keyData = try KeychainService.shared.retrieveKey(account: account, context: context)
                print("✅ Retrieved existing key")
            } catch KeychainError.itemNotFound {
                print("🆕 Generating new key...")
                // Generate and store a new key on first lock
                let newKey = CryptoService.shared.generateKey()
                try KeychainService.shared.storeKey(newKey, account: account)
                
                // Also store a recovery key based on the folder path
                let recoveryAccount = recoveryAccountId(for: folderURL.path)
                try KeychainService.shared.storeKey(newKey, account: recoveryAccount)
                print("✅ Generated and stored new key with recovery backup")
                
                keyData = newKey
                print("✅ Generated and stored new key")
            } catch {
                print("❌ Keychain error: \(error)")
                throw error
            }

            // Now do file operations with security-scoped access
            print("📦 Starting file operations...")
            try withSecurityScopedAccess(url: folderURL) {
                print("📦 Creating zip archive...")
                try ArchiveService.shared.zipFolder(at: folderURL, to: zipURL)
                defer { 
                    print("🧹 Cleaning up zip file...")
                    try? FileManager.default.removeItem(at: zipURL) 
                }

                print("🔐 Encrypting archive...")
                let zipData = try Data(contentsOf: zipURL)
                print("📊 Zip size: \(zipData.count) bytes")
                let ciphertext = try CryptoService.shared.encrypt(plaintext: zipData, keyData: keyData)
                print("📊 Encrypted size: \(ciphertext.count) bytes")
                
                print("💾 Writing encrypted file...")
                try ciphertext.write(to: lockURL, options: [.atomic])

                print("🗑️ Securely deleting original folder...")
                try SecureDeleteService.shared.secureDeleteFolder(at: folderURL)
                print("✅ Lock operation completed successfully")
            }
        } catch {
            print("❌ Lock operation failed: \(error)")
            throw error
        }
    }

    func unlock(folder: RegisteredFolder) async throws {
        print("🔓 Starting unlock operation for: \(folder.name)")
        
        // For unlock, we'll work with the original path since we just need to recreate the folder
        let originalPath = folder.originalPath
        let folderURL = URL(fileURLWithPath: originalPath)
        let parent = folderURL.deletingLastPathComponent()
        let name = folder.name
        let zipURL = parent.appendingPathComponent(name + ".zip")
        let lockURL = parent.appendingPathComponent(name + ".lockit")
        
        print("📁 Target folder URL: \(folderURL.path)")
        print("🔐 Lock URL: \(lockURL.path)")

        let fm = FileManager.default
        if fm.fileExists(atPath: folderURL.path) { 
            print("❌ Folder already exists - already unlocked")
            throw FolderLockError.unlockAlreadyUnlocked 
        }
        guard fm.fileExists(atPath: lockURL.path) else { 
            print("❌ Lock file not found")
            throw FolderLockError.keyMissing 
        }

        // Auth and retrieve key
        print("🔑 Starting authentication...")
        let context = try await BiometryAuth.shared.authenticate(reason: "Authenticate to unlock \(name)")
        let account = accountId(for: folder)
        let keyData = try KeychainService.shared.retrieveKey(account: account, context: context)
        print("✅ Authentication and key retrieval successful")

        // File operations - no security scope needed for unlock since we're working in the same directory
        print("📦 Starting file operations...")
        do {
            print("🔐 Decrypting archive...")
            let ciphertext = try Data(contentsOf: lockURL)
            let zipData = try CryptoService.shared.decrypt(ciphertext: ciphertext, keyData: keyData)
            print("📊 Decrypted size: \(zipData.count) bytes")
            
            print("💾 Writing temporary zip file...")
            try zipData.write(to: zipURL, options: [.atomic])

            print("📦 Extracting archive...")
            // Extract to the parent directory, not to the folder itself
            try ArchiveService.shared.unzipArchive(at: zipURL, to: parent)
            
            // Ensure the target folder exists (important for empty folders)
            if !fm.fileExists(atPath: folderURL.path) {
                print("📁 Creating target folder (was empty): \(folderURL.path)")
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            
            print("🧹 Cleaning up...")
            
            // Force cleanup with multiple attempts
            var zipRemoved = false
            for attempt in 1...3 {
                print("🗑️ Attempt \(attempt): Removing temporary zip file: \(zipURL.path)")
                if fm.fileExists(atPath: zipURL.path) {
                    do {
                        // Try to ensure no file handles are open
                        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                        try fm.removeItem(at: zipURL)
                        print("✅ Successfully removed zip file on attempt \(attempt)")
                        zipRemoved = true
                        break
                    } catch {
                        print("❌ Attempt \(attempt) failed to remove zip file: \(error)")
                        if attempt < 3 {
                            try await Task.sleep(nanoseconds: 100_000_000) // Wait before retry
                        }
                    }
                } else {
                    print("⚠️ Zip file doesn't exist at expected location on attempt \(attempt)")
                    zipRemoved = true
                    break
                }
            }
            
            if !zipRemoved {
                print("🚨 WARNING: Could not remove temporary zip file after 3 attempts!")
            }
            
            print("🗑️ Removing lock file: \(lockURL.path)")
            if fm.fileExists(atPath: lockURL.path) {
                do {
                    try fm.removeItem(at: lockURL)
                    print("✅ Successfully removed lock file")
                } catch {
                    print("❌ Failed to remove lock file: \(error)")
                }
            } else {
                print("⚠️ Lock file doesn't exist at expected location")
            }
            
            print("✅ Unlock operation completed successfully")
        } catch {
            print("❌ Unlock operation failed: \(error)")
            throw error
        }
    }
    
    func recoverLockedFile(lockFileURL: URL) async throws -> String {
        print("🔓 Starting recovery operation for: \(lockFileURL.path)")
        
        let fm = FileManager.default
        let parent = lockFileURL.deletingLastPathComponent()
        let lockFileName = lockFileURL.lastPathComponent
        
        // Extract folder name from .lockit file
        guard lockFileName.hasSuffix(".lockit") else {
            throw FolderLockError.keyMissing
        }
        
        let folderName = String(lockFileName.dropLast(7)) // Remove ".lockit"
        let folderURL = parent.appendingPathComponent(folderName)
        let zipURL = parent.appendingPathComponent(folderName + ".zip")
        
        print("📁 Recovering folder: \(folderName)")
        print("📁 Target folder URL: \(folderURL.path)")
        
        if fm.fileExists(atPath: folderURL.path) {
            throw FolderLockError.unlockAlreadyUnlocked
        }
        
        guard fm.fileExists(atPath: lockFileURL.path) else {
            throw FolderLockError.keyMissing
        }
        
        // We need to try different possible account IDs since we don't have the original folder registration
        print("🔑 Attempting recovery authentication...")
        let context = try await BiometryAuth.shared.authenticate(reason: "Authenticate to recover \(folderName)")
        
        // Use deterministic recovery key based on the original folder path
        let originalFolderPath = folderURL.path
        let recoveryAccount = recoveryAccountId(for: originalFolderPath)
        
        print("🔑 Looking for recovery key: \(recoveryAccount)")
        
        // Try to retrieve the recovery key
        var keyData: Data?
        do {
            keyData = try KeychainService.shared.retrieveKey(account: recoveryAccount, context: context)
            print("✅ Found recovery key for folder: \(folderName)")
        } catch KeychainError.itemNotFound {
            print("❌ No recovery key found for this folder path")
            throw FolderLockError.keyMissing
        } catch {
            print("❌ Failed to retrieve recovery key: \(error)")
            throw error
        }
        
        guard let validKeyData = keyData else {
            print("❌ No valid decryption key found")
            throw FolderLockError.keyMissing
        }
        
        print("📦 Starting file operations...")
        do {
            print("🔐 Decrypting archive...")
            let ciphertext = try Data(contentsOf: lockFileURL)
            let zipData = try CryptoService.shared.decrypt(ciphertext: ciphertext, keyData: validKeyData)
            print("📊 Decrypted size: \(zipData.count) bytes")
            
            print("💾 Writing temporary zip file...")
            try zipData.write(to: zipURL, options: [.atomic])

            print("📦 Extracting archive...")
            try ArchiveService.shared.unzipArchive(at: zipURL, to: parent)
            
            // Ensure the target folder exists (important for empty folders)
            if !fm.fileExists(atPath: folderURL.path) {
                print("📁 Creating target folder (was empty): \(folderURL.path)")
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            
            print("🧹 Cleaning up...")
            try? fm.removeItem(at: zipURL)
            
            // Delete the original .lockit file since it's been successfully recovered
            print("🗑️ Deleting original encrypted file...")
            try? fm.removeItem(at: lockFileURL)
            print("✅ Deleted original .lockit file")
            
            print("✅ Recovery operation completed successfully")
            return folderName
        } catch {
            print("❌ Recovery operation failed: \(error)")
            throw error
        }
    }
}

