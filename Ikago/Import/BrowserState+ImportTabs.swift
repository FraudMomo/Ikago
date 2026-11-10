import CryptoKit
import Foundation

extension BrowserState {
    /// A source group's identity is scoped to its profile and destination Space, not its title.
    /// Stable folder IDs let subsequent imports add tabs without duplicating groups or changing user edits.
    func mergeImportedTabs(_ imported: [ImportTab], into spaceID: UUID) -> (tabs: Int, groups: Int, limited: Int) {
        var addedTabs = 0, addedGroups = 0, limited = 0
        var urls = Set(tabs.filter { $0.spaceID == spaceID }.map(\.url))
        var groupedURLs: [String: Set<String>] = [:]
        for tab in tabs where tab.spaceID == spaceID {
            if let id = tab.folderID { groupedURLs[id, default: []].insert(tab.url) }
        }
        for item in imported where AddressResolver.isWebURL(item.url) {
            var folderID: String?
            if let name = item.group, !item.pinned {
                let id = Self.importFolderID(item.groupID ?? "named:\(name)", spaceID: spaceID)
                guard !groupedURLs[id, default: []].contains(item.url) else { continue }
                guard tabs.count < Session.maxTabs else { limited += 1; continue }
                if !folders.contains(where: { $0.id == id && $0.spaceID == spaceID }) {
                    guard folders.count < 500 else { limited += 1; continue }
                    let tag = item.groupColor.flatMap(FolderTag.init(rawValue:))?.rawValue
                    folders.append(TabFolder(id: id, name: String(name.prefix(64)), spaceID: spaceID, isOpen: !item.groupCollapsed, tag: tag))
                    addedGroups += 1
                }
                folderID = id
                groupedURLs[id, default: []].insert(item.url)
            } else {
                guard !urls.contains(item.url) else { continue }
                guard tabs.count < Session.maxTabs else { limited += 1; continue }
            }
            tabs.append(TabItem(url: item.url, title: String(item.title.prefix(512)), pinned: item.pinned, spaceID: spaceID, folderID: folderID))
            urls.insert(item.url); addedTabs += 1
        }
        tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
        return (addedTabs, addedGroups, limited)
    }

    private static func importFolderID(_ sourceID: String, spaceID: UUID) -> String {
        let digest = SHA256.hash(data: Data("ikago-import-group:\(spaceID.uuidString):\(sourceID)".utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let parts = [(0, 8), (8, 12), (12, 16), (16, 20), (20, 32)].map { start, end in
            String(hex[hex.index(hex.startIndex, offsetBy: start)..<hex.index(hex.startIndex, offsetBy: end)])
        }
        return parts.joined(separator: "-")
    }
}
