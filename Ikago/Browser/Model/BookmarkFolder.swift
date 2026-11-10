import Foundation

/// Shared bookmark folders are independent of Space-specific live tab groups.
struct BookmarkFolder: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var parentID: String? = nil

    static func validate(_ folders: [Self], bookmarks: [Bookmark]) throws {
        struct InvalidFolders: Error {}
        let ids = Set(folders.map(\.id))
        guard folders.count <= 500, ids.count == folders.count else { throw InvalidFolders() }
        let parents = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.parentID) })
        for folder in folders {
            guard Session.isValidID(folder.id), !folder.name.isEmpty, folder.name.utf8.count <= 256,
                  folder.parentID.map(ids.contains) ?? true else { throw InvalidFolders() }
            var seen: Set<String> = [folder.id]
            var ancestor = folder.parentID
            while let id = ancestor {
                guard seen.insert(id).inserted, seen.count <= 32 else { throw InvalidFolders() }
                ancestor = parents[id] ?? nil
            }
        }
        guard bookmarks.allSatisfy({ $0.folderID.map(ids.contains) ?? true }) else { throw InvalidFolders() }
    }
}
