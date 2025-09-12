import Foundation

struct RegisteredFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var originalPath: String
    var bookmarkData: Data
    var isLocked: Bool

    init(id: UUID = UUID(), name: String, originalPath: String, bookmarkData: Data, isLocked: Bool) {
        self.id = id
        self.name = name
        self.originalPath = originalPath
        self.bookmarkData = bookmarkData
        self.isLocked = isLocked
    }
}

final class PreferencesService {
    static let shared = PreferencesService()
    private let defaults = UserDefaults.standard
    private let key = "registeredFolders"
    private init() {}

    func load() -> [RegisteredFolder] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RegisteredFolder].self, from: data)) ?? []
    }

    func save(_ folders: [RegisteredFolder]) {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: key)
        }
    }
}

