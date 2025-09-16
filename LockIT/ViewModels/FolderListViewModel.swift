import Foundation
import SwiftUI

@MainActor
final class FolderListViewModel: ObservableObject {
    static let shared = FolderListViewModel()

    @Published var folders: [RegisteredFolder] = []
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    private let prefs = PreferencesService.shared
    private let locker = FolderLockService.shared

    init() {
        folders = prefs.load()
        refreshLockStates()
    }

    func refreshLockStates() {
        print("🔄 Refreshing lock states for \(folders.count) folders...")
        folders = folders.map { folder in
            var f = folder
            let wasLocked = f.isLocked
            f.isLocked = locker.isLocked(folder: folder)
            print("📁 \(folder.name): \(wasLocked ? "🔒" : "🔓") -> \(f.isLocked ? "🔒" : "🔓")")
            return f
        }
        prefs.save(folders)
        print("✅ Lock states refreshed and saved")
    }

    func chooseFolder() {
        guard folders.count < 3 else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                // Create bookmark for the selected folder itself
                let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                let name = url.lastPathComponent
                let folder = RegisteredFolder(name: name, originalPath: url.path, bookmarkData: bookmark, isLocked: false)
                folders.append(folder)
                prefs.save(folders)
                print("✅ Registered folder: \(name) at path: \(url.path)")
            } catch {
                print("❌ Failed to register folder: \(error)")
                errorMessage = "Failed to register folder."
            }
        }
    }
    
    func createFolder() {
        guard folders.count < 3 else { return }
        
        // First, let user choose where to create the folder
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Choose Location"
        panel.message = "Choose where to create the new folder"
        
        if panel.runModal() == .OK, let parentURL = panel.url {
            // Now ask for folder name
            let alert = NSAlert()
            alert.messageText = "Create New Folder"
            alert.informativeText = "Enter a name for the new folder:"
            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")
            
            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            textField.stringValue = "New Folder"
            textField.selectText(nil)
            alert.accessoryView = textField
            
            if alert.runModal() == .alertFirstButtonReturn {
                let folderName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !folderName.isEmpty {
                    let newFolderURL = parentURL.appendingPathComponent(folderName)
                    
                    do {
                        // Create the folder
                        try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: true)
                        print("✅ Created folder: \(newFolderURL.path)")
                        
                        // Create bookmark for the new folder
                        let bookmark = try newFolderURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                        let folder = RegisteredFolder(name: folderName, originalPath: newFolderURL.path, bookmarkData: bookmark, isLocked: false)
                        folders.append(folder)
                        prefs.save(folders)
                        print("✅ Registered new folder: \(folderName) at path: \(newFolderURL.path)")
                    } catch {
                        print("❌ Failed to create folder: \(error)")
                        errorMessage = "Failed to create folder: \(error.localizedDescription)"
                    }
                } else {
                    errorMessage = "Folder name cannot be empty."
                }
            }
        }
    }

    func removeFolder(_ folder: RegisteredFolder) {
        folders.removeAll { $0.id == folder.id }
        prefs.save(folders)
    }

    func lock(_ folder: RegisteredFolder) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await locker.lock(folder: folder)
            print("🔄 Updating folder state after successful lock...")
            
            // Update the folder state directly since bookmark resolution will fail after deletion
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[index].isLocked = true
                print("✅ Set \(folder.name) to locked state")
            }
            
            prefs.save(folders)
            errorMessage = nil // Clear any previous errors
            print("📊 Updated folder states: \(folders.map { "\($0.name): \($0.isLocked ? "🔒" : "🔓")" })")
        } catch {
            print("Lock error: \(error)")
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain), code: \(nsError.code)")
                print("Error userInfo: \(nsError.userInfo)")
            }
            errorMessage = "Lock failed: \(error.localizedDescription)"
        }
    }

    func unlock(_ folder: RegisteredFolder) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await locker.unlock(folder: folder)
            print("🔄 Updating folder state after successful unlock...")
            
            // Update the folder state directly
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[index].isLocked = false
                print("✅ Set \(folder.name) to unlocked state")
            }
            
            prefs.save(folders)
            errorMessage = nil // Clear any previous errors
            print("📊 Updated folder states: \(folders.map { "\($0.name): \($0.isLocked ? "🔒" : "🔓")" })")
        } catch {
            print("Unlock error: \(error)")
            errorMessage = "Unlock failed: \(error.localizedDescription)"
        }
    }

    func lockAll() async {
        for folder in folders {
            if !locker.isLocked(folder: folder) {
                try? await locker.lock(folder: folder)
            }
        }
        refreshLockStates()
    }
    
    func recoverLockedFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["lockit"]
        panel.prompt = "Select"
        panel.message = "Select an encrypted .lockit file to decrypt and add to LockIT"
        
        if panel.runModal() == .OK, let lockFileURL = panel.url {
            Task {
                isBusy = true
                defer { isBusy = false }
                
                do {
                    let recoveredFolderName = try await locker.recoverLockedFile(lockFileURL: lockFileURL)
                    
                    // Automatically add the recovered folder to the app
                    await MainActor.run {
                        let recoveredFolderURL = lockFileURL.deletingLastPathComponent().appendingPathComponent(recoveredFolderName)
                        
                        do {
                            let bookmark = try recoveredFolderURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                            let folder = RegisteredFolder(name: recoveredFolderName, originalPath: recoveredFolderURL.path, bookmarkData: bookmark, isLocked: false)
                            folders.append(folder)
                            prefs.save(folders)
                            refreshLockStates()
                            print("✅ Recovered and added folder: \(recoveredFolderName)")
                            
                            // Clear any previous error messages
                            errorMessage = nil
                            
                            // Show success message
                            let alert = NSAlert()
                            alert.messageText = "File Decrypted Successfully!"
                            alert.informativeText = "Folder '\(recoveredFolderName)' has been decrypted and added to LockIT."
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                            
                        } catch {
                            print("❌ Failed to add recovered folder: \(error)")
                            errorMessage = "Decrypted folder but couldn't add to app: \(error.localizedDescription)"
                        }
                    }
                } catch {
                    print("Recovery error: \(error)")
                    await MainActor.run {
                        if error is BiometryError {
                            errorMessage = "Recovery cancelled or authentication failed."
                        } else {
                            errorMessage = "Recovery failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
}

