import Foundation

final class SecureDeleteService {
    static let shared = SecureDeleteService()
    private init() {}

    func secureDeleteFolder(at url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            // Best-effort: removeItem. For more rigorous secure wipe, overwrite files before delete.
            try fm.removeItem(at: url)
        }
    }
}

